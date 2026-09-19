// AOSO/core/warp.ks
// Deadline registry + request wrapper. Actual SET WARP / WARPTO stay in
// flight/maneuver.ks (aoso_warp_approach). Controllers register the next
// critical UT so a long rails coast cannot skip a burn or SOI.

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

FUNCTION aoso_warp_request {
    PARAMETER eta_s.
    PARAMETER rails_lead_s.
    PARAMETER physics_until_s IS -1.
    LOCAL safe IS aoso_warp_safe_eta(eta_s).
    RETURN aoso_warp_approach(safe, rails_lead_s, physics_until_s).
}
