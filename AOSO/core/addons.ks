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
    "AOSO", FALSE,
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

    SET AOSO_ADDON_STATUS["AOSO"] TO aoso_addons_any_available(LIST("AOSO")).
    SET AOSO_ADDON_STATUS["MECHJEB"] TO aoso_addons_any_available(LIST("MJ", "MechJeb")).
    SET AOSO_ADDON_STATUS["ASTROGATOR"] TO aoso_addons_any_available(LIST("ASTROGATOR")).
    SET AOSO_ADDON_STATUS["KER"] TO aoso_addons_any_available(LIST("KE", "KerbalEngineer")).
    SET AOSO_ADDON_STATUS["SIMPLEJSON"] TO aoso_addons_any_available(LIST("JSON", "simpleJson")).
    SET AOSO_ADDON_STATUS["CHECKED"] TO TRUE.

    aoso_log("INFO", "ADDONS", "AOSO=" + AOSO_ADDON_STATUS["AOSO"] +
        " MechJeb=" + AOSO_ADDON_STATUS["MECHJEB"] +
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
// AOSO native numerical backend (optional).
// This is the ONLY script module allowed to touch ADDONS:AOSO.
// Missing DLL or suffixes always degrade to pure KerboScript.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_native {
    IF NOT aoso_addon_available("AOSO") { RETURN 0. }
    IF ADDONS:HASADDON("AOSO") AND ADDONS:AVAILABLE("AOSO") {
        RETURN ADDONS:AOSO.
    }
    RETURN 0.
}

FUNCTION aoso_addon_native_available {
    LOCAL native_obj IS aoso_addon_native().
    IF native_obj:ISTYPE("Scalar") { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_addon_native_version {
    LOCAL native_obj IS aoso_addon_native().
    IF native_obj:ISTYPE("Scalar") { RETURN "". }
    IF native_obj:HASSUFFIX("VERSION") { RETURN native_obj:VERSION. }
    RETURN "".
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
    // READALL() returns a FileContent, which only supports :STRING/:BINARY/
    // :ITERATOR - it has no :LENGTH-as-line-count or :POP suffix like a List.
    LOCAL text IS f:READALL():STRING.
    IF text:LENGTH = 0 { RETURN default_value. }
    RETURN aoso_json_decode(text).
}

// ---------------------------------------------------------------------
// MechJeb aero (optional). Stock kOS has SHIP:Q and no drag force.
// belpyro/kOS.MechJeb2.Addon exposes VESSEL:DRAG (kN), DRAGCOEF, AOA,
// DYNAMICPRESSURE. KER / Astrogator / simpleJson do not. FAR is not an
// AOSO addon. Callers must use these wrappers — never ADDONS:MJ directly.
// Missing suffixes return -999 so an old MJ build cannot throw.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_mj_obj {
    IF NOT aoso_addon_available("MECHJEB") { RETURN 0. }
    IF ADDONS:HASADDON("MJ") {
        IF ADDONS:AVAILABLE("MJ") { RETURN ADDONS:MJ. }
    }
    IF ADDONS:HASADDON("MechJeb") {
        IF ADDONS:AVAILABLE("MechJeb") { RETURN ADDONS:MechJeb. }
    }
    RETURN 0.
}

FUNCTION aoso_addon_mj_vessel {
    LOCAL mj IS aoso_addon_mj_obj().
    IF mj:ISTYPE("Scalar") { RETURN 0. }
    IF mj:HASSUFFIX("VESSEL") { RETURN mj:VESSEL. }
    IF mj:HASSUFFIX("VESSELINFO") { RETURN mj:VESSELINFO. }
    RETURN 0.
}

FUNCTION aoso_addon_mj_drag_kn {
    LOCAL wrap IS aoso_addon_mj_vessel().
    IF wrap:ISTYPE("Scalar") { RETURN -1. }
    IF wrap:HASSUFFIX("DRAG") { RETURN wrap:DRAG. }
    IF wrap:HASSUFFIX("PUREDRAG") { RETURN wrap:PUREDRAG. }
    RETURN -1.
}

FUNCTION aoso_addon_mj_cd {
    LOCAL wrap IS aoso_addon_mj_vessel().
    IF wrap:ISTYPE("Scalar") { RETURN -1. }
    IF wrap:HASSUFFIX("DRAGCOEF") { RETURN wrap:DRAGCOEF. }
    IF wrap:HASSUFFIX("CD") { RETURN wrap:CD. }
    RETURN -1.
}

FUNCTION aoso_addon_mj_aoa {
    LOCAL wrap IS aoso_addon_mj_vessel().
    IF wrap:ISTYPE("Scalar") { RETURN -999. }
    IF wrap:HASSUFFIX("AOA") { RETURN wrap:AOA. }
    RETURN -999.
}

// ---------------------------------------------------------------------
// Astrogator (optional status integration only). Intercept creation is
// intentionally disabled; AOSO owns porkchop/Hohmann planning and capture-PE
// acceptance.
// ---------------------------------------------------------------------

FUNCTION aoso_addon_astrogator_obj {
    IF NOT aoso_addon_available("ASTROGATOR") { RETURN 0. }
    IF ADDONS:HASADDON("ASTROGATOR") {
        IF ADDONS:AVAILABLE("ASTROGATOR") { RETURN ADDONS:ASTROGATOR. }
    }
    RETURN 0.
}

// Add the ejection node to dest. want_plane=FALSE for polar hops (do not
// match the moon's equatorial plane). Returns the node or 0.
FUNCTION aoso_addon_astrogator_add_transfer {
    PARAMETER dest.
    PARAMETER want_plane IS TRUE.
    aoso_log_warn("ADDONS", "Astrogator intercepts disabled. AOSO plans intercepts (dest=" + dest:NAME + ").").
    RETURN 0.
}

