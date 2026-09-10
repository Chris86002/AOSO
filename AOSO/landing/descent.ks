// AOSO/landing/descent.ks
// Suicide-burn (hoverslam) + final-approach descent guidance.
//
// The previous trigger used only ABS(VERTICALSPEED). Acacius hit Mun at
// ~687 m/s surface from a 1166 x -2 km ellipse; vertical speed at 5 km was
// only ~120 m/s so the burn started at ~5 km instead of the ~30 km
// kinematics actually required, then FINAL_APPROACH engaged at 150 m while
// still hypersonic.
//
// Community / MechJeb-style hoverslam (elwanderer, HerrCraziDev, Garwel
// SBLAND, kOS-Hoverslam):
//   maxDecel = AVAILABLETHRUST/MASS - g
//   stopDist = VELOCITY:SURFACE:SQRMAGNITUDE / (2 * maxDecel)
//   burn when (ALT:RADAR - radarOffset) <= stopDist * margin
//   lock steering to srfretrograde until horizontal AND vertical speed are
//   small, then a vertical final approach. Do not switch to "up + 3 m/s"
//   while still going 600 m/s.

GLOBAL AOSO_DESCENT IS aoso_state_new_machine().
GLOBAL AOSO_DESCENT_RADAR_OFFSET IS 8.

FUNCTION aoso_descent_local_gravity {
    RETURN SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
}

// Distance (m) from CoM to the lowest part along UP, plus a small gear
// allowance. ALT:RADAR is measured from the CPU/root; Acacius's root is the
// Mk1 Lander Can at the top of a ~44 m stack, so an uncorrected radar would
// report the nose-to-ground distance.
FUNCTION aoso_descent_measure_radar_offset {
    LOCAL configured IS aoso_config_get("DESCENT_RADAR_OFFSET", 0).
    IF configured > 0 { RETURN configured. }

    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL axis IS SHIP:UP:VECTOR.
    LOCAL min_along IS 0.
    LOCAL seen IS FALSE.
    FOR p IN plist {
        LOCAL along IS VDOT(p:POSITION, axis).
        IF NOT seen {
            SET min_along TO along.
            SET seen TO TRUE.
        } ELSE {
            IF along < min_along { SET min_along TO along. }
        }
    }
    LOCAL offset_m IS 0 - min_along.
    IF offset_m < 2 { SET offset_m TO 2. }
    IF offset_m > 80 { SET offset_m TO 80. }
    RETURN offset_m + 2.
}

FUNCTION aoso_descent_true_radar {
    LOCAL radar_m IS ALT:RADAR - AOSO_DESCENT_RADAR_OFFSET.
    IF radar_m < 1 { RETURN 1. }
    RETURN radar_m.
}

// Maximum net deceleration (m/s^2) available against gravity at full
// throttle. 0 when the current stage cannot hover, so callers can burn
// immediately instead of computing a negative stopping distance.
FUNCTION aoso_descent_max_deceleration {
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL accel IS SHIP:AVAILABLETHRUST / SHIP:MASS.
    RETURN MAX(0, accel - aoso_descent_local_gravity()).
}

// Kinematic stopping distance (m) to kill the full surface-velocity vector
// (not just vertical speed) at constant net deceleration.
FUNCTION aoso_descent_stopping_distance {
    PARAMETER speed_ms.
    PARAMETER decel.
    IF decel <= 0 { RETURN -1. }
    RETURN (speed_ms ^ 2) / (2 * decel).
}

// Radar altitude (m) at which the suicide burn must start.
FUNCTION aoso_descent_burn_trigger_alt {
    LOCAL speed_ms IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL decel IS aoso_descent_max_deceleration().
    LOCAL stop_dist IS aoso_descent_stopping_distance(speed_ms, decel).
    IF stop_dist < 0 { RETURN 9E+9. }
    LOCAL pad_mult IS aoso_config_get("DESCENT_STOP_MARGIN", 1.2).
    IF pad_mult < 1 { SET pad_mult TO 1. }
    LOCAL margin_s IS aoso_config_get("DESCENT_BURN_MARGIN_S", 4).
    LOCAL vs_abs IS ABS(VERTICALSPEED).
    // elwanderer: extra -VS/10 worth of reaction height, plus configured
    // seconds of surface speed so a 0.1 s scheduler tick cannot eat the burn.
    RETURN (stop_dist * pad_mult) + (speed_ms * margin_s) + (vs_abs / 10).
}

// Throttle (0-1) for the hoverslam: 1.0 whenever remaining radar is at or
// inside the raw stop distance, otherwise stopDist/radar (the classic
// kOS-Hoverslam idealThrottle) so we do not over-burn if we started early.
FUNCTION aoso_descent_required_throttle {
    LOCAL h IS aoso_descent_true_radar().
    LOCAL speed_ms IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL decel IS aoso_descent_max_deceleration().
    LOCAL stop_dist IS aoso_descent_stopping_distance(speed_ms, decel).
    IF stop_dist < 0 { RETURN 1. }
    IF h <= stop_dist { RETURN 1. }
    RETURN MAX(0.15, MIN(1, stop_dist / h)).
}

FUNCTION aoso_descent_final_approach_throttle {
    LOCAL target_v IS aoso_config_get("DESCENT_FINAL_SPEED", -3).
    LOCAL error IS target_v - VERTICALSPEED.
    LOCAL g IS aoso_descent_local_gravity().

    LOCAL kp IS 0.6.
    LOCAL accel_cmd IS g - (kp * error).

    LOCAL max_accel IS 0.
    IF SHIP:MASS > 0 { SET max_accel TO SHIP:AVAILABLETHRUST / SHIP:MASS. }
    IF max_accel <= 0 { RETURN 0. }

    RETURN MAX(0, MIN(1, accel_cmd / max_accel)).
}

FUNCTION aoso_descent_should_final_approach {
    LOCAL h IS aoso_descent_true_radar().
    LOCAL final_alt IS aoso_config_get("DESCENT_FINAL_APPROACH_ALT", 150).
    IF h > final_alt { RETURN FALSE. }
    LOCAL max_speed IS aoso_config_get("DESCENT_FINAL_SPEED_MAX", 25).
    IF SHIP:VELOCITY:SURFACE:MAG > max_speed { RETURN FALSE. }
    IF GROUNDSPEED > 15 { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_descent_on_abort {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_state_transition(AOSO_DESCENT, "ABORTED").
}

FUNCTION aoso_descent_freefall_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    SET AOSO_DESCENT_RADAR_OFFSET TO aoso_descent_measure_radar_offset().
    aoso_log_info("DESCENT", "Radar offset=" + ROUND(AOSO_DESCENT_RADAR_OFFSET, 1) + " m.").
}

FUNCTION aoso_descent_freefall_execute {
    PARAMETER data.
    aoso_parachute_auto_check().

    IF VERTICALSPEED >= 0 { RETURN. }

    // Atmospheric bodies: wait for air/chutes to do the first half. A
    // TWR~1 stack cannot hoverslam from 70 km on Kerbin.
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE > 8000 {
            IF aoso_descent_max_deceleration() < 3 { RETURN. }
        }
    }

    aoso_steer_srf_retrograde().

    LOCAL trigger IS aoso_descent_burn_trigger_alt().
    LOCAL radar IS aoso_descent_true_radar().
    LOCAL speed_ms IS SHIP:VELOCITY:SURFACE:MAG.

    IF radar <= trigger {
        SET WARP TO 0.
        aoso_log_info("DESCENT", "Suicide burn now: radar=" + ROUND(radar, 0) + " m trigger=" + ROUND(trigger, 0) +
            " m vSrf=" + ROUND(speed_ms, 1) + " m/s vVert=" + ROUND(VERTICALSPEED, 1) +
            " m/s decel=" + ROUND(aoso_descent_max_deceleration(), 2) + " m/s^2.").
        aoso_state_transition(AOSO_DESCENT, "BURN").
        RETURN.
    }

    LOCAL tti IS 9E9.
    IF speed_ms > 1 { SET tti TO radar / speed_ms. }
    IF radar < (trigger * 2) {
        SET WARP TO 0.
    } ELSE {
        IF tti < 45 {
            SET WARP TO 0.
        } ELSE {
            IF WARP = 0 {
                IF aoso_maneuver_can_warp() { SET WARP TO 3. }
            }
        }
    }
}

FUNCTION aoso_descent_burn_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_steer_srf_retrograde().
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }
}

FUNCTION aoso_descent_burn_execute {
    PARAMETER data.
    aoso_parachute_auto_check().
    SET WARP TO 0.

    aoso_steer_srf_retrograde().
    LOCK THROTTLE TO aoso_descent_required_throttle().

    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_DESCENT).
        RETURN.
    }

    LOCAL radar IS aoso_descent_true_radar().
    IF radar < 250 { LEGS ON. }

    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
        RETURN.
    }

    IF aoso_descent_should_final_approach() {
        aoso_state_transition(AOSO_DESCENT, "FINAL_APPROACH").
    }
}

FUNCTION aoso_descent_final_approach_entry {
    PARAMETER data.
    aoso_steer_up().
    LEGS ON.
}

FUNCTION aoso_descent_final_approach_execute {
    PARAMETER data.
    // If we somehow picked up speed again (bounce, slope), go back to the
    // hoverslam instead of holding a 3 m/s vertical while sliding sideways.
    IF NOT aoso_descent_should_final_approach() {
        IF SHIP:STATUS <> "LANDED" {
            aoso_log_warn("DESCENT", "Final approach still fast (vSrf=" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) +
                " m/s) - returning to suicide burn.").
            aoso_state_transition(AOSO_DESCENT, "BURN").
            RETURN.
        }
    }

    aoso_steer_up().
    LOCK THROTTLE TO aoso_descent_final_approach_throttle().

    aoso_staging_auto_check().

    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
        RETURN.
    }
    IF aoso_descent_true_radar() <= aoso_config_get("DESCENT_TOUCHDOWN_ALT", 0.5) {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
    }
}

FUNCTION aoso_descent_touchdown_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_log_info("DESCENT", "Touchdown, throttle cut.").
}

FUNCTION aoso_descent_is_landed {
    RETURN AOSO_DESCENT["current"] = "TOUCHDOWN".
}

FUNCTION aoso_descent_is_aborted {
    RETURN AOSO_DESCENT["current"] = "ABORTED".
}

FUNCTION aoso_descent_start {
    aoso_state_define(AOSO_DESCENT, "FREEFALL", aoso_descent_freefall_entry@, aoso_descent_freefall_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "BURN", aoso_descent_burn_entry@, aoso_descent_burn_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "FINAL_APPROACH", aoso_descent_final_approach_entry@, aoso_descent_final_approach_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "TOUCHDOWN", aoso_descent_touchdown_entry@, 0, 0).
    aoso_state_define(AOSO_DESCENT, "ABORTED", 0, 0, 0).

    aoso_state_transition(AOSO_DESCENT, "FREEFALL").
    aoso_log_info("DESCENT", "Descent guidance started in FREEFALL (surface-velocity suicide burn).").
}

FUNCTION aoso_descent_tick {
    aoso_state_update(AOSO_DESCENT).
}

FUNCTION aoso_descent_register_task {
    PARAMETER interval_s IS 0.1.
    aoso_sched_add("descent_guidance", interval_s, aoso_descent_tick@).
}