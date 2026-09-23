// AOSO/mission/launch_hold.ks
// Pad commit. On PRELAUNCH the ship does not ignite until every launch
// light is green and the operator presses LAUNCH.
//
// The CRT button only sets AOSO_LAUNCH_COMMIT. This file owns the
// calculations and the later call to aoso_mission_start(). Later surface
// hops (LANDED / SPLASHED) are not held: an unattended tour can still
// leave the Mun without someone sitting on the button.

GLOBAL AOSO_LAUNCH_COMMIT IS FALSE.
GLOBAL AOSO_LAUNCH_PREP_DONE IS FALSE.
GLOBAL AOSO_LAUNCH_PHASE IS 0.
GLOBAL AOSO_LAUNCH_STARTED IS FALSE.
GLOBAL AOSO_LAUNCH_INHIBIT_LOG IS FALSE.
GLOBAL AOSO_LAUNCH_BOARD IS LEXICON().
GLOBAL AOSO_LAUNCH_DEPART IS LEXICON().
GLOBAL AOSO_LAUNCH_DEPART_AT IS -1.
GLOBAL AOSO_LAUNCH_ORDER IS LIST(
    "wd", "eng", "fuel", "pwr", "ctrl", "stg",
    "ves", "cls", "bgt", "pln", "prj", "dep"
).

FUNCTION aoso_launch_hold_active {
    IF NOT aoso_config_get("LAUNCH_HOLD", TRUE) { RETURN FALSE. }
    IF SHIP:STATUS <> "PRELAUNCH" { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_launch_blocked {
    IF NOT aoso_launch_hold_active() { RETURN FALSE. }
    IF AOSO_LAUNCH_COMMIT { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_launch_put {
    PARAMETER lamps.
    PARAMETER lamp_id.
    PARAMETER lamp_label.
    PARAMETER lamp_state.
    PARAMETER lamp_detail.
    SET lamps[lamp_id] TO LEXICON(
        "label", lamp_label,
        "state", lamp_state,
        "detail", lamp_detail
    ).
    IF lamp_state <> "GO" {
        SET AOSO_LAUNCH_BOARD["arm"] TO FALSE.
        IF AOSO_LAUNCH_BOARD["reason"] = "" {
            SET AOSO_LAUNCH_BOARD["reason"] TO lamp_label + "  " + lamp_state.
            IF lamp_detail <> "" {
                SET AOSO_LAUNCH_BOARD["reason"] TO AOSO_LAUNCH_BOARD["reason"] + "  " + lamp_detail.
            }
        }
    }
}

FUNCTION aoso_launch_depart_refresh {
    PARAMETER min_age.
    LOCAL refresh_it IS TRUE.
    IF AOSO_LAUNCH_DEPART:HASKEY("status") {
        IF TIME:SECONDS - AOSO_LAUNCH_DEPART_AT < min_age { SET refresh_it TO FALSE. }
    }
    IF NOT refresh_it { RETURN. }
    SET AOSO_LAUNCH_DEPART TO aoso_depart_certify().
    SET AOSO_LAUNCH_DEPART_AT TO TIME:SECONDS.
}

FUNCTION aoso_launch_board_eval {
    PARAMETER force IS FALSE.
    IF NOT force {
        IF AOSO_LAUNCH_BOARD:HASKEY("at") {
            IF TIME:SECONDS - AOSO_LAUNCH_BOARD["at"] < 0.25 { RETURN. }
        }
    }

    SET AOSO_LAUNCH_BOARD["arm"] TO TRUE.
    SET AOSO_LAUNCH_BOARD["reason"] TO "".
    SET AOSO_LAUNCH_BOARD["items"] TO LEXICON().
    LOCAL lamps IS AOSO_LAUNCH_BOARD["items"].
    SET AOSO_LAUNCH_BOARD["commit"] TO AOSO_LAUNCH_COMMIT.

    LOCAL parts_n IS 0.
    LOCAL eng_n IS 0.
    IF AOSO_PROFILE:HASKEY("part_count") { SET parts_n TO AOSO_PROFILE["part_count"]. }
    IF AOSO_PROFILE:HASKEY("propulsion") {
        IF AOSO_PROFILE["propulsion"]:HASKEY("engines") {
            SET eng_n TO AOSO_PROFILE["propulsion"]["engines"].
        }
    }

    LOCAL wd_state IS "GO".
    LOCAL wd_detail IS "OK".
    IF aoso_watchdog_is_tripped() {
        SET wd_state TO "FAIL".
        SET wd_detail TO "TRIPPED".
    }
    aoso_launch_put(lamps, "wd", "WATCH", wd_state, wd_detail).

    LOCAL twr_now IS 0.
    IF AOSO_LAUNCH_DEPART:HASKEY("twr") {
        SET twr_now TO AOSO_LAUNCH_DEPART["twr"].
    } ELSE {
        IF parts_n > 0 {
            IF DEFINED AOSO_CAPS {
                SET twr_now TO aoso_caps_surface_twr_for_config("ALL", SHIP:BODY:NAME, SHIP:MASS).
            }
        }
    }
    LOCAL eng_state IS "CALC".
    LOCAL eng_detail IS "WORKING".
    IF parts_n <= 0 {
        SET eng_state TO "CALC".
        SET eng_detail TO "SCAN".
    } ELSE {
        IF eng_n <= 0 {
            SET eng_state TO "FAIL".
            SET eng_detail TO "NO ENG".
        } ELSE {
            IF twr_now >= 1.05 {
                SET eng_state TO "GO".
                SET eng_detail TO "TWR " + ROUND(twr_now, 2).
            } ELSE {
                SET eng_state TO "FAIL".
                SET eng_detail TO "TWR " + ROUND(twr_now, 2).
            }
        }
    }
    aoso_launch_put(lamps, "eng", "ENGINES", eng_state, eng_detail).

    LOCAL fuel_pct IS 0.
    IF parts_n > 0 { SET fuel_pct TO aoso_resource_pct("LiquidFuel"). }
    LOCAL fuel_state IS "CALC".
    LOCAL fuel_detail IS "SCAN".
    IF parts_n > 0 {
        SET fuel_detail TO ROUND(fuel_pct, 0) + "%".
        IF fuel_pct < 8 {
            SET fuel_state TO "FAIL".
        } ELSE {
            SET fuel_state TO "GO".
        }
    }
    aoso_launch_put(lamps, "fuel", "FUEL", fuel_state, fuel_detail).

    LOCAL ec_pct IS aoso_resource_pct("ElectricCharge").
    LOCAL ec_floor IS aoso_config_get("WATCHDOG_EC_CRITICAL_PCT", 5).
    LOCAL pwr_state IS "GO".
    LOCAL pwr_detail IS "EC " + ROUND(ec_pct, 0) + "%".
    IF ec_pct <= ec_floor {
        SET pwr_state TO "FAIL".
    }
    aoso_launch_put(lamps, "pwr", "POWER", pwr_state, pwr_detail).

    LOCAL ctrl_ok IS FALSE.
    LOCAL ctrl_detail IS "NONE".
    IF SHIP:CREW:LENGTH > 0 {
        SET ctrl_ok TO TRUE.
        SET ctrl_detail TO "CREW " + SHIP:CREW:LENGTH.
    }
    IF SHIP:CONTROLPART:ISTYPE("Part") {
        SET ctrl_ok TO TRUE.
        IF ctrl_detail = "NONE" { SET ctrl_detail TO "CPU". }
    }
    LOCAL ctrl_state IS "FAIL".
    IF ctrl_ok { SET ctrl_state TO "GO". }
    aoso_launch_put(lamps, "ctrl", "CONTROL", ctrl_state, ctrl_detail).

    LOCAL stg_state IS "GO".
    LOCAL stg_detail IS "AUTO".
    IF aoso_config_get("SAFE_MODE", FALSE) {
        SET stg_state TO "FAIL".
        SET stg_detail TO "SAFE MODE".
    }
    aoso_launch_put(lamps, "stg", "STAGE", stg_state, stg_detail).

    LOCAL ves_state IS "CALC".
    LOCAL ves_detail IS "SCAN".
    IF parts_n > 0 {
        SET ves_state TO "GO".
        SET ves_detail TO parts_n + " PARTS".
    }
    aoso_launch_put(lamps, "ves", "VESSEL", ves_state, ves_detail).

    LOCAL class_name IS "".
    IF AOSO_CLASS_LAST:HASKEY("class") { SET class_name TO AOSO_CLASS_LAST["class"]. }
    LOCAL cls_state IS "CALC".
    LOCAL cls_detail IS "WORKING".
    IF class_name <> "" {
        SET cls_state TO "GO".
        SET cls_detail TO class_name.
    }
    aoso_launch_put(lamps, "cls", "CLASS", cls_state, cls_detail).

    LOCAL bgt_state IS "CALC".
    LOCAL bgt_detail IS "WORKING".
    IF AOSO_BUDGET:HASKEY("refreshed_at") {
        SET bgt_state TO "GO".
        SET bgt_detail TO ROUND(aoso_budget_get("mission_dv", 0), 0) + " M/S".
    }
    aoso_launch_put(lamps, "bgt", "BUDGET", bgt_state, bgt_detail).

    LOCAL pln_state IS "CALC".
    LOCAL pln_detail IS "WORKING".
    IF AOSO_PLAN_LAST:HASKEY("built_at") {
        SET pln_state TO "GO".
        LOCAL plan_n IS 0.
        IF AOSO_PLAN_LAST:HASKEY("targets") {
            LOCAL plan_targets IS AOSO_PLAN_LAST["targets"].
            SET plan_n TO plan_targets:LENGTH.
        }
        SET pln_detail TO plan_n + " BODIES".
        IF AOSO_PLAN_LAST:HASKEY("provisional") {
            IF AOSO_PLAN_LAST["provisional"] { SET pln_detail TO pln_detail + " PROVISIONAL". }
        }
    }
    aoso_launch_put(lamps, "pln", "PLAN", pln_state, pln_detail).

    LOCAL prj_state IS "CALC".
    LOCAL prj_detail IS "WORKING".
    IF AOSO_PROJECT_LAST:HASKEY("at") {
        SET prj_state TO "GO".
        LOCAL end_dv IS 0.
        IF AOSO_PROJECT_LAST:HASKEY("end_dv") { SET end_dv TO AOSO_PROJECT_LAST["end_dv"]. }
        SET prj_detail TO "END " + ROUND(end_dv, 0).
    }
    aoso_launch_put(lamps, "prj", "PROJECT", prj_state, prj_detail).

    LOCAL dep_state IS "CALC".
    LOCAL dep_detail IS "WORKING".
    IF AOSO_LAUNCH_DEPART:HASKEY("status") {
        SET dep_detail TO AOSO_LAUNCH_DEPART["reason"].
        IF AOSO_LAUNCH_DEPART["status"] = "NOT_READY" {
            SET dep_state TO "FAIL".
        } ELSE {
            SET dep_state TO "GO".
        }
    }
    aoso_launch_put(lamps, "dep", "DEPART", dep_state, dep_detail).

    IF AOSO_LAUNCH_BOARD["arm"] {
        SET AOSO_LAUNCH_BOARD["reason"] TO "all lights green".
    }
    LOCAL cert_txt IS "".
    IF DEFINED AOSO_CERT_LAST {
        IF AOSO_CERT_LAST:HASKEY("status") { SET cert_txt TO AOSO_CERT_LAST["status"]. }
    }
    SET AOSO_LAUNCH_BOARD["cert"] TO cert_txt.
    SET AOSO_LAUNCH_BOARD["at"] TO TIME:SECONDS.
}

FUNCTION aoso_launch_request {
    aoso_launch_board_eval(TRUE).
    IF NOT aoso_launch_hold_active() {
        aoso_log_info("LAUNCH", "Launch button ignored. Not on the pad.").
        RETURN FALSE.
    }
    IF AOSO_LAUNCH_COMMIT { RETURN TRUE. }
    IF NOT AOSO_LAUNCH_BOARD["arm"] {
        aoso_log_warn("LAUNCH", "Button dark. " + AOSO_LAUNCH_BOARD["reason"]).
        RETURN FALSE.
    }
    SET AOSO_LAUNCH_COMMIT TO TRUE.
    SET AOSO_LAUNCH_INHIBIT_LOG TO FALSE.
    aoso_log_info("LAUNCH", "Launch button green. Operator commit.").
    aoso_ui_set("LAUNCH", "commit").
    RETURN TRUE.
}

FUNCTION aoso_launch_prep_tick {
    IF NOT aoso_launch_hold_active() { RETURN. }

    IF AOSO_LAUNCH_COMMIT {
        IF NOT AOSO_LAUNCH_STARTED {
            SET AOSO_LAUNCH_STARTED TO TRUE.
            IF AOSO_MISSION["current"] = "" {
                aoso_log_info("LAUNCH", "Commit accepted. Starting the mission.").
                aoso_mission_start().
            } ELSE {
                aoso_log_info("LAUNCH", "Commit accepted. Pad hold released.").
            }
        }
        RETURN.
    }

    IF AOSO_LAUNCH_PHASE = 0 {
        SET AOSO_LAUNCH_PHASE TO 1.
        aoso_launch_board_eval(TRUE).
        aoso_ui_set("HOLD", "systems check").
        RETURN.
    }

    IF AOSO_LAUNCH_PHASE = 1 {
        IF NOT AOSO_PLAN_LAST:HASKEY("built_at") {
            aoso_ui_set("HOLD", "building the plan").
            aoso_plan_build().
        }
        SET AOSO_LAUNCH_PREP_DONE TO TRUE.
        SET AOSO_LAUNCH_PHASE TO 2.
        aoso_launch_board_eval(TRUE).
        RETURN.
    }

    IF AOSO_LAUNCH_PHASE = 2 {
        aoso_cert_eval("grand_tour").
        aoso_assure_eval().
        aoso_launch_depart_refresh(0).
        SET AOSO_LAUNCH_PHASE TO 3.
        aoso_launch_board_eval(TRUE).
        RETURN.
    }

    IF AOSO_LAUNCH_DEPART:HASKEY("status") {
        IF AOSO_LAUNCH_DEPART["status"] = "NOT_READY" {
            aoso_launch_depart_refresh(2).
        }
    } ELSE {
        aoso_launch_depart_refresh(0).
    }
    aoso_launch_board_eval(TRUE).
    IF AOSO_LAUNCH_BOARD["arm"] {
        aoso_ui_set("HOLD", "launch armed").
    } ELSE {
        aoso_ui_set("HOLD", AOSO_LAUNCH_BOARD["reason"]).
    }
}

FUNCTION aoso_launch_prep_register {
    aoso_mission_register_task().
    aoso_sched_add("launch_hold", 0.35, aoso_launch_prep_tick@).
}
