// AOSO/flight/ascent_opt.ks
// Launch-profile search + per-phase efficiency.
//
// A smooth gravity turn (GravityTurn / MechJeb classic) only has one
// free knob once pitch is AoA-limited onto prograde: how fast the nose
// *eases* off vertical. Searching 13-20 deg kicks made the start look
// violent (AoA = kick until FPA caught up). This module sweeps nod rate
// (0.30, 0.40, 0.50, 0.65, 0.85 deg/s) across pad reverts, scores each
// by leftover LiquidFuel minus a circularization tax, then locks the
// winner. The start itself stays within ASCENT_AOA_LIMIT of the flight
// path on every trial.
//
// Default grid is 5 rates plus one optional refine past the best edge --
// 6 flights, set by ASCENT_OPT_MAX_TRIALS. When ASCENT_OPTIMIZE is FALSE
// the search is idle but phases are still recorded.
//
// Phases (sectioned so two rates can be compared period-by-period):
//   VERTICAL    pad -> turn start
//   PITCHOVER   smooth nod (AoA-limited)
//   DENSE_AIR   gravity turn below ASCENT_DENSE_ALT (default 40 km)
//   UPPER_ATM   40 km -> coast
//   COAST       AP hold / warp to circularization
//   CIRCULARIZE vis-viva burn
// Each phase stores dt, dAlt, dApo, dLF, dOx, mean TWR / pitch / AoA / Q.

GLOBAL AOSO_ASCENT_OPT IS LEXICON(
    "loaded", FALSE,
    "store", LEXICON(),
    "phase", "",
    "phase_t0", 0,
    "phase_alt0", 0,
    "phase_apo0", 0,
    "phase_peri0", 0,
    "phase_lf0", 0,
    "phase_ox0", 0,
    "sum_twr", 0,
    "sum_pitch", 0,
    "sum_aoa", 0,
    "sum_q", 0,
    "max_q", 0,
    "samples", 0,
    "phases", LIST(),
    "applied_rate", -1,
    "applied_mode", "heuristic"
).

FUNCTION aoso_ascent_opt_grid {
    LOCAL g IS LIST().
    g:ADD(0.30).
    g:ADD(0.40).
    g:ADD(0.50).
    g:ADD(0.65).
    g:ADD(0.85).
    RETURN g.
}

FUNCTION aoso_ascent_opt_rate_key {
    PARAMETER rate.
    RETURN "" + ROUND(rate * 100, 0).
}

FUNCTION aoso_ascent_opt_key {
    RETURN SHIP:NAME + "|" + SHIP:BODY:NAME.
}

FUNCTION aoso_ascent_opt_empty_store {
    RETURN LEXICON("vessels", LEXICON()).
}

FUNCTION aoso_ascent_opt_load {
    IF AOSO_ASCENT_OPT["loaded"] { RETURN AOSO_ASCENT_OPT["store"]. }
    LOCAL loaded IS aoso_json_read_persistent(
        AOSO_CONST["ASCENT_OPT_FILE"],
        AOSO_CONST["ASCENT_OPT_ARCHIVE_FILE"],
        aoso_ascent_opt_empty_store()
    ).
    IF NOT loaded:ISTYPE("Lexicon") { SET loaded TO aoso_ascent_opt_empty_store(). }
    IF NOT loaded:HASKEY("vessels") { SET loaded["vessels"] TO LEXICON(). }
    SET AOSO_ASCENT_OPT["store"] TO loaded.
    SET AOSO_ASCENT_OPT["loaded"] TO TRUE.
    RETURN loaded.
}

FUNCTION aoso_ascent_opt_save {
    aoso_json_write_persistent(
        AOSO_CONST["ASCENT_OPT_FILE"],
        AOSO_CONST["ASCENT_OPT_ARCHIVE_FILE"],
        AOSO_ASCENT_OPT["store"]
    ).
}

FUNCTION aoso_ascent_opt_row {
    LOCAL store IS aoso_ascent_opt_load().
    LOCAL k IS aoso_ascent_opt_key().
    IF store["vessels"]:HASKEY(k) { RETURN store["vessels"][k]. }
    LOCAL row IS LEXICON(
        "vessel", SHIP:NAME,
        "body", SHIP:BODY:NAME,
        "status", "searching",
        "trial_index", 0,
        "trials", LIST(),
        "best", LEXICON(),
        "next_rate", 0.30
    ).
    SET store["vessels"][k] TO row.
    RETURN row.
}

FUNCTION aoso_ascent_opt_score {
    PARAMETER rec.
    LOCAL stable IS TRUE.
    IF rec:HASKEY("stable") { SET stable TO rec["stable"]. }
    IF NOT stable { RETURN -100000. }
    LOCAL lf IS 0.
    LOCAL circ IS 0.
    IF rec:HASKEY("orbit_lf") { SET lf TO rec["orbit_lf"]. }
    IF rec:HASKEY("circ_dv") { SET circ TO rec["circ_dv"]. }
    RETURN lf - (circ * 0.25).
}

FUNCTION aoso_ascent_opt_pick_next_rate {
    PARAMETER row.
    LOCAL grid IS aoso_ascent_opt_grid().
    LOCAL used IS LEXICON().
    FOR t IN row["trials"] {
        IF t:HASKEY("pitchover_rate") {
            LOCAL used_key IS aoso_ascent_opt_rate_key(t["pitchover_rate"]).
            SET used[used_key] TO TRUE.
        }
    }
    FOR d IN grid {
        LOCAL key IS aoso_ascent_opt_rate_key(d).
        IF NOT used:HASKEY(key) { RETURN d. }
    }

    LOCAL best_rate IS 0.
    IF row["best"]:HASKEY("pitchover_rate") { SET best_rate TO row["best"]["pitchover_rate"]. }
    IF best_rate > 0 {
        IF best_rate <= 0.32 {
            IF NOT used:HASKEY("22") { RETURN 0.22. }
        }
        IF best_rate >= 0.82 {
            IF NOT used:HASKEY("100") { RETURN 1.00. }
        }
    }
    RETURN -1.
}

FUNCTION aoso_ascent_opt_hud {
    LOCAL row IS aoso_ascent_opt_row().
    LOCAL mode IS AOSO_ASCENT_OPT["applied_mode"].
    LOCAL rate IS AOSO_ASCENT_OPT["applied_rate"].
    LOCAL n IS row["trials"]:LENGTH.
    LOCAL max_n IS aoso_config_get("ASCENT_OPT_MAX_TRIALS", 6).
    LOCAL best_txt IS "none".
    IF row["best"]:HASKEY("orbit_lf") {
        IF row["best"]:HASKEY("pitchover_rate") {
            SET best_txt TO "r" + ROUND(row["best"]["pitchover_rate"], 2) + " LF=" + ROUND(row["best"]["orbit_lf"], 0).
        }
    }
    IF rate < 0 { RETURN "Ascent opt " + row["status"] + " n=" + n + "/" + max_n + " best " + best_txt. }
    RETURN "Ascent " + mode + " r" + ROUND(rate, 2) + "  " + n + "/" + max_n + " best " + best_txt.
}

// Decide the nod rate for this flight. Called from LIFTOFF after the CoM
// heuristic has filled data["pitchover_rate"].
FUNCTION aoso_ascent_opt_apply {
    PARAMETER data.
    LOCAL heuristic IS data["pitchover_rate"].
    LOCAL row IS aoso_ascent_opt_row().
    LOCAL want_search IS aoso_config_get("ASCENT_OPTIMIZE", TRUE).
    LOCAL max_n IS aoso_config_get("ASCENT_OPT_MAX_TRIALS", 6).

    IF NOT want_search {
        IF row["status"] = "locked" {
            IF row["best"]:HASKEY("pitchover_rate") {
                SET data["pitchover_rate"] TO row["best"]["pitchover_rate"].
                SET AOSO_ASCENT_OPT["applied_rate"] TO data["pitchover_rate"].
                SET AOSO_ASCENT_OPT["applied_mode"] TO "locked".
                aoso_log_info("ASCENT_OPT", "Search off; flying locked best rate=" + ROUND(data["pitchover_rate"], 2) + " deg/s (heuristic was " + ROUND(heuristic, 2) + ").").
                RETURN.
            }
        }
        SET AOSO_ASCENT_OPT["applied_rate"] TO heuristic.
        SET AOSO_ASCENT_OPT["applied_mode"] TO "heuristic".
        aoso_log_info("ASCENT_OPT", "Search off; heuristic rate=" + ROUND(heuristic, 2) + " deg/s.").
        RETURN.
    }

    IF row["status"] = "locked" {
        IF row["best"]:HASKEY("pitchover_rate") {
            SET data["pitchover_rate"] TO row["best"]["pitchover_rate"].
            SET AOSO_ASCENT_OPT["applied_rate"] TO data["pitchover_rate"].
            SET AOSO_ASCENT_OPT["applied_mode"] TO "locked".
            aoso_log_info("ASCENT_OPT", "Locked best rate=" + ROUND(data["pitchover_rate"], 2) + " deg/s, orbit_lf=" + ROUND(row["best"]["orbit_lf"], 1) + " circ_dv=" + ROUND(row["best"]["circ_dv"], 1) + ".").
            RETURN.
        }
    }

    IF row["trials"]:LENGTH >= max_n {
        SET row["status"] TO "locked".
        aoso_ascent_opt_save().
        IF row["best"]:HASKEY("pitchover_rate") {
            SET data["pitchover_rate"] TO row["best"]["pitchover_rate"].
            SET AOSO_ASCENT_OPT["applied_rate"] TO data["pitchover_rate"].
            SET AOSO_ASCENT_OPT["applied_mode"] TO "locked".
            aoso_log_info("ASCENT_OPT", "Trial budget spent; locking rate=" + ROUND(data["pitchover_rate"], 2) + " deg/s.").
            RETURN.
        }
    }

    LOCAL next_rate IS aoso_ascent_opt_pick_next_rate(row).
    IF next_rate < 0 {
        SET row["status"] TO "locked".
        aoso_ascent_opt_save().
        IF row["best"]:HASKEY("pitchover_rate") {
            SET data["pitchover_rate"] TO row["best"]["pitchover_rate"].
        }
        SET AOSO_ASCENT_OPT["applied_rate"] TO data["pitchover_rate"].
        SET AOSO_ASCENT_OPT["applied_mode"] TO "locked".
        aoso_log_info("ASCENT_OPT", "Grid complete; locking rate=" + ROUND(data["pitchover_rate"], 2) + " deg/s.").
        RETURN.
    }

    SET data["pitchover_rate"] TO next_rate.
    SET row["next_rate"] TO next_rate.
    SET row["trial_index"] TO row["trials"]:LENGTH + 1.
    aoso_ascent_opt_save().
    SET AOSO_ASCENT_OPT["applied_rate"] TO next_rate.
    SET AOSO_ASCENT_OPT["applied_mode"] TO "trial".
    aoso_log_info("ASCENT_OPT", "Trial " + row["trial_index"] + "/" + max_n + " rate=" + ROUND(next_rate, 2) + " deg/s (heuristic would be " + ROUND(heuristic, 2) + "). Revert to pad between trials; leftover LF ranks them.").
}

FUNCTION aoso_ascent_opt_reset_accum {
    SET AOSO_ASCENT_OPT["sum_twr"] TO 0.
    SET AOSO_ASCENT_OPT["sum_pitch"] TO 0.
    SET AOSO_ASCENT_OPT["sum_aoa"] TO 0.
    SET AOSO_ASCENT_OPT["sum_q"] TO 0.
    SET AOSO_ASCENT_OPT["max_q"] TO 0.
    SET AOSO_ASCENT_OPT["samples"] TO 0.
}

FUNCTION aoso_ascent_opt_phase_close {
    IF AOSO_ASCENT_OPT["phase"] = "" { RETURN. }
    LOCAL n IS AOSO_ASCENT_OPT["samples"].
    LOCAL mean_twr IS 0.
    LOCAL mean_pitch IS 0.
    LOCAL mean_aoa IS 0.
    LOCAL mean_q IS 0.
    IF n > 0 {
        SET mean_twr TO AOSO_ASCENT_OPT["sum_twr"] / n.
        SET mean_pitch TO AOSO_ASCENT_OPT["sum_pitch"] / n.
        SET mean_aoa TO AOSO_ASCENT_OPT["sum_aoa"] / n.
        SET mean_q TO AOSO_ASCENT_OPT["sum_q"] / n.
    }
    LOCAL dt IS TIME:SECONDS - AOSO_ASCENT_OPT["phase_t0"].
    LOCAL d_alt IS ALTITUDE - AOSO_ASCENT_OPT["phase_alt0"].
    LOCAL d_apo IS APOAPSIS - AOSO_ASCENT_OPT["phase_apo0"].
    LOCAL d_lf IS AOSO_ASCENT_OPT["phase_lf0"] - aoso_resource_amount("LiquidFuel").
    LOCAL d_ox IS AOSO_ASCENT_OPT["phase_ox0"] - aoso_resource_amount("Oxidizer").
    LOCAL rec IS LEXICON(
        "name", AOSO_ASCENT_OPT["phase"],
        "dt", dt,
        "d_alt", d_alt,
        "d_apo", d_apo,
        "d_peri", PERIAPSIS - AOSO_ASCENT_OPT["phase_peri0"],
        "d_lf", d_lf,
        "d_ox", d_ox,
        "lf_end", aoso_resource_amount("LiquidFuel"),
        "alt_end", ALTITUDE,
        "apo_end", APOAPSIS,
        "peri_end", PERIAPSIS,
        "mean_twr", mean_twr,
        "mean_pitch", mean_pitch,
        "mean_aoa", mean_aoa,
        "mean_q", mean_q,
        "max_q", AOSO_ASCENT_OPT["max_q"]
    ).
    AOSO_ASCENT_OPT["phases"]:ADD(rec).
    aoso_log_info("ASCENT_OPT", "Phase " + rec["name"] + " dt=" + ROUND(dt, 1) + "s dAlt=" + ROUND(d_alt, 0) +
        " dApo=" + ROUND(d_apo, 0) + " dLF=" + ROUND(d_lf, 1) + " meanTWR=" + ROUND(mean_twr, 2) +
        " meanAoA=" + ROUND(mean_aoa, 1) + " deg meanQ=" + ROUND(mean_q, 3) + ".").
    SET AOSO_ASCENT_OPT["phase"] TO "".
}

FUNCTION aoso_ascent_opt_phase_open {
    PARAMETER name.
    IF AOSO_ASCENT_OPT["phase"] = name { RETURN. }
    aoso_ascent_opt_phase_close().
    SET AOSO_ASCENT_OPT["phase"] TO name.
    SET AOSO_ASCENT_OPT["phase_t0"] TO TIME:SECONDS.
    SET AOSO_ASCENT_OPT["phase_alt0"] TO ALTITUDE.
    SET AOSO_ASCENT_OPT["phase_apo0"] TO APOAPSIS.
    SET AOSO_ASCENT_OPT["phase_peri0"] TO PERIAPSIS.
    SET AOSO_ASCENT_OPT["phase_lf0"] TO aoso_resource_amount("LiquidFuel").
    SET AOSO_ASCENT_OPT["phase_ox0"] TO aoso_resource_amount("Oxidizer").
    aoso_ascent_opt_reset_accum().
}

FUNCTION aoso_ascent_opt_sample {
    IF AOSO_ASCENT_OPT["phase"] = "" { RETURN. }
    LOCAL twr IS aoso_perf_twr().
    LOCAL pitch IS aoso_ascent_facing_pitch().
    LOCAL fpa IS aoso_ascent_flight_path_pitch().
    LOCAL aoa IS pitch - fpa.
    LOCAL qnow IS SHIP:Q.
    SET AOSO_ASCENT_OPT["sum_twr"] TO AOSO_ASCENT_OPT["sum_twr"] + twr.
    SET AOSO_ASCENT_OPT["sum_pitch"] TO AOSO_ASCENT_OPT["sum_pitch"] + pitch.
    SET AOSO_ASCENT_OPT["sum_aoa"] TO AOSO_ASCENT_OPT["sum_aoa"] + aoa.
    SET AOSO_ASCENT_OPT["sum_q"] TO AOSO_ASCENT_OPT["sum_q"] + qnow.
    IF qnow > AOSO_ASCENT_OPT["max_q"] { SET AOSO_ASCENT_OPT["max_q"] TO qnow. }
    SET AOSO_ASCENT_OPT["samples"] TO AOSO_ASCENT_OPT["samples"] + 1.
}

FUNCTION aoso_ascent_opt_desired_phase {
    LOCAL st IS AOSO_ASCENT["current"].
    IF st = "LIFTOFF" { RETURN "VERTICAL". }
    IF st = "PITCHOVER" { RETURN "PITCHOVER". }
    IF st = "GRAVITY_TURN" {
        LOCAL dense_alt IS aoso_config_get("ASCENT_DENSE_ALT", 40000).
        IF ALTITUDE < dense_alt { RETURN "DENSE_AIR". }
        RETURN "UPPER_ATM".
    }
    IF st = "COAST" { RETURN "COAST". }
    IF st = "CIRCULARIZE" { RETURN "CIRCULARIZE". }
    RETURN "".
}

FUNCTION aoso_ascent_opt_begin {
    SET AOSO_ASCENT_OPT["phases"] TO LIST().
    SET AOSO_ASCENT_OPT["phase"] TO "".
    SET AOSO_ASCENT_OPT["applied_rate"] TO -1.
    SET AOSO_ASCENT_OPT["applied_mode"] TO "heuristic".
    aoso_ascent_opt_reset_accum().
    aoso_ascent_opt_load().
}

FUNCTION aoso_ascent_opt_tick {
    LOCAL st IS AOSO_ASCENT["current"].
    IF st = "" { RETURN. }
    IF st = "DONE" { RETURN. }
    IF st = "ABORTED" { RETURN. }
    LOCAL want IS aoso_ascent_opt_desired_phase().
    IF want = "" { RETURN. }
    aoso_ascent_opt_phase_open(want).
    aoso_ascent_opt_sample().
}

FUNCTION aoso_ascent_opt_commit {
    PARAMETER rec.
    aoso_ascent_opt_phase_close().
    SET rec["phases"] TO AOSO_ASCENT_OPT["phases"].
    SET rec["opt_mode"] TO AOSO_ASCENT_OPT["applied_mode"].

    LOCAL row IS aoso_ascent_opt_row().
    LOCAL score IS aoso_ascent_opt_score(rec).
    SET rec["score"] TO score.

    LOCAL trial IS LEXICON(
        "ut", rec["ut"],
        "pitchover_deg", rec["pitchover_deg"],
        "pitchover_rate", 0.45,
        "orbit_lf", rec["orbit_lf"],
        "used_lf", rec["used_lf"],
        "circ_dv", rec["circ_dv"],
        "apo", rec["apo"],
        "peri", rec["peri"],
        "score", score,
        "stable", TRUE,
        "phases", rec["phases"]
    ).
    IF rec:HASKEY("pitchover_rate") { SET trial["pitchover_rate"] TO rec["pitchover_rate"]. }
    IF rec:HASKEY("stable") { SET trial["stable"] TO rec["stable"]. }

    row["trials"]:ADD(trial).
    UNTIL row["trials"]:LENGTH <= 20 {
        row["trials"]:REMOVE(0).
    }

    LOCAL is_best IS FALSE.
    IF trial["stable"] {
        IF NOT row["best"]:HASKEY("score") {
            SET is_best TO TRUE.
        } ELSE {
            IF score > row["best"]["score"] { SET is_best TO TRUE. }
        }
    }
    IF is_best {
        SET row["best"] TO trial.
        aoso_log_info("ASCENT_OPT", "NEW BEST rate=" + ROUND(trial["pitchover_rate"], 2) + " deg/s score=" + ROUND(score, 1) +
            " orbit_lf=" + ROUND(trial["orbit_lf"], 1) + " circ_dv=" + ROUND(trial["circ_dv"], 1) + " m/s.").
    } ELSE {
        LOCAL best_line IS "no stable best yet".
        IF row["best"]:HASKEY("pitchover_rate") {
            SET best_line TO "best r" + ROUND(row["best"]["pitchover_rate"], 2) +
                " LF=" + ROUND(row["best"]["orbit_lf"], 1) +
                " circ=" + ROUND(row["best"]["circ_dv"], 1) +
                " score=" + ROUND(row["best"]["score"], 1).
        }
        aoso_log_info("ASCENT_OPT", "Trial rate=" + ROUND(trial["pitchover_rate"], 2) + " deg/s score=" + ROUND(score, 1) +
            " (this " + ROUND(trial["orbit_lf"], 1) + " LF, circ " + ROUND(trial["circ_dv"], 1) + ") - " + best_line + ".").
    }

    LOCAL max_n IS aoso_config_get("ASCENT_OPT_MAX_TRIALS", 6).
    IF row["trials"]:LENGTH >= max_n {
        SET row["status"] TO "locked".
        IF row["best"]:HASKEY("pitchover_rate") {
            aoso_log_info("ASCENT_OPT", "Search complete after " + row["trials"]:LENGTH + " trial(s). Locked rate=" +
                ROUND(row["best"]["pitchover_rate"], 2) + " deg/s. Set ASCENT_OPTIMIZE=false to freeze, or delete 0:/aoso_ascent_opt.json to restart.").
        } ELSE {
            aoso_log_warn("ASCENT_OPT", "Search complete but no stable orbit was recorded - leaving heuristic in charge.").
            SET row["status"] TO "searching".
        }
    } ELSE {
        IF aoso_ascent_opt_pick_next_rate(row) < 0 {
            SET row["status"] TO "locked".
            IF row["best"]:HASKEY("pitchover_rate") {
                aoso_log_info("ASCENT_OPT", "Grid exhausted. Locked rate=" + ROUND(row["best"]["pitchover_rate"], 2) + " deg/s.").
            }
        } ELSE {
            SET row["status"] TO "searching".
            aoso_log_info("ASCENT_OPT", "Revert to the pad for trial " + (row["trials"]:LENGTH + 1) + "/" + max_n + ".").
        }
    }
    aoso_ascent_opt_save().
}
