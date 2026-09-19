// AOSO/core/boot.ks
// Boot sequence. RUN once from main.ks before any subsystem is used.
// Order matters: constants -> logger -> addons -> config -> json (already
// available) -> everything else.

FUNCTION aoso_boot {
    CLEARSCREEN.
    PRINT "=================================================".
    PRINT " AOSO - Autonomous KSP Flight Computer".
    PRINT "=================================================".

    // Start this attempt's on-disk log clean (see core/logger.ks's own
    // aoso_log_reset() header) before the very first aoso_log_* call below.
    aoso_log_reset().
    aoso_config_load().
    aoso_observe_init().
    aoso_log_set_level(aoso_config_get("LOG_LEVEL", "INFO")).
    aoso_log_info("BOOT", "Vessel: " + SHIP:NAME).
    LOCAL ipu_now IS CONFIG:IPU.
    IF ipu_now < 400 {
        SET CONFIG:IPU TO 400.
        aoso_log_info("BOOT", "CONFIG:IPU raised " + ipu_now + " -> 400 (AOSO needs the headroom for PLAN/HUD).").
    } ELSE {
        aoso_log_info("BOOT", "CONFIG:IPU=" + ipu_now + ".").
        IF ipu_now < 800 {
            aoso_log_warn("BOOT", "CONFIG:IPU is " + ipu_now + ". 1000+ is more comfortable during ascent; 2000 is optional headroom, not required.").
        }
    }
    aoso_addons_detect().

    aoso_body_database_load().
    aoso_profile_refresh("boot").
    aoso_brain_init().
    aoso_cfg_id_lock().
    aoso_xp_load().
    aoso_world_refresh("boot").
    aoso_checkpoints_load().

    aoso_log_info("BOOT", "Boot sequence complete.").
    RETURN TRUE.
}
