// AOSO/core/warp.ks
// Deadline registry + request wrapper. Actual SET WARP stays in
// flight/maneuver.ks (aoso_warp_approach). Controllers register the next
// critical UT so a long rails coast cannot skip a burn or SOI.
//
// WARPTO is unused: the main loop WAIT 0 under rails jumps UT and cancels
// it. SET WARP must step down early — warp 7 (100000x) can skip a node by
// minutes in one tick (Acacius mid-course ETA 41708 → -360).

GLOBAL AOSO_WARP_DEADLINES IS LEXICON().
GLOBAL AOSO_WARP_WALL_EST IS 0.06.

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

    // Rise quickly when KSP hitches, decay slowly when it recovers. Using a
    // raw single-frame sample made warp rates bounce in and out as frame
    // time jittered.
    IF sample > AOSO_WARP_WALL_EST {
        SET AOSO_WARP_WALL_EST TO sample.
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
    IF idx = 6 { RETURN 7200. }  // KSP can jump several thousand seconds per scheduler tick at 10000x
    IF idx = 5 { RETURN 480. }
    IF idx = 4 { RETURN 150. }
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

FUNCTION aoso_warp_rails_want {
    PARAMETER eta_s.
    PARAMETER lead_s.
    LOCAL remain IS eta_s - lead_s.
    IF remain <= 0 { RETURN 0. }

    LOCAL cap IS aoso_config_get("MAX_WARP_FACTOR", 7).
    IF cap > 7 { SET cap TO 7. }
    IF cap < 1 { SET cap TO 1. }

    LOCAL wall_est IS aoso_warp_update_wall_est().
    LOCAL idx IS cap.
    UNTIL idx <= 0 {
        LOCAL floor_s IS aoso_warp_min_remain(idx).
        LOCAL jump_s IS aoso_warp_rails_factor(idx) * wall_est.
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

FUNCTION aoso_warp_request {
    PARAMETER eta_s.
    PARAMETER rails_lead_s.
    PARAMETER physics_until_s IS -1.
    LOCAL safe IS aoso_warp_safe_eta(eta_s).
    RETURN aoso_warp_approach(safe, rails_lead_s, physics_until_s).
}
