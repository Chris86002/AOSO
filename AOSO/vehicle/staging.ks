// AOSO/vehicle/staging.ks
// Flameout-driven automatic staging. Deliberately conservative: it advances
// the stage when the currently-ignited engines can no longer usefully thrust,
// while never discarding a stage that still has usable engines or firing while
// the vessel coasts with the throttle down. Two cases trigger it:
//   1. every currently-ignited engine has flamed out (the whole active stage
//      is spent), or
//   2. a spent BOOSTER subset can be dropped while the core keeps burning --
//      vehicle/parts.ks's aoso_parts_boosters_ready_to_jettison() confirms the
//      next separation jettisons only flamed-out engines. Without this second
//      case, radial boosters (which flame out while the core still burns) were
//      never dropped, so their near-empty tanks tripped a false fuel abort.
// Disabled outright when AOSO_CONFIG["SAFE_MODE"] is set, so an operator can
// always take manual control without fighting the automation.

FUNCTION aoso_staging_should_stage {
    PARAMETER commanded_throttle IS THROTTLE.

    IF STAGE:NUMBER <= 0 { RETURN FALSE. } // nothing left to stage
    IF aoso_config_get("SAFE_MODE", FALSE) { RETURN FALSE. }
    IF commanded_throttle <= 0 { RETURN FALSE. } // don't stage while coasting

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

    IF flamedout_count = lit_count { RETURN TRUE. } // whole active stage is spent
    RETURN aoso_parts_boosters_ready_to_jettison(). // spent booster subset can drop
}

FUNCTION aoso_staging_auto_check {
    IF aoso_staging_should_stage() {
        aoso_log_info("STAGING", "Auto-staging: flameout detected, stage " + STAGE:NUMBER + " -> " + (STAGE:NUMBER - 1)).
        STAGE.
        WAIT UNTIL STAGE:READY.
        aoso_vessel_scan().
        aoso_parts_scan().
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
