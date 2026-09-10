// AOSO/world/world.ks
// Aggregates the world model the planner consumes:
//
//              WORLD MODEL
//                   │
//                   ▼
//  VESSEL → FEASIBILITY ENGINE → MISSION PLANNER → EXECUTOR
//
// Rebuilds the "here" snapshot (body + orbit + resources + network) on
// boot and whenever the vehicle profile notices a body/status change.
// Body facts themselves never change mid-save, so AOSO_WORLD_BODY_CACHE
// is only cleared on a SOI change.

GLOBAL AOSO_WORLD IS LEXICON().

FUNCTION aoso_world_refresh {
    PARAMETER reason IS "manual".

    LOCAL here_name IS SHIP:BODY:NAME.
    LOCAL prev_body IS "".
    IF AOSO_WORLD:HASKEY("here_name") { SET prev_body TO AOSO_WORLD["here_name"]. }
    IF prev_body <> "" {
        IF prev_body <> here_name { aoso_world_body_clear_cache(). }
    }

    LOCAL here_body IS aoso_world_body(here_name).
    LOCAL home_name IS aoso_config_get("HOME_BODY", "Kerbin").
    LOCAL home_body IS aoso_world_body(home_name).

    SET AOSO_WORLD TO LEXICON(
        "here_name", here_name,
        "here", here_body,
        "home_name", home_name,
        "home", home_body,
        "orbit", aoso_world_orbit_summary(),
        "resources", aoso_world_resources_summary(here_name),
        "network", aoso_world_network_summary(),
        "reason", reason,
        "refreshed_at", TIME:SECONDS
    ).

    aoso_log_info("WORLD", "Here=" + here_name + " g=" + ROUND(here_body["g_surf"], 2) +
        " land_diff=" + ROUND(here_body["landing_difficulty"], 2) +
        " ore=" + here_body["has_ore"] + " atm=" + here_body["atm"] +
        " stable=" + AOSO_WORLD["orbit"]["stable"] + " (" + reason + ").").
    RETURN AOSO_WORLD.
}

FUNCTION aoso_world_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_WORLD:HASKEY(key) { RETURN AOSO_WORLD[key]. }
    RETURN default_value.
}

FUNCTION aoso_world_here {
    IF AOSO_WORLD:HASKEY("here") { RETURN AOSO_WORLD["here"]. }
    RETURN aoso_world_body(SHIP:BODY:NAME).
}
