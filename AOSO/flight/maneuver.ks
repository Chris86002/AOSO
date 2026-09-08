// AOSO/flight/maneuver.ks
// Generic maneuver-node creation and execution. Pure vis-viva/kOS-native
// NODE math -- no MechJeb/Astrogator dependency (see core/addons.ks) -- so
// every later phase (orbital nav, interplanetary, return) can reuse
// aoso_maneuver_execute_next() as its burn executor instead of each writing
// its own throttle/steering loop.

// Delta-v (m/s, signed) needed at the current apoapsis to circularize:
// target circular speed minus the vessel's actual speed there, derived from
// the current orbit's semi-major axis via vis-viva.
FUNCTION aoso_maneuver_circularize_dv_at_apoapsis {
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + APOAPSIS.
    LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.

    LOCAL v_circ IS SQRT(mu / radius).
    LOCAL v_now IS SQRT(MAX(0, mu * (2 / radius - 1 / sma))).

    RETURN v_circ - v_now.
}

FUNCTION aoso_maneuver_add_circularize_at_apoapsis {
    LOCAL dv IS aoso_maneuver_circularize_dv_at_apoapsis().
    LOCAL nd IS NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dv).
    ADD nd.
    aoso_log_info("MANEUVER", "Circularization node added: dv=" + ROUND(dv, 1) + " m/s at apoapsis.").
    RETURN nd.
}

FUNCTION aoso_maneuver_has_pending {
    RETURN HASNODE.
}

// Tapers throttle down as the remaining node dv shrinks so the burn doesn't
// overshoot the target dv on the final tick.
FUNCTION aoso_maneuver_throttle_for_dv {
    PARAMETER remaining_dv.
    IF remaining_dv > 2 { RETURN 1.0. }
    RETURN MAX(0.05, remaining_dv / 2).
}

// Non-blocking: call once per scheduler tick (or in a tight WAIT 0 loop).
// Aligns with the next node's burn vector, waits until half the estimated
// burn time remains, then burns it down and removes the node. Returns TRUE
// once there is no pending node left to execute (including when there was
// never one), FALSE while a burn is still in progress.
FUNCTION aoso_maneuver_execute_next {
    IF NOT HASNODE {
        RETURN TRUE.
    }

    LOCAL nd IS NEXTNODE.
    LOCAL burn_dv IS nd:BURNVECTOR:MAG.

    aoso_steer_to_vector(nd:BURNVECTOR).

    IF burn_dv < 0.05 {
        LOCK THROTTLE TO 0.
        aoso_steer_release().
        REMOVE nd.
        aoso_log_info("MANEUVER", "Node executed.").
        RETURN TRUE.
    }

    IF NOT aoso_steer_is_aligned(nd:BURNVECTOR, 2) {
        LOCK THROTTLE TO 0.
        RETURN FALSE.
    }

    LOCAL burn_time IS 0.
    SET burn_time TO aoso_perf_burn_time_for_dv(burn_dv).

    IF nd:ETA > (burn_time / 2 + 1) {
        LOCK THROTTLE TO 0.
        RETURN FALSE.
    }

    LOCK THROTTLE TO aoso_maneuver_throttle_for_dv(burn_dv).
    aoso_staging_auto_check().
    RETURN FALSE.
}

FUNCTION aoso_maneuver_clear_all {
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
}
