// AOSO/ux/telemetry.ks
// Phase 12 (Hardening & UX): periodic CSV telemetry logging to
// AOSO_CONST["TELEMETRY_FILE"], a path core/constants.ks has reserved since
// Phase 1 but that no module wrote to until now. Deliberately a flat CSV
// (unlike every JSON file this repo persists via core/json.ks) since
// telemetry is meant for external post-flight analysis/plotting, not for
// aoso_json_read() round-tripping like state/config/checkpoints.

GLOBAL AOSO_TELEMETRY_HEADER_WRITTEN IS FALSE.

FUNCTION aoso_telemetry_header {
    RETURN "met_s,body,altitude_m,apoapsis_m,periapsis_m,speed_ms,vspeed_ms,ec_pct,fuel_pct,mission_state,mission_step".
}

FUNCTION aoso_telemetry_row {
    LOCAL ec_pct IS 0.
    IF DEFINED aoso_power_ec_pct { SET ec_pct TO aoso_power_ec_pct(). }
    LOCAL fuel_pct IS 0.
    IF DEFINED aoso_stage_propellant_pct { SET fuel_pct TO aoso_stage_propellant_pct(). }
    LOCAL mission_state IS "".
    IF DEFINED AOSO_MISSION { SET mission_state TO AOSO_MISSION["current"]. }
    LOCAL mission_step IS "".
    IF DEFINED aoso_mission_current_step_name { SET mission_step TO aoso_mission_current_step_name(). }

    RETURN ROUND(MISSIONTIME, 1) + "," + SHIP:BODY:NAME + "," + ROUND(ALTITUDE, 1) + "," +
        ROUND(SHIP:APOAPSIS, 1) + "," + ROUND(SHIP:PERIAPSIS, 1) + "," +
        ROUND(SHIP:VELOCITY:SURFACE:MAG, 2) + "," + ROUND(VERTICALSPEED, 2) + "," +
        ROUND(ec_pct, 1) + "," + ROUND(fuel_pct, 1) + "," + mission_state + "," + mission_step.
}

// Writes the CSV header once (only if the file doesn't already exist, so a
// resumed session appends to the same file rather than starting a new
// header partway through), then appends one row every call.
FUNCTION aoso_telemetry_tick {
    LOCAL path IS AOSO_CONST["TELEMETRY_FILE"].

    IF NOT AOSO_TELEMETRY_HEADER_WRITTEN {
        IF NOT EXISTS(path) {
            LOCAL header_file IS OPEN(path).
            header_file:WRITELN(aoso_telemetry_header()).
        }
        SET AOSO_TELEMETRY_HEADER_WRITTEN TO TRUE.
    }

    LOCAL f IS OPEN(path).
    f:WRITELN(aoso_telemetry_row()).
}

// Wires telemetry logging into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_telemetry_register_task {
    PARAMETER interval_s IS 5.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("telemetry", interval_s, aoso_telemetry_tick@).
    }
}
