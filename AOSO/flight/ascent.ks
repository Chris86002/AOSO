// AOSO/flight/ascent.ks
// True gravity-turn ascent, then a vis-viva circularization at apoapsis.
//
// NASA, MechJeb PVG, and the GravityTurn mod all fly the same profile:
//   1. Vertical rise to a few tens of m/s.
//   2. A small, fixed pitchover (5-15 deg off vertical).
//   3. Zero angle-of-attack: lock to surface prograde and let gravity
//      rotate the velocity vector toward the horizon. Throttle holds
//      time-to-apoapsis near ASCENT_HOLD_AP_S so high-TWR stacks flatten
//      instead of going vertical, and low-TWR stacks keep AP from collapsing.
//   4. Once dynamic pressure drops, follow orbital prograde.
//   5. Cut when apoapsis is at target, hold it against drag until out of
//      the atmosphere, coast to AP, circularize.
//
// A cosine pitch-vs-altitude table is not a gravity turn: it commanded 0 deg
// at 45 km while Acacius's flight path was still 42 deg (huge AoA, drag).
// Clamping that table to FPA +/- 5 deg was also wrong: 5 deg of constant
// lead on a TWR 1.6 stack never lets gravity do the work, so the trajectory
// stays too steep and circularization costs 600+ m/s.

GLOBAL AOSO_ASCENT IS aoso_state_new_machine().
GLOBAL AOSO_ASCENT_MAX_Q_SEEN IS 0.

// Surface flight-path pitch (deg above horizon): 90 straight up, 0 horizontal.
FUNCTION aoso_ascent_flight_path_pitch {
    LOCAL vel IS SHIP:VELOCITY:SURFACE.
    IF vel:MAG < 1 { RETURN 90. }
    RETURN MAX(0, MIN(90, 90 - VANG(SHIP:UP:VECTOR, vel))).
}

FUNCTION aoso_ascent_in_atmosphere {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    RETURN ALTITUDE < SHIP:BODY:ATM:HEIGHT.
}

// Follow surface velocity in the launch plane (zero AoA) while Q is still
// meaningful; orbital prograde once the air is thin. Heading is held so a
// weathercock does not walk inclination off the launch azimuth.
FUNCTION aoso_ascent_follow_prograde {
    PARAMETER data.
    LOCAL use_srf IS FALSE.
    IF aoso_ascent_in_atmosphere() {
        IF SHIP:Q > 0.02 { SET use_srf TO TRUE. }
    }
    IF use_srf {
        aoso_steer_heading_pitch(data["heading"], aoso_ascent_flight_path_pitch()).
    } ELSE {
        aoso_steer_prograde().
    }
}

// Pitchover magnitude (deg from vertical). Higher TWR can afford a slightly
// larger kick so the stack does not hang vertical; low TWR stays gentle so
// it does not pancake into the air. Matches the TWR-scaled 5-15 deg kick
// used by GravityTurn / MechJeb PVG pitch-rate, not a 45 deg "turn".
FUNCTION aoso_ascent_pitchover_deg {
    LOCAL twr IS aoso_perf_twr().
    LOCAL base IS aoso_config_get("ASCENT_PITCHOVER_DEG", 8).
    IF twr < 1.2 { RETURN MAX(5, base - 3). }
    IF twr < 1.55 { RETURN base. }
    IF twr < 2.1 { RETURN base + 2. }
    RETURN base + 6.
}

FUNCTION aoso_ascent_pitchover_speed {
    LOCAL twr IS aoso_perf_twr().
    LOCAL base IS aoso_config_get("ASCENT_PITCHOVER_SPEED", 50).
    IF twr < 1.3 { RETURN base + 30. }
    IF twr < 1.8 { RETURN base. }
    RETURN MAX(30, base - 15).
}

// Throttle multiplier for max-Q limiting. Tracks the highest dynamic
// pressure (SHIP:Q) observed so far this ascent and only throttles back
// while within 10% of that running peak. Disabled (returns 1.0) whenever
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

// Gravity-turn throttle: hold time-to-apoapsis near ASCENT_HOLD_AP_S.
// Too-long ETA:AP means the trajectory is still vertical -> throttle down
// so gravity can rotate the velocity vector. Too-short ETA:AP means the
// trajectory is flattening too fast -> throttle up to push AP out. This is
// how the GravityTurn plugin and lamont-granquist's kOS port shape the
// ascent with throttle instead of a pitch table. Floor keeps us from
// hanging in the soup; q-limit still applies.
FUNCTION aoso_ascent_turn_throttle {
    LOCAL q_mult IS aoso_ascent_throttle_for_q().
    LOCAL target_apo IS AOSO_ASCENT["data"]["target_apo"].

    IF APOAPSIS >= target_apo {
        IF APOAPSIS < target_apo * 1.005 { RETURN MIN(0.12, q_mult). }
        RETURN 0.
    }

    IF NOT aoso_ascent_in_atmosphere() { RETURN q_mult. }
    IF APOAPSIS < 2500 { RETURN q_mult. }

    LOCAL eta_ap IS ETA:APOAPSIS.
    LOCAL eta_pe IS ETA:PERIAPSIS.
    IF eta_ap > eta_pe { RETURN q_mult. }

    LOCAL hold_s IS aoso_config_get("ASCENT_HOLD_AP_S", 45).
    LOCAL err IS hold_s - eta_ap.
    LOCAL th IS 0.6 + (err * 0.02).
    IF th < 0.35 { SET th TO 0.35. }
    IF th > 1 { SET th TO 1. }
    IF th > q_mult { SET th TO q_mult. }
    RETURN th.
}

FUNCTION aoso_ascent_on_abort {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_state_transition(AOSO_ASCENT, "ABORTED").
}

FUNCTION aoso_ascent_liftoff_entry {
    PARAMETER data.
    SET data["ignite_attempts"] TO 0.
    SET data["thrust_since"] TO 0.
    SET data["pitchover_deg"] TO aoso_config_get("ASCENT_PITCHOVER_DEG", 8).
    SET data["pitchover_speed"] TO aoso_config_get("ASCENT_PITCHOVER_SPEED", 50).
    LOCK THROTTLE TO 1.0.
}

// Ignites the vehicle's engines a stage at a time. vehicle/staging.ks's
// aoso_staging_auto_check() deliberately never does this itself (it only
// advances *past* an already-lit stage that has flamed out), so without
// this, nothing ever calls the first STAGE and the vehicle sits on the pad
// forever with the throttle locked open but no thrust. Non-blocking (one
// STAGE attempt per tick, gated on STAGE:READY) per core/scheduler.ks's
// task contract, unlike flight/launch.ks's aoso_launch_ignite() which is
// meant for a pre-loop blocking countdown instead.
//
// Some vehicles release launch clamps/holds in a stage *after* engine
// ignition, so thrust alone isn't proof the vehicle is free to fly. Once
// engines are lit, this allows a few more STAGE attempts if SHIP:STATUS is
// still "PRELAUNCH" after a short grace period, instead of leaving a
// fully-throttled vehicle clamped to the pad forever. The grace period
// matters: SHIP:STATUS only flips away from "PRELAUNCH" once the vessel
// physically starts moving, which can lag ignition by a tick or two even
// on vehicles with no clamps at all, and staging early could jettison an
// unrelated stage.
FUNCTION aoso_ascent_liftoff_execute {
    PARAMETER data.

    LOCAL attempts_left IS STAGE:NUMBER > 0 AND data["ignite_attempts"] < 6.

    IF SHIP:AVAILABLETHRUST <= 0 {
        IF NOT attempts_left {
            aoso_log_error("ASCENT", "No thrust after ignition attempts - aborting ascent.").
            aoso_state_abort(AOSO_ASCENT).
            RETURN.
        }
        IF STAGE:READY {
            aoso_log_info("ASCENT", "Liftoff ignition: staging (" + STAGE:NUMBER + ").").
            STAGE.
            SET data["ignite_attempts"] TO data["ignite_attempts"] + 1.
        }
        RETURN.
    }

    IF data["thrust_since"] = 0 { SET data["thrust_since"] TO TIME:SECONDS. }

    IF SHIP:STATUS = "PRELAUNCH" AND TIME:SECONDS - data["thrust_since"] > 3 AND attempts_left {
        IF STAGE:READY {
            aoso_log_warn("ASCENT", "Still PRELAUNCH " + ROUND(TIME:SECONDS - data["thrust_since"], 1) + "s after ignition - staging (" + STAGE:NUMBER + ") to clear holds.").
            STAGE.
            SET data["ignite_attempts"] TO data["ignite_attempts"] + 1.
        }
        RETURN.
    }

    aoso_steer_heading_pitch(data["heading"], 90).
    LOCK THROTTLE TO 1.0.
    aoso_staging_auto_check().

    SET data["pitchover_deg"] TO aoso_ascent_pitchover_deg().
    SET data["pitchover_speed"] TO aoso_ascent_pitchover_speed().

    IF SHIP:VELOCITY:SURFACE:MAG >= data["pitchover_speed"] {
        IF ALTITUDE > 80 {
            aoso_log_info("ASCENT", "Pitchover " + ROUND(data["pitchover_deg"], 0) + " deg at " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + " m/s, TWR=" + ROUND(aoso_perf_twr(), 2) + ".").
            aoso_state_transition(AOSO_ASCENT, "PITCHOVER").
        }
    }
}

// Hold a fixed pitch until surface velocity catches up (MechJeb PVG
// PITCHPROGRAM -> ZEROLIFT). After that, commanding anything other than
// prograde is steering loss, not a gravity turn.
FUNCTION aoso_ascent_pitchover_execute {
    PARAMETER data.
    LOCAL cmd IS 90 - data["pitchover_deg"].
    aoso_steer_heading_pitch(data["heading"], cmd).
    LOCK THROTTLE TO aoso_ascent_throttle_for_q().
    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    LOCAL fpa IS aoso_ascent_flight_path_pitch().
    IF fpa <= cmd + 1.5 {
        aoso_log_info("ASCENT", "Prograde caught up (FPA=" + ROUND(fpa, 1) + " deg) - zero-AoA gravity turn.").
        aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
        RETURN.
    }
    IF ALTITUDE > 8000 {
        aoso_log_info("ASCENT", "Pitchover still not caught up at " + ROUND(ALTITUDE, 0) + " m - following prograde.").
        aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
    }
}

FUNCTION aoso_ascent_turn_execute {
    PARAMETER data.
    aoso_ascent_follow_prograde(data).
    LOCK THROTTLE TO aoso_ascent_turn_throttle().

    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    IF APOAPSIS < data["target_apo"] { RETURN. }

    // AP is at target. Stay in this state with the hold-AP trickle until we
    // are essentially out of the atmosphere, otherwise drag eats the AP
    // during coast and we circularize from a steep ellipse.
    IF aoso_ascent_in_atmosphere() {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT * 0.92 { RETURN. }
    }
    LOCK THROTTLE TO 0.
    aoso_state_transition(AOSO_ASCENT, "COAST").
}

FUNCTION aoso_ascent_coast_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
}

// Coasts to (just short of) apoapsis, nudging the throttle back up only if
// drag has let the apoapsis decay noticeably below target, then hands off to
// CIRCULARIZE once we're within half an estimated burn-time of apoapsis.
FUNCTION aoso_ascent_coast_execute {
    PARAMETER data.
    aoso_ascent_follow_prograde(data).

    IF APOAPSIS < data["target_apo"] * 0.98 {
        SET WARP TO 0.
        LOCK THROTTLE TO 0.2.
    } ELSE {
        LOCK THROTTLE TO 0.
    }

    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    // Never light the circularization burn inside the atmosphere.
    IF aoso_ascent_in_atmosphere() { RETURN. }

    LOCAL burn_time IS aoso_perf_burn_time_for_dv(ABS(aoso_maneuver_circularize_dv_at_apoapsis())).
    LOCAL lead_s IS burn_time / 2.

    IF ETA:APOAPSIS > (lead_s + 20) {
        IF WARP = 0 {
            IF aoso_maneuver_can_warp() {
                WARPTO(TIME:SECONDS + ETA:APOAPSIS - (lead_s + 15)).
            }
        }
        RETURN.
    }
    SET WARP TO 0.

    IF ETA:APOAPSIS <= (lead_s + 5) {
        LOCK THROTTLE TO 0.
        aoso_state_transition(AOSO_ASCENT, "CIRCULARIZE").
    }
}

FUNCTION aoso_ascent_circularize_entry {
    PARAMETER data.
    SET WARP TO 0.
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
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_log_info("ASCENT", "Ascent complete. Apo=" + ROUND(APOAPSIS, 0) + " Peri=" + ROUND(PERIAPSIS, 0)).
}

FUNCTION aoso_ascent_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_log_error("ASCENT", "Ascent aborted.").
}

FUNCTION aoso_ascent_define_states {
    aoso_state_define(AOSO_ASCENT, "LIFTOFF", aoso_ascent_liftoff_entry@, aoso_ascent_liftoff_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "PITCHOVER", 0, aoso_ascent_pitchover_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "GRAVITY_TURN", 0, aoso_ascent_turn_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "COAST", aoso_ascent_coast_entry@, aoso_ascent_coast_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "CIRCULARIZE", aoso_ascent_circularize_entry@, aoso_ascent_circularize_execute@, 0).
    aoso_state_define(AOSO_ASCENT, "DONE", aoso_ascent_done_entry@, 0, 0).
    aoso_state_define(AOSO_ASCENT, "ABORTED", aoso_ascent_aborted_entry@, 0, 0).
}

// Entry point: call once to arm the full ascent FSM (ignition, gravity
// turn, coast, circularization), then drive it every tick with
// aoso_ascent_update() (directly, or via aoso_ascent_register_task()). Safe
// to call whether or not the engines are already lit -- the LIFTOFF state
// stages until thrust is flowing before doing anything else.
FUNCTION aoso_ascent_start {
    PARAMETER launch_heading IS 90.
    PARAMETER target_apo IS 0.
    IF target_apo <= 0 { SET target_apo TO aoso_config_get("ASCENT_TARGET_APO", 80000). }

    SET AOSO_ASCENT_MAX_Q_SEEN TO 0.
    aoso_ascent_define_states().
    SET AOSO_ASCENT["data"] TO LEXICON("heading", launch_heading, "target_apo", target_apo, "pitchover_deg", 8, "pitchover_speed", 50).
    aoso_state_transition(AOSO_ASCENT, "LIFTOFF").
}

FUNCTION aoso_ascent_update {
    aoso_state_update(AOSO_ASCENT).
}

FUNCTION aoso_ascent_register_task {
    PARAMETER interval_s IS 0.1.
    aoso_sched_add("ascent_guidance", interval_s, aoso_ascent_update@).
}

FUNCTION aoso_ascent_is_done {
    RETURN AOSO_ASCENT["current"] = "DONE".
}

FUNCTION aoso_ascent_is_aborted {
    RETURN AOSO_ASCENT["current"] = "ABORTED".
}
