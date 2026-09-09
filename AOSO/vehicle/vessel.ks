// AOSO/vehicle/vessel.ks
// Vessel identification. Scans the active vessel's parts once (on boot and
// whenever the caller detects a vessel change, e.g. staging/docking/undocking)
// and records a summary in AOSO_VESSEL. Every capability flag here is derived
// from stock kOS list types (PARTS/ENGINES/DOCKINGPORTS) and PART:HASMODULE,
// never invented suffixes -- kOS has no "LIST PARACHUTES"; parachute
// presence/count is instead detected the same PART:HASMODULE way as
// RCS/solar/antenna/legs below (deployment itself is handled by
// landing/parachute.ks via the documented CHUTES/CHUTESSAFE bindings).
// Decouplers are counted the same PART:HASMODULE way too rather than via
// kOS's "LIST DECOUPLERS": on some installs (mixed decoupler/separator mods)
// that built-in throws "Specified argument was out of the range of valid
// values" (a kOS/KSP-side ArgumentOutOfRangeException) while walking the
// vessel's stage-separator parts, which would otherwise abort aoso_boot().
// Persisted to VESSEL_FILE so a reload/scene-change can skip a redundant
// scan until the caller asks for one.
//
// Phase 7 (Refuel & power) adds has_harvesters/has_converters/has_radiators
// the same HASMODULE way: ModuleResourceHarvester and ModuleResourceConverter
// back both stock ISRU drills/converters *and* stock fuel cells (they are
// the same underlying part modules), so this scan deliberately does not try
// to tell them apart -- power/power.ks and refuel/isru.ks instead defer that
// distinction to kOS's own FUELCELLS/ISRU/DRILLS bindings (core/addons.ks's
// "no invented suffixes" stance), which already know how to target the
// right modules at runtime.
//
// has_bays flags a service bay/cargo bay (ModuleCargoBay). It is recorded
// purely as an informational capability flag: power/power.ks deliberately
// never commands bays open (operator preference) -- solar panels are extended
// directly via their own ModuleDeployableSolarPanel actions -- so nothing here
// drives kOS's BAYS binding.
//
// has_fairings flags the other common "canopy": a stock procedural fairing
// (e.g. the AE-FF1/2/3 "Airstream Protective Shell" parts), backed by
// ModuleProceduralFairing. Unlike ModuleCargoBay, kOS has no documented
// global for fairings -- they're one-shot deployed (jettisoned) via that
// PartModule's own "Deploy" KSPEvent (PartModule:DOEVENT("Deploy")), which
// power/power.ks calls directly rather than assuming a fairing always sits
// on a stage vehicle/staging.ks's flameout-driven auto-stager would ever
// separate on its own.

GLOBAL AOSO_VESSEL IS LEXICON().

FUNCTION aoso_vessel_scan {
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL doclist IS LIST().
    LIST DOCKINGPORTS IN doclist.

    LOCAL has_rcs IS FALSE.
    LOCAL has_solar IS FALSE.
    LOCAL has_antenna IS FALSE.
    LOCAL has_legs IS FALSE.
    LOCAL has_harvesters IS FALSE.
    LOCAL has_converters IS FALSE.
    LOCAL has_radiators IS FALSE.
    LOCAL has_bays IS FALSE.
    LOCAL has_fairings IS FALSE.
    LOCAL parachute_count IS 0.
    LOCAL decoupler_count IS 0.
    FOR p IN plist {
        IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") { SET has_rcs TO TRUE. }
        IF p:HASMODULE("ModuleDeployableSolarPanel") { SET has_solar TO TRUE. }
        IF p:HASMODULE("ModuleDataTransmitter") { SET has_antenna TO TRUE. }
        IF p:HASMODULE("ModuleLandingLeg") { SET has_legs TO TRUE. }
        IF p:HASMODULE("ModuleParachute") { SET parachute_count TO parachute_count + 1. }
        IF p:HASMODULE("ModuleResourceHarvester") { SET has_harvesters TO TRUE. }
        IF p:HASMODULE("ModuleResourceConverter") { SET has_converters TO TRUE. }
        IF p:HASMODULE("ModuleDeployableRadiator") { SET has_radiators TO TRUE. }
        IF p:HASMODULE("ModuleCargoBay") { SET has_bays TO TRUE. }
        IF p:HASMODULE("ModuleProceduralFairing") { SET has_fairings TO TRUE. }
        IF p:HASMODULE("ModuleDecouple") OR p:HASMODULE("ModuleAnchoredDecoupler") OR p:HASMODULE("LaunchClamp") {
            SET decoupler_count TO decoupler_count + 1.
        }
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
        "decoupler_count", decoupler_count,
        "docking_port_count", doclist:LENGTH,
        "parachute_count", parachute_count,
        "crew_count", SHIP:CREW:LENGTH,
        "has_rcs", has_rcs,
        "has_solar_panels", has_solar,
        "has_antenna", has_antenna,
        "has_landing_legs", has_legs,
        "has_harvesters", has_harvesters,
        "has_converters", has_converters,
        "has_radiators", has_radiators,
        "has_bays", has_bays,
        "has_fairings", has_fairings,
        "resources", res_snapshot,
        "scanned_at", TIME:SECONDS
    ).

    aoso_log_info("VESSEL", "Scanned " + SHIP:NAME + ": " + plist:LENGTH + " parts, " +
        elist:LENGTH + " engines, " + (STAGE:NUMBER + 1) + " stages.").

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
