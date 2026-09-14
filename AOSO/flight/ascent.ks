// AOSO/flight/ascent.ks
// True gravity-turn ascent, then a vis-viva circularization at apoapsis.
//
// NASA / GravityTurn / MechJeb classic:
//   1. Vertical until there is enough speed (and Q) to control a turn.
//   2. Ride surface prograde with a small lead (about 3 deg, eased in over
//      ~8 s -- not a 13 deg kick). The nose stays near the prograde marker.
//   3. Throttle is the loft lever: cap TWR ~1.7 while the flight path is
//      still steep so gravity can pull the trajectory over. A TWR 2.6
//      stack at full throttle and 1.8 deg of lead is a sounding rocket
//      (Acacius: FPA 83 deg at 30 km, 1807 m/s circularization, never
//      aligned). After the path shallows, the 45 s-to-AP hold.
//   4. Out of the atmosphere, orbital prograde, coast, circularize.
//   5. Each ascent is sectioned VERTICAL / STARTTURN / DENSE_AIR /
//      UPPER_ATM / COAST / CIRCULARIZE. Optimizer sweeps start speed.
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
            SET stop_s TO MAX(stop_s, 3.2).
            SET pitch_ts TO MAX(pitch_ts, 2.4).
        }
        IF data["stack_length"] > 30 {
            SET stop_s TO MAX(stop_s, 4.0).
            SET pitch_ts TO MAX(pitch_ts, 2.8).
        }
        IF data["com_frac"] > 0.55 {
            SET stop_s TO MAX(stop_s, 3.8).
            SET pitch_ts TO MAX(pitch_ts, 2.6).
        }
        IF stop_s > 4.5 { SET stop_s TO 4.5. }
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

// Small lead below the flight path. Starts at 1 deg (invisible kick) and
// eases to the target over blend_s. If the path is still too steep after
// a few seconds, add a little extra -- still a few degrees, not 13.
FUNCTION aoso_ascent_live_bias {
    PARAMETER data.
    LOCAL target IS 3.2.
    IF data:HASKEY("turn_bias") { SET target TO data["turn_bias"]. }
    IF target < 1 { SET target TO 1. }
    IF target > 4.5 { SET target TO 4.5. }

    LOCAL t0 IS 0.
    IF data:HASKEY("turn_t0") { SET t0 TO data["turn_t0"]. }
    IF t0 <= 0 { RETURN target. }

    LOCAL blend IS 8.
    IF data:HASKEY("turn_blend_s") { SET blend TO data["turn_blend_s"]. }
    IF blend < 5 { SET blend TO 5. }
    IF blend > 12 { SET blend TO 12. }

    LOCAL elapsed IS TIME:SECONDS - t0.
    IF elapsed <= 0 { RETURN 1. }
    LOCAL frac IS elapsed / blend.
    IF frac > 1 { SET frac TO 1. }
    LOCAL s IS 0.5 * (1 - COS(frac * 180)).
    LOCAL bias IS 1 + ((target - 1) * s).

    IF elapsed > 12 {
        LOCAL fpa IS aoso_ascent_flight_path_pitch().
        IF fpa > 75 {
            SET bias TO bias + MIN(2.0, (fpa - 75) * 0.25).
        } ELSE {
            IF fpa > 62 {
                SET bias TO bias + MIN(1.0, (fpa - 62) * 0.08).
            }
        }
    }
    IF bias > 5 { SET bias TO 5. }
    RETURN bias.
}

FUNCTION aoso_ascent_turn_bias {
    PARAMETER com_frac IS 0.5.
    LOCAL twr IS aoso_perf_twr().
    LOCAL bias IS aoso_config_get("ASCENT_TURN_BIAS_DEG", 3.2).
    IF twr >= 1.8 { SET bias TO bias + 0.3. }
    IF twr >= 2.2 { SET bias TO bias + 0.4. }
    IF twr < 1.3 { SET bias TO bias - 0.5. }
    IF com_frac > 0.55 { SET bias TO bias - 0.4. }
    IF bias < 1.6 { SET bias TO 1.6. }
    IF bias > 4.5 { SET bias TO 4.5. }
    RETURN bias.
}

FUNCTION aoso_ascent_turn_blend_s {
    PARAMETER stack_len IS 0.
    LOCAL blend IS aoso_config_get("ASCENT_TURN_BLEND_S", 8).
    IF stack_len > 30 { SET blend TO blend + 2. }
    IF blend < 6 { SET blend TO 6. }
    IF blend > 12 { SET blend TO 12. }
    RETURN blend.
}

// Surface prograde + small lead for the whole atmosphere (heading held so
// weathercock does not walk inclination). Switching to orbital prograde
// at Q=0.02 while still going 70 deg up was an 11 deg yank on Acacius.
FUNCTION aoso_ascent_follow_prograde {
    PARAMETER data.
    IF aoso_ascent_in_atmosphere() {
        LOCAL fpa IS aoso_ascent_flight_path_pitch().
        LOCAL cmd IS fpa - aoso_ascent_live_bias(data).
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
    LOCAL mult IS AOSO_CONFIG["MAX_Q_LIMIT_MULT"].
    IF mult >= 1.0 { RETURN 1.0. }

    IF SHIP:Q > AOSO_ASCENT_MAX_Q_SEEN { SET AOSO_ASCENT_MAX_Q_SEEN TO SHIP:Q. }

    IF AOSO_ASCENT_MAX_Q_SEEN > 0 AND SHIP:Q >= AOSO_ASCENT_MAX_Q_SEEN * 0.9 {
        RETURN mult.
    }
    RETURN 1.0.
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

    IF APOAPSIS >= target_apo {
        IF aoso_ascent_in_atmosphere() {
            IF ALTITUDE < SHIP:BODY:ATM:HEIGHT * 0.9 { RETURN MIN(0.25, q_mult). }
        }
        IF APOAPSIS < target_apo * 1.005 { RETURN MIN(0.12, q_mult). }
        RETURN 0.
    }

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
    RETURN "GT+TWRCAP/s" + ROUND(spd, 0).
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
        "turn_bias", data["turn_bias"],
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
    SET data["turn_bias"] TO aoso_config_get("ASCENT_TURN_BIAS_DEG", 3.2).
    SET data["turn_blend_s"] TO aoso_config_get("ASCENT_TURN_BLEND_S", 8).
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
    aoso_throttle_set(1).
    aoso_staging_auto_check().
    aoso_ascent_cache_stack_layout(data).
    aoso_ascent_snapshot_pad(data).

    SET data["pitchover_speed"] TO aoso_ascent_pitchover_speed(data["com_frac"], data["stack_length"]).
    SET data["pitchover_min_alt"] TO aoso_ascent_pitchover_min_alt(data["com_frac"], data["stack_length"]).
    SET data["turn_bias"] TO aoso_ascent_turn_bias(data["com_frac"]).
    SET data["turn_blend_s"] TO aoso_ascent_turn_blend_s(data["stack_length"]).
    IF AOSO_ASCENT_OPT["applied_speed"] < 0 {
        aoso_ascent_opt_apply(data).
    } ELSE {
        SET data["pitchover_speed"] TO AOSO_ASCENT_OPT["applied_speed"].
    }

    IF SHIP:VELOCITY:SURFACE:MAG >= data["pitchover_speed"] {
        IF ALTITUDE > data["pitchover_min_alt"] {
            aoso_log_info("ASCENT", "Gravity turn at " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + " m/s, bias=" + ROUND(data["turn_bias"], 1) + " deg over " + ROUND(data["turn_blend_s"], 0) + " s, TWR cap=" + ROUND(aoso_config_get("ASCENT_TWR_LIMIT", 1.7), 2) + ", TWR=" + ROUND(aoso_perf_twr(), 2) + ", CoM=" + ROUND(data["com_frac"], 2) + ", len=" + ROUND(data["stack_length"], 1) + " m.").
            aoso_state_transition(AOSO_ASCENT, "GRAVITY_TURN").
        }
    }
}

FUNCTION aoso_ascent_turn_entry {
    PARAMETER data.
    IF data["turn_t0"] = 0 {
        SET data["turn_t0"] TO TIME:SECONDS.
    }
}

FUNCTION aoso_ascent_turn_execute {
    PARAMETER data.
    aoso_ascent_follow_prograde(data).
    aoso_throttle_set(aoso_ascent_turn_throttle()).

    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    IF APOAPSIS < data["target_apo"] { RETURN. }

    IF aoso_ascent_in_atmosphere() {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT * 0.92 { RETURN. }
    }
    aoso_throttle_set(0).
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
    aoso_ascent_follow_prograde(data).
    aoso_staging_auto_check().
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

    IF APOAPSIS < data["target_apo"] * 0.98 {
        SET WARP TO 0.
        aoso_throttle_set(0.2).
    } ELSE {
        aoso_throttle_set(0).
    }

    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_ASCENT).
        RETURN.
    }

    IF aoso_ascent_in_atmosphere() { RETURN. }

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
    aoso_throttle_set(0).
    aoso_ascent_restore_steering(data).
    aoso_steer_release().
    aoso_log_info("ASCENT", "Ascent complete. Apo=" + ROUND(APOAPSIS, 0) + " Peri=" + ROUND(PERIAPSIS, 0)).
    aoso_ascent_persist_run(data).
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
            "turn_bias", data["turn_bias"],
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
}

FUNCTION aoso_ascent_define_states {
    aoso_state_define(AOSO_ASCENT, "LIFTOFF", aoso_ascent_liftoff_entry@, aoso_ascent_liftoff_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "GRAVITY_TURN", aoso_ascent_turn_entry@, aoso_ascent_turn_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "COAST", aoso_ascent_coast_entry@, aoso_ascent_coast_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "CIRCULARIZE", aoso_ascent_circularize_entry@, aoso_ascent_circularize_execute@, 0, 0, 0, aoso_ascent_on_abort@).
    aoso_state_define(AOSO_ASCENT, "DONE", aoso_ascent_done_entry@, 0, 0).
    aoso_state_define(AOSO_ASCENT, "ABORTED", aoso_ascent_aborted_entry@, 0, 0).
}

FUNCTION aoso_ascent_start {
    PARAMETER launch_heading IS 90.
    PARAMETER target_apo IS 0.
    IF target_apo <= 0 { SET target_apo TO aoso_config_get("ASCENT_TARGET_APO", 80000). }

    SET AOSO_ASCENT_MAX_Q_SEEN TO 0.
    aoso_ascent_opt_begin().
    aoso_ascent_define_states().
    SET AOSO_ASCENT["data"] TO LEXICON(
        "heading", launch_heading,
        "target_apo", target_apo,
        "pitchover_speed", 80,
        "pitchover_min_alt", 200,
        "turn_bias", 3.2,
        "turn_blend_s", 8,
        "turn_t0", 0,
        "com_frac", -1,
        "stack_length", 0,
        "circ_now", FALSE,
        "circ_dv", 0
    ).
    aoso_log_info("ASCENT", "Profile=" + aoso_ascent_profile_name() + " gravity-turn (prograde + eased lead, TWR cap=" + ROUND(aoso_config_get("ASCENT_TWR_LIMIT", 1.7), 2) + ") holdAP=" + ROUND(aoso_config_get("ASCENT_HOLD_AP_S", 45), 0) + "s target=" + ROUND(target_apo, 0) + "m. If this line is missing, GameData still has the old ascent.").
    aoso_state_transition(AOSO_ASCENT, "LIFTOFF").
}

FUNCTION aoso_ascent_update {
    aoso_ascent_opt_tick().
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
