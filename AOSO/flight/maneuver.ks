// AOSO/flight/maneuver.ks
// Generic maneuver-node creation and execution. Pure vis-viva/kOS-native
// NODE math -- no MechJeb/Astrogator dependency (see core/addons.ks) -- so
// every later phase (orbital nav, interplanetary, return) can reuse
// aoso_maneuver_execute_next() as its burn executor instead of each writing
// its own throttle/steering loop.
//
// Burn execution: short burns (circularization) lock facing at ignition so
// a TWR jump cannot hunt NEXTNODE:BURNVECTOR. Long burns (Mun 840 m/s)
// follow the live marker until a few seconds remain, then lock and feather.
// Acacius's 104 s Mun burn locked at ignition, staged, and left the marker;
// the intercept missed. Feathering used to start at 2 m/s remaining -- at
// TWR ~1 that is a fraction of a tick -- so the cut always arrived late.

GLOBAL AOSO_MANEUVER_LOCK IS V(0, 0, 0).
GLOBAL AOSO_MANEUVER_BURNING IS FALSE.
GLOBAL AOSO_MANEUVER_LAST_REMAINING IS 0.
GLOBAL AOSO_MANEUVER_RESULT IS "ok".

FUNCTION aoso_maneuver_reset_exec {
    SET AOSO_MANEUVER_BURNING TO FALSE.
    SET AOSO_MANEUVER_LOCK TO V(0, 0, 0).
    SET AOSO_MANEUVER_LAST_REMAINING TO 0.
}

FUNCTION aoso_maneuver_last_result {
    RETURN AOSO_MANEUVER_RESULT.
}

FUNCTION aoso_maneuver_align_s {
    LOCAL s IS aoso_config_get("MANEUVER_ALIGN_S", 120).
    IF s < 120 { SET s TO 120. }
    RETURN s.
}

FUNCTION aoso_maneuver_can_warp {
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" { RETURN FALSE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT + 1000 { RETURN FALSE. }
    }
    RETURN TRUE.
}

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

// Same vis-viva circularization but at the current radius, for when we
// already passed apoapsis (ETA:AP jumped a full period) and waiting would
// put periapsis back in the atmosphere.
FUNCTION aoso_maneuver_add_circularize_here {
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL v_circ IS SQRT(mu / radius).
    LOCAL v_now IS SQRT(MAX(0, mu * (2 / radius - 1 / sma))).
    LOCAL dv IS v_circ - v_now.
    LOCAL nd IS NODE(TIME:SECONDS + 10, 0, 0, dv).
    ADD nd.
    aoso_log_info("MANEUVER", "Circularization node added: dv=" + ROUND(dv, 1) + " m/s now (past apoapsis).").
    RETURN nd.
}

FUNCTION aoso_maneuver_has_pending {
    RETURN HASNODE.
}

// Instantaneous acceleration (m/s^2) available from currently ignited
// engines. Used to convert remaining dv into a burn-time so feathering
// starts ~MANEUVER_FEATHER_S seconds out instead of at a fixed 2 m/s.
FUNCTION aoso_maneuver_current_accel {
    IF SHIP:MASS <= 0 { RETURN 0. }
    RETURN SHIP:AVAILABLETHRUST / SHIP:MASS.
}

// Tapers throttle so remaining dv is killed in roughly MANEUVER_FEATHER_S
// seconds. Full throttle while remaining burn time is above that window;
// linear fade after. Recalculated every tick so a mid-burn staging/relight
// that jumps TWR still feathers instead of overshooting.
FUNCTION aoso_maneuver_throttle_for_dv {
    PARAMETER remaining_dv.

    LOCAL accel IS aoso_maneuver_current_accel().
    IF accel <= 0 { RETURN 0. }
    IF remaining_dv <= 0.05 { RETURN 0. }

    LOCAL t_remain IS remaining_dv / accel.
    LOCAL feather_s IS aoso_config_get("MANEUVER_FEATHER_S", 2).
    IF t_remain > feather_s { RETURN 1.0. }
    RETURN MAX(0.05, t_remain / feather_s).
}

FUNCTION aoso_maneuver_finish_node {
    PARAMETER nd.
    PARAMETER reason.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    IF HASNODE { REMOVE nd. }
    aoso_maneuver_reset_exec().
    IF reason = "missed" { SET AOSO_MANEUVER_RESULT TO "missed". }
    ELSE {
        IF reason = "no thrust" OR reason = "incomplete" { SET AOSO_MANEUVER_RESULT TO "incomplete". }
        ELSE { SET AOSO_MANEUVER_RESULT TO "ok". }
    }
    aoso_log_info("MANEUVER", "Node executed (" + reason + ").").
}

// Non-blocking: call once per scheduler tick (or in a tight WAIT 0 loop).
// Warps out with ~2 minutes of physics time to point the ship before
// ignition. Long burns follow the live node marker (Mun 840 m/s); short
// burns lock facing at ignition so a TWR jump cannot hunt. Stage even if
// throttle is already 0. If the node is already in the past, or the burn
// dies with a lot of dv left, finish as missed/incomplete so the caller
// can replan the next pass.
// Returns TRUE once there is no pending node left, FALSE while in progress.
FUNCTION aoso_maneuver_execute_next {
    IF NOT HASNODE {
        IF AOSO_MANEUVER_BURNING { aoso_maneuver_reset_exec(). }
        RETURN TRUE.
    }

    LOCAL nd IS NEXTNODE.
    LOCAL remaining_vec IS nd:BURNVECTOR.
    LOCAL remaining IS remaining_vec:MAG.

    IF remaining < 0.08 {
        aoso_maneuver_finish_node(nd, "complete").
        RETURN TRUE.
    }

    IF NOT AOSO_MANEUVER_BURNING {
        aoso_steer_prepare_for_burn().
        aoso_steer_to_vector(remaining_vec).

        IF nd:ETA < -8 {
            aoso_log_warn("MANEUVER", "Missed node (ETA=" + ROUND(nd:ETA, 1) + "s) - retry next pass.").
            aoso_maneuver_finish_node(nd, "missed").
            RETURN TRUE.
        }

        LOCAL burn_time IS aoso_perf_burn_time_for_dv(remaining).
        LOCAL ignite_lead IS burn_time / 2.
        LOCAL align_s IS aoso_maneuver_align_s().
        LOCAL warp_lead IS ignite_lead + align_s.

        IF WARP > 0 {
            IF nd:ETA <= warp_lead + 8 { SET WARP TO 0. }
            LOCK THROTTLE TO 0.
            RETURN FALSE.
        }

        IF nd:ETA > warp_lead + 5 {
            IF aoso_maneuver_can_warp() {
                WARPTO(TIME:SECONDS + nd:ETA - warp_lead).
            }
            LOCK THROTTLE TO 0.
            RETURN FALSE.
        }
        SET WARP TO 0.

        IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

        IF nd:ETA > ignite_lead + 1 {
            LOCK THROTTLE TO 0.
            RETURN FALSE.
        }

        IF NOT aoso_steer_is_aligned(remaining_vec, 8) {
            LOCAL err_deg IS aoso_steer_error_deg(remaining_vec).
            IF nd:ETA >= 0 {
                LOCK THROTTLE TO 0.
                RETURN FALSE.
            }
            IF err_deg > 20 {
                IF nd:ETA < -8 {
                    aoso_log_warn("MANEUVER", "Never aligned in time - retry next pass.").
                    aoso_maneuver_finish_node(nd, "missed").
                    RETURN TRUE.
                }
                LOCK THROTTLE TO 0.
                RETURN FALSE.
            }
        }

        IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

        SET WARP TO 0.
        SET AOSO_MANEUVER_LOCK TO remaining_vec.
        SET AOSO_MANEUVER_BURNING TO TRUE.
        SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
        SET AOSO_MANEUVER_RESULT TO "ok".
        LOCAL accel0 IS aoso_maneuver_current_accel().
        LOCAL t0 IS 0.
        IF accel0 > 0.05 { SET t0 TO remaining / accel0. }
        IF t0 > aoso_config_get("MANEUVER_FOLLOW_ABOVE_S", 8) {
            aoso_log_info("MANEUVER", "Burn started, following node, remaining=" + ROUND(remaining, 1) + " m/s.").
        } ELSE {
            SET AOSO_MANEUVER_LOCK TO SHIP:FACING:FOREVECTOR.
            aoso_log_info("MANEUVER", "Burn lock engaged, remaining=" + ROUND(remaining, 1) + " m/s.").
        }
    }

    IF SHIP:AVAILABLETHRUST <= 0 {
        aoso_staging_ensure_thrust().
        IF SHIP:AVAILABLETHRUST <= 0 {
            aoso_maneuver_finish_node(nd, "no thrust").
            RETURN TRUE.
        }
    }
    aoso_staging_auto_check().

    LOCAL accel IS aoso_maneuver_current_accel().
    LOCAL t_remain IS 0.
    IF accel > 0.05 { SET t_remain TO remaining / accel. }
    LOCAL follow_s IS aoso_config_get("MANEUVER_FOLLOW_ABOVE_S", 8).

    IF t_remain > follow_s {
        SET AOSO_MANEUVER_LOCK TO remaining_vec.
        aoso_steer_to_vector(remaining_vec).
    } ELSE {
        IF AOSO_MANEUVER_LOCK:MAG < 0.1 {
            SET AOSO_MANEUVER_LOCK TO SHIP:FACING:FOREVECTOR.
        }
        aoso_steer_to_vector(AOSO_MANEUVER_LOCK).
    }

    LOCAL remaining_along IS VDOT(AOSO_MANEUVER_LOCK:NORMALIZED, remaining_vec).

    IF remaining_along < 0.08 {
        aoso_maneuver_finish_node(nd, "feather cut").
        RETURN TRUE.
    }
    IF remaining > AOSO_MANEUVER_LAST_REMAINING + 0.4 {
        IF remaining > 30 {
            aoso_maneuver_finish_node(nd, "incomplete").
        } ELSE {
            aoso_maneuver_finish_node(nd, "overshoot cut").
        }
        RETURN TRUE.
    }

    SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
    LOCK THROTTLE TO aoso_maneuver_throttle_for_dv(remaining_along).
    RETURN FALSE.
}

FUNCTION aoso_maneuver_clear_all {
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
    aoso_maneuver_reset_exec().
}
