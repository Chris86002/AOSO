// AOSO/core/constants.ks
// Physical, math and system-wide constants. Loaded once by boot.ks.
// No runtime dependency on any addon.

GLOBAL AOSO_CONST IS LEXICON(
    "G0", 9.80665,                     // standard gravity, m/s^2
    "AU", 13599840256,                 // astronomical unit (Kerbin-scale, meters) - stock KSP value
    "DEG2RAD", 0.0174532925199433,
    "RAD2DEG", 57.2957795130823,
    "TWO_PI", 6.28318530717959,
    "SMALL", 0.0000001,                 // epsilon for float comparisons
    "MAX_WARP_FACTOR", 7,
    "DEFAULT_PARKING_ALT", 100000,      // meters, safe default parking orbit
    "KERBIN_ATM_TOP", 70000,            // meters, Kerbin atmosphere edge
    "SCHEDULER_TICK", 0.05,             // seconds, base loop wait
    "LOG_FLUSH_INTERVAL", 5,            // seconds between buffered log flushes
    "STATE_FILE", "0:/aoso_state.json",
    "CONFIG_FILE", "0:/aoso_config.json",
    "MISSION_FILE", "0:/aoso_mission.json",
    "VESSEL_FILE", "0:/aoso_vessel.json",
    "BODY_DB_FILE", "0:/aoso_body_database.json",
    "ROUTE_FILE", "0:/aoso_route.json",
    "TELEMETRY_FILE", "0:/aoso_telemetry.csv",
    "LOG_FILE", "0:/aoso_log.txt",
    "CHECKPOINT_FILE", "0:/aoso_checkpoints.json"
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
