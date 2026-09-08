// AOSO/interplanetary/bodydb.ks
// Phase 5 (Interplanetary) foundation: a pure-kOS celestial body database,
// scanning every body via kOS's `LIST BODIES IN ...` command once and
// caching each body's mu, SOI radius, physical radius, parent name and
// heliocentric-ish orbit stats (semi-major axis, period, eccentricity) into
// AOSO_BODY_DB, persisted to AOSO_CONST["BODY_DB_FILE"]. This is the
// function core/boot.ks already conditionally calls (`IF DEFINED
// aoso_body_database_load`), matching how Phase 2's aoso_vessel_scan
// slotted into boot.ks's existing call. Every other interplanetary/*.ks
// module looks up bodies here instead of re-querying BODIES/SUN directly,
// so callers can pass body names (strings) instead of live orbitable
// references.

GLOBAL AOSO_BODY_DB IS LEXICON().

// A body's own star has no ORBIT (nothing to patch-conic against), so it is
// recorded with SMA/PERIOD/ECCENTRICITY/PARENT left at safe defaults instead
// of guessing at a suffix that may not exist for the root body.
FUNCTION aoso_body_database_entry {
    PARAMETER body_ref.

    LOCAL entry IS LEXICON(
        "NAME", body_ref:NAME,
        "MU", body_ref:MU,
        "RADIUS", body_ref:RADIUS,
        "SOI_RADIUS", body_ref:SOIRADIUS,
        "PARENT", "",
        "SMA", 0,
        "PERIOD", 0,
        "ECCENTRICITY", 0
    ).

    IF body_ref:NAME <> SUN:NAME {
        SET entry["PARENT"] TO body_ref:ORBIT:BODY:NAME.
        SET entry["SMA"] TO body_ref:ORBIT:SEMIMAJORAXIS.
        SET entry["PERIOD"] TO body_ref:ORBIT:PERIOD.
        SET entry["ECCENTRICITY"] TO body_ref:ORBIT:ECCENTRICITY.
    }

    RETURN entry.
}

// Scans every body kOS knows about (`LIST BODIES IN ...`) into AOSO_BODY_DB.
// Safe to call more than once; always rebuilds from the live universe.
FUNCTION aoso_body_database_build {
    SET AOSO_BODY_DB TO LEXICON().
    LIST BODIES IN all_bodies.
    FOR b IN all_bodies {
        SET AOSO_BODY_DB[b:NAME] TO aoso_body_database_entry(b).
    }
    IF DEFINED aoso_log_info {
        aoso_log_info("BODYDB", "Body database built: " + AOSO_BODY_DB:LENGTH + " bodies.").
    }
    RETURN AOSO_BODY_DB.
}

FUNCTION aoso_body_database_save {
    aoso_json_write(AOSO_CONST["BODY_DB_FILE"], AOSO_BODY_DB).
}

// Loads the persisted database if present, otherwise builds one fresh from
// the live universe and saves it (bodies/orbits never change mid-save, so a
// cached copy is just a faster path to the same data on the next boot).
FUNCTION aoso_body_database_load {
    LOCAL loaded IS aoso_json_read(AOSO_CONST["BODY_DB_FILE"], LEXICON()).
    IF loaded:ISTYPE("Lexicon") AND loaded:LENGTH > 0 {
        SET AOSO_BODY_DB TO loaded.
        RETURN AOSO_BODY_DB.
    }
    aoso_body_database_build().
    aoso_body_database_save().
    RETURN AOSO_BODY_DB.
}

// Looks up a cached entry by name, building the database on demand if it
// hasn't been loaded yet this session.
FUNCTION aoso_body_database_get {
    PARAMETER body_name.
    IF AOSO_BODY_DB:LENGTH = 0 { aoso_body_database_load(). }
    IF AOSO_BODY_DB:HASKEY(body_name) { RETURN AOSO_BODY_DB[body_name]. }
    RETURN LEXICON().
}
