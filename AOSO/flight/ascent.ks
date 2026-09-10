// AOSO/flight/ascent.ks
// True gravity-turn ascent, then a vis-viva circularization at apoapsis.
//
// NASA, MechJeb PVG, and the GravityTurn mod all fly the same profile:
//   1. Vertical rise until there is enough speed (and Q) for the stack to
//      actually control a kick. Delay is TWR-scaled and CoM-aware: a
//      nose-heavy or long "payload on a stick" stack (Acacius: Convert-O-Tron
//      root, ISRU up top) needs 100-120 m/s, not 50, or cooked steering
//      flops it before dynamic pressure can damp the rotation.
//   2. A small pitchover (5-14 deg off vertical), ramped at ~0.5-0.8 deg/s
//      like MechJeb PVG, never an instant step.
//   3. Zero angle-of-attack on surface prograde, with a pitch floor so we
//      do not flatten to 10 deg and crawl 50-70 km at 35% throttle. Full
//      throttle until we are out of thick air; the 45 s-to-AP hold only
//      starts after that.
//   4. Once dynamic pressure drops, follow orbital prograde.
//   5. Cut when apoapsis is at target, hold it against drag until out of
//      the atmosphere, coast to AP, circularize.
//
// kOS exposes CoM for free: PART:POSITION is in SHIP-RAW, origin at the
// vessel CoM. Stack CoM fraction along UP is (0 - aft) / length: 0.5 is
// mid-stack, higher is nose-heavy.
//
// A cosine pitch-vs-altitude table is not a gravity turn: it commanded 0 deg
// at 45 km while Acacius's flight path was still 42 deg (huge AoA, drag).
// Clamping that table to FPA +/- 5 deg was also wrong: 5 deg of constant
// lead on a TWR 1.6 stack never lets gravity do the work, so the trajectory
// stays too steep and circularization costs 600+ m/s. An instant 8 deg kick
// at 50 m/s on a top-heavy stack is also wrong: prograde "catches up" because
// the nose already fell through the command.

GLOBAL AOSO_ASCENT IS aoso_state_new_machine().
GLOBAL AOSO_ASCENT_MAX_Q_SEEN IS 0.

// Surface flight-path pitch (deg above horizon): 90 straight up, 0 horizontal.
FUNCTION aoso_ascent_flight_path_pitch {
    LOCAL vel IS SHIP:VELOCITY:SURFACE.
    IF vel:MAG < 1 { RETURN 90. }
    RETURN MAX(0, MIN(90, 90 - VANG(SHIP:UP:VECTOR, vel))).
}

FUNCTION aoso_ascent_facing_pitch {
    RETURN MAX(0, MIN(90, 90 - VANG(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR))).
}

FUNCTION aoso_ascent_in_atmosphere {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    RETURN ALTITUDE < SHIP:BODY:ATM:HEIGHT.
}

// Where the CoM sits on the stack, measured while the ship is still vertical.
// PART:POSITION is relative to vessel CoM; VDOT along UP is >0 toward the
// nose and <0 toward the engines. com_frac = (0 - min) / (max - min):
//   0.5 = mid-stack, >0.58 = nose/payload-heavy, <0.42 = engine-heavy.
// length is hull span along UP in metres (long sticks need more speed too).
FUNCTION aoso_ascent_stack_layout {
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL axis IS SHIP:UP:VECTOR.
    LOCAL min_along IS 0.
    LOCAL max_along IS 0.
    LOCAL seen IS FALSE.
    FOR p IN plist {
        LOCAL along IS VDOT(p:POSITION, axis).
        IF NOT seen {
            SET min_along TO along.
            SET max_along TO along.
            SET seen TO TRUE.
        } ELSE {
            IF along < min_along { SET min_along TO along. }
            IF along > max_along { SET max_along TO along. }
        }
    }
    IF NOT seen { RETURN LEXICON("com_frac", 0.5, "length", 0). }
    LOCAL span IS max_along - min_along.
    IF span < 0.1 { RETURN LEXICON("com_frac", 0.5, "length", span). }
    RETURN LEXICON("com_frac", (0 - min_along) / span, "length", span).
}

FUNCTION aoso_ascent_cache_stack_layout {
    PARAMETER data.
    IF data:HASKEY("com_frac") {
        IF data["com_frac"] >= 0 { RETURN. }
    }
    LOCAL layout IS aoso_ascent_stack_layout().
    SET data["com_frac"] TO layout["com_frac"].
    SET data["stack_length"] TO layout["length"].
    aoso_log_info("ASCENT", "Stack CoM frac=" + ROUND(data["com_frac"], 2) + " length=" + ROUND(data["stack_length"], 1) + " m (0.5=mid, >0.58=nose-heavy).").

    // Cooked steering overshoots on long / nose-heavy stacks, especially
    // when the root part is the payload (kOS docs: put root near CoM).
    // Raise MAXSTOPPINGTIME so the PID does not snap the nose over.
    IF NOT data:HASKEY("steering_stopping_saved") {
        SET data["steering_stopping_saved"] TO STEERINGMANAGER:MAXSTOPPINGTIME.
        LOCAL stop_s IS data["steering_stopping_saved"].
        IF data["com_frac"] > 0.55 { SET stop_s TO MAX(stop_s, 6). }
        ELSE {
            IF data["stack_length"] > 16 { SET stop_s TO MAX(stop_s, 4). }
        }
        SET STEERINGMANAGER:MAXSTOPPINGTIME TO stop_s.
    }
}

FUNCTION aoso_ascent_restore_steering {
    PARAMETER data.
    IF data:HASKEY("steering_stopping_saved") {
        SET STEERINGMANAGER:MAXSTOPPINGTIME TO data["steering_stopping_saved"].
    }
}

// Follow surface velocity in the launch plane, with a pitch floor in
// atmosphere so we punch out of 50-70 km instead of flattening to 10 deg
// and crawling at 35% throttle. Orbital prograde once the air is gone.
FUNCTION aoso_ascent_follow_prograde {
    PARAMETER data.
    IF NOT aoso_ascent_in_atmosphere() {
        aoso_steer_prograde().
        RETURN.
    }

    LOCAL pitch IS aoso_ascent_flight_path_pitch().
    LOCAL floor_alt IS aoso_config_get("ASCENT_ATMO_MIN_PITCH_ALT", 55000).
    LOCAL floor_deg IS aoso_config_get("ASCENT_ATMO_MIN_PITCH", 40).
    LOCAL floor_p IS 0.
    IF ALTITUDE < floor_alt {
        SET floor_p TO floor_deg.
    } ELSE {
        // Ease 40 deg at 55 km down to 15 deg at atmosphere top.
        LOCAL span IS SHIP:BODY:ATM:HEIGHT - floor_alt.
        IF span < 1000 { SET span TO 1000. }
        LOCAL frac IS (ALTITUDE - floor_alt) / span.
        IF frac > 1 { SET frac TO 1. }
        SET floor_p TO floor_deg + ((15 - floor_deg) * frac).
        IF floor_p < 15 { SET floor_p TO 15. }
    }
    IF pitch < floor_p {
        SET pitch TO floor_p.
        IF NOT data:HASKEY("floor_logged") {
            SET data["floor_logged"] TO TRUE.
            aoso_log_info("ASCENT", "Atmo pitch floor " + ROUND(floor_p, 0) + " deg at " + ROUND(ALTITUDE, 0) + " m - punching out instead of crawling.").
        }
    }
    aoso_steer_heading_pitch(data["heading"], pitch).
}

// Pitchover magnitude (deg from vertical). Higher TWR can afford a slightly
// larger kick so the stack does not hang vertical; low TWR stays gentle so
// it does not pancake into the air. Nose-heavy / long stacks get a smaller
// kick so the ramp does not command a flop. Matches GravityTurn / MechJeb
// PVG (5-15 deg), not a 45 deg "turn".
FUNCTION aoso_ascent_pitchover_deg {
    PARAMETER com_frac IS 0.5.
    PARAMETER stack_len IS 0.
    LOCAL twr IS aoso_perf_twr().
    LOCAL base IS aoso_config_get("ASCENT_PITCHOVER_DEG", 10).
    LOCAL deg IS base.
    IF twr < 1.2 { SET deg TO MAX(5, base - 3). }
    ELSE {
        IF twr < 1.55 { SET deg TO MAX(base, 10). }
        ELSE {
            IF twr < 2.1 { SET deg TO base + 2. }
            ELSE { SET deg TO base + 6. }
        }
    }
    IF com_frac < 0.48 { SET deg TO deg + 2. }
    IF com_frac > 0.52 { SET deg TO deg - 2. }
    IF com_frac > 0.62 { SET deg TO deg - 1. }
    IF stack_len > 16 {
        IF com_frac > 0.5 { SET deg TO deg - 1. }
    }
    IF deg < 5 { SET deg TO 5. }
    IF deg > 14 { SET deg TO 14. }
    RETURN deg.
}

// Vertical-rise speed before the kick. Runtime extras apply even if a
// persisted aoso_config.json still has the old 50 m/s default: CoM and
// stack length floors are what keep a top-heavy stick from tipping at
// 50 m/s with no Q to damp it.
FUNCTION aoso_ascent_pitchover_speed {
    PARAMETER com_frac IS 0.5.
    PARAMETER stack_len IS 0.
    LOCAL twr IS aoso_perf_twr().
    LOCAL base IS aoso_config_get("ASCENT_PITCHOVER_SPEED", 80).
    LOCAL speed IS base.
    IF twr < 1.3 { SET speed TO base + 30. }
    ELSE {
        IF twr >= 1.8 { SET speed TO MAX(40, base - 15). }
    }
    IF com_frac > 0.5 { SET speed TO speed + ((com_frac - 0.5) * 250). }
    IF stack_len > 16 { SET speed TO speed + 25. }
    IF com_frac > 0.58 {
        IF speed < 110 { SET speed TO 110. }
    }
    ELSE {
        IF stack_len > 15 {
            IF speed < 90 { SET speed TO 90. }
        }
    }
    IF speed < 70 { SET speed TO 70. }
    IF speed > 140 { SET speed TO 140. }
    RETURN speed.
}

FUNCTION aoso_ascent_pitchover_min_alt {
    PARAMETER com_frac IS 0.5.
    PARAMETER stack_len IS 0.
    // Do not name this `alt` — that clobbers kOS's builtin ALT (ALT:RADAR).
    LOCAL min_alt IS aoso_config_get("ASCENT_PITCHOVER_MIN_ALT", 200).
    IF com_frac > 0.5 { SET min_alt TO min_alt + ((com_frac - 0.5) * 1200). }
    IF stack_len > 16 { SET min_alt TO min_alt + 80. }
    IF min_alt < 150 { SET min_alt TO 150. }
    IF min_alt > 500 { SET min_alt TO 500. }
    RETURN min_alt.
}

// MechJeb PVG pitch-program rate. Instant steps at low Q are what flop
// a top-heavy stack; 0.4-0.8 deg/s lets SAS/gimbal catch the rotation.
FUNCTION aoso_ascent_pitchover_rate {
    PARAMETER com_frac IS 0.5.
    PARAMETER stack_len IS 0.
    LOCAL rate IS aoso_config_get("ASCENT_PITCHOVER_RATE", 0.75).
    IF com_frac > 0.5 { SET rate TO rate - ((com_frac - 0.5) * 1.2). }
    IF stack_len > 16 {
        IF com_frac > 0.5 {
            IF rate > 0.55 { SET rate TO 0.55. }
        }
    }
    IF rate < 0.4 { SET rate TO 0.4. }
    RETURN rate.
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

// Gravity-turn throttle. Full throttle in thick air so 50-70 km is not a
// 35% crawl. The 45 s-to-AP hold only starts after we have punched out.
FUNCTION aoso_ascent_turn_throttle {
    LOCAL q_mult IS aoso_ascent_throttle_for_q().
    LOCAL target_apo IS AOSO_ASCENT["data"]["target_apo"].

    IF APOAPSIS >= target_apo {
        IF aoso_ascent_in_atmosphere() {
            IF ALTITUDE < SHIP:BODY:ATM:HEIGHT * 0.9 { RETURN MIN(0.25, q_mult). }
        }
        IF APOAPSIS < target_apo * 1.005 { RETURN MIN(0.12, q_mult). }
        RETURN 0.
    }

    IF aoso_ascent_in_atmosphere() {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT * 0.8 { RETURN q_mult. }
    }

    IF NOT aoso_ascent_in_atmosphere() { RETURN q_mult. }
    IF APOAPSIS < 2500 { RETURN q_mult. }

    LOCAL eta_ap IS ETA:APOAPSIS.
    LOCAL eta_pe IS ETA:PERIAPSIS.
    IF eta_ap > eta_pe { RETURN q_mult. }

    LOCAL hold_s IS aoso_config_get("ASCENT_HOLD_AP_S", 45).
    LOCAL err IS hold_s - eta_ap.
    LOCAL th IS 0.6 + (err * 0.02).
    IF th < 0.45 { SET th TO 0.45. }
    IF th > 1 { SET th TO 1. }
    IF th > q_mult { SET th TO q_mult. }
    RETURN th.
}

FUNCTION aoso_ascent_on_abort {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_ascent_restore_steering(data).
    aoso_state_transition(AOSO_ASCENT, "ABORTED").
}

FUNCTION aoso_ascent_liftoff_entry {
    PARAMETER data.
    SET data["ignite_attempts"] TO 0.
    SET data["thrust_since"] TO 0.
    SET data["com_frac"] TO -1.
    SET data["stack_length"] TO 0.
    SET data["pitchover_deg"] TO aoso_config_get("ASCENT_PITCHOVER_DEG", 10).
    SET data["pitchover_speed"] TO aoso_config_get("ASCENT_PITCHOVER_SPEED", 80).
    SET data["pitchover_min_alt"] TO aoso_config_get("ASCENT_PITCHOVER_MIN_ALT", 200).
    SET data["pitchover_rate"] TO aoso_config_get("ASCENT_PITCHOVER_RATE", 0.75).
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
    aoso_ascent_cache_stack_layout(data).

    SET data["pitchover_deg"] TO aoso_ascent_pitchover_deg(data["com_frac"], data["stack_length"]).
    SET data["pitchover_speed"] TO aoso_ascent_pitchover_speed(data["com_frac"], data["stack_length"]).
    SET data["pitchover_min_alt"] TO aoso_ascent_pitchover_min_alt(data["com_frac"], data["stack_length"]).
    SET data["pitchover_rate"] TO aoso_ascent_pitchover_rate(data["com_frac"], data["stack_length"]).

    IF SHIP:VELOCITY:SURFACE:MAG >= data["pitchover_speed"] {
        IF ALTITUDE > data["pitchover_min_alt"] {
            aoso_log_info("ASCENT", "Pitchover " + ROUND(data["pitchover_deg"], 1) + " deg at " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + " m/s, TWR=" + ROUND(aoso_perf_twr(), 2) + ", CoM=" + ROUND(data["com_frac"], 2) + ", len=" + ROUND(data["stack_length"], 1) + " m, rate=" + ROUND(data["pitchover_rate"], 2) + " deg/s, minAlt=" + ROUND(data["pitchover_min_alt"], 0) + ".").
            aoso_state_transition(AOSO_ASCENT, "PITCHOVER").
        }
    }
}

FUNCTION aoso_ascent_pitchover_entry {
    PARAMETER data.
    SET data["pitchover_t0"] TO TIME:SECONDS.
}

// Ramp pitch from vertical to 90-kick at pitchover_rate. Do not follow
// prograde until the *target* kick is in and FPA has caught it (comparing
// FPA to the in-progress ramp would end the kick after 1 deg). If the
// nose already fell through the command, stop kicking and lock prograde.
FUNCTION aoso_ascent_pitchover_execute {
    PARAMETER data.
    LOCAL target_cmd IS 90 - data["pitchover_deg"].
    LOCAL elapsed IS TIME:SECONDS - data["pitchover_t0"].
    LOCAL rate IS data["pitchover_rate"].
    IF rate < 0.1 { SET rate TO 0.1. }
    LOCAL cmd IS 90 - (elapsed * rate).
    IF cmd < target_cmd { SET cmd TO target_cmd. }

    aoso_steer_heading_pitch(data["heading"], cmd).
    LOCK THROTTLE TO aoso_ascent_throttle_for_q().
    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    LOCAL fpa IS aoso_ascent_flight_path_pitch().
    LOCAL facing_p IS aoso_ascent_facing_pitch().

    IF facing_p < target_cmd - 4 {
        aoso_log_warn("ASCENT", "Pitchover overshoot (facing=" + ROUND(facing_p, 1) + " deg, cmd=" + ROUND(target_cmd, 1) + ") - locking to prograde.").
        aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
        RETURN.
    }

    IF cmd <= target_cmd + 0.25 {
        IF fpa <= target_cmd + 1.5 {
            aoso_log_info("ASCENT", "Prograde caught up (FPA=" + ROUND(fpa, 1) + " deg) - zero-AoA gravity turn.").
            aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
            RETURN.
        }
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
// CIRCULARIZE with MANEUVER_ALIGN_S seconds of physics time to point the ship.
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

    // Stage the core even with throttle closed. Auto-staging refuses to
    // fire at throttle 0, which left Acacius coasting at 0.3% stage fuel
    // with eight unlit engines.
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

    // Past apoapsis: ETA:APOAPSIS jumps to a full period and we fall into
    // the atmosphere if we wait. Rails warp also refuses a PE-in-atmo
    // ellipse, so the old "WARPTO then wait for ETA:AP < 5s" never fired.
    IF ETA:APOAPSIS > ETA:PERIAPSIS {
        SET data["circ_now"] TO TRUE.
        LOCK THROTTLE TO 0.
        aoso_state_transition(AOSO_ASCENT, "CIRCULARIZE").
        RETURN.
    }

    LOCAL burn_time IS aoso_perf_burn_time_for_dv(ABS(aoso_maneuver_circularize_dv_at_apoapsis())).
    LOCAL lead_s IS burn_time / 2.
    LOCAL align_s IS aoso_maneuver_align_s().

    IF ETA:APOAPSIS > (lead_s + align_s + 5) {
        IF WARP = 0 {
            IF aoso_maneuver_can_warp() {
                WARPTO(TIME:SECONDS + ETA:APOAPSIS - (lead_s + align_s)).
            }
        }
        RETURN.
    }
    SET WARP TO 0.

    IF ETA:APOAPSIS <= (lead_s + align_s) {
        SET data["circ_now"] TO FALSE.
        LOCK THROTTLE TO 0.
        aoso_state_transition(AOSO_ASCENT, "CIRCULARIZE").
    }
}

FUNCTION aoso_ascent_circularize_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }
    IF data:HASKEY("circ_now") {
        IF data["circ_now"] {
            aoso_maneuver_add_circularize_here().
            RETURN.
        }
    }
    aoso_maneuver_add_circularize_at_apoapsis().
}

FUNCTION aoso_ascent_circularize_execute {
    PARAMETER data.
    IF aoso_maneuver_execute_next() {
        LOCAL circ_res IS aoso_maneuver_last_result().
        IF circ_res = "ok" {
            aoso_state_transition(AOSO_ASCENT, "DONE").
        } ELSE {
            aoso_log_warn("ASCENT", "Circularization " + circ_res + " - retrying.").
            IF ETA:APOAPSIS > ETA:PERIAPSIS {
                aoso_maneuver_add_circularize_here().
            } ELSE {
                aoso_maneuver_add_circularize_at_apoapsis().
            }
        }
    }
}

FUNCTION aoso_ascent_done_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_ascent_restore_steering(data).
    aoso_steer_release().
    aoso_log_info("ASCENT", "Ascent complete. Apo=" + ROUND(APOAPSIS, 0) + " Peri=" + ROUND(PERIAPSIS, 0)).
}

FUNCTION aoso_ascent_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_ascent_restore_steering(data).
    aoso_log_error("ASCENT", "Ascent aborted.").
}

FUNCTION aoso_ascent_define_states {
    aoso_state_define(AOSO_ASCENT, "LIFTOFF", aoso_ascent_liftoff_entry@, aoso_ascent_liftoff_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "PITCHOVER", aoso_ascent_pitchover_entry@, aoso_ascent_pitchover_execute@, 0, 0, 0, aoso_ascent_on_abort@).
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
    SET AOSO_ASCENT["data"] TO LEXICON(
        "heading", launch_heading,
        "target_apo", target_apo,
        "pitchover_deg", 10,
        "pitchover_speed", 80,
        "pitchover_min_alt", 200,
        "pitchover_rate", 0.75,
        "com_frac", -1,
        "stack_length", 0,
        "pitchover_t0", 0,
        "circ_now", FALSE
    ).
    aoso_log_info("ASCENT", "Profile=PITCHOVER+FLOOR+PUNCH CoM-aware ramp floor=" + ROUND(aoso_config_get("ASCENT_ATMO_MIN_PITCH", 40), 0) + "deg@" + ROUND(aoso_config_get("ASCENT_ATMO_MIN_PITCH_ALT", 55000), 0) + "m holdAP=" + ROUND(aoso_config_get("ASCENT_HOLD_AP_S", 45), 0) + "s target=" + ROUND(target_apo, 0) + "m. If this line is missing, GameData still has the old ascent.").
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
