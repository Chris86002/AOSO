// AOSO/core/config.ks
// Central configuration store with sensible, documented defaults. Persisted
// to AOSO_CONST["CONFIG_FILE"] as JSON and reloaded on boot so operator
// overrides from a previous session survive reloads/resume.

GLOBAL AOSO_CONFIG IS LEXICON(
    "PARKING_ORBIT_ALT", 100000,        // m, default parking orbit altitude
    "FUEL_RESERVE_PCT", 10,             // % of stage fuel kept as untouchable reserve
    "ABORT_FUEL_PCT", 3,                // % remaining that forces an abort
    "MAX_WARP_FACTOR", 6,               // cap on TIMEWARP:WARP used by any module
    "OPTIMIZATION_MODE", "BALANCED",    // FUEL | TIME | SAFETY | BALANCED | MINIMUM_DV
    "LOG_LEVEL", "DEBUG",               // TRACE..FATAL
    "PRECISION_LANDING_RADIUS", 150,    // m, acceptable TARGET_ERROR for KSC return
    "MAX_SLOPE_DEG", 15,                // landing-site scoring cutoff
    "DEORBIT_PE_ALT", 30000,            // m, target periapsis for deorbit burns
    "SAFE_MODE", FALSE,
    "AUTO_CHECKPOINT_INTERVAL", 30,     // s between automatic checkpoint saves
    "WATCHDOG_TIMEOUT", 120,            // s of no-progress before watchdog intervenes
    "ASCENT_TURN_START_ALT", 500,       // m, altitude gravity turn begins
    "ASCENT_TURN_END_ALT", 45000,       // m, altitude gravity turn should be done by
    "ASCENT_TARGET_APO", 80000,         // m, default target apoapsis for ascent AP
    "MAX_Q_LIMIT_MULT", 1.0             // throttle back factor near max-Q (1.0=off)
).

FUNCTION aoso_config_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_CONFIG:HASKEY(key) { RETURN AOSO_CONFIG[key]. }
    RETURN default_value.
}

FUNCTION aoso_config_set {
    PARAMETER key.
    PARAMETER value.
    SET AOSO_CONFIG[key] TO value.
}

FUNCTION aoso_config_load {
    LOCAL loaded IS aoso_json_read(AOSO_CONST["CONFIG_FILE"], LEXICON()).
    IF loaded:ISTYPE("Lexicon") {
        FOR k IN loaded:KEYS {
            SET AOSO_CONFIG[k] TO loaded[k].
        }
    }
    IF DEFINED aoso_log_set_level { aoso_log_set_level(aoso_config_get("LOG_LEVEL", "DEBUG")). }
    RETURN AOSO_CONFIG.
}

FUNCTION aoso_config_save {
    aoso_json_write(AOSO_CONST["CONFIG_FILE"], AOSO_CONFIG).
}
