// AOSO/core/addons.ks
// Addon abstraction layer. Every optional integration (MechJeb, Astrogator,
// Kerbal Engineer, simpleJson) is accessed ONLY through the functions in
// this file. Each function first checks addon availability and falls back
// to a pure-kOS implementation (or a safe default) when the addon is not
// installed. No other module may reference ADDONS:* directly.
//
// kOS's ADDONS:AVAILABLE(name) looks up the identifier each bridge mod
// registers itself under via [kOSAddon("...")], which is almost never the
// full mod name -- e.g. belpyro/kOS.MechJeb2.Addon registers "MJ" (not
// "MechJeb"), markjfisher/kOS-KerbalEngineer registers "KE" (not
// "KerbalEngineer"), and Thr0in/kOS-simpleJson registers "JSON" (not
// "simpleJson"). Only kOS-Astrogator happens to register "ASTROGATOR",
// matching the mod name. Every check below therefore tries every known
// identifier for that integration so detection works regardless of which
// compatible bridge mod is installed.

GLOBAL AOSO_ADDON_STATUS IS LEXICON(
    "MECHJEB", FALSE,
    "ASTROGATOR", FALSE,
    "KER", FALSE,
    "SIMPLEJSON", FALSE,
    "CHECKED", FALSE
).

// Returns TRUE if any of the given kOS addon identifiers is registered and
// reports itself available.
FUNCTION aoso_addons_any_available {
    PARAMETER names.
    FOR n IN names {
        IF ADDONS:HASADDON(n) AND ADDONS:AVAILABLE(n) { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_addons_detect {
    IF AOSO_ADDON_STATUS["CHECKED"] { RETURN AOSO_ADDON_STATUS. }

    SET AOSO_ADDON_STATUS["MECHJEB"] TO aoso_addons_any_available(LIST("MJ", "MechJeb")).
    SET AOSO_ADDON_STATUS["ASTROGATOR"] TO aoso_addons_any_available(LIST("ASTROGATOR")).
    SET AOSO_ADDON_STATUS["KER"] TO aoso_addons_any_available(LIST("KE", "KerbalEngineer")).
    SET AOSO_ADDON_STATUS["SIMPLEJSON"] TO aoso_addons_any_available(LIST("JSON", "simpleJson")).
    SET AOSO_ADDON_STATUS["CHECKED"] TO TRUE.

    aoso_log("INFO", "ADDONS", "MechJeb=" + AOSO_ADDON_STATUS["MECHJEB"] +
        " Astrogator=" + AOSO_ADDON_STATUS["ASTROGATOR"] +
        " KER=" + AOSO_ADDON_STATUS["KER"] +
        " simpleJson=" + AOSO_ADDON_STATUS["SIMPLEJSON"]).
    RETURN AOSO_ADDON_STATUS.
}

FUNCTION aoso_addon_available {
    PARAMETER name.
    aoso_addons_detect().
    IF AOSO_ADDON_STATUS:HASKEY(name) { RETURN AOSO_ADDON_STATUS[name]. }
    RETURN FALSE.
}

// ---------------------------------------------------------------------
// MechJeb wrappers. If unavailable, callers should use core kOS steering
// (COCKPIT/STEERING) and RCS/throttle directly; these wrappers simply
// report unavailability so guidance modules can branch.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_mj_available {
    RETURN aoso_addon_available("MECHJEB").
}

// Attempts a MechJeb-driven smart A.S.S attitude hold. Returns TRUE if the
// command was issued via MechJeb, FALSE if the caller must fall back to
// native kOS STEERING.
FUNCTION aoso_addon_mj_set_attitude {
    PARAMETER mode_name.  // e.g. "PROGRADE", "RETROGRADE", "SURFACE"
    IF NOT aoso_addon_mj_available() { RETURN FALSE. }
    // MechJeb's kOS mod exposes ADDONS:MJ:ASCENTAP / SMARTASS etc. Since the
    // exact suffix surface varies by MechJeb release, and this repo must not
    // invent suffixes, MechJeb attitude control is not driven here directly;
    // instead we report available=TRUE but let the caller keep using native
    // kOS STEERING as the actually-executed control law. This keeps the
    // system correct on every MechJeb version without guessing at its API.
    RETURN FALSE.
}

// ---------------------------------------------------------------------
// Astrogator wrappers - transfer planning. Astrogator's kOS bridge does not
// expose a stable/documented suffix set for programmatic transfer solving
// in vanilla kOS, so the abstraction here is a capability probe only; the
// real Lambert/Hohmann solving always happens in navigation/porkchop.ks and
// navigation/transfer_planner.ks using pure orbital mechanics. This keeps
// results reproducible and avoids invented syntax.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_astrogator_available {
    RETURN aoso_addon_available("ASTROGATOR").
}

// ---------------------------------------------------------------------
// Kerbal Engineer wrappers - performance/sensor readouts. KER's values are
// reproduced with pure kOS SHIP:* suffixes in vehicle/performance.ks, so
// this wrapper only reports availability for optional cross-checking /
// display purposes.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_ker_available {
    RETURN aoso_addon_available("KER").
}

// ---------------------------------------------------------------------
// simpleJson wrappers - used by core/json.ks. If unavailable, core/json.ks
// falls back to its own pure-kOS encoder/decoder automatically.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_simplejson_available {
    RETURN aoso_addon_available("SIMPLEJSON").
}

FUNCTION aoso_addon_simplejson_write {
    PARAMETER file_path.
    PARAMETER value.
    // simpleJson exposes BUILTIN:JSONSTRINGIFY in some builds; that suffix is
    // not consistently documented across kOS versions, so to guarantee
    // correctness we always use the pure-kOS encoder for file writes and
    // simply record that simpleJson was detected.
    LOCAL text IS aoso_json_encode(value).
    // OPEN() returns a plain BooleanValue(false) instead of a file handle
    // when the path doesn't exist yet, so CREATE it the first time and
    // OPEN+CLEAR it (to overwrite) on every call after that.
    LOCAL f IS 0.
    IF EXISTS(file_path) {
        SET f TO OPEN(file_path).
        f:CLEAR().
    } ELSE {
        SET f TO CREATE(file_path).
    }
    f:WRITELN(text).
    RETURN TRUE.
}

FUNCTION aoso_addon_simplejson_read {
    PARAMETER file_path.
    PARAMETER default_value.
    IF NOT EXISTS(file_path) { RETURN default_value. }
    LOCAL f IS OPEN(file_path).
    LOCAL lines IS f:READALL().
    LOCAL text IS "".
    UNTIL lines:LENGTH = 0 {
        SET text TO text + lines:POP().
    }
    IF text:LENGTH = 0 { RETURN default_value. }
    RETURN aoso_json_decode(text).
}
