// AOSO/ux/hud.ks
// Phase 12 (Hardening & UX): a fixed-position terminal status readout so an
// operator watching the console doesn't have to scroll back through
// core/logger.ks's own PRINT'd log lines to see what AOSO is currently
// doing. Uses PRINT ... AT(col,row), which redraws in place without
// scrolling, so it can be safely combined with the logger's ordinary
// scrolling PRINT calls underneath it -- the same layout convention every
// kOS HUD script uses. Every value is either a stock SHIP:*/bound-variable
// suffix or one of this repo's own getters (vehicle/resources.ks,
// power/power.ks, mission/mission.ks); no new suffixes are invented.

GLOBAL AOSO_HUD_ROWS IS 11. // rows 0..(AOSO_HUD_ROWS-1) are reserved for the HUD

// Pads/truncates to the terminal width so a shorter status line fully
// overwrites a longer one left over from a previous tick instead of
// leaving stale trailing characters on screen.
FUNCTION aoso_hud_line {
    PARAMETER row.
    PARAMETER text.

    LOCAL width IS 50.
    IF TERMINAL:WIDTH > 0 { SET width TO TERMINAL:WIDTH. }

    LOCAL out IS text.
    IF out:LENGTH > width { SET out TO out:SUBSTRING(0, width). }
    UNTIL out:LENGTH >= width { SET out TO out + " ". }
    PRINT out AT(0, row).
}

FUNCTION aoso_hud_mission_status {
    // kOS's grammar only allows a single unary prefix (NOT *or* DEFINED, not
    // both), so "IF NOT DEFINED x OR ..." is a parse error -- nest the
    // DEFINED check instead.
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "" {
            LOCAL step_name IS "".
            SET step_name TO aoso_mission_current_step_name().
            RETURN AOSO_MISSION["current"] + " / " + step_name.
        }
    }
    RETURN "N/A".
}

FUNCTION aoso_hud_draw {
    LOCAL ec_pct IS 0.
    SET ec_pct TO aoso_power_ec_pct().
    LOCAL fuel_pct IS 0.
    SET fuel_pct TO aoso_stage_propellant_pct().
    LOCAL watchdog_status IS "OK".
    IF aoso_watchdog_is_tripped() { SET watchdog_status TO "TRIPPED". }
    LOCAL mode IS "AUTO".
    IF aoso_config_get("SAFE_MODE", FALSE) { SET mode TO "SAFE". }

    aoso_hud_line(0, "==== AOSO - " + SHIP:NAME + " (" + mode + ") ====").
    aoso_hud_line(1, "Body: " + SHIP:BODY:NAME + "   MET: " + ROUND(MISSIONTIME, 0) + "s").
    aoso_hud_line(2, "Alt: " + ROUND(ALTITUDE, 0) + "m   Radar: " + ROUND(ALT:RADAR, 0) + "m").
    aoso_hud_line(3, "Apo: " + ROUND(SHIP:APOAPSIS, 0) + "m   Peri: " + ROUND(SHIP:PERIAPSIS, 0) + "m").
    aoso_hud_line(4, "Speed: " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) + "m/s   VSpd: " + ROUND(VERTICALSPEED, 1) + "m/s").
    aoso_hud_line(5, "Fuel(stage): " + ROUND(fuel_pct, 1) + "%   EC: " + ROUND(ec_pct, 1) + "%").
    aoso_hud_line(6, "Throttle: " + ROUND(THROTTLE * 100, 0) + "%   SAS: " + SAS + "   RCS: " + RCS).
    aoso_hud_line(7, "Mission: " + aoso_hud_mission_status()).
    aoso_hud_line(8, "Watchdog: " + watchdog_status + "   " + aoso_hud_dv_status()).
    aoso_hud_line(9, aoso_hud_caps_status()).
    aoso_hud_line(10, aoso_hud_feas_status()).
}

FUNCTION aoso_hud_dv_status {
    LOCAL mission_dv IS 0.
    LOCAL total_dv IS 0.
    IF DEFINED AOSO_BUDGET {
        IF AOSO_BUDGET:HASKEY("mission_dv") { SET mission_dv TO AOSO_BUDGET["mission_dv"]. }
        IF AOSO_BUDGET:HASKEY("total_dv") { SET total_dv TO AOSO_BUDGET["total_dv"]. }
    }
    RETURN "dV mis " + ROUND(mission_dv, 0) + "/" + ROUND(total_dv, 0).
}

FUNCTION aoso_hud_caps_status {
    LOCAL land_c IS "n".
    LOCAL isru_c IS "n".
    LOCAL dock_c IS "n".
    IF DEFINED AOSO_PROFILE {
        IF aoso_profile_capable("can_land") { SET land_c TO "Y". }
        IF aoso_profile_capable("can_isru") { SET isru_c TO "Y". }
        IF aoso_profile_capable("can_dock") { SET dock_c TO "Y". }
    }
    RETURN "Caps land=" + land_c + " isru=" + isru_c + " dock=" + dock_c + aoso_hud_stage_pred().
}

FUNCTION aoso_hud_stage_pred {
    IF DEFINED AOSO_CAPS {
        IF AOSO_CAPS:HASKEY("prediction") {
            LOCAL pred IS AOSO_CAPS["prediction"].
            IF pred:HASKEY("twr_next") {
                RETURN "  nextTWR " + ROUND(pred["twr_next"], 2).
            }
        }
    }
    RETURN "".
}

FUNCTION aoso_hud_feas_status {
    IF DEFINED AOSO_FEAS_LAST {
        IF AOSO_FEAS_LAST:HASKEY("body") {
            LOCAL extra IS "".
            IF DEFINED AOSO_LEARN_LAST {
                IF AOSO_LEARN_LAST:HASKEY("deviation_pct") {
                    SET extra TO "  learn " + ROUND(AOSO_LEARN_LAST["deviation_pct"], 1) + "%".
                }
            }
            RETURN "Feas " + AOSO_FEAS_LAST["body"] + ": " + AOSO_FEAS_LAST["result"] + extra.
        }
    }
    RETURN "Feas: -".
}

// Wires the HUD into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_hud_register_task {
    PARAMETER interval_s IS 1.
    aoso_sched_add("hud", interval_s, aoso_hud_draw@).
}
