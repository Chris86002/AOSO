// AOSO/landing/parachute.ks
// Atmospheric parachute deployment. kOS has no per-part "Parachute"
// structure/LIST keyword to iterate (see vehicle/vessel.ks's note on this) --
// parachutes are controlled fleet-wide through the documented CHUTES/
// CHUTESSAFE global bindings instead (core/addons.ks's same "no invented
// suffixes" stance). CHUTESSAFE in particular already reproduces exactly
// the behavior this module would otherwise have to hand-roll: it arms only
// the parachutes that are currently safe to deploy given airspeed/dynamic
// pressure, and does nothing to ones that aren't yet, so this module's only
// job is deciding *when* to ask for that (inside an atmosphere, once
// armed).

FUNCTION aoso_parachute_available {
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    FOR p IN plist {
        IF p:HASMODULE("ModuleParachute") { RETURN TRUE. }
    }
    RETURN FALSE.
}

// TRUE once the vessel is inside an atmosphere at all -- CHUTESSAFE itself
// (not this module) is responsible for the airspeed/dynamic-pressure safety
// judgment call once armed.
FUNCTION aoso_parachute_should_arm {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    RETURN ALTITUDE <= SHIP:BODY:ATM:HEIGHT.
}

// Arms every parachute that can currently be deployed safely, once inside
// an atmosphere. Idempotent -- CHUTESSAFE ON is a no-op for chutes that are
// already armed/deployed. Call once per scheduler tick (or from
// landing/descent.ks's BURN/FINAL_APPROACH states) via
// aoso_parachute_register_task().
FUNCTION aoso_parachute_auto_check {
    IF NOT aoso_parachute_should_arm() { RETURN. }
    IF CHUTESSAFE { RETURN. } // already armed

    SET CHUTESSAFE TO TRUE.
    IF DEFINED aoso_log_info {
        aoso_log_info("PARACHUTE", "CHUTESSAFE armed at altitude=" + ROUND(ALTITUDE, 0) +
            "m, airspeed=" + ROUND(SHIP:AIRSPEED, 1) + " m/s.").
    }
}

// Wires the parachute check into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_parachute_register_task {
    PARAMETER interval_s IS 0.5.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("auto_parachute", interval_s, aoso_parachute_auto_check@).
    }
}
