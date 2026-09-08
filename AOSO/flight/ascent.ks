// AOSO/flight/ascent.ks
// Ascent guidance: gravity turn from ASCENT_TURN_START_ALT to
// ASCENT_TURN_END_ALT, max-Q throttle limiting, and handoff to a
// flight/maneuver.ks circularization burn. Built on core/state.ks as its own
// independent machine (AOSO_ASCENT) so it can run alongside the mission-level
// machine a later phase adds, per state.ks's own multi-machine design.

GLOBAL AOSO_ASCENT IS aoso_state_new_machine().
GLOBAL AOSO_ASCENT_MAX_Q_SEEN IS 0.

// Gravity-turn pitch (deg above horizon) for a given altitude: 90 (straight
// up) below ASCENT_TURN_START_ALT, 0 (flat) at/above ASCENT_TURN_END_ALT,
// eased between with a cosine so the turn starts gently and flattens out
// near the top rather than pitching over sharply at either boundary.
FUNCTION aoso_ascent_pitch_for_altitude {
    PARAMETER altitude_m.

    LOCAL start_alt IS aoso_config_get("ASCENT_TURN_START_ALT", 500).
    LOCAL end_alt IS aoso_config_get("ASCENT_TURN_END_ALT", 45000).

    IF altitude_m <= start_alt { RETURN 90. }
    IF altitude_m >= end_alt { RETURN 0. }

    LOCAL frac IS (altitude_m - start_alt) / (end_alt - start_alt).
    RETURN MAX(0, MIN(90, 90 * COS(frac * 90))).
}

// Throttle multiplier for max-Q limiting. Tracks the highest dynamic
// pressure (SHIP:Q) observed so far this ascent and only throttles back
// while within 10% of that running peak -- i.e. actually near max-Q --
// rather than guessing at an absolute altitude/pressure threshold, which
// would need per-vehicle/per-body tuning. Disabled (returns 1.0) whenever
// MAX_Q_LIMIT_MULT is left at its default of 1.0.
FUNCTION aoso_ascent_throttle_for_q {
    LOCAL mult IS aoso_config_get("MAX_Q_LIMIT_MULT", 1.0).
    IF mult >= 1.0 { RETURN 1.0. }

    IF SHIP:Q > AOSO_ASCENT_MAX_Q_SEEN { SET AOSO_ASCENT_MAX_Q_SEEN TO SHIP:Q. }

    IF AOSO_ASCENT_MAX_Q_SEEN > 0 AND SHIP:Q >= AOSO_ASCENT_MAX_Q_SEEN * 0.9 {
        RETURN mult.
    }
    RETURN 1.0.
}

FUNCTION aoso_ascent_on_abort {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_state_transition(AOSO_ASCENT, "ABORTED").
}

FUNCTION aoso_ascent_liftoff_entry {
    PARAMETER data.
    LOCK THROTTLE TO 1.0.
}

FUNCTION aoso_ascent_liftoff_execute {
    PARAMETER data.
    aoso_steer_heading_pitch(data["heading"], 90).
    IF DEFINED aoso_staging_auto_check { aoso_staging_auto_check(). }
    IF ALTITUDE > aoso_config_get("ASCENT_TURN_START_ALT", 500) {
        aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
    }
}

FUNCTION aoso_ascent_turn_execute {
    PARAMETER data.
    aoso_steer_heading_pitch(data["heading"], aoso_ascent_pitch_for_altitude(ALTITUDE)).
    LOCK THROTTLE TO aoso_ascent_throttle_for_q().

    IF DEFINED aoso_staging_auto_check { aoso_staging_auto_check(). }
    IF DEFINED aoso_fuel_abort_check {
        IF aoso_fuel_abort_check() {
            aoso_state_abort(AOSO_ASCENT).
            RETURN.
        }
    }

    IF APOAPSIS >= data["target_apo"] {
        LOCK THROTTLE TO 0.
        aoso_state_transition(AOSO_ASCENT, "COAST").
    }
}

FUNCTION aoso_ascent_coast_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
}

// Coasts to (just short of) apoapsis, nudging the throttle back up only if
// drag has let the apoapsis decay noticeably below target, then hands off to
// CIRCULARIZE once we're within half an estimated burn-time of apoapsis.
FUNCTION aoso_ascent_coast_execute {
    PARAMETER data.
    aoso_steer_prograde().

    IF APOAPSIS < data["target_apo"] * 0.98 {
        LOCK THROTTLE TO 0.15.
    } ELSE {
        LOCK THROTTLE TO 0.
    }

    IF DEFINED aoso_fuel_abort_check {
        IF aoso_fuel_abort_check() {
            aoso_state_abort(AOSO_ASCENT).
            RETURN.
        }
    }

    LOCAL burn_time IS 0.
    IF DEFINED aoso_perf_burn_time_for_dv {
        SET burn_time TO aoso_perf_burn_time_for_dv(ABS(aoso_maneuver_circularize_dv_at_apoapsis())).
    }

    IF ETA:APOAPSIS <= (burn_time / 2 + 5) {
        LOCK THROTTLE TO 0.
        aoso_state_transition(AOSO_ASCENT, "CIRCULARIZE").
    }
}

FUNCTION aoso_ascent_circularize_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_maneuver_add_circularize_at_apoapsis().
}

FUNCTION aoso_ascent_circularize_execute {
    PARAMETER data.
    IF aoso_maneuver_execute_next() {
        aoso_state_transition(AOSO_ASCENT, "DONE").
    }
}

FUNCTION aoso_ascent_done_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    IF DEFINED aoso_log_info {
        aoso_log_info("ASCENT", "Ascent complete. Apo=" + ROUND(APOAPSIS, 0) + " Peri=" + ROUND(PERIAPSIS, 0)).
    }
}

FUNCTION aoso_ascent_aborted_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    IF DEFINED aoso_log_error { aoso_log_error("ASCENT", "Ascent aborted."). }
}

FUNCTION aoso_ascent_define_states {
    aoso_state_define(AOSO_ASCENT, "LIFTOFF", aoso_ascent_liftoff_entry@, aoso_ascent_liftoff_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "GRAVITY_TURN", 0, aoso_ascent_turn_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "COAST", aoso_ascent_coast_entry@, aoso_ascent_coast_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "CIRCULARIZE", aoso_ascent_circularize_entry@, aoso_ascent_circularize_execute@, 0).
    aoso_state_define(AOSO_ASCENT, "DONE", aoso_ascent_done_entry@, 0, 0).
    aoso_state_define(AOSO_ASCENT, "ABORTED", aoso_ascent_aborted_entry@, 0, 0).
}

// Entry point: call once (after aoso_launch_sequence() confirms liftoff) to
// arm the gravity turn / circularization FSM, then drive it every tick with
// aoso_ascent_update() (directly, or via aoso_ascent_register_task()).
FUNCTION aoso_ascent_start {
    PARAMETER launch_heading IS 90.
    PARAMETER target_apo IS 0.
    IF target_apo <= 0 { SET target_apo TO aoso_config_get("ASCENT_TARGET_APO", 80000). }

    SET AOSO_ASCENT_MAX_Q_SEEN TO 0.
    aoso_ascent_define_states().
    SET AOSO_ASCENT["data"] TO LEXICON("heading", launch_heading, "target_apo", target_apo).
    aoso_state_transition(AOSO_ASCENT, "LIFTOFF").
}

FUNCTION aoso_ascent_update {
    aoso_state_update(AOSO_ASCENT).
}

FUNCTION aoso_ascent_register_task {
    PARAMETER interval_s IS 0.1.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("ascent_guidance", interval_s, aoso_ascent_update@).
    }
}

FUNCTION aoso_ascent_is_done {
    RETURN AOSO_ASCENT["current"] = "DONE".
}

FUNCTION aoso_ascent_is_aborted {
    RETURN AOSO_ASCENT["current"] = "ABORTED".
}
