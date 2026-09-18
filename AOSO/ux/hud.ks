// AOSO/ux/hud.ks
// Terminal status via PRINT AT (no kOS GUI window). The log keeps
// scrolling; these rows redraw in place so a long PLAN / warp / polar
// coast still shows what the ship is doing.

GLOBAL AOSO_HUD_ROWS IS 13.
GLOBAL AOSO_HUD_SPACES IS "                                                                                                    ".
GLOBAL AOSO_UI IS LEXICON("doing", "", "detail", "").

FUNCTION aoso_ui_set {
    PARAMETER doing.
    PARAMETER detail IS "".
    SET AOSO_UI["doing"] TO doing.
    SET AOSO_UI["detail"] TO detail.
}

FUNCTION aoso_ui_clear {
    SET AOSO_UI["doing"] TO "".
    SET AOSO_UI["detail"] TO "".
}

FUNCTION aoso_ui_pulse {
    PARAMETER doing.
    PARAMETER detail IS "".
    aoso_ui_set(doing, detail).
    aoso_hud_draw().
}

FUNCTION aoso_hud_line {
    PARAMETER row.
    PARAMETER text.

    LOCAL width IS 50.
    IF TERMINAL:WIDTH > 0 { SET width TO TERMINAL:WIDTH. }
    IF width > 100 { SET width TO 100. }

    LOCAL out IS text.
    IF out:LENGTH > width { SET out TO out:SUBSTRING(0, width). }
    IF out:LENGTH < width {
        SET out TO out + AOSO_HUD_SPACES:SUBSTRING(0, width - out:LENGTH).
    }
    PRINT out AT(0, row).
}

FUNCTION aoso_hud_km {
    PARAMETER meters.
    IF meters < 0 { RETURN ROUND(meters, 0) + " m". }
    IF meters >= 1000000 { RETURN ROUND(meters / 1000, 0) + " km". }
    IF meters >= 10000 { RETURN ROUND(meters / 1000, 1) + " km". }
    RETURN ROUND(meters, 0) + " m".
}

FUNCTION aoso_hud_eta {
    PARAMETER secs.
    IF secs < 0 { RETURN "now". }
    IF secs < 90 { RETURN ROUND(secs, 0) + "s". }
    IF secs < 3600 { RETURN ROUND(secs / 60, 1) + " min". }
    IF secs < 21600 { RETURN ROUND(secs / 3600, 1) + " h". }
    RETURN ROUND(secs / 21600, 1) + " d".
}

FUNCTION aoso_hud_warp_txt {
    RETURN aoso_warp_diag_txt().
}

FUNCTION aoso_hud_doing_text {
    IF AOSO_MANEUVER_BURNING {
        RETURN "BURNING  " + ROUND(AOSO_MANEUVER_LAST_REMAINING, 1) + " m/s left".
    }
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        RETURN "Node T-" + aoso_hud_eta(nd:ETA) + "  " + ROUND(nd:DELTAV:MAG, 1) + " m/s  " + aoso_hud_warp_txt().
    }
    IF AOSO_UI["doing"] <> "" { RETURN AOSO_UI["doing"]. }
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] = "COAST" {
            IF SHIP:ORBIT:HASNEXTPATCH {
                RETURN "Coasting to " + SHIP:ORBIT:NEXTPATCH:BODY:NAME + "  SOI " + aoso_hud_eta(SHIP:ORBIT:NEXTPATCHETA).
            }
            IF AOSO_GOTO["data"]:HASKEY("expect_body") {
                IF AOSO_GOTO["data"]["expect_body"] <> "" {
                    LOCAL left_e IS AOSO_GOTO["data"]["expect_ut"] - TIME:SECONDS.
                    RETURN "Trusting " + AOSO_GOTO["data"]["expect_body"] + " intercept  " + aoso_hud_eta(left_e).
                }
            }
            RETURN "Coasting - no patch yet".
        }
        IF AOSO_GOTO["current"] = "CAPTURE" { RETURN "Capture at PE (Oberth / polar if landing)". }
        IF AOSO_GOTO["current"] = "PLAN" { RETURN "Planning hop". }
        IF AOSO_GOTO["current"] = "WAIT" { RETURN "Waiting on transfer window". }
        IF AOSO_GOTO["current"] = "BURN" { RETURN "Transfer burn". }
    }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] = "POLAR" { RETURN "Polar insertion / plane change". }
        IF AOSO_TOUR["current"] = "SCAN" { RETURN "Scanning landing sites". }
        IF AOSO_TOUR["current"] = "DEORBIT" { RETURN "Waiting to deorbit over site". }
        IF AOSO_TOUR["current"] = "DESCEND" { RETURN "Descent". }
        IF AOSO_TOUR["current"] = "REFUEL" { RETURN "ISRU refuel". }
    }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" { RETURN "Ascent  " + AOSO_ASCENT["current"]. }
        }
    }
    RETURN aoso_hud_mission_status().
}

FUNCTION aoso_hud_mission_status {
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "" {
            RETURN AOSO_MISSION["current"] + " / " + aoso_mission_current_step_name().
        }
    }
    RETURN "idle".
}

FUNCTION aoso_hud_dv_status {
    LOCAL mission_dv IS 0.
    LOCAL total_dv IS 0.
    IF DEFINED AOSO_BUDGET {
        IF AOSO_BUDGET:HASKEY("mission_dv") { SET mission_dv TO AOSO_BUDGET["mission_dv"]. }
        IF AOSO_BUDGET:HASKEY("total_dv") { SET total_dv TO AOSO_BUDGET["total_dv"]. }
    }
    RETURN "dV " + ROUND(mission_dv, 0) + "/" + ROUND(total_dv, 0).
}

FUNCTION aoso_hud_caps_status {
    LOCAL class_txt IS "".
    IF DEFINED AOSO_CLASS_LAST {
        IF AOSO_CLASS_LAST:HASKEY("class") { SET class_txt TO AOSO_CLASS_LAST["class"] + "  ". }
    }
    LOCAL land_c IS "n".
    LOCAL isru_c IS "n".
    IF DEFINED AOSO_PROFILE {
        IF aoso_profile_capable("can_land") { SET land_c TO "Y". }
        IF aoso_profile_capable("can_isru") { SET isru_c TO "Y". }
    }
    RETURN class_txt + "land=" + land_c + " isru=" + isru_c.
}

FUNCTION aoso_hud_feas_status {
    LOCAL plan_txt IS "".
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("targets") {
                LOCAL idx IS AOSO_TOUR["data"]["index"].
                LOCAL tgts IS AOSO_TOUR["data"]["targets"].
                IF idx >= 0 {
                    IF idx < tgts:LENGTH {
                        SET plan_txt TO "Next " + tgts[idx] + "  ".
                    }
                }
            }
        }
    }
    IF DEFINED AOSO_FEAS_LAST {
        IF AOSO_FEAS_LAST:HASKEY("body") {
            RETURN plan_txt + "Feas " + AOSO_FEAS_LAST["body"] + ": " + AOSO_FEAS_LAST["result"].
        }
    }
    IF plan_txt <> "" { RETURN plan_txt. }
    RETURN "Feas: -".
}

FUNCTION aoso_hud_ascent_opt_status {
    IF DEFINED AOSO_ASCENT_OPT {
        RETURN aoso_ascent_opt_hud().
    }
    RETURN "Ascent opt: -".
}

FUNCTION aoso_hud_draw {
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 {
            aoso_hud_line(0, "AOSO CPU HIGH - shedding HUD").
            aoso_hud_line(1, SHIP:NAME + "  " + aoso_hud_doing_text()).
            aoso_hud_line(2, aoso_hud_mission_status()).
            RETURN.
        }
    }

    LOCAL mode IS "AUTO".
    IF AOSO_CONFIG["SAFE_MODE"] { SET mode TO "SAFE". }
    LOCAL ap_txt IS aoso_hud_km(aoso_orbit_apoapsis_alt()).
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { SET ap_txt TO "hyper". }

    aoso_hud_line(0, "==== AOSO  " + SHIP:NAME + "  " + mode + "  " + aoso_hud_warp_txt() + " ====").
    aoso_hud_line(1, "DOING  " + aoso_hud_doing_text()).
    aoso_hud_line(2, "       " + AOSO_UI["detail"]).
    aoso_hud_line(3, "Body " + SHIP:BODY:NAME + "  " + SHIP:STATUS + "  inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + "  e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 3)).
    aoso_hud_line(4, "Alt " + aoso_hud_km(ALTITUDE) + "  AP " + ap_txt + "  PE " + aoso_hud_km(PERIAPSIS)).
    aoso_hud_line(5, "Fuel " + ROUND(aoso_stage_propellant_pct(), 0) + "%  LF " + ROUND(aoso_resource_pct("LiquidFuel"), 0) + "%  EC " + ROUND(aoso_power_ec_pct(), 0) + "%  " + aoso_hud_dv_status()).
    aoso_hud_line(6, "Mission " + aoso_hud_mission_status() + "  " + aoso_hud_caps_status()).
    aoso_hud_line(7, aoso_hud_feas_status()).
    aoso_hud_line(8, aoso_hud_ascent_opt_status()).
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        aoso_hud_line(9, "Node T-" + aoso_hud_eta(nd:ETA) + "  " + ROUND(nd:DELTAV:MAG, 1) + " m/s  pro " + ROUND(nd:PROGRADE, 0) + " nml " + ROUND(nd:NORMAL, 0) + " rad " + ROUND(nd:RADIALOUT, 0)).
    } ELSE {
        aoso_hud_line(9, "Node none").
    }
    IF SHIP:ORBIT:HASNEXTPATCH {
        aoso_hud_line(10, "Patch " + SHIP:ORBIT:NEXTPATCH:BODY:NAME + " PE " + aoso_hud_km(SHIP:ORBIT:NEXTPATCH:PERIAPSIS) + " in " + aoso_hud_eta(SHIP:ORBIT:NEXTPATCHETA)).
    } ELSE {
        aoso_hud_line(10, "Patch none").
    }
    LOCAL wd IS "OK".
    IF aoso_watchdog_is_tripped() { SET wd TO "TRIPPED". }
    aoso_hud_line(11, "Watchdog " + wd + "  MET " + ROUND(MISSIONTIME, 0) + "s").
    aoso_hud_line(12, "").
}

FUNCTION aoso_hud_register_task {
    PARAMETER interval_s IS 0.5.
    aoso_hud_draw().
    aoso_sched_add("hud", interval_s, aoso_hud_draw@).
}
