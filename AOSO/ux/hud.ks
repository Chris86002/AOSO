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

GLOBAL AOSO_HUD_ROWS IS 9. // rows 0..(AOSO_HUD_ROWS-1) are reserved for the HUD

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
    IF NOT DEFINED AOSO_MISSION OR AOSO_MISSION["current"] = "" { RETURN "N/A". }
    LOCAL step_name IS "".
    IF DEFINED aoso_mission_current_step_name { SET step_name TO aoso_mission_current_step_name(). }
    RETURN AOSO_MISSION["current"] + " / " + step_name.
}

FUNCTION aoso_hud_draw {
    LOCAL ec_pct IS 0.
    IF DEFINED aoso_power_ec_pct { SET ec_pct TO aoso_power_ec_pct(). }
    LOCAL fuel_pct IS 0.
    IF DEFINED aoso_stage_propellant_pct { SET fuel_pct TO aoso_stage_propellant_pct(). }
    LOCAL watchdog_status IS "OK".
    IF DEFINED aoso_watchdog_is_tripped AND aoso_watchdog_is_tripped() { SET watchdog_status TO "TRIPPED". }
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
    aoso_hud_line(8, "Watchdog: " + watchdog_status).
}

// Wires the HUD into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_hud_register_task {
    PARAMETER interval_s IS 1.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("hud", interval_s, aoso_hud_draw@).
    }
}
