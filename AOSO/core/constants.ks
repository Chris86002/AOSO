// AOSO/core/constants.ks
// Physical, math and system-wide constants. Loaded once by boot.ks.
// No runtime dependency on any addon.

GLOBAL AOSO_CONST IS LEXICON(
    "G0", 9.80665,                     // standard gravity, m/s^2
    "DEG2RAD", 0.0174532925199433,
    "RAD2DEG", 57.2957795130823,
    "LOG_FLUSH_INTERVAL", 5,            // seconds between buffered log flushes
    "CONFIG_FILE", "0:/aoso_config.json",
    "VESSEL_FILE", "0:/aoso_vessel.json",
    "PART_DB_FILE", "0:/aoso_part_database.json",
    "BODY_DB_FILE", "0:/aoso_body_database.json",
    "ROUTE_FILE", "0:/aoso_route.json",
    "TELEMETRY_FILE", "0:/aoso_telemetry.csv",
    "TELEMETRY_PREV_FILE", "0:/aoso_telemetry_prev.csv",
    "LOG_FILE", "0:/aoso_log.txt",
    "CHECKPOINT_FILE", "0:/aoso_checkpoints.json",
    "LEARN_FILE", "0:/aoso_learn.json",
    "LEARN_ARCHIVE_FILE", "archive:/aoso_learn.json",
    "XP_FILE", "0:/aoso_xp.json",
    "XP_ARCHIVE_FILE", "archive:/aoso_xp.json",
    "CFG_ID_FILE", "0:/aoso_cfg_id.json",
    "ASCENT_RUNS_FILE", "0:/aoso_ascent_runs.json",
    "ASCENT_RUNS_ARCHIVE_FILE", "archive:/aoso_ascent_runs.json",
    "ASCENT_OPT_FILE", "0:/aoso_ascent_opt.json",
    "ASCENT_OPT_ARCHIVE_FILE", "archive:/aoso_ascent_opt.json",
    "PROFILE_FILE", "0:/aoso_profile.json",
    "MATRIX_FILE", "0:/aoso_matrix.json",
    "EVENTS_FILE", "0:/aoso_events.csv",
    "EVENTS_PREV_FILE", "0:/aoso_events_prev.csv",
    "FLIGHTREC_FILE", "0:/aoso_flightrec.txt",
    "FLIGHTREC_PREV_FILE", "0:/aoso_flightrec_prev.txt",
    "TICK_FILE", "0:/aoso_ticks.csv",
    "HUD_FILE", "0:/aoso_hud.json",
    "SCHEMA_VERSION", 2,
    "SOI_RADIUS_INFINITE", 1000000000000000  // sentinel (m) for a body with no SOI boundary (e.g. the Sun), since kOS cannot push a real Infinity value onto its stack
).

// Log level ordinals shared by logger.ks and config.ks
GLOBAL AOSO_LOG_LEVELS IS LEXICON(
    "TRACE", 0,
    "DEBUG", 1,
    "INFO", 2,
    "WARN", 3,
    "ERROR", 4,
    "FATAL", 5
).

// Convenience accessor so other modules don't need to know this is a lexicon.
// NOTE: kOS identifiers are case-insensitive, so this function must NOT be
// named "aoso_const" (it would collide with the GLOBAL AOSO_CONST lexicon
// above and cause "not enough arguments" errors whenever AOSO_CONST is
// referenced as a variable).
FUNCTION aoso_const_get {
    PARAMETER key.
    IF AOSO_CONST:HASKEY(key) {
        RETURN AOSO_CONST[key].
    }
    RETURN 0.
}
