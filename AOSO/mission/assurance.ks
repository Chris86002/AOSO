// AOSO/mission/assurance.ks
// Continuation: can the CURRENT ship finish the CURRENT plan?
// Weakest remaining leg, fuel margin, departure readiness.

GLOBAL AOSO_ASSURE_LAST IS LEXICON().

FUNCTION aoso_assure_weakest {
    LOCAL weakest IS "".
    LOCAL worst IS 99999.
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("weakest") {
            IF AOSO_PROJECT_LAST["weakest"] <> "" {
                RETURN LEXICON("body", AOSO_PROJECT_LAST["weakest"], "margin", AOSO_PROJECT_LAST["min_margin"]).
            }
        }
    }
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("targets") {
            LOCAL hop IS aoso_budget_get("mission_dv", 0).
            FOR dest_name IN AOSO_PLAN_LAST["targets"] {
                LOCAL row IS aoso_matrix_get(dest_name).
                LOCAL need IS row["transfer_dv"].
                LOCAL margin IS hop - need.
                IF margin < worst {
                    SET worst TO margin.
                    SET weakest TO dest_name.
                }
            }
            RETURN LEXICON("body", weakest, "margin", worst).
        }
    }
    RETURN LEXICON("body", "", "margin", 0).
}

FUNCTION aoso_depart_certify {
    LOCAL st IS SHIP:STATUS.
    IF st <> "LANDED" {
        IF st <> "PRELAUNCH" {
            IF st <> "SPLASHED" {
                RETURN LEXICON("status", "READY", "reason", "already flying", "warnings", LIST()).
            }
        }
    }
    LOCAL warn IS LIST().
    // Pad / PRELAUNCH is the live stack, boosters included.
    // LANDER TWR is the stripped hopper after those boosters are gone.
    // Scoring a Kerbin pad launch as LANDER is why Acacius sat at TWR
    // 0.17 (vacuum core at ASL) with boosters that give ~1.57.
    LOCAL twr IS aoso_profile_surface_twr(SHIP:BODY:NAME).
    LOCAL twr_cfg IS "pad".
    IF DEFINED AOSO_CAPS {
        IF st = "PRELAUNCH" {
            SET twr TO aoso_caps_surface_twr_for_config("ALL", SHIP:BODY:NAME, SHIP:MASS).
            SET twr_cfg TO "pad".
        } ELSE {
            SET twr TO aoso_caps_surface_twr_for_config("LANDER", SHIP:BODY:NAME, 0).
            SET twr_cfg TO "lander".
            IF twr < 1.05 {
                LOCAL stack_twr IS aoso_caps_surface_twr_for_config("ALL", SHIP:BODY:NAME, SHIP:MASS).
                IF stack_twr > twr {
                    SET twr TO stack_twr.
                    SET twr_cfg TO "pad".
                }
            }
        }
    }
    LOCAL min_twr IS aoso_config_get("TOUR_MIN_LAND_TWR", 1.4).
    LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
    LOCAL takeoff_dv IS aoso_feas_takeoff_cost(SHIP:BODY:NAME).
    LOCAL mission_dv IS aoso_budget_get("mission_dv", 0).
    LOCAL status_name IS "READY".
    LOCAL reason IS "launch ok".

    IF twr < 1.05 {
        RETURN LEXICON("status", "NOT_READY", "reason", "surface TWR " + ROUND(twr, 2), "warnings", warn).
    }
    // AVAILABLETHRUST is 0 until ascent lights engines. POSSIBLE
    // thrust already passed the TWR gate above, so unlit engines on
    // the pad or a landed hopper are not "no propulsion".
    IF twr < min_twr { warn:ADD("TWR " + ROUND(twr, 2) + " below tour minimum " + min_twr). }
    IF fuel_pct < 8 {
        RETURN LEXICON("status", "NOT_READY", "reason", "fuel " + ROUND(fuel_pct, 0) + "%", "warnings", warn).
    }
    IF takeoff_dv > 0 {
        IF mission_dv + 50 < takeoff_dv {
            RETURN LEXICON("status", "NOT_READY", "reason", "takeoff " + ROUND(takeoff_dv, 0) + " vs mission dV " + ROUND(mission_dv, 0), "warnings", warn).
        }
    }
    IF DEFINED AOSO_TOPO {
        LOCAL nxt IS aoso_topo_get("next_stage", LEXICON()).
        IF nxt:ISTYPE("Lexicon") {
            IF nxt:HASKEY("legs_lost") {
                IF nxt["legs_lost"] > 0 { warn:ADD("next stage drops landing legs"). }
            }
        }
    }
    IF SHIP:VELOCITY:SURFACE:MAG > 0.8 {
        RETURN LEXICON("status", "NOT_READY", "reason", "not stationary", "warnings", warn).
    }
    IF warn:LENGTH > 0 { SET status_name TO "READY_WITH_WARNING". SET reason TO warn[0]. }
    aoso_log_info("DEPART", status_name + " twr=" + ROUND(twr, 2) + " (" + twr_cfg + ") fuel=" + ROUND(fuel_pct, 0) + "% " + reason + ".").
    RETURN LEXICON("status", status_name, "reason", reason, "warnings", warn, "twr", twr, "fuel_pct", fuel_pct).
}

FUNCTION aoso_assure_eval {
    LOCAL weak IS aoso_assure_weakest().
    LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
    LOCAL dv IS aoso_budget_get("mission_dv", 0).
    LOCAL cert IS aoso_cert_status().
    LOCAL can_return IS aoso_profile_capable("can_return_to_kerbin").
    LOCAL health IS "OK".
    IF weak["margin"] < 200 { SET health TO "TIGHT". }
    IF weak["margin"] < 0 { SET health TO "AT_RISK". }
    IF cert = "NOT_CERTIFIED" { SET health TO "BLOCKED". }
    IF fuel_pct < 12 { SET health TO "FUEL". }

    LOCAL snap IS LEXICON(
        "health", health,
        "cert", cert,
        "mission_dv", dv,
        "fuel_pct", fuel_pct,
        "weak_body", weak["body"],
        "weak_margin", weak["margin"],
        "min_twr_margin", 0,
        "next_refuel", "",
        "return_margin", 0,
        "confidence", 0.6,
        "can_return", can_return,
        "at", TIME:SECONDS
    ).
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("min_margin") { SET snap["weak_margin"] TO AOSO_PROJECT_LAST["min_margin"]. }
        IF AOSO_PROJECT_LAST:HASKEY("weakest") { SET snap["weak_body"] TO AOSO_PROJECT_LAST["weakest"]. }
        IF AOSO_PROJECT_LAST:HASKEY("next_refuel") { SET snap["next_refuel"] TO AOSO_PROJECT_LAST["next_refuel"]. }
        IF AOSO_PROJECT_LAST:HASKEY("end_dv") { SET snap["return_margin"] TO AOSO_PROJECT_LAST["end_dv"]. }
        IF AOSO_PROJECT_LAST:HASKEY("min_twr") { SET snap["min_twr_margin"] TO AOSO_PROJECT_LAST["min_twr"]. }
        SET snap["confidence"] TO 0.75.
    }
    SET AOSO_ASSURE_LAST TO snap.
    RETURN snap.
}

FUNCTION aoso_assure_health {
    IF AOSO_ASSURE_LAST:HASKEY("health") { RETURN AOSO_ASSURE_LAST["health"]. }
    RETURN "UNKNOWN".
}
