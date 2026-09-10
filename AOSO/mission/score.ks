// AOSO/mission/score.ks
// Opportunity scoring: CAN vs SHOULD. A destination can be technically
// possible and still a bad next stop (Eve landing on a hopper, Duna with
// an 80-day closed window while Minmus is free). Scores 0-100.

GLOBAL AOSO_OPP_LAST IS LEXICON().

FUNCTION aoso_opp_weights {
    LOCAL mode IS aoso_config_get("OPTIMIZATION_MODE", "BALANCED").
    IF mode = "MINIMUM_DV" OR mode = "FUEL" {
        RETURN LEXICON("dv", 0.55, "margin", 0.15, "safety", 0.15, "window", 0.1, "time", 0.05).
    }
    IF mode = "TIME" {
        RETURN LEXICON("dv", 0.15, "margin", 0.1, "safety", 0.15, "window", 0.25, "time", 0.35).
    }
    IF mode = "SAFETY" {
        RETURN LEXICON("dv", 0.15, "margin", 0.35, "safety", 0.35, "window", 0.1, "time", 0.05).
    }
    RETURN LEXICON("dv", 0.3, "margin", 0.2, "safety", 0.2, "window", 0.2, "time", 0.1).
}

FUNCTION aoso_opp_class_bonus {
    PARAMETER dest_name.
    LOCAL bonus IS 0.
    LOCAL class_name IS aoso_classify_name().
    LOCAL planet_name IS aoso_feas_planet_of(dest_name).
    LOCAL here_planet IS aoso_feas_planet_of(SHIP:BODY:NAME).
    IF aoso_classify_get("prefer_nearby", FALSE) {
        IF planet_name = here_planet { SET bonus TO bonus + 12. }
        IF dest_name = "Mun" OR dest_name = "Minmus" { SET bonus TO bonus + 8. }
    }
    IF aoso_classify_get("prefer_refuel_first", FALSE) {
        IF dest_name = "Minmus" OR dest_name = "Gilly" OR dest_name = "Ike" OR dest_name = "Pol" {
            SET bonus TO bonus + 10.
        }
    }
    IF aoso_classify_get("prefer_outer", FALSE) {
        IF dest_name = "Dres" OR dest_name = "Eeloo" OR dest_name = "Moho" { SET bonus TO bonus + 8. }
        IF planet_name = "Jool" { SET bonus TO bonus + 10. }
    }
    IF aoso_classify_get("prefer_atmo", FALSE) {
        IF dest_name = "Duna" OR dest_name = "Laythe" { SET bonus TO bonus + 10. }
        IF dest_name = "Eve" { SET bonus TO bonus + 4. }
    }
    IF aoso_classify_get("prefer_orbit_only", FALSE) {
        IF dest_name = "Eve" OR dest_name = "Tylo" { SET bonus TO bonus - 5. }
    }
    IF class_name = "hopper" {
        IF dest_name = "Eve" OR dest_name = "Tylo" OR dest_name = "Moho" { SET bonus TO bonus - 15. }
    }
    RETURN bonus.
}

FUNCTION aoso_opp_score {
    PARAMETER dest_name.
    LOCAL row IS aoso_matrix_get(dest_name).
    LOCAL w IS aoso_opp_weights().
    LOCAL win IS aoso_window_evaluate(SHIP:BODY:NAME, dest_name).

    LOCAL can_go IS TRUE.
    IF row["result"] = "SKIP" { SET can_go TO FALSE. }

    LOCAL dv_need IS row["transfer_dv"].
    LOCAL dv_part IS 100 * (1 - MIN(dv_need, 8000) / 8000).
    LOCAL ratio IS row["orbit"]["ratio"].
    LOCAL margin_part IS MIN(100, ratio * 40).
    LOCAL land_diff IS aoso_world_body_stat(dest_name, "landing_difficulty", 0.5).
    LOCAL safety_part IS 100 * (1 - land_diff).
    LOCAL window_part IS win["efficiency"] * 100.
    LOCAL time_part IS 100 - MIN(80, win["wait_days"] * 4).
    IF time_part < 5 { SET time_part TO 5. }

    LOCAL total IS dv_part * w["dv"] + margin_part * w["margin"] + safety_part * w["safety"] +
        window_part * w["window"] + time_part * w["time"].
    SET total TO total + aoso_opp_class_bonus(dest_name).

    LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
    IF row["can_refuel"] {
        IF fuel_pct < aoso_config_get("TOUR_REFUEL_BELOW_PCT", 60) {
            SET total TO total + 12.
        } ELSE {
            SET total TO total + 3.
        }
    }
    IF NOT can_go { SET total TO 0. }
    IF total < 0 { SET total TO 0. }
    IF total > 100 { SET total TO 100. }

    LOCAL min_should IS aoso_config_get("PLANNER_MIN_SHOULD_SCORE", 30).
    LOCAL should_go IS FALSE.
    IF can_go {
        IF total >= min_should { SET should_go TO TRUE. }
    }

    RETURN LEXICON(
        "body", dest_name,
        "score", ROUND(total, 1),
        "can", can_go,
        "should", should_go,
        "result", row["result"],
        "wait_days", win["wait_days"],
        "efficiency", win["efficiency"],
        "transfer_dv", dv_need
    ).
}

FUNCTION aoso_opp_build {
    LOCAL catalog IS aoso_matrix_catalog().
    LOCAL rows IS LEXICON().
    LOCAL can_list IS LIST().
    LOCAL should_list IS LIST().
    FOR dest_name IN catalog {
        LOCAL scored IS aoso_opp_score(dest_name).
        SET rows[dest_name] TO scored.
        IF scored["can"] { can_list:ADD(dest_name). }
        IF scored["should"] { should_list:ADD(dest_name). }
    }
    SET AOSO_OPP_LAST TO LEXICON(
        "rows", rows,
        "can", can_list,
        "should", should_list,
        "at", TIME:SECONDS
    ).
    aoso_opp_log().
    RETURN AOSO_OPP_LAST.
}

FUNCTION aoso_opp_log {
    IF NOT AOSO_OPP_LAST:HASKEY("rows") { RETURN. }
    LOCAL can_txt IS "".
    FOR n IN AOSO_OPP_LAST["can"] {
        IF can_txt <> "" { SET can_txt TO can_txt + ", ". }
        SET can_txt TO can_txt + n.
    }
    LOCAL should_txt IS "".
    FOR n IN AOSO_OPP_LAST["should"] {
        IF should_txt <> "" { SET should_txt TO should_txt + ", ". }
        SET should_txt TO should_txt + n.
    }
    aoso_log_info("OPP", "CAN: " + can_txt).
    aoso_log_info("OPP", "SHOULD: " + should_txt).
}

FUNCTION aoso_opp_get {
    PARAMETER dest_name.
    IF AOSO_OPP_LAST:HASKEY("rows") {
        IF AOSO_OPP_LAST["rows"]:HASKEY(dest_name) {
            RETURN AOSO_OPP_LAST["rows"][dest_name].
        }
    }
    RETURN aoso_opp_score(dest_name).
}
