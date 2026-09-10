// AOSO/world/resources.ks
// What the *body* offers, not what the vessel is carrying. Ore, oxygen,
// atmosphere -- the feasibility engine uses this to decide whether ISRU
// or jets even make sense here. Vessel tanks live in vehicle/resources.ks.

FUNCTION aoso_world_has_ore {
    PARAMETER body_name IS SHIP:BODY:NAME.
    RETURN aoso_world_body_stat(body_name, "has_ore", FALSE).
}

FUNCTION aoso_world_has_oxygen {
    PARAMETER body_name IS SHIP:BODY:NAME.
    RETURN aoso_world_body_stat(body_name, "has_oxygen", FALSE).
}

FUNCTION aoso_world_has_atmosphere {
    PARAMETER body_name IS SHIP:BODY:NAME.
    LOCAL described IS aoso_world_body(body_name).
    RETURN described["atm"].
}

FUNCTION aoso_world_resources_summary {
    PARAMETER body_name IS SHIP:BODY:NAME.
    LOCAL described IS aoso_world_body(body_name).
    RETURN LEXICON(
        "body", body_name,
        "ore", described["has_ore"],
        "oxygen", described["has_oxygen"],
        "atmosphere", described["atm"],
        "pressure_sl", described["pressure_sl"]
    ).
}
