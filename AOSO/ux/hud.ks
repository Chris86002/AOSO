// AOSO/ux/hud.ks
// Terminal status via PRINT AT (no kOS GUI window). The log keeps
// scrolling; these rows redraw in place so a long PLAN / warp / polar
// coast still shows what the ship is doing.
//
// Subsystems publish into AOSO_SYS with aoso_sys_set(); aoso_hud_draw()
// also polls live globals so a module that forgets to report still shows.

GLOBAL AOSO_HUD_ROWS IS 20.
GLOBAL AOSO_HUD_SPACES IS "                                                                                                    ".
GLOBAL AOSO_UI IS LEXICON("doing", "", "detail", "").
GLOBAL AOSO_SYS IS LEXICON().

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

FUNCTION aoso_sys_set {
    PARAMETER sys_name.
    PARAMETER status.
    PARAMETER detail IS "".
    SET AOSO_SYS[sys_name] TO LEXICON("status", status, "detail", detail, "ut", TIME:SECONDS).
}

FUNCTION aoso_sys_status {
    PARAMETER sys_name.
    IF NOT AOSO_SYS:HASKEY(sys_name) { RETURN "OFF". }
    RETURN AOSO_SYS[sys_name]["status"].
}

FUNCTION aoso_hud_line {
    PARAMETER row.
    PARAMETER text.

    LOCAL width IS 64.
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

FUNCTION aoso_hud_pad {
    PARAMETER s.
    PARAMETER n.
    LOCAL out IS "" + s.
    UNTIL out:LENGTH >= n {
        SET out TO out + " ".
    }
    IF out:LENGTH > n { RETURN out:SUBSTRING(0, n). }
    RETURN out.
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
            IF AOSO_GOTO:HASKEY("data") {
                IF AOSO_GOTO["data"]:HASKEY("expect_body") {
                    IF AOSO_GOTO["data"]["expect_body"] <> "" {
                        LOCAL left_e IS AOSO_GOTO["data"]["expect_ut"] - TIME:SECONDS.
                        RETURN "Trusting " + AOSO_GOTO["data"]["expect_body"] + " intercept  " + aoso_hud_eta(left_e).
                    }
                }
            }
            RETURN "Coasting - no patch yet".
        }
        IF AOSO_GOTO["current"] = "CAPTURE" { RETURN "Capture at PE (Oberth / polar if landing)". }
        IF AOSO_GOTO["current"] = "PLAN" { RETURN "Planning hop". }
        IF AOSO_GOTO["current"] = "WAIT" { RETURN "Waiting on transfer window". }
        IF AOSO_GOTO["current"] = "BURN" { RETURN "Transfer burn". }
        IF AOSO_GOTO["current"] = "LAUNCH" { RETURN "Launching before hop". }
    }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] = "POLAR" { RETURN "Polar insertion / plane change". }
        IF AOSO_TOUR["current"] = "SCAN" { RETURN "Scanning landing sites". }
        IF AOSO_TOUR["current"] = "DEORBIT" { RETURN "Waiting to deorbit over site". }
        IF AOSO_TOUR["current"] = "DESCEND" { RETURN "Descent". }
        IF AOSO_TOUR["current"] = "REFUEL" { RETURN "ISRU refuel". }
        IF AOSO_TOUR["current"] = "RETURN" { RETURN "Returning home". }
        IF AOSO_TOUR["current"] = "KSC" { RETURN "KSC precision return". }
    }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" { RETURN "Ascent  " + AOSO_ASCENT["current"]. }
        }
    }
    IF DEFINED AOSO_DESCENT {
        IF AOSO_DESCENT["current"] <> "" {
            IF AOSO_DESCENT["current"] <> "TOUCHDOWN" {
                IF AOSO_DESCENT["current"] <> "ABORTED" {
                    RETURN "Descent  " + AOSO_DESCENT["current"].
                }
            }
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
    RETURN "dV " + ROUND(mission_dv, 0) + "/" + ROUND(total_dv, 0) + " m/s".
}

FUNCTION aoso_hud_caps_status {
    LOCAL class_txt IS "".
    IF DEFINED AOSO_CLASS_LAST {
        IF AOSO_CLASS_LAST:HASKEY("class") { SET class_txt TO AOSO_CLASS_LAST["class"] + "  ". }
    }
    LOCAL land_c IS "n".
    LOCAL isru_c IS "n".
    LOCAL dock_c IS "n".
    IF DEFINED AOSO_PROFILE {
        IF aoso_profile_capable("can_land") { SET land_c TO "Y". }
        IF aoso_profile_capable("can_isru") { SET isru_c TO "Y". }
        IF aoso_profile_capable("can_dock") { SET dock_c TO "Y". }
    }
    RETURN class_txt + "land=" + land_c + " isru=" + isru_c + " dock=" + dock_c.
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

FUNCTION aoso_hud_twr {
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL g IS SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
    IF g <= 0 { RETURN 0. }
    RETURN SHIP:AVAILABLETHRUST / (SHIP:MASS * g).
}

FUNCTION aoso_hud_aoa_deg {
    IF SHIP:VELOCITY:SURFACE:MAG < 1 { RETURN 0. }
    RETURN VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE).
}

FUNCTION aoso_hud_cpu_txt {
    LOCAL ipu IS CONFIG:IPU.
    LOCAL used IS 0.
    LOCAL frac IS 0.
    LOCAL cname IS "NORMAL".
    IF DEFINED AOSO_CPU_USED { SET used TO AOSO_CPU_USED. }
    IF DEFINED AOSO_CPU_FRAC { SET frac TO AOSO_CPU_FRAC. }
    IF DEFINED AOSO_CPU_NAME { SET cname TO AOSO_CPU_NAME. }
    RETURN cname + "  " + ROUND(100 * frac, 0) + "% of " + ipu + " IPU  used " + ROUND(used, 0).
}

FUNCTION aoso_hud_poll_systems {
    LOCAL cpu_st IS "NOM".
    LOCAL cpu_det IS aoso_hud_cpu_txt().
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 { SET cpu_st TO "FAIL". }
        ELSE {
            IF AOSO_CPU_LEVEL >= 2 { SET cpu_st TO "DEG". }
        }
    }
    aoso_sys_set("CPU", cpu_st, cpu_det).

    LOCAL ec IS aoso_power_ec_pct().
    LOCAL pwr_st IS "NOM".
    IF ec <= aoso_config_get("WATCHDOG_EC_CRITICAL_PCT", 5) { SET pwr_st TO "FAIL". }
    ELSE {
        IF ec <= aoso_config_get("LOW_EC_PCT", 20) { SET pwr_st TO "DEG". }
    }
    aoso_sys_set("PWR", pwr_st, ROUND(ec, 0) + "% EC").

    LOCAL wd_st IS "NOM".
    LOCAL wd_det IS "OK".
    IF aoso_watchdog_is_tripped() {
        SET wd_st TO "FAIL".
        SET wd_det TO "TRIPPED".
    }
    aoso_sys_set("WD", wd_st, wd_det).

    LOCAL stg_st IS "NOM".
    LOCAL stg_det IS "stg " + STAGE:NUMBER.
    IF SHIP:AVAILABLETHRUST <= 0 {
        IF SHIP:STATUS = "FLYING" { SET stg_st TO "DEG". SET stg_det TO "no thrust". }
        IF SHIP:STATUS = "SUB_ORBITAL" { SET stg_st TO "DEG". SET stg_det TO "no thrust". }
    }
    aoso_sys_set("STG", stg_st, stg_det).

    LOCAL steer_st IS "NOM".
    LOCAL steer_det IS "OFF".
    IF DEFINED AOSO_STEER_MODE { SET steer_det TO AOSO_STEER_MODE. }
    IF AOSO_MANEUVER_BURNING {
        IF DEFINED AOSO_STEER_MODE {
            IF AOSO_STEER_MODE = "OFF" { SET steer_st TO "DEG". }
        }
    }
    aoso_sys_set("STEER", steer_st, steer_det).

    LOCAL wrp_st IS "NOM".
    aoso_sys_set("WRP", wrp_st, aoso_hud_warp_txt()).

    LOCAL nav_st IS "NOM".
    LOCAL nav_det IS "idle".
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] <> "" { SET nav_det TO AOSO_GOTO["current"]. }
        IF AOSO_GOTO["current"] = "ABORTED" { SET nav_st TO "FAIL". }
        IF AOSO_GOTO:HASKEY("data") {
            IF AOSO_GOTO["data"]:HASKEY("goal") {
                IF AOSO_GOTO["data"]["goal"] <> "" {
                    SET nav_det TO nav_det + " -> " + AOSO_GOTO["data"]["goal"].
                }
            }
            IF AOSO_GOTO["data"]:HASKEY("hop") {
                IF AOSO_GOTO["data"]["hop"] <> "" {
                    SET nav_det TO nav_det + " hop " + AOSO_GOTO["data"]["hop"].
                }
            }
        }
    }
    aoso_sys_set("NAV", nav_st, nav_det).

    LOCAL msn_st IS "NOM".
    LOCAL msn_det IS aoso_hud_mission_status().
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] = "ABORTED" { SET msn_st TO "FAIL". }
    }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] = "ABORTED" { SET msn_st TO "FAIL". }
        IF AOSO_TOUR["current"] <> "" {
            SET msn_det TO msn_det + "  tour " + AOSO_TOUR["current"].
        }
    }
    aoso_sys_set("MSN", msn_st, msn_det).

    LOCAL com_st IS "NOM".
    LOCAL com_det IS "ok".
    LOCAL net IS aoso_world_network_summary().
    IF NOT net["has_antenna"] {
        SET com_st TO "DEG".
        SET com_det TO "no antenna".
    }
    IF net["blackout_risk"] {
        SET com_st TO "DEG".
        SET com_det TO "blackout risk".
    }
    IF NOT net["in_home_soi"] {
        SET com_det TO com_det + "  deep".
    }
    aoso_sys_set("COM", com_st, com_det).
}

FUNCTION aoso_hud_sys_rollup {
    LOCAL worst IS "NOM".
    LOCAL fail_n IS 0.
    LOCAL deg_n IS 0.
    FOR k IN AOSO_SYS:KEYS {
        LOCAL st IS AOSO_SYS[k]["status"].
        IF st = "FAIL" {
            SET worst TO "FAIL".
            SET fail_n TO fail_n + 1.
        } ELSE {
            IF st = "DEG" {
                IF worst <> "FAIL" { SET worst TO "DEG". }
                SET deg_n TO deg_n + 1.
            }
        }
    }
    IF worst = "FAIL" { RETURN "FAIL  " + fail_n + " failed  " + deg_n + " degraded". }
    IF worst = "DEG" { RETURN "DEGRADED  " + deg_n + " caution". }
    RETURN "NOMINAL".
}

FUNCTION aoso_hud_sys_chip {
    PARAMETER name.
    LOCAL st IS aoso_sys_status(name).
    RETURN name + ":" + st.
}

FUNCTION aoso_hud_prepare_terminal {
    IF TERMINAL:WIDTH < 64 { SET TERMINAL:WIDTH TO 64. }
    IF TERMINAL:HEIGHT < 42 { SET TERMINAL:HEIGHT TO 42. }
}

FUNCTION aoso_hud_draw {
    aoso_hud_prepare_terminal().
    aoso_hud_poll_systems().

    LOCAL shed IS FALSE.
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 { SET shed TO TRUE. }
    }
    IF shed {
        aoso_hud_line(0, "AOSO  SYS " + aoso_hud_sys_rollup() + "  CPU CRITICAL - compact HUD").
        aoso_hud_line(1, SHIP:NAME + "  " + aoso_hud_doing_text()).
        aoso_hud_line(2, aoso_hud_mission_status() + "  " + aoso_sys_status("PWR") + " EC " + ROUND(aoso_power_ec_pct(), 0) + "%").
        aoso_hud_line(3, aoso_hud_cpu_txt()).
        RETURN.
    }

    LOCAL mode IS "AUTO".
    IF AOSO_CONFIG["SAFE_MODE"] { SET mode TO "SAFE". }
    LOCAL ap_txt IS aoso_hud_km(aoso_orbit_apoapsis_alt()).
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { SET ap_txt TO "hyper". }

    LOCAL sas_txt IS "SAS off".
    IF SAS { SET sas_txt TO "SAS " + SASMODE. }
    LOCAL rcs_txt IS "RCS off".
    IF RCS { SET rcs_txt TO "RCS on". }

    aoso_hud_line(0, "==== AOSO  " + SHIP:NAME + "  " + mode + "  SYS " + aoso_hud_sys_rollup() + " ====").
    aoso_hud_line(1, aoso_hud_sys_chip("CPU") + "  " + aoso_hud_sys_chip("PWR") + "  " + aoso_hud_sys_chip("WD") + "  " + aoso_hud_sys_chip("STG") + "  " + aoso_hud_sys_chip("COM")).
    aoso_hud_line(2, aoso_hud_sys_chip("NAV") + "  " + aoso_hud_sys_chip("MSN") + "  " + aoso_hud_sys_chip("STEER") + "  " + aoso_hud_sys_chip("WRP")).
    aoso_hud_line(3, "CPU  " + aoso_hud_cpu_txt()).
    aoso_hud_line(4, "DOING  " + aoso_hud_doing_text()).
    aoso_hud_line(5, "       " + AOSO_UI["detail"]).
    aoso_hud_line(6, "Body " + SHIP:BODY:NAME + "  " + SHIP:STATUS + "  inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + "  e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 3)).
    aoso_hud_line(7, "Alt " + aoso_hud_km(ALTITUDE) + "  AP " + ap_txt + "  PE " + aoso_hud_km(PERIAPSIS) + "  TWR " + ROUND(aoso_hud_twr(), 2)).
    aoso_hud_line(8, "Fuel " + ROUND(aoso_stage_propellant_pct(), 0) + "%  LF " + ROUND(aoso_resource_pct("LiquidFuel"), 0) + "%  EC " + ROUND(aoso_power_ec_pct(), 0) + "%  " + aoso_hud_dv_status()).
    aoso_hud_line(9, "Thr " + ROUND(THROTTLE * 100, 0) + "%  Q " + ROUND(SHIP:Q, 3) + " atm  AoA " + ROUND(aoso_hud_aoa_deg(), 1) + "  " + sas_txt + "  " + rcs_txt).
    aoso_hud_line(10, "Mission " + aoso_hud_mission_status() + "  " + aoso_hud_caps_status()).
    aoso_hud_line(11, aoso_hud_feas_status()).
    aoso_hud_line(12, aoso_hud_ascent_opt_status()).
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        aoso_hud_line(13, "Node T-" + aoso_hud_eta(nd:ETA) + "  " + ROUND(nd:DELTAV:MAG, 1) + " m/s  pro " + ROUND(nd:PROGRADE, 0) + " nml " + ROUND(nd:NORMAL, 0) + " rad " + ROUND(nd:RADIALOUT, 0)).
    } ELSE {
        aoso_hud_line(13, "Node none").
    }
    IF SHIP:ORBIT:HASNEXTPATCH {
        aoso_hud_line(14, "Patch " + SHIP:ORBIT:NEXTPATCH:BODY:NAME + " PE " + aoso_hud_km(SHIP:ORBIT:NEXTPATCH:PERIAPSIS) + " in " + aoso_hud_eta(SHIP:ORBIT:NEXTPATCHETA)).
    } ELSE {
        aoso_hud_line(14, "Patch none").
    }
    LOCAL nav_det IS "".
    IF AOSO_SYS:HASKEY("NAV") { SET nav_det TO AOSO_SYS["NAV"]["detail"]. }
    LOCAL pwr_det IS "".
    IF AOSO_SYS:HASKEY("PWR") { SET pwr_det TO AOSO_SYS["PWR"]["detail"]. }
    LOCAL wd_det IS "OK".
    IF AOSO_SYS:HASKEY("WD") { SET wd_det TO AOSO_SYS["WD"]["detail"]. }
    aoso_hud_line(15, "NAV " + nav_det + "  PWR " + pwr_det + "  WD " + wd_det).
    aoso_hud_line(16, "COM " + AOSO_SYS["COM"]["detail"] + "  STEER " + AOSO_SYS["STEER"]["detail"] + "  " + aoso_hud_warp_txt()).
    aoso_hud_line(17, "Watchdog " + wd_det + "  MET " + ROUND(MISSIONTIME, 0) + "s  IPU " + CONFIG:IPU).
    aoso_hud_line(18, "").
    aoso_hud_line(19, "").
}

FUNCTION aoso_hud_register_task {
    PARAMETER interval_s IS 0.25.
    aoso_hud_prepare_terminal().
    aoso_hud_draw().
    aoso_sched_add("hud", interval_s, aoso_hud_draw@).
}
