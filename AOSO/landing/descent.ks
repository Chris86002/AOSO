// AOSO/landing/descent.ks
// Phase 6 (Landing) core: suicide-burn + final-approach descent guidance.
// Built on core/state.ks as its own independent machine (AOSO_DESCENT), the
// same pattern flight/ascent.ks uses, so ascent and descent machines can
// coexist without interfering with each other. Pure vis-viva/kinematics --
// no MechJeb dependency (see core/addons.ks) -- reusing flight/steering.ks
// for attitude and vehicle/staging.ks + vehicle/resources.ks for the same
// auto-staging/fuel-abort checks flight/ascent.ks already relies on.
//
// Scope: this handles the powered part of the descent only, from coasting
// in free-fall down through touchdown. landing/deorbit.ks is responsible
// for getting the periapsis low enough to get here, and landing/parachute.ks
// handles atmospheric deceleration before this ever needs to fire (for
// atmospheric bodies, by the time this machine's BURN state is needed,
// velocity should already be well below what the raw suicide-burn math
// assumes for an airless body).

GLOBAL AOSO_DESCENT IS aoso_state_new_machine().

// Local gravitational acceleration (m/s^2) at the current altitude, mirroring
// the g calculation vehicle/performance.ks and flight/ascent.ks already use.
FUNCTION aoso_descent_local_gravity {
    RETURN SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
}

// Maximum net deceleration (m/s^2) available straight up against gravity
// with the current stage's engines at full throttle. Returns 0 (rather than
// a negative number) when available thrust cannot even overcome gravity, so
// callers can detect "cannot stop" instead of computing a nonsensical
// negative stopping distance.
FUNCTION aoso_descent_max_deceleration {
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL accel IS SHIP:AVAILABLETHRUST / SHIP:MASS.
    RETURN MAX(0, accel - aoso_descent_local_gravity()).
}

// Kinematic stopping distance (m) to bring vertical speed v_speed (m/s,
// unsigned) to zero at constant deceleration decel (m/s^2).
FUNCTION aoso_descent_stopping_distance {
    PARAMETER v_speed.
    PARAMETER decel.
    IF decel <= 0 { RETURN -1. } // cannot stop with current thrust
    RETURN (v_speed ^ 2) / (2 * decel).
}

// Radar altitude (m) at which the suicide burn must start: the kinematic
// stopping distance for the current vertical speed plus a reaction-time
// margin (DESCENT_BURN_MARGIN_S seconds of current descent rate), so the
// scheduler's tick cadence and steering-alignment time don't eat into the
// stopping distance itself.
FUNCTION aoso_descent_burn_trigger_alt {
    LOCAL v IS ABS(VERTICALSPEED).
    LOCAL decel IS aoso_descent_max_deceleration().
    LOCAL stop_dist IS aoso_descent_stopping_distance(v, decel).
    IF stop_dist < 0 { RETURN 9E+9. } // never "safe" to wait -- burn now
    LOCAL margin_alt IS v * aoso_config_get("DESCENT_BURN_MARGIN_S", 3).
    RETURN stop_dist + margin_alt.
}

// Throttle (0-1) needed this instant to reach zero vertical speed exactly at
// the ground: solves v^2 = 2*a_net*h for the net deceleration a_net needed
// over the remaining radar altitude h, adds back local gravity to get the
// actual thrust-side acceleration required (a_net = thrust_accel - g), then
// scales by the vessel's current max acceleration.
FUNCTION aoso_descent_required_throttle {
    LOCAL h IS MAX(1, ALT:RADAR).
    LOCAL v IS ABS(VERTICALSPEED).
    LOCAL g IS aoso_descent_local_gravity().

    LOCAL a_net_needed IS (v ^ 2) / (2 * h).
    LOCAL thrust_accel_needed IS a_net_needed + g.

    LOCAL max_accel IS 0.
    IF SHIP:MASS > 0 { SET max_accel TO SHIP:AVAILABLETHRUST / SHIP:MASS. }
    IF max_accel <= 0 { RETURN 0. }

    RETURN MAX(0, MIN(1, thrust_accel_needed / max_accel)).
}

// Proportional throttle (0-1) that holds a slow, constant target descent
// rate (DESCENT_FINAL_SPEED, negative m/s) rather than braking to a full
// stop -- used once close enough to the ground that a suicide-burn's exact
// zero-at-ground solution would be too twitchy/sensitive to noise.
FUNCTION aoso_descent_final_approach_throttle {
    LOCAL target_v IS aoso_config_get("DESCENT_FINAL_SPEED", -3).
    LOCAL error IS target_v - VERTICALSPEED. // negative if descending faster than target
    LOCAL g IS aoso_descent_local_gravity().

    LOCAL kp IS 0.6.
    LOCAL accel_cmd IS g - (kp * error).

    LOCAL max_accel IS 0.
    IF SHIP:MASS > 0 { SET max_accel TO SHIP:AVAILABLETHRUST / SHIP:MASS. }
    IF max_accel <= 0 { RETURN 0. }

    RETURN MAX(0, MIN(1, accel_cmd / max_accel)).
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
}

FUNCTION aoso_descent_freefall_execute {
    PARAMETER data.
    IF DEFINED aoso_parachute_auto_check { aoso_parachute_auto_check(). }

    IF VERTICALSPEED >= 0 { RETURN. } // still climbing/coasting outward, nothing to do yet

    aoso_steer_srf_retrograde().

    IF ALT:RADAR <= aoso_descent_burn_trigger_alt() {
        aoso_state_transition(AOSO_DESCENT, "BURN").
    }
}

FUNCTION aoso_descent_burn_entry {
    PARAMETER data.
    aoso_steer_srf_retrograde().
}

FUNCTION aoso_descent_burn_execute {
    PARAMETER data.
    IF DEFINED aoso_parachute_auto_check { aoso_parachute_auto_check(). }

    aoso_steer_srf_retrograde().

    LOCK THROTTLE TO aoso_descent_required_throttle().

    IF DEFINED aoso_staging_auto_check { aoso_staging_auto_check(). }
    IF DEFINED aoso_fuel_abort_check {
        IF aoso_fuel_abort_check() {
            aoso_state_abort(AOSO_DESCENT).
            RETURN.
        }
    }

    IF ALT:RADAR <= aoso_config_get("DESCENT_FINAL_APPROACH_ALT", 150) {
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
    aoso_steer_up().
    LOCK THROTTLE TO aoso_descent_final_approach_throttle().

    IF DEFINED aoso_staging_auto_check { aoso_staging_auto_check(). }

    IF ALT:RADAR <= aoso_config_get("DESCENT_TOUCHDOWN_ALT", 0.5) OR SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
    }
}

FUNCTION aoso_descent_touchdown_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    IF DEFINED aoso_log_info { aoso_log_info("DESCENT", "Touchdown, throttle cut."). }
}

FUNCTION aoso_descent_is_landed {
    RETURN AOSO_DESCENT["current"] = "TOUCHDOWN".
}

// Wires all states into AOSO_DESCENT and starts the machine in FREEFALL.
// Call once (e.g. after a deorbit burn completes) before scheduling
// aoso_descent_tick(). No timeout is set on BURN/FINAL_APPROACH: an
// engine-out or fuel-exhaustion condition is instead handled explicitly via
// aoso_fuel_abort_check() -> aoso_state_abort(), consistent with
// flight/ascent.ks's own abort path.
FUNCTION aoso_descent_start {
    aoso_state_define(AOSO_DESCENT, "FREEFALL", aoso_descent_freefall_entry@, aoso_descent_freefall_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "BURN", aoso_descent_burn_entry@, aoso_descent_burn_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "FINAL_APPROACH", aoso_descent_final_approach_entry@, aoso_descent_final_approach_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "TOUCHDOWN", aoso_descent_touchdown_entry@, 0, 0).
    aoso_state_define(AOSO_DESCENT, "ABORTED", 0, 0, 0).

    aoso_state_transition(AOSO_DESCENT, "FREEFALL").
    IF DEFINED aoso_log_info { aoso_log_info("DESCENT", "Descent guidance started in FREEFALL."). }
}

FUNCTION aoso_descent_tick {
    aoso_state_update(AOSO_DESCENT).
}

// Wires the descent tick into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_descent_register_task {
    PARAMETER interval_s IS 0.1.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("descent_guidance", interval_s, aoso_descent_tick@).
    }
}
