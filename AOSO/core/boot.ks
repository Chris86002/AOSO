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
    LOCAL ipu_tgt IS aoso_config_get("IPU_TARGET", 2000).
    IF ipu_tgt < 400 { SET ipu_tgt TO 400. }
    IF ipu_now < ipu_tgt {
        SET CONFIG:IPU TO ipu_tgt.
        aoso_log_info("BOOT", "CONFIG:IPU raised " + ipu_now + " -> " + ipu_tgt + " (headroom, not a utilization target).").
    } ELSE {
        aoso_log_info("BOOT", "CONFIG:IPU=" + ipu_now + " (target " + ipu_tgt + ").").
    }
    aoso_addons_detect().

    aoso_body_database_load().
    aoso_profile_refresh("boot").
    aoso_brain_init().
    IF DEFINED AOSO_TOPO {
        IF AOSO_TOPO:HASKEY("rev") { SET AOSO_CTX["rev_topo"] TO AOSO_TOPO["rev"]. }
        aoso_ctx_clear_dirty("dirty_topo").
    }
    aoso_cfg_id_lock().
    aoso_xp_load().
    aoso_world_refresh("boot").
    aoso_checkpoints_load().
    IF DEFINED AOSO_CERT_LAST {
        aoso_cert_eval("grand_tour").
        aoso_assure_eval().
    }
    IF DEFINED AOSO_CHECKPOINT {
        IF AOSO_CHECKPOINT["step_index"] >= 0 {
            LOCAL now_ctx IS aoso_checkpoints_context().
            LOCAL saved IS aoso_checkpoints_data().
            LOCAL exp_body IS "".
            LOCAL exp_st IS "".
            LOCAL exp_fp IS "".
            IF saved:HASKEY("body") { SET exp_body TO saved["body"]. }
            IF saved:HASKEY("status") { SET exp_st TO saved["status"]. }
            IF saved:HASKEY("topo_fp") { SET exp_fp TO saved["topo_fp"]. }
            aoso_log_info("BOOT", "Checkpoint expected body=" + exp_body + " status=" + exp_st +
                " topo=" + exp_fp + "  actual body=" + now_ctx["body"] + " status=" + now_ctx["status"] +
                " topo=" + now_ctx["topo_fp"] + ".").
            IF exp_fp <> "" {
                IF exp_fp <> now_ctx["topo_fp"] {
                    aoso_log_warn("BOOT", "Topology fingerprint changed since checkpoint - recertifying from live ship.").
                    aoso_ctx_mark_topo().
                    aoso_cert_eval("grand_tour").
                }
            }
        }
    }

    aoso_log_info("BOOT", "Boot sequence complete.").
    RETURN TRUE.
}
