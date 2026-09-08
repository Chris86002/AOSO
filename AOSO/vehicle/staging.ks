// AOSO/vehicle/staging.ks
// Flameout-driven automatic staging. Deliberately conservative: it only
// advances the stage when every currently-ignited engine has flamed out
// while thrust is still being commanded, so it never discards a stage that
// still has usable engines (e.g. one of several parallel boosters flaming
// out early) or fires while the vessel is coasting with the throttle down.
// Disabled outright when AOSO_CONFIG["SAFE_MODE"] is set, so an operator can
// always take manual control without fighting the automation.

FUNCTION aoso_staging_should_stage {
    PARAMETER commanded_throttle IS THROTTLE.

    IF STAGE:NUMBER <= 0 { RETURN FALSE. } // nothing left to stage
    IF aoso_config_get("SAFE_MODE", FALSE) { RETURN FALSE. }

    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL lit_count IS 0.
    LOCAL flamedout_count IS 0.
    FOR e IN elist {
        IF e:IGNITION {
            SET lit_count TO lit_count + 1.
            IF e:FLAMEOUT { SET flamedout_count TO flamedout_count + 1. }
        }
    }

    IF lit_count = 0 { RETURN FALSE. } // nothing ignited yet - not our call

    RETURN flamedout_count = lit_count AND commanded_throttle > 0.
}

FUNCTION aoso_staging_auto_check {
    IF aoso_staging_should_stage() {
        aoso_log_info("STAGING", "Auto-staging: flameout detected, stage " + STAGE:NUMBER + " -> " + (STAGE:NUMBER - 1)).
        STAGE.
        WAIT UNTIL STAGE:READY.
        aoso_vessel_scan().
        aoso_capabilities_refresh().
    }
}

// Wires the flameout check into core/scheduler.ks. Kept separate from
// aoso_staging_auto_check() so callers can still invoke that directly
// (e.g. a single manual check) without registering a recurring task.
FUNCTION aoso_staging_register_task {
    PARAMETER interval_s IS 0.5.
    aoso_sched_add("auto_staging", interval_s, aoso_staging_auto_check@).
}
