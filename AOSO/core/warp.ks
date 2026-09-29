// AOSO/core/warp.ks
// Deadline registry + request wrapper. Actual SET WARP stays in
// flight/maneuver.ks (aoso_warp_approach). Controllers register the next
// critical UT so a long rails coast cannot skip a burn or SOI.
//
// WARPTO is unused: the main loop WAIT 0 under rails jumps UT and cancels
// it. SET WARP must step down early — one rails frame at 10000x has jumped
// ~8000 s and skipped a Minmus capture node (ETA 122 s, then -18 s, still
// at 100x). 100000x straight to 0 also froze FlightIntegrator on unpack.

GLOBAL AOSO_WARP_DEADLINES IS LEXICON().
GLOBAL AOSO_WARP_WALL_EST IS 0.06.
GLOBAL AOSO_WARP_DEMOTE_UNTIL_RT IS 0.
GLOBAL AOSO_WARP_DEMOTE_CAP IS 0.
GLOBAL AOSO_WARP_CMD_RT IS -1.

FUNCTION aoso_warp_deadline_set {
    PARAMETER name.
    PARAMETER ut.
    SET AOSO_WARP_DEADLINES[name] TO ut.
}

FUNCTION aoso_warp_deadline_clear {
    PARAMETER name.
    IF AOSO_WARP_DEADLINES:HASKEY(name) { AOSO_WARP_DEADLINES:REMOVE(name). }
}

FUNCTION aoso_warp_next_deadline {
    LOCAL soon IS 0.
    FOR k IN AOSO_WARP_DEADLINES:KEYS {
        LOCAL ut IS AOSO_WARP_DEADLINES[k].
        IF ut > TIME:SECONDS {
            IF soon = 0 { SET soon TO ut. }
            ELSE {
                IF ut < soon { SET soon TO ut. }
            }
        }
    }
    RETURN soon.
}

FUNCTION aoso_warp_safe_eta {
    PARAMETER eta_s.
    LOCAL next_ut IS aoso_warp_next_deadline().
    IF next_ut <= 0 { RETURN eta_s. }
    LOCAL d_eta IS next_ut - TIME:SECONDS.
    IF d_eta < eta_s { RETURN d_eta. }
    RETURN eta_s.
}

// Rails index from remaining time to the align window. These thresholds
// are based on observed stock-KSP rails frame jumps, not on a desire to
// loiter at low warp. Each step keeps several worst-case frames of margin
// before the steering/alignment lead, so long coasts go much faster without
// reducing the final precision window. MAX_WARP_FACTOR=6 remains the safe
// default; index 7 (100000x) still requires an explicit operator override.
FUNCTION aoso_warp_rails_factor {
    PARAMETER idx.
    IF idx = 1 { RETURN 5. }
    IF idx = 2 { RETURN 10. }
    IF idx = 3 { RETURN 50. }
    IF idx = 4 { RETURN 100. }
    IF idx = 5 { RETURN 1000. }
    IF idx = 6 { RETURN 10000. }
    IF idx = 7 { RETURN 100000. }
    RETURN 1.
}

FUNCTION aoso_warp_update_wall_est {
    // Do not learn frame timing while KSP is still ramping between warp
    // rates. During that transition RATE is intentionally in-between, and
    // feeding those transient frames back into the guard made the requested
    // index bounce up/down before the previous command had even settled.
    IF WARPMODE = "RAILS" {
        IF WARP > 0 {
            IF NOT KUNIVERSE:TIMEWARP:ISSETTLED { RETURN AOSO_WARP_WALL_EST. }
        }
    }

    LOCAL sample IS 0.06.
    IF DEFINED AOSO_WALL_DT {
        IF AOSO_WALL_DT > 0.005 {
            IF AOSO_WALL_DT < 0.25 { SET sample TO AOSO_WALL_DT. }
            ELSE { SET sample TO 0.25. }
        }
    }

    // Rise quickly when KSP hitches, but not in one sample. A single frame
    // used to pin this at the 0.18 s clamp, the index-7 guard became
    // 144000 s, and rails chattered 100000x ↔ 10000x. Each change restarts
    // the on-rails temperature catch-up.
    IF sample > AOSO_WARP_WALL_EST {
        SET AOSO_WARP_WALL_EST TO (AOSO_WARP_WALL_EST * 0.5) + (sample * 0.5).
    } ELSE {
        SET AOSO_WARP_WALL_EST TO (AOSO_WARP_WALL_EST * 0.96) + (sample * 0.04).
    }
    IF AOSO_WARP_WALL_EST < 0.035 { SET AOSO_WARP_WALL_EST TO 0.035. }
    IF AOSO_WARP_WALL_EST > 0.18 { SET AOSO_WARP_WALL_EST TO 0.18. }
    RETURN AOSO_WARP_WALL_EST.
}

FUNCTION aoso_warp_min_remain {
    PARAMETER idx.
    IF idx = 7 { RETURN 86400. } // leave 100000x at least a day before a critical event
    IF idx = 6 { RETURN 20000. } // one 10000x hitch is ~8000-12500 s; 7200 was inside it
    IF idx = 5 { RETURN 2000. }  // one 1000x hitch is ~600-1500 s
    IF idx = 4 { RETURN 250. }   // one 100x hitch jumped 141 s
    IF idx = 3 { RETURN 70. }
    IF idx = 2 { RETURN 35. }
    IF idx = 1 { RETURN 15. }
    RETURN 0.
}

FUNCTION aoso_warp_guard_frames {
    PARAMETER idx.
    IF idx >= 7 { RETURN 8. } // extra margin for 100000x
    IF idx >= 6 { RETURN 6. }
    RETURN 5.
}

// Worst frame the guard will believe. Calm wall_est (clamped at 0.18 s) is
// smaller than the hitches that skipped the Minmus capture: ~0.83 s at
// 10000x, ~0.6 s at 1000x, ~1.4 s at 100x. Floors and this wall both have
// to clear or the rate is illegal.
FUNCTION aoso_warp_guard_wall {
    PARAMETER idx.
    LOCAL worst IS 0.2.
    IF idx >= 6 { SET worst TO 1.25. }
    ELSE {
        IF idx >= 5 { SET worst TO 1.0. }
        ELSE {
            IF idx >= 4 { SET worst TO 0.8. }
        }
    }
    IF AOSO_WARP_WALL_EST > worst { RETURN AOSO_WARP_WALL_EST. }
    RETURN worst.
}

FUNCTION aoso_warp_rails_want {
    PARAMETER eta_s.
    PARAMETER lead_s.
    LOCAL remain IS eta_s - lead_s.
    IF remain <= 0 { RETURN 0. }

    LOCAL cap IS aoso_config_get("MAX_WARP_FACTOR", 6).
    IF cap > 7 { SET cap TO 7. }
    IF cap < 1 { SET cap TO 1. }
    // Index 7 is opt-in. The old default (and the 6→7 migration) put a
    // 117-part ship on 100000x for days; the unpack then froze KSP.
    IF cap > 6 {
        IF NOT aoso_config_get("WARP_ALLOW_100000", FALSE) { SET cap TO 6. }
    }

    aoso_warp_update_wall_est().
    LOCAL idx IS cap.
    UNTIL idx <= 0 {
        LOCAL floor_s IS aoso_warp_min_remain(idx).
        LOCAL jump_s IS aoso_warp_rails_factor(idx) * aoso_warp_guard_wall(idx).
        LOCAL guard_s IS jump_s * aoso_warp_guard_frames(idx).

        // Promotion hysteresis: once KSP has stepped down, require noticeably
        // more headroom before asking it to climb again. This prevents an ETA
        // sitting near a threshold from oscillating 50x -> 10000x -> 50x.
        IF WARPMODE = "RAILS" {
            IF idx > WARP {
                SET guard_s TO guard_s * aoso_config_get("WARP_PROMOTE_MARGIN", 1.35).
            }
        }

        // Choose the highest rate that still leaves several observed KSP
        // update frames before the unchanged precision/alignment lead.
        IF remain >= floor_s {
            IF remain > guard_s { RETURN idx. }
        }
        SET idx TO idx - 1.
    }
    RETURN 0.
}

// Next warp index to command. At most one step toward target_idx.
// Returns the current WARP when this tick must not SET WARP again.
// Does not SET WARP — flight/maneuver.ks owns that.
FUNCTION aoso_warp_step_target {
    PARAMETER target_idx.
    IF target_idx < 0 { SET target_idx TO 0. }
    IF target_idx > 7 { SET target_idx TO 7. }
    IF WARP = target_idx { RETURN WARP. }

    LOCAL now_rt IS KUNIVERSE:REALTIME.
    LOCAL since_cmd IS 999.
    IF AOSO_WARP_CMD_RT >= 0 {
        SET since_cmd TO now_rt - AOSO_WARP_CMD_RT.
    }

    IF target_idx > WARP {
        IF NOT KUNIVERSE:TIMEWARP:ISSETTLED { RETURN WARP. }
        IF since_cmd < aoso_config_get("WARP_STEP_MIN_S", 0.2) { RETURN WARP. }
        IF now_rt < AOSO_WARP_DEMOTE_UNTIL_RT {
            IF WARP <= AOSO_WARP_DEMOTE_CAP { RETURN WARP. }
        }
        LOCAL up_idx IS WARP + 1.
        IF up_idx > target_idx { SET up_idx TO target_idx. }
        SET AOSO_WARP_CMD_RT TO now_rt.
        RETURN up_idx.
    }

    LOCAL down_idx IS WARP - 1.
    IF down_idx < target_idx { SET down_idx TO target_idx. }
    LOCAL wait_s IS aoso_config_get("WARP_STEP_MIN_S", 0.2).
    // While KSP is still ramping, do not queue another index every
    // scheduler tick. A stuck ISSETTLED flag still steps down, just slower,
    // so a node cannot sit at 10000x until ETA goes negative.
    IF NOT KUNIVERSE:TIMEWARP:ISSETTLED { SET wait_s TO wait_s * 4. }
    // Last step into unpack sits on a settled 5x (or physics 2x) frame.
    // Commanding 0 while a higher rails rate is still catching up is the
    // FlightIntegrator storm: pack, "unloaded Ns", unpack, freeze.
    IF down_idx <= 0 {
        IF WARP <= 1 {
            LOCAL unpack_s IS aoso_config_get("WARP_UNPACK_SETTLE_S", 1.5).
            IF unpack_s > wait_s { SET wait_s TO unpack_s. }
            IF NOT KUNIVERSE:TIMEWARP:ISSETTLED {
                IF since_cmd < wait_s { RETURN WARP. }
            }
        }
    }
    IF since_cmd < wait_s { RETURN WARP. }
    SET AOSO_WARP_DEMOTE_CAP TO down_idx.
    SET AOSO_WARP_DEMOTE_UNTIL_RT TO now_rt + aoso_config_get("WARP_DEMOTE_HOLD_S", 8).
    SET AOSO_WARP_CMD_RT TO now_rt.
    RETURN down_idx.
}

// -1 means this tick is not an emergency drop. Otherwise the rails index
// to SET. One frame at the current rate would cross eta_s.
// 1000x and above drop two indices and never straight to 0 — that unpack
// is the FlightIntegrator freeze. 100x and below may drop to target_idx,
// including 0, which is what a capture inside the align window needs.
// Does not SET WARP.
FUNCTION aoso_warp_urgent_index {
    PARAMETER target_idx.
    PARAMETER eta_s.
    IF WARP <= 0 { RETURN -1. }
    IF WARPMODE <> "RAILS" { RETURN -1. }
    IF target_idx < 0 { SET target_idx TO 0. }
    IF target_idx >= WARP { RETURN -1. }
    LOCAL factor_now IS aoso_warp_rails_factor(WARP).
    LOCAL hitch_s IS factor_now * 1.5.
    IF eta_s >= hitch_s { RETURN -1. }
    IF WARP >= 5 {
        LOCAL drop_idx IS WARP - 2.
        IF drop_idx < 2 { SET drop_idx TO 2. }
        IF drop_idx < target_idx { SET drop_idx TO target_idx. }
        RETURN drop_idx.
    }
    RETURN target_idx.
}

FUNCTION aoso_warp_request {
    PARAMETER eta_s.
    PARAMETER rails_lead_s.
    PARAMETER physics_until_s IS -1.
    LOCAL safe IS aoso_warp_safe_eta(eta_s).
    RETURN aoso_warp_approach(safe, rails_lead_s, physics_until_s).
}
