// AOSO/core/warp.ks
// Deadline registry + request wrapper. Actual SET WARP stays in
// flight/maneuver.ks (aoso_warp_approach). Controllers register the next
// critical UT so a long rails coast cannot skip a burn or SOI.
//
// WARPTO is unused: the main loop WAIT 0 under rails jumps UT and cancels
// it. SET WARP must step down early — warp 7 (100000x) can skip a node by
// minutes in one tick (Acacius mid-course ETA 41708 → -360).

GLOBAL AOSO_WARP_DEADLINES IS LEXICON().

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

FUNCTION aoso_warp_rails_want {
    PARAMETER eta_s.
    PARAMETER lead_s.
    LOCAL remain IS eta_s - lead_s.
    LOCAL cap IS aoso_config_get("MAX_WARP_FACTOR", 6).
    IF cap > 7 { SET cap TO 7. }
    IF cap < 1 { SET cap TO 1. }
    LOCAL want IS 0.
    IF remain >= 15 { SET want TO 1. }
    IF remain >= 35 { SET want TO 2. }
    IF remain >= 75 { SET want TO 3. }
    IF remain >= 180 { SET want TO 4. }
    IF remain >= 600 { SET want TO 5. }
    IF remain >= 2400 { SET want TO 6. }
    IF remain >= 180000 { SET want TO 7. }
    IF want > cap { SET want TO cap. }

    // Adaptive frame-jump guard. Estimate how much game time one recent
    // real-time update would advance at the requested rails factor, then
    // require five such frames of margin before the precision lead. A
    // temporary KSP hitch automatically lowers the chosen warp rate without
    // permanently slowing normal coasts.
    LOCAL wall_sample IS 0.06.
    IF DEFINED AOSO_WALL_DT {
        IF AOSO_WALL_DT > wall_sample { SET wall_sample TO AOSO_WALL_DT. }
    }
    IF wall_sample > 0.25 { SET wall_sample TO 0.25. }
    UNTIL want <= 0 {
        LOCAL jump_guard IS aoso_warp_rails_factor(want) * wall_sample * 5.
        IF remain > jump_guard { RETURN want. }
        SET want TO want - 1.
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
