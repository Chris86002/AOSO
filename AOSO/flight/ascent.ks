// AOSO/flight/ascent.ks
// True gravity-turn ascent, then a vis-viva circularization at apoapsis.
//
// MechJeb Classic pitch program (MechJebModuleAscentClassicAutopilot.FlightPathAngle):
//   pitch = clamp(90 - ((alt-turnStart)/(turnEnd-turnStart))^shape * (90-turnEndAngle), 0.01, 89.99)
// Vertical while alt < turnStart OR speed < turnStartSpeed. AoA limiter (default 7 deg)
// around flight-path pitch so the nose does not yank. Out of atmosphere: orbital prograde.
// Throttle still caps TWR (default 2.2) then holds ~45 s-to-AP after the path shallows.
// Cut throttle and COAST as soon as apoapsis reaches ASCENT_TARGET_APO (80 km on Kerbin).
// Callers that pass PARKING_ORBIT_ALT (100 km) do not keep the gravity-turn burn going.
// Optimizer sweeps start speed; steering is this altitude program, not a prograde lead.
//
// Do not name locals `alt` -- that clobbers kOS's builtin ALT (ALT:RADAR).

GLOBAL AOSO_ASCENT IS aoso_state_new_machine().
GLOBAL AOSO_ASCENT_MAX_Q_SEEN IS 0.

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

FUNCTION aoso_ascent_stack_layout {
    LOCAL plist IS aoso_parts_list().
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

    // Enough slowing to not snap a long stick, not so much that a 3 deg
    // lead never appears (Acacius: MAXSTOPPINGTIME 8 left STARTTURN AoA
    // at 0.1 deg and then could not point at the circ node).
    IF NOT data:HASKEY("steering_stopping_saved") {
        SET data["steering_stopping_saved"] TO STEERINGMANAGER:MAXSTOPPINGTIME.
        SET data["steering_pitchts_saved"] TO STEERINGMANAGER:PITCHTS.
        LOCAL stop_s IS data["steering_stopping_saved"].
        LOCAL pitch_ts IS data["steering_pitchts_saved"].
        IF data["stack_length"] > 16 {
            SET stop_s TO MAX(stop_s, 3.0).
            SET pitch_ts TO MAX(pitch_ts, 2.4).
        }
        IF data["stack_length"] > 30 {
            SET stop_s TO MAX(stop_s, 3.0).
            SET pitch_ts TO MAX(pitch_ts, 2.4).
        }
        IF data["com_frac"] > 0.55 {
            SET stop_s TO MAX(stop_s, 3.0).
            SET pitch_ts TO MAX(pitch_ts, 2.4).
        }
        IF stop_s > 3.2 { SET stop_s TO 3.2. }
        SET STEERINGMANAGER:MAXSTOPPINGTIME TO stop_s.
        SET STEERINGMANAGER:PITCHTS TO pitch_ts.
    }
}

FUNCTION aoso_ascent_restore_steering {
    PARAMETER data.
    IF data:HASKEY("steering_stopping_saved") {
        SET STEERINGMANAGER:MAXSTOPPINGTIME TO data["steering_stopping_saved"].
    }
    IF data:HASKEY("steering_pitchts_saved") {
        SET STEERINGMANAGER:PITCHTS TO data["steering_pitchts_saved"].
    }
}

FUNCTION aoso_ascent_turn_blend_s {
    PARAMETER stack_len IS 0.
    LOCAL blend IS aoso_config_get("ASCENT_TURN_BLEND_S", 8).
    IF stack_len > 30 { SET blend TO blend + 2. }
    IF blend < 6 { SET blend TO 6. }
    IF blend > 12 { SET blend TO 12. }
    RETURN blend.
}

FUNCTION aoso_ascent_turn_start_alt {
    PARAMETER com_frac IS 0.5.
    PARAMETER stack_len IS 0.
    LOCAL start_a IS aoso_config_get("ASCENT_TURN_START_ALT", 1000).
    LOCAL twr IS aoso_perf_twr().
    IF twr < 1.35 { SET start_a TO start_a + 400. }
    IF stack_len > 30 { SET start_a TO start_a + 300. }
    IF com_frac > 0.55 { SET start_a TO start_a + 250. }
    IF start_a < 400 { SET start_a TO 400. }
    IF start_a > 2500 { SET start_a TO 2500. }
    RETURN start_a.
}

FUNCTION aoso_ascent_turn_end_alt {
    LOCAL end_a IS aoso_config_get("ASCENT_TURN_END_ALT", 0).
    IF end_a > 0 { RETURN end_a. }
    IF SHIP:BODY:ATM:EXISTS { RETURN 0.93 * SHIP:BODY:ATM:HEIGHT. }
    RETURN 30000.
}

FUNCTION aoso_ascent_turn_shape {
    LOCAL s IS aoso_config_get("ASCENT_TURN_SHAPE", 0.45).
    IF s < 0.25 { SET s TO 0.25. }
    IF s > 0.8 { SET s TO 0.8. }
    RETURN s.
}

FUNCTION aoso_ascent_max_aoa {
    LOCAL a IS aoso_config_get("ASCENT_MAX_AOA", 7).
    IF a < 3 { SET a TO 3. }
    IF a > 15 { SET a TO 15. }
    RETURN a.
}

FUNCTION aoso_ascent_program_pitch {
    PARAMETER data.
    LOCAL alt_now IS ALTITUDE.
    LOCAL spd IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL start_alt IS 1000.
    IF data:HASKEY("turn_start_alt") { SET start_alt TO data["turn_start_alt"]. }
    LOCAL start_spd IS 80.
    IF data:HASKEY("pitchover_speed") { SET start_spd TO data["pitchover_speed"]. }
    IF alt_now < start_alt { RETURN 90. }
    IF spd < start_spd { RETURN 90. }
    LOCAL t0 IS start_alt.
    IF data:HASKEY("turn_alt0") {
        IF data["turn_alt0"] > t0 { SET t0 TO data["turn_alt0"]. }
    }
    LOCAL end_alt IS 65000.
    IF data:HASKEY("turn_end_alt") {
        IF data["turn_end_alt"] > 0 { SET end_alt TO data["turn_end_alt"]. }
    }
    LOCAL end_ang IS 0.
    IF data:HASKEY("turn_end_angle") { SET end_ang TO data["turn_end_angle"]. }
    IF alt_now >= end_alt { RETURN end_ang. }
    LOCAL span IS end_alt - t0.
    IF span < 100 { RETURN end_ang. }
    LOCAL frac IS (alt_now - t0) / span.
    IF frac < 0 { SET frac TO 0. }
    IF frac > 1 { SET frac TO 1. }
    LOCAL shape IS 0.45.
    IF data:HASKEY("turn_shape") { SET shape TO data["turn_shape"]. }
    LOCAL shaped IS frac ^ shape.
    LOCAL p IS 90 - shaped * (90 - end_ang).
    IF p < 0.01 { SET p TO 0.01. }
    IF p > 89.99 { SET p TO 89.99. }
    RETURN p.
}

FUNCTION aoso_ascent_steer {
    PARAMETER data.
    IF aoso_ascent_in_atmosphere() {
        LOCAL cmd IS aoso_ascent_program_pitch(data).
        LOCAL fpa IS aoso_ascent_flight_path_pitch().
        LOCAL max_aoa IS aoso_ascent_max_aoa().
        LOCAL lo IS fpa - max_aoa.
        LOCAL hi IS fpa + max_aoa.
        IF cmd < lo { SET cmd TO lo. }
        IF cmd > hi { SET cmd TO hi. }
        IF cmd < 0 { SET cmd TO 0. }
        IF cmd > 90 { SET cmd TO 90. }
        aoso_steer_heading_pitch(data["heading"], cmd).
    } ELSE {
        aoso_steer_prograde().
    }
}

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
    IF stack_len > 16 {
        IF com_frac > 0.5 { SET speed TO speed + 25. }
    }
    IF com_frac > 0.58 {
        IF speed < 110 { SET speed TO 110. }
    } ELSE {
        IF stack_len > 15 {
            IF com_frac > 0.5 {
                IF speed < 90 { SET speed TO 90. }
            }
        }
    }
    IF com_frac < 0.45 {
        IF speed > 90 { SET speed TO 90. }
    }
    IF speed < 70 { SET speed TO 70. }
    IF speed > 140 { SET speed TO 140. }
    RETURN speed.
}

FUNCTION aoso_ascent_pitchover_min_alt {
    PARAMETER com_frac IS 0.5.
    PARAMETER stack_len IS 0.
    LOCAL min_alt IS aoso_config_get("ASCENT_PITCHOVER_MIN_ALT", 200).
    IF com_frac > 0.5 { SET min_alt TO min_alt + ((com_frac - 0.5) * 1200). }
    IF stack_len > 16 {
        IF com_frac > 0.5 { SET min_alt TO min_alt + 80. }
    }
    IF min_alt < 150 { SET min_alt TO 150. }
    IF min_alt > 500 { SET min_alt TO 500. }
    RETURN min_alt.
}

FUNCTION aoso_ascent_throttle_for_q {
    LOCAL cap IS aoso_config_get("ASCENT_MAX_Q", 0.30).
    LOCAL qnow IS SHIP:Q.
    IF qnow > AOSO_ASCENT_MAX_Q_SEEN { SET AOSO_ASCENT_MAX_Q_SEEN TO qnow. }

    LOCAL th IS 1.
    IF cap > 0 {
        IF qnow > cap * 0.85 {
            SET th TO cap / MAX(qnow, 0.001).
            IF th < 0.35 { SET th TO 0.35. }
            IF th > 1 { SET th TO 1. }
            aoso_log_every(8, "ASCENT", "Max-Q throttle Q=" + ROUND(qnow, 3) + " cap=" + ROUND(cap, 3) +
                " th=" + ROUND(th, 2) + " AoA=" + ROUND(aoso_aero_aoa(), 1) + " deg drag=" +
                ROUND(aoso_aero_drag_kn(), 1) + " kN (" + aoso_aero_drag_source() + ").").
        }
    }

    LOCAL mult IS AOSO_CONFIG["MAX_Q_LIMIT_MULT"].
    IF mult < 1.0 {
        IF AOSO_ASCENT_MAX_Q_SEEN > 0 {
            IF qnow >= AOSO_ASCENT_MAX_Q_SEEN * 0.9 {
                IF th > mult { SET th TO mult. }
            }
        }
    }
    RETURN th.
}

// TWR cap so gravity can turn a high-thrust stack, then the 45 s-to-AP hold.
FUNCTION aoso_ascent_twr_throttle {
    LOCAL twr IS aoso_perf_twr().
    LOCAL lim IS AOSO_CONFIG["ASCENT_TWR_LIMIT"].
    IF lim < 1.3 { SET lim TO 1.3. }
    IF lim > 2.4 { SET lim TO 2.4. }
    IF twr <= lim { RETURN 1. }
    LOCAL th IS lim / twr.
    IF th < 0.40 { SET th TO 0.40. }
    IF th > 1 { SET th TO 1. }
    RETURN th.
}

FUNCTION aoso_ascent_turn_throttle {
    LOCAL q_mult IS aoso_ascent_throttle_for_q().
    LOCAL twr_th IS aoso_ascent_twr_throttle().
    LOCAL target_apo IS AOSO_ASCENT["data"]["target_apo"].

    // Hard cut at the ascent target. A 25% trickle until 0.9*atm was why
    // Acacius rode 43 km apo at 38 km alt up to 476 km by the time it
    // left dense air. Drag hold belongs in COAST, not here.
    IF APOAPSIS >= target_apo { RETURN 0. }

    LOCAL fpa IS aoso_ascent_flight_path_pitch().
    // Steep + in air: TWR cap is the only loft lever. Full throttle here
    // is why Acacius lofted (TWR 2.6, FPA 83 deg at 30 km).
    IF aoso_ascent_in_atmosphere() {
        IF fpa > 42 {
            RETURN MIN(q_mult, twr_th).
        }
    }

    IF NOT aoso_ascent_in_atmosphere() { RETURN MIN(q_mult, twr_th). }
    IF APOAPSIS < 2500 { RETURN MIN(q_mult, twr_th). }

    LOCAL eta_ap IS ETA:APOAPSIS.
    LOCAL eta_pe IS ETA:PERIAPSIS.
    IF eta_ap > eta_pe { RETURN MIN(q_mult, twr_th). }

    LOCAL hold_s IS AOSO_CONFIG["ASCENT_HOLD_AP_S"].
    LOCAL err IS hold_s - eta_ap.
    LOCAL th IS 0.6 + (err * 0.02).
    IF th < 0.35 { SET th TO 0.35. }
    IF th > 1 { SET th TO 1. }
    IF th > q_mult { SET th TO q_mult. }
    IF th > twr_th { SET th TO twr_th. }
    RETURN th.
}

FUNCTION aoso_ascent_profile_name {
    LOCAL spd IS 0.
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["data"]:HASKEY("pitchover_speed") {
            SET spd TO AOSO_ASCENT["data"]["pitchover_speed"].
        }
    }
    RETURN "MJCL/s" + ROUND(spd, 0).
}

FUNCTION aoso_ascent_snapshot_pad {
    PARAMETER data.
    IF data:HASKEY("pad_lf") { RETURN. }
    SET data["pad_lf"] TO aoso_resource_amount("LiquidFuel").
    SET data["pad_ox"] TO aoso_resource_amount("Oxidizer").
    SET data["pad_mass"] TO SHIP:MASS.
    SET data["pad_ut"] TO TIME:SECONDS.
    aoso_log_info("ASCENT", "Pad snapshot LF=" + ROUND(data["pad_lf"], 1) + " Ox=" + ROUND(data["pad_ox"], 1) + " mass=" + ROUND(data["pad_mass"], 2) + " t.").
}

FUNCTION aoso_ascent_persist_run {
    PARAMETER data.
    LOCAL lf IS aoso_resource_amount("LiquidFuel").
    LOCAL ox IS aoso_resource_amount("Oxidizer").
    LOCAL pad_lf IS 0.
    IF data:HASKEY("pad_lf") { SET pad_lf TO data["pad_lf"]. }
    LOCAL used_lf IS pad_lf - lf.
    LOCAL circ_dv IS 0.
    IF data:HASKEY("circ_dv") { SET circ_dv TO data["circ_dv"]. }
    LOCAL profile IS aoso_ascent_profile_name().
    LOCAL rec IS LEXICON(
        "ut", TIME:SECONDS,
        "body", SHIP:BODY:NAME,
        "profile", profile,
        "pad_lf", pad_lf,
        "orbit_lf", lf,
        "used_lf", used_lf,
        "orbit_ox", ox,
        "apo", APOAPSIS,
        "peri", PERIAPSIS,
        "circ_dv", circ_dv,
        "com_frac", data["com_frac"],
        "turn_speed", data["pitchover_speed"],
        "turn_blend_s", data["turn_blend_s"],
        "mass", SHIP:MASS
    ).

    LOCAL runs_path IS AOSO_CONST["ASCENT_RUNS_FILE"].
    LOCAL store IS aoso_json_read_persistent(
        runs_path,
        AOSO_CONST["ASCENT_RUNS_ARCHIVE_FILE"],
        LEXICON("runs", LIST(), "best", LEXICON())
    ).
    IF NOT store:ISTYPE("Lexicon") { SET store TO LEXICON("runs", LIST(), "best", LEXICON()). }
    IF NOT store:HASKEY("runs") { SET store["runs"] TO LIST(). }
    IF NOT store:HASKEY("best") { SET store["best"] TO LEXICON(). }

    store["runs"]:ADD(rec).
    UNTIL store["runs"]:LENGTH <= 15 {
        store["runs"]:REMOVE(0).
    }

    LOCAL stable IS TRUE.
    IF SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT + 5000 { SET stable TO FALSE. }
    } ELSE {
        IF PERIAPSIS < 5000 { SET stable TO FALSE. }
    }
    SET rec["stable"] TO stable.

    LOCAL best_line IS "no previous best".
    IF stable {
        LOCAL body_name IS SHIP:BODY:NAME.
        LOCAL prev IS 0.
        IF store["best"]:HASKEY(body_name) { SET prev TO store["best"][body_name]. }
        LOCAL is_best IS FALSE.
        IF NOT prev:ISTYPE("Lexicon") {
            SET is_best TO TRUE.
        } ELSE {
            IF NOT prev:HASKEY("orbit_lf") {
                SET is_best TO TRUE.
            } ELSE {
                IF lf > prev["orbit_lf"] { SET is_best TO TRUE. }
            }
        }
        IF is_best {
            LOCAL best_map IS store["best"].
            SET best_map[body_name] TO rec.
            SET best_line TO "NEW BEST for " + body_name + " (LF remaining " + ROUND(lf, 1) + ").".
        } ELSE {
            SET best_line TO "best so far: profile=" + prev["profile"] + " orbit_lf=" + ROUND(prev["orbit_lf"], 1) +
                " used_lf=" + ROUND(prev["used_lf"], 1) + " circ_dv=" + ROUND(prev["circ_dv"], 1) +
                " " + ROUND(prev["apo"], 0) + "x" + ROUND(prev["peri"], 0) + "m.".
        }
    } ELSE {
        SET best_line TO "orbit not stable, not ranked.".
    }

    aoso_ascent_opt_commit(rec).
    IF rec:HASKEY("phases") { rec:REMOVE("phases"). }
    FOR r IN store["runs"] {
        IF r:ISTYPE("Lexicon") {
            IF r:HASKEY("phases") { r:REMOVE("phases"). }
        }
    }
    IF store["best"]:ISTYPE("Lexicon") {
        FOR bk IN store["best"]:KEYS {
            LOCAL b IS store["best"][bk].
            IF b:ISTYPE("Lexicon") {
                IF b:HASKEY("phases") { b:REMOVE("phases"). }
            }
        }
    }
    aoso_json_write_persistent(runs_path, AOSO_CONST["ASCENT_RUNS_ARCHIVE_FILE"], store).
    aoso_learn_record_ascent(rec).
    aoso_log_info("ASCENT", "Fuel-to-orbit profile=" + profile + " pad_lf=" + ROUND(pad_lf, 1) +
        " orbit_lf=" + ROUND(lf, 1) + " used_lf=" + ROUND(used_lf, 1) +
        " circ_dv=" + ROUND(circ_dv, 1) + " m/s apo=" + ROUND(APOAPSIS, 0) +
        " peri=" + ROUND(PERIAPSIS, 0) + " - " + best_line).
}

FUNCTION aoso_ascent_on_abort {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_ascent_restore_steering(data).
    aoso_state_transition(AOSO_ASCENT, "ABORTED").
}

FUNCTION aoso_ascent_liftoff_entry {
    PARAMETER data.
    SET data["ignite_attempts"] TO 0.
    SET data["thrust_since"] TO 0.
    SET data["com_frac"] TO -1.
    SET data["stack_length"] TO 0.
    SET data["pitchover_speed"] TO aoso_config_get("ASCENT_PITCHOVER_SPEED", 80).
    SET data["pitchover_min_alt"] TO aoso_config_get("ASCENT_PITCHOVER_MIN_ALT", 200).
    SET data["turn_blend_s"] TO aoso_config_get("ASCENT_TURN_BLEND_S", 8).
    SET data["turn_start_alt"] TO aoso_config_get("ASCENT_TURN_START_ALT", 1000).
    SET data["turn_end_alt"] TO aoso_ascent_turn_end_alt().
    SET data["turn_shape"] TO aoso_ascent_turn_shape().
    SET data["turn_end_angle"] TO aoso_config_get("ASCENT_TURN_END_ANGLE", 0).
    SET data["turn_alt0"] TO 0.
    SET data["loft_flagged"] TO FALSE.
    aoso_throttle_set(1).
}

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
            aoso_staging_after_stage().
            SET data["ignite_attempts"] TO data["ignite_attempts"] + 1.
        }
        RETURN.
    }

    IF data["thrust_since"] = 0 { SET data["thrust_since"] TO TIME:SECONDS. }

    IF SHIP:STATUS = "PRELAUNCH" AND TIME:SECONDS - data["thrust_since"] > 3 AND attempts_left {
        IF STAGE:READY {
            aoso_log_warn("ASCENT", "Still PRELAUNCH " + ROUND(TIME:SECONDS - data["thrust_since"], 1) + "s after ignition - staging (" + STAGE:NUMBER + ") to clear holds.").
            STAGE.
            aoso_staging_after_stage().
            SET data["ignite_attempts"] TO data["ignite_attempts"] + 1.
        }
        RETURN.
    }

    aoso_steer_heading_pitch(data["heading"], 90).
    aoso_throttle_set(1).
    aoso_staging_auto_check().
    IF SHIP:VELOCITY:SURFACE:MAG > 5 {
        aoso_ascent_cache_stack_layout(data).
        aoso_ascent_snapshot_pad(data).

        SET data["pitchover_speed"] TO aoso_ascent_pitchover_speed(data["com_frac"], data["stack_length"]).
        SET data["pitchover_min_alt"] TO aoso_ascent_pitchover_min_alt(data["com_frac"], data["stack_length"]).
        SET data["turn_blend_s"] TO aoso_ascent_turn_blend_s(data["stack_length"]).
        SET data["turn_start_alt"] TO aoso_ascent_turn_start_alt(data["com_frac"], data["stack_length"]).
        SET data["turn_end_alt"] TO aoso_ascent_turn_end_alt().
        SET data["turn_shape"] TO aoso_ascent_turn_shape().
        SET data["turn_end_angle"] TO aoso_config_get("ASCENT_TURN_END_ANGLE", 0).
        IF AOSO_ASCENT_OPT["applied_speed"] < 0 {
            aoso_ascent_opt_apply(data).
        } ELSE {
            SET data["pitchover_speed"] TO AOSO_ASCENT_OPT["applied_speed"].
        }
    }

    IF SHIP:VELOCITY:SURFACE:MAG >= data["pitchover_speed"] {
        IF ALTITUDE > data["pitchover_min_alt"] {
            SET data["turn_alt0"] TO ALTITUDE.
            aoso_log_info("ASCENT", "Gravity turn at " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + " m/s, MJ-classic startAlt=" + ROUND(data["turn_start_alt"], 0) + " endAlt=" + ROUND(data["turn_end_alt"], 0) + " shape=" + ROUND(data["turn_shape"], 2) + " maxAoA=" + ROUND(aoso_ascent_max_aoa(), 1) + " TWR cap=" + ROUND(aoso_config_get("ASCENT_TWR_LIMIT", 2.2), 2) + ", TWR=" + ROUND(aoso_perf_twr(), 2) + ", CoM=" + ROUND(data["com_frac"], 2) + ", len=" + ROUND(data["stack_length"], 1) + " m.").
            aoso_log_info("ASCENT", "Aero source=" + aoso_aero_drag_source() + " Q=" + ROUND(SHIP:Q, 3) +
                " cap=" + ROUND(aoso_config_get("ASCENT_MAX_Q", 0.30), 3) + " AoA=" + ROUND(aoso_aero_aoa(), 1) +
                " deg drag=" + ROUND(aoso_aero_drag_kn(), 1) + " kN.").
            aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
        }
    }
}

FUNCTION aoso_ascent_turn_entry {
    PARAMETER data.
    IF data["turn_t0"] = 0 {
        SET data["turn_t0"] TO TIME:SECONDS.
    }
    IF NOT data:HASKEY("turn_alt0") {
        SET data["turn_alt0"] TO ALTITUDE.
    } ELSE {
        IF data["turn_alt0"] = 0 { SET data["turn_alt0"] TO ALTITUDE. }
    }
}

FUNCTION aoso_ascent_turn_execute {
    PARAMETER data.
    aoso_ascent_steer(data).
    aoso_throttle_set(aoso_ascent_turn_throttle()).

    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    IF NOT data:HASKEY("loft_flagged") { SET data["loft_flagged"] TO FALSE. }
    IF NOT data["loft_flagged"] {
        IF ALTITUDE > 25000 {
            LOCAL fpa_now IS aoso_ascent_flight_path_pitch().
            IF fpa_now > 75 {
                SET data["loft_flagged"] TO TRUE.
                aoso_observe_anomaly("LOFT", "HIGH", 45, fpa_now).
            }
        }
    }

    IF APOAPSIS < data["target_apo"] { RETURN. }

    // Coast as soon as apo is at the target, even still in atmosphere.
    // Waiting for 0.92*atm kept the gravity-turn burn alive and lofted
    // apo from ~80 km to hundreds of km on the way out of the air.
    aoso_throttle_set(0).
    aoso_log_info("ASCENT", "Apo " + ROUND(APOAPSIS, 0) + "m >= target " + ROUND(data["target_apo"], 0) + "m - cutting throttle, coasting (pitch program unchanged).").
    aoso_state_transition(AOSO_ASCENT, "COAST").
}

FUNCTION aoso_ascent_coast_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_ascent_restore_steering(data).
    aoso_steer_prepare_for_burn().
}

FUNCTION aoso_ascent_coast_execute {
    PARAMETER data.
    IF aoso_ascent_in_atmosphere() {
        aoso_ascent_steer(data).
        aoso_staging_auto_check().
        IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }
        IF APOAPSIS < data["target_apo"] {
            SET WARP TO 0.
            aoso_throttle_set(0.12).
        } ELSE {
            aoso_throttle_set(0).
            IF ALTITUDE > aoso_config_get("ASCENT_DENSE_ALT", 40000) {
                aoso_warp_set_physics_cruise().
            }
        }
        IF aoso_fuel_abort_check() {
            aoso_state_abort(AOSO_ASCENT).
            RETURN.
        }
        RETURN.
    }

    // Space: jettison the airstream shell and extend panels. Do not wait
    // for the shedable power task -- CPU HIGH during coast used to skip
    // this until Minmus.
    aoso_power_on_space().

    // Circularization attitude: east and horizontal. Prograde while
    // still climbing is pitched up; rails warp then freezes the wrong
    // inertial facing. Point at the burn before we warp.
    aoso_steer_heading_pitch(data["heading"], 0).
    aoso_staging_auto_check().
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

    // Hold the ascent target against drag; never push apo past it.
    IF APOAPSIS < data["target_apo"] {
        SET WARP TO 0.
        aoso_throttle_set(0.12).
    } ELSE {
        aoso_throttle_set(0).
    }

    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    IF ETA:APOAPSIS > ETA:PERIAPSIS {
        SET data["circ_now"] TO TRUE.
        aoso_throttle_set(0).
        aoso_state_transition(AOSO_ASCENT, "CIRCULARIZE").
        RETURN.
    }

    LOCAL burn_time IS aoso_perf_burn_time_for_dv(ABS(aoso_maneuver_circularize_dv_at_apoapsis())).
    LOCAL lead_s IS burn_time / 2.
    LOCAL align_s IS aoso_maneuver_align_s().

    IF ETA:APOAPSIS > (lead_s + align_s + 5) {
        LOCAL wst IS aoso_warp_approach(ETA:APOAPSIS, lead_s + align_s, lead_s + aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
        RETURN.
    }
    SET WARP TO 0.

    IF ETA:APOAPSIS <= (lead_s + align_s) {
        SET data["circ_now"] TO FALSE.
        aoso_throttle_set(0).
        aoso_state_transition(AOSO_ASCENT, "CIRCULARIZE").
    }
}

FUNCTION aoso_ascent_circularize_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_ascent_restore_steering(data).
    aoso_steer_prepare_for_burn().
    aoso_power_on_space().
    aoso_staging_auto_check().
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }
    IF data:HASKEY("circ_now") {
        IF data["circ_now"] {
            aoso_maneuver_add_circularize_here().
            SET data["circ_dv"] TO ABS(aoso_maneuver_circularize_dv_at_apoapsis()).
            RETURN.
        }
    }
    aoso_maneuver_add_circularize_at_apoapsis().
    SET data["circ_dv"] TO ABS(aoso_maneuver_circularize_dv_at_apoapsis()).
}

FUNCTION aoso_ascent_circularize_execute {
    PARAMETER data.

    // Lofted sounding-rocket fallback: stop retrying nodes while falling
    // through the atmosphere. Commit the trial so the optimizer drops it.
    IF aoso_ascent_in_atmosphere() {
        IF VERTICALSPEED < -20 {
            IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT {
                aoso_log_error("ASCENT", "Circularization failed - falling back into atmosphere (apo=" + ROUND(APOAPSIS, 0) + " peri=" + ROUND(PERIAPSIS, 0) + ").").
                aoso_state_abort(AOSO_ASCENT).
                RETURN.
            }
        }
    }

    IF aoso_maneuver_execute_next() {
        LOCAL circ_res IS aoso_maneuver_last_result().
        LOCAL pe_ok IS TRUE.
        IF SHIP:BODY:ATM:EXISTS {
            IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT + 2000 { SET pe_ok TO FALSE. }
        }
        IF circ_res = "ok" {
            IF pe_ok {
                aoso_state_transition(AOSO_ASCENT, "DONE").
            } ELSE {
                aoso_log_warn("ASCENT", "Circularization cut with peri still in atmosphere (apo=" + ROUND(APOAPSIS, 0) + " peri=" + ROUND(PERIAPSIS, 0) + ") - retrying.").
                SET circ_res TO "incomplete".
            }
        }
        IF circ_res <> "ok" {
            aoso_log_warn("ASCENT", "Circularization " + circ_res + " - retrying.").
            LOCAL park IS aoso_config_get("ASCENT_TARGET_APO", 80000).
            IF APOAPSIS > park * 1.35 {
                aoso_log_warn("ASCENT", "Apo lofted to " + ROUND(APOAPSIS, 0) + "m - dropping it back to " + ROUND(park, 0) + "m at periapsis instead of circularizing up there.").
                aoso_hohmann_add_apoapsis_change(park).
            } ELSE {
                IF ETA:APOAPSIS > ETA:PERIAPSIS {
                    aoso_maneuver_add_circularize_here().
                } ELSE {
                    aoso_maneuver_add_circularize_at_apoapsis().
                }
            }
        }
    }
}

FUNCTION aoso_ascent_done_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_ascent_restore_steering(data).
    aoso_steer_release().
    aoso_log_info("ASCENT", "Ascent complete. Apo=" + ROUND(APOAPSIS, 0) + " Peri=" + ROUND(PERIAPSIS, 0)).
    aoso_ascent_persist_run(data).
    LOCAL res IS aoso_result_make("ASCENT", "SUCCESS", "orbit").
    IF data:HASKEY("pad_lf") {
        SET res["actual_fuel"] TO aoso_resource_amount("LiquidFuel").
        SET res["fuel_used"] TO data["pad_lf"] - res["actual_fuel"].
    }
    IF data:HASKEY("circ_dv") { SET res["actual_dv"] TO data["circ_dv"]. }
    aoso_result_emit(res).
    IF data:HASKEY("circ_dv") {
        IF data["circ_dv"] > 1 {
            aoso_xp_record("CIRCULARIZATION", SHIP:BODY:NAME, 80, data["circ_dv"], FALSE).
        }
    }
    aoso_event_publish("ORBIT_ACHIEVED", "ascent", SHIP:BODY:NAME).
}

FUNCTION aoso_ascent_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_ascent_restore_steering(data).
    aoso_log_error("ASCENT", "Ascent aborted.").
    IF AOSO_ASCENT_OPT["applied_speed"] >= 0 {
        LOCAL rec IS LEXICON(
            "ut", TIME:SECONDS,
            "body", SHIP:BODY:NAME,
            "profile", aoso_ascent_profile_name(),
            "pad_lf", 0,
            "orbit_lf", aoso_resource_amount("LiquidFuel"),
            "used_lf", 0,
            "circ_dv", 9999,
            "apo", APOAPSIS,
            "peri", PERIAPSIS,
            "turn_speed", data["pitchover_speed"],
            "turn_blend_s", data["turn_blend_s"],
            "stable", FALSE
        ).
        IF data:HASKEY("pad_lf") {
            SET rec["pad_lf"] TO data["pad_lf"].
            SET rec["used_lf"] TO rec["pad_lf"] - rec["orbit_lf"].
        }
        IF data:HASKEY("circ_dv") {
            IF data["circ_dv"] > 0 { SET rec["circ_dv"] TO data["circ_dv"]. }
        }
        aoso_ascent_opt_commit(rec).
    }
    LOCAL res_a IS aoso_result_make("ASCENT", "ABORTED", "aborted").
    IF data:HASKEY("pad_lf") {
        SET res_a["actual_fuel"] TO aoso_resource_amount("LiquidFuel").
        SET res_a["fuel_used"] TO data["pad_lf"] - res_a["actual_fuel"].
    }
    aoso_result_emit(res_a).
}

FUNCTION aoso_ascent_define_states {
    aoso_state_define(AOSO_ASCENT, "LIFTOFF", aoso_ascent_liftoff_entry@, aoso_ascent_liftoff_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "GRAVITY_TURN", aoso_ascent_turn_entry@, aoso_ascent_turn_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "COAST", aoso_ascent_coast_entry@, aoso_ascent_coast_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "CIRCULARIZE", aoso_ascent_circularize_entry@, aoso_ascent_circularize_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "DONE", aoso_ascent_done_entry@, 0, 0).
    aoso_state_define(AOSO_ASCENT, "ABORTED", aoso_ascent_aborted_entry@, 0, 0).
}

FUNCTION aoso_ascent_resolve_target {
    PARAMETER requested IS 0.
    LOCAL apo_tgt IS aoso_config_get("ASCENT_TARGET_APO", 80000).
    IF apo_tgt < 10000 { SET apo_tgt TO 80000. }

    IF SHIP:BODY:ATM:EXISTS {
        LOCAL floor_apo IS SHIP:BODY:ATM:HEIGHT + 10000.
        IF apo_tgt < floor_apo { SET apo_tgt TO floor_apo. }
        // Tour/goto pass PARKING_ORBIT_ALT (100 km). Atmospheric ascent
        // burns to ASCENT_TARGET_APO (80 km on Kerbin), not parking.
        RETURN apo_tgt.
    }

    IF requested > 0 { RETURN requested. }
    RETURN apo_tgt.
}

FUNCTION aoso_ascent_start {
    PARAMETER launch_heading IS 90.
    PARAMETER target_apo IS 0.
    SET target_apo TO aoso_ascent_resolve_target(target_apo).

    SET AOSO_ASCENT_MAX_Q_SEEN TO 0.
    aoso_ascent_opt_begin().
    aoso_ascent_define_states().
    SET AOSO_ASCENT["data"] TO LEXICON(
        "heading", launch_heading,
        "target_apo", target_apo,
        "pitchover_speed", 80,
        "pitchover_min_alt", 200,
        "turn_blend_s", 8,
        "turn_t0", 0,
        "turn_alt0", 0,
        "turn_start_alt", 1000,
        "turn_end_alt", 0,
        "turn_shape", 0.45,
        "turn_end_angle", 0,
        "loft_flagged", FALSE,
        "com_frac", -1,
        "stack_length", 0,
        "circ_now", FALSE,
        "circ_dv", 0
    ).
    LOCAL shape_now IS aoso_ascent_turn_shape().
    LOCAL start_a IS aoso_config_get("ASCENT_TURN_START_ALT", 1000).
    LOCAL end_a IS aoso_ascent_turn_end_alt().
    LOCAL max_aoa IS aoso_ascent_max_aoa().
    LOCAL twr_cap IS aoso_config_get("ASCENT_TWR_LIMIT", 2.2).
    aoso_log_info("ASCENT", "Profile=" + aoso_ascent_profile_name() + " gravity-turn (MechJeb-classic pitch program, shape=" + ROUND(shape_now, 2) + ", startAlt=" + ROUND(start_a, 0) + ", endAlt=" + ROUND(end_a, 0) + ", maxAoA=" + ROUND(max_aoa, 1) + ", TWR cap=" + ROUND(twr_cap, 2) + ") holdAP=" + ROUND(aoso_config_get("ASCENT_HOLD_AP_S", 45), 0) + "s target=" + ROUND(target_apo, 0) + "m (cut throttle here; parking is not the burn). If this line is missing, GameData still has the old ascent.").
    aoso_decide("ASCENT", "start", aoso_ascent_profile_name(), "start speed / shape", "spd=" + ROUND(AOSO_ASCENT["data"]["pitchover_speed"], 0) + " shape=" + ROUND(shape_now, 2) + " startAlt=" + ROUND(start_a, 0) + " endAlt=" + ROUND(end_a, 0)).
    aoso_state_transition(AOSO_ASCENT, "LIFTOFF").
}

FUNCTION aoso_ascent_update {
    LOCAL st IS AOSO_ASCENT["current"].
    IF st <> "" {
        IF st <> "DONE" {
            IF st <> "ABORTED" {
                aoso_ui_set("Ascent  " + st, "ap " + ROUND(APOAPSIS, 0) + "  pe " + ROUND(PERIAPSIS, 0)).
                LOCAL p IS 0.1.
                IF st = "GRAVITY_TURN" { SET p TO 0.35. }
                IF st = "COAST" { SET p TO 0.65. }
                IF st = "CIRCULARIZE" { SET p TO 0.85. }
                LOCAL tgt IS 80000.
                IF AOSO_ASCENT["data"]:HASKEY("target_apo") { SET tgt TO AOSO_ASCENT["data"]["target_apo"]. }
                IF tgt > 0 {
                    LOCAL frac IS ALTITUDE / tgt.
                    IF frac > 1 { SET frac TO 1. }
                    IF st = "LIFTOFF" { SET p TO 0.05 + 0.1 * frac. }
                    IF st = "GRAVITY_TURN" { SET p TO 0.15 + 0.45 * frac. }
                }
                aoso_hb_set("ascent", st, p).
            }
        }
    }
    aoso_ascent_opt_tick().
    aoso_state_update(AOSO_ASCENT).
}

FUNCTION aoso_ascent_is_done {
    RETURN AOSO_ASCENT["current"] = "DONE".
}

FUNCTION aoso_ascent_is_aborted {
    RETURN AOSO_ASCENT["current"] = "ABORTED".
}
