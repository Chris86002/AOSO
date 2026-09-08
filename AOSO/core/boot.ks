// AOSO/core/boot.ks
// Boot sequence. RUN once from main.ks before any subsystem is used.
// Order matters: constants -> logger -> addons -> config -> json (already
// available) -> everything else.

FUNCTION aoso_boot {
    CLEARSCREEN.
    PRINT "=================================================".
    PRINT " AOSO - Autonomous KSP Flight Computer".
    PRINT "=================================================".

    aoso_config_load().
    aoso_log_set_level(aoso_config_get("LOG_LEVEL", "DEBUG")).
    aoso_log_info("BOOT", "Vessel: " + SHIP:NAME).
    aoso_addons_detect().

    aoso_vessel_scan().
    aoso_capabilities_refresh().
    aoso_body_database_load().
    aoso_checkpoints_load().

    aoso_log_info("BOOT", "Boot sequence complete.").
    RETURN TRUE.
}
