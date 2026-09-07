// AOSO/vehicle/vessel.ks
// Vessel identification. Scans the active vessel's parts once (on boot and
// whenever the caller detects a vessel change, e.g. staging/docking/undocking)
// and records a summary in AOSO_VESSEL. Every capability flag here is derived
// from stock kOS list types (PARTS/ENGINES/DECOUPLERS/DOCKINGPORTS) and
// PART:HASMODULE, never invented suffixes -- kOS has no "LIST PARACHUTES";
// parachute presence/count is instead detected the same PART:HASMODULE way
// as RCS/solar/antenna/legs below (deployment itself is handled by
// landing/parachute.ks via the documented CHUTES/CHUTESSAFE bindings).
// Persisted to VESSEL_FILE so a reload/scene-change can skip a redundant
// scan until the caller asks for one.

GLOBAL AOSO_VESSEL IS LEXICON().

FUNCTION aoso_vessel_scan {
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL declist IS LIST().
    LIST DECOUPLERS IN declist.
    LOCAL doclist IS LIST().
    LIST DOCKINGPORTS IN doclist.

    LOCAL has_rcs IS FALSE.
    LOCAL has_solar IS FALSE.
    LOCAL has_antenna IS FALSE.
    LOCAL has_legs IS FALSE.
    LOCAL parachute_count IS 0.
    FOR p IN plist {
        IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") { SET has_rcs TO TRUE. }
        IF p:HASMODULE("ModuleDeployableSolarPanel") { SET has_solar TO TRUE. }
        IF p:HASMODULE("ModuleDataTransmitter") { SET has_antenna TO TRUE. }
        IF p:HASMODULE("ModuleLandingLeg") { SET has_legs TO TRUE. }
        IF p:HASMODULE("ModuleParachute") { SET parachute_count TO parachute_count + 1. }
    }

    LOCAL res_snapshot IS LIST().
    FOR r IN SHIP:RESOURCES {
        res_snapshot:ADD(LEXICON("name", r:NAME, "amount", r:AMOUNT, "capacity", r:CAPACITY)).
    }

    SET AOSO_VESSEL TO LEXICON(
        "name", SHIP:NAME,
        "body", SHIP:BODY:NAME,
        "status", SHIP:STATUS,
        "mass", SHIP:MASS,
        "part_count", plist:LENGTH,
        "stage_count", STAGE:NUMBER + 1,
        "engine_count", elist:LENGTH,
        "decoupler_count", declist:LENGTH,
        "docking_port_count", doclist:LENGTH,
        "parachute_count", parachute_count,
        "crew_count", SHIP:CREW:LENGTH,
        "has_rcs", has_rcs,
        "has_solar_panels", has_solar,
        "has_antenna", has_antenna,
        "has_landing_legs", has_legs,
        "resources", res_snapshot,
        "scanned_at", TIME:SECONDS
    ).

    IF DEFINED aoso_log_info {
        aoso_log_info("VESSEL", "Scanned " + SHIP:NAME + ": " + plist:LENGTH + " parts, " +
            elist:LENGTH + " engines, " + (STAGE:NUMBER + 1) + " stages.").
    }

    aoso_vessel_save().
    RETURN AOSO_VESSEL.
}

FUNCTION aoso_vessel_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_VESSEL:HASKEY(key) { RETURN AOSO_VESSEL[key]. }
    RETURN default_value.
}

FUNCTION aoso_vessel_save {
    aoso_json_write(AOSO_CONST["VESSEL_FILE"], AOSO_VESSEL).
}

FUNCTION aoso_vessel_load {
    LOCAL loaded IS aoso_json_read(AOSO_CONST["VESSEL_FILE"], LEXICON()).
    IF loaded:ISTYPE("Lexicon") AND loaded:HASKEY("scanned_at") {
        SET AOSO_VESSEL TO loaded.
        RETURN TRUE.
    }
    RETURN FALSE.
}
