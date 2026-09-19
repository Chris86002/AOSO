// AOSO/mission/certify.ks
// Snapshot: can this spacecraft attempt the requested mission?
// CERTIFIED is not a guarantee. It means no known hard blocker.

GLOBAL AOSO_CERT_LAST IS LEXICON().

FUNCTION aoso_cert_ability {
    LOCAL dv IS aoso_budget_get("mission_dv", 0).
    LOCAL twr IS aoso_caps_get("twr", 0).
    LOCAL hw IS aoso_topo_hw().
    RETURN LEXICON(
        "available_dv", dv,
        "available_twr", twr,
        "can_land", aoso_profile_capable("can_land"),
        "can_isru", aoso_profile_capable("can_isru"),
        "can_return", aoso_profile_capable("can_return_to_kerbin"),
        "solar", hw["solar"],
        "heatshield", hw["heatshield"],
        "legs", hw["legs"],
        "chutes", hw["chute"],
        "rwheel", hw["rwheel"],
        "rcs", hw["rcs"],
        "confidence", 0.7
    ).
}

FUNCTION aoso_cert_eval {
    PARAMETER mission_kind IS "grand_tour".

    LOCAL hard IS LIST().
    LOCAL warn IS LIST().
    LOCAL unk IS LIST().
    LOCAL ability IS aoso_cert_ability().
    LOCAL dv IS ability["available_dv"].
    LOCAL twr_now IS ability["available_twr"].

    IF dv < 100 {
        IF SHIP:STATUS = "PRELAUNCH" {
            warn:ADD("pad mission dV still settling").
        } ELSE {
            hard:ADD("mission dV " + ROUND(dv, 0) + " m/s").
        }
    }
    IF NOT ability["can_return"] { warn:ADD("return-to-Kerbin flag is weak"). }

    IF ability["solar"] < 1 {
        IF ability["available_dv"] > 0 { warn:ADD("no solar panels; EC depends on fuel cells/RTG"). }
    }
    IF ability["rwheel"] < 1 {
        IF ability["rcs"] < 1 { warn:ADD("little steering hardware (no RW/RCS counted)"). }
    }

    IF mission_kind = "grand_tour" {
        LOCAL eve_twr IS aoso_profile_surface_twr("Eve").
        LOCAL tylo_twr IS aoso_profile_surface_twr("Tylo").
        IF DEFINED AOSO_CAPS {
            SET eve_twr TO aoso_caps_surface_twr_for_config("LANDER", "Eve", 0).
            SET tylo_twr TO aoso_caps_surface_twr_for_config("LANDER", "Tylo", 0).
        }
        LOCAL min_twr IS aoso_config_get("TOUR_MIN_LAND_TWR", 1.4).
        IF eve_twr < 1.05 { warn:ADD("Eve surface TWR " + ROUND(eve_twr, 2) + " — Eve landing not certified"). }
        ELSE {
            IF eve_twr < 1.6 { warn:ADD("Eve surface TWR " + ROUND(eve_twr, 2) + " — Eve landing not certified"). }
        }
        IF tylo_twr < 1.05 { warn:ADD("Tylo surface TWR " + ROUND(tylo_twr, 2) + " — Tylo landing is a bottleneck"). }
        ELSE {
            IF tylo_twr < min_twr { warn:ADD("Tylo surface TWR " + ROUND(tylo_twr, 2) + " — Tylo landing is a bottleneck"). }
        }
        IF NOT ability["can_land"] { warn:ADD("no landing hardware — orbit-only tour"). }
        IF NOT ability["can_isru"] { warn:ADD("no ISRU — later hops use leftover fuel only"). }
        IF ability["heatshield"] < 1 { warn:ADD("no heat shield — Eve/Laythe/Kerbin entry is a risk"). }
        unk:ADD("window geometry at each hop is not certified until porkchop").
        IF DEFINED AOSO_PROJECT_LAST {
            IF AOSO_PROJECT_LAST:HASKEY("ok") {
                IF NOT AOSO_PROJECT_LAST["ok"] {
                    LOCAL weak_n IS "".
                    IF AOSO_PROJECT_LAST:HASKEY("weakest") { SET weak_n TO AOSO_PROJECT_LAST["weakest"]. }
                    warn:ADD("projected route fails at " + weak_n + " leftover " + ROUND(AOSO_PROJECT_LAST["min_margin"], 0) + " m/s").
                }
            }
            IF AOSO_PROJECT_LAST:HASKEY("min_margin") {
                IF AOSO_PROJECT_LAST["min_margin"] < 200 {
                    warn:ADD("weakest remaining margin " + ROUND(AOSO_PROJECT_LAST["min_margin"], 0) + " m/s at " + AOSO_PROJECT_LAST["weakest"]).
                }
            }
        }
    }

    IF SHIP:STATUS = "FLYING" { hard:ADD("cannot certify mid-ascent"). }

    LOCAL status_name IS "CERTIFIED".
    LOCAL conf IS 0.82.
    IF warn:LENGTH > 0 {
        SET status_name TO "CONDITIONAL".
        SET conf TO 0.62.
    }
    IF hard:LENGTH > 0 {
        SET status_name TO "NOT_CERTIFIED".
        SET conf TO 0.25.
    }

    LOCAL report IS LEXICON(
        "status", status_name,
        "mission", mission_kind,
        "hard_blockers", hard,
        "warnings", warn,
        "uncertainties", unk,
        "ability", ability,
        "confidence", conf,
        "weakest", "",
        "min_margin", 0,
        "at", TIME:SECONDS
    ).
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("weakest") { SET report["weakest"] TO AOSO_PROJECT_LAST["weakest"]. }
        IF AOSO_PROJECT_LAST:HASKEY("min_margin") { SET report["min_margin"] TO AOSO_PROJECT_LAST["min_margin"]. }
    }
    SET AOSO_CERT_LAST TO report.
    aoso_log_info("CERT", status_name + " " + mission_kind + " dv=" + ROUND(dv, 0) +
        " twr=" + ROUND(twr_now, 2) + " warn=" + warn:LENGTH + " hard=" + hard:LENGTH + ".").
    RETURN report.
}

FUNCTION aoso_cert_status {
    IF AOSO_CERT_LAST:HASKEY("status") { RETURN AOSO_CERT_LAST["status"]. }
    RETURN "UNKNOWN".
}
