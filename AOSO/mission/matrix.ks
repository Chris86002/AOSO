// AOSO/mission/matrix.ks
// Per-body capability matrix: not a pile of booleans, but CAPABLE / MARGIN
// / CONFIDENCE for orbit, land, and return. Built from the feasibility
// engine + dV budget so the planner can say "Duna landing YES LOW 78%".

GLOBAL AOSO_MATRIX_LAST IS LEXICON().

FUNCTION aoso_matrix_margin_label {
    PARAMETER ratio.
    IF ratio >= 2 { RETURN "HIGH". }
    IF ratio >= 1.3 { RETURN "MED". }
    IF ratio >= 1 { RETURN "LOW". }
    RETURN "NONE".
}

FUNCTION aoso_matrix_cell {
    PARAMETER capable.
    PARAMETER need_dv.
    PARAMETER have_dv.
    PARAMETER confidence.
    LOCAL ratio IS 0.
    IF need_dv <= 1 {
        SET ratio TO 9.
    } ELSE {
        SET ratio TO have_dv / need_dv.
    }
    LOCAL label IS aoso_matrix_margin_label(ratio).
    IF NOT capable { SET label TO "--". }
    RETURN LEXICON(
        "capable", capable,
        "margin", label,
        "confidence", ROUND(confidence, 2),
        "need", ROUND(need_dv, 0),
        "have", ROUND(have_dv, 0),
        "ratio", ROUND(ratio, 2)
    ).
}

FUNCTION aoso_matrix_row {
    PARAMETER dest_name.
    LOCAL report IS aoso_feas_evaluate(dest_name).
    LOCAL have IS report["mission_dv"].
    LOCAL orbit_need IS report["transfer_dv"] + report["capture_dv"].
    LOCAL land_need IS orbit_need + report["land_dv"].
    LOCAL return_need IS report["return_dv"].
    IF report["can_land"] {
        IF report["can_takeoff"] {
            SET return_need TO land_need + report["takeoff_dv"] + report["return_dv"].
        }
    }

    LOCAL land_ok IS FALSE.
    IF report["can_land"] {
        IF report["can_takeoff"] { SET land_ok TO TRUE. }
    }

    LOCAL orbit_conf IS 0.7.
    IF report["can_reach"] { SET orbit_conf TO 0.75. }
    IF have > orbit_need * 1.5 { SET orbit_conf TO MIN(0.99, orbit_conf + 0.2). }
    IF NOT report["can_reach"] { SET orbit_conf TO 0.85. }

    LOCAL land_conf IS 0.5.
    IF report["can_land"] { SET land_conf TO MIN(0.98, 0.55 + (1 - aoso_world_body_stat(dest_name, "landing_difficulty", 0.5)) * 0.4). }
    IF NOT report["can_land"] { SET land_conf TO 0.9. }

    LOCAL return_conf IS 0.55.
    IF report["can_return"] { SET return_conf TO MIN(0.97, 0.5 + have / 12000). }
    IF NOT report["can_return"] { SET return_conf TO 0.85. }

    RETURN LEXICON(
        "body", dest_name,
        "result", report["result"],
        "reason", report["reason"],
        "orbit", aoso_matrix_cell(report["can_reach"], orbit_need, have, orbit_conf),
        "land", aoso_matrix_cell(land_ok, land_need, have, land_conf),
        "ret", aoso_matrix_cell(report["can_return"], return_need, have, return_conf),
        "can_refuel", report["can_refuel"],
        "surface_twr", report["surface_twr"],
        "transfer_dv", report["transfer_dv"]
    ).
}

FUNCTION aoso_matrix_catalog {
    RETURN LIST("Mun", "Minmus", "Eve", "Gilly", "Moho", "Duna", "Ike", "Dres", "Jool", "Laythe", "Vall", "Tylo", "Bop", "Pol", "Eeloo").
}

FUNCTION aoso_matrix_build {
    LOCAL catalog IS aoso_matrix_catalog().
    LOCAL rows IS LEXICON().
    LOCAL n_yes IS 0.
    LOCAL n_orbit IS 0.
    LOCAL n_skip IS 0.
    FOR dest_name IN catalog {
        LOCAL row IS aoso_matrix_row(dest_name).
        SET rows[dest_name] TO row.
        IF row["result"] = "FEASIBLE" { SET n_yes TO n_yes + 1. }
        IF row["result"] = "ORBIT_ONLY" { SET n_orbit TO n_orbit + 1. }
        IF row["result"] = "SKIP" { SET n_skip TO n_skip + 1. }
    }
    SET AOSO_MATRIX_LAST TO LEXICON(
        "rows", rows,
        "feasible", n_yes,
        "orbit_only", n_orbit,
        "skipped", n_skip,
        "at", TIME:SECONDS
    ).
    aoso_json_write(AOSO_CONST["MATRIX_FILE"], AOSO_MATRIX_LAST).
    aoso_matrix_log().
    RETURN AOSO_MATRIX_LAST.
}

FUNCTION aoso_matrix_cell_txt {
    PARAMETER cell.
    LOCAL flag IS "NO ".
    IF cell["capable"] { SET flag TO "YES". }
    RETURN flag + " " + cell["margin"] + " " + ROUND(cell["confidence"] * 100, 0) + "%".
}

FUNCTION aoso_matrix_log {
    IF NOT AOSO_MATRIX_LAST:HASKEY("rows") { RETURN. }
    aoso_log_info("MATRIX", "Capability matrix  (capable  margin  confidence)").
    FOR dest_name IN aoso_matrix_catalog() {
        IF AOSO_MATRIX_LAST["rows"]:HASKEY(dest_name) {
            LOCAL row IS AOSO_MATRIX_LAST["rows"][dest_name].
            aoso_log_info("MATRIX", dest_name + "  orbit " + aoso_matrix_cell_txt(row["orbit"]) +
                "  land " + aoso_matrix_cell_txt(row["land"]) +
                "  return " + aoso_matrix_cell_txt(row["ret"]) +
                "  " + row["result"]).
        }
    }
    aoso_log_info("MATRIX", "Summary: " + AOSO_MATRIX_LAST["feasible"] + " landable, " +
        AOSO_MATRIX_LAST["orbit_only"] + " orbit-only, " +
        AOSO_MATRIX_LAST["skipped"] + " skipped.").
}

FUNCTION aoso_matrix_get {
    PARAMETER dest_name.
    IF AOSO_MATRIX_LAST:HASKEY("rows") {
        IF AOSO_MATRIX_LAST["rows"]:HASKEY(dest_name) {
            RETURN AOSO_MATRIX_LAST["rows"][dest_name].
        }
    }
    RETURN aoso_matrix_row(dest_name).
}
