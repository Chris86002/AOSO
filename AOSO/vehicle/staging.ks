// AOSO/vehicle/staging.ks
// Flameout-driven automatic staging, plus serial-stack relight. Deliberately
// conservative: it advances the stage when the currently-ignited engines can
// no longer usefully thrust, while never discarding a stage that still has
// usable engines or firing while the vessel coasts with the throttle down.
// Three cases trigger it:
//   1. every currently-ignited engine has flamed out (the whole active stage
//      is spent), or
//   2. a spent BOOSTER subset can be dropped while the core keeps burning --
//      vehicle/parts.ks's aoso_parts_boosters_ready_to_jettison() confirms the
//      next separation jettisons only flamed-out engines. Without this second
//      case, radial boosters (which flame out while the core still burns) were
//      never dropped, so their near-empty tanks tripped a false fuel abort, or
//   3. the vessel is already airborne, throttle is open, nothing is ignited,
//      and an un-ignited engine still exists. Case 1's single STAGE() often
//      only jettisons the spent engines; on a serial stack the next engines
//      live in a later KSP stage and stay dark. Without this third case
//      auto-staging used to return FALSE at lit_count=0 ("nothing ignited
//      yet - not our call") and the vessel coasted to apoapsis at TWR 0 with
//      a full next-stage fuel tank (Acacius: flameout 6->5, then TWR=0 with
//      9 unlit engines). Pad ignition is still flight/ascent.ks LIFTOFF's
//      job -- case 3 is gated on SHIP:STATUS so it cannot fight the
//      clamp/ignition sequence. Consecutive relight STAGE()s are capped so a
//      dead upper stage cannot dump parachutes or the payload.
// Disabled outright when AOSO_CONFIG["SAFE_MODE"] is set, so an operator can
// always take manual control without fighting the automation.

// Extra STAGE()s spent trying to light the next engine group after a
// full flameout. Reset to 0 whenever a burning engine is observed.
GLOBAL AOSO_STAGING_RELIGHT_ATTEMPTS IS 0.

FUNCTION aoso_staging_airborne {
    LOCAL st IS SHIP:STATUS.
    RETURN st <> "PRELAUNCH" AND st <> "LANDED" AND st <> "SPLASHED".
}

FUNCTION aoso_staging_should_stage {
    PARAMETER commanded_throttle IS THROTTLE.

    IF STAGE:NUMBER <= 0 { RETURN FALSE. } // nothing left to stage
    IF aoso_config_get("SAFE_MODE", FALSE) { RETURN FALSE. }
    IF commanded_throttle <= 0 { RETURN FALSE. } // don't stage while coasting
    IF NOT STAGE:READY { RETURN FALSE. }

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

    IF lit_count = 0 {
        // Serial-stack relight. Not our call on the pad (LIFTOFF ignites)
        // and not after the cap (don't walk the rest of the stack).
        IF NOT aoso_staging_airborne() { RETURN FALSE. }
        IF AOSO_STAGING_RELIGHT_ATTEMPTS >= 6 { RETURN FALSE. }
        IF NOT aoso_parts_has_unignited_engine() { RETURN FALSE. }
        RETURN TRUE.
    }

    SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.

    IF flamedout_count = lit_count { RETURN TRUE. } // whole active stage is spent
    RETURN aoso_parts_boosters_ready_to_jettison(). // spent booster subset can drop
}

// After dropping a spent stage, keep staging until something burns again.
// Serial stacks put "jettison empties" and "ignite next engines" in
// different KSP stages; one STAGE() is not enough. Bounded so we cannot
// dump the payload if the next engines refuse to light.
FUNCTION aoso_staging_relight_until_thrust {
    LOCAL extra IS 0.
    UNTIL aoso_parts_has_burning_engine() OR STAGE:NUMBER <= 0 OR extra >= 4 OR AOSO_STAGING_RELIGHT_ATTEMPTS >= 6 OR NOT aoso_parts_has_unignited_engine() {
        IF NOT STAGE:READY { WAIT UNTIL STAGE:READY. }
        aoso_log_info("STAGING", "Relight: no thrust after staging, lighting next stage (" + STAGE:NUMBER + ").").
        STAGE.
        SET extra TO extra + 1.
        SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
        WAIT UNTIL STAGE:READY.
        WAIT 0.15. // let newly ignited engines register IGNITION
    }
    IF aoso_parts_has_burning_engine() {
        SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.
        IF extra > 0 {
            aoso_log_info("STAGING", "Relight: thrust restored after " + extra + " extra stage event(s).").
        }
    } ELSE IF extra > 0 {
        aoso_log_warn("STAGING", "Relight: still no thrust after " + AOSO_STAGING_RELIGHT_ATTEMPTS + " extra stage event(s).").
    }
}

FUNCTION aoso_staging_auto_check {
    IF aoso_staging_should_stage() {
        LOCAL prev IS STAGE:NUMBER.
        LOCAL had_ignition IS FALSE.
        LOCAL elist IS LIST().
        LIST ENGINES IN elist.
        FOR e IN elist {
            IF e:IGNITION { SET had_ignition TO TRUE. }
        }

        IF had_ignition {
            aoso_log_info("STAGING", "Auto-staging: flameout detected, stage " + prev + " -> " + (prev - 1)).
        } ELSE {
            aoso_log_info("STAGING", "Relight: no burning engines, staging (" + prev + ").").
            SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
        }

        STAGE.
        WAIT UNTIL STAGE:READY.
        WAIT 0.15. // let newly ignited engines register IGNITION

        IF NOT aoso_parts_has_burning_engine() {
            aoso_staging_relight_until_thrust().
        } ELSE {
            SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.
        }

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
