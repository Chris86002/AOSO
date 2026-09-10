// AOSO/world/body.ks
// World-model view of a celestial body: live kOS BODY() facts plus the
// stock dV / difficulty / resource table the feasibility engine spends.
// Vehicle intelligence asks the world "how hard is landing here?" instead
// of hard-coding Mun vs Eve inside tour.ks.
//
// Live suffixes only (MU, RADIUS, SOIRADIUS, ATM, ORBIT). dV numbers are
// the well-known LKO baseline map, same source mission/feasibility.ks used
// to own -- one table, so the planner and the world cannot drift.

GLOBAL AOSO_WORLD_KNOWN IS LEXICON(
    "Kerbin", LEXICON("transfer_from_lko", 0, "capture", 0, "land", 900, "takeoff", 3400, "return", 0, "landing_difficulty", 0.35, "escape_difficulty", 0.45, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", TRUE),
    "Mun", LEXICON("transfer_from_lko", 860, "capture", 310, "land", 580, "takeoff", 580, "return", 310, "landing_difficulty", 0.4, "escape_difficulty", 0.2, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Minmus", LEXICON("transfer_from_lko", 930, "capture", 160, "land", 180, "takeoff", 180, "return", 160, "landing_difficulty", 0.15, "escape_difficulty", 0.08, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Eve", LEXICON("transfer_from_lko", 1070, "capture", 1330, "land", 1200, "takeoff", 8000, "return", 1330, "landing_difficulty", 0.95, "escape_difficulty", 1, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Gilly", LEXICON("transfer_from_lko", 1740, "capture", 50, "land", 30, "takeoff", 30, "return", 50, "landing_difficulty", 0.05, "escape_difficulty", 0.02, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Moho", LEXICON("transfer_from_lko", 2760, "capture", 2410, "land", 870, "takeoff", 870, "return", 2410, "landing_difficulty", 0.55, "escape_difficulty", 0.55, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Duna", LEXICON("transfer_from_lko", 1060, "capture", 610, "land", 1450, "takeoff", 1450, "return", 360, "landing_difficulty", 0.4, "escape_difficulty", 0.35, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Ike", LEXICON("transfer_from_lko", 1330, "capture", 180, "land", 390, "takeoff", 390, "return", 180, "landing_difficulty", 0.35, "escape_difficulty", 0.15, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Dres", LEXICON("transfer_from_lko", 1640, "capture", 665, "land", 430, "takeoff", 430, "return", 665, "landing_difficulty", 0.35, "escape_difficulty", 0.18, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Jool", LEXICON("transfer_from_lko", 1920, "capture", 160, "land", 0, "takeoff", 0, "return", 160, "landing_difficulty", 1, "escape_difficulty", 1, "has_surface", FALSE, "has_ore", FALSE, "has_oxygen", FALSE),
    "Laythe", LEXICON("transfer_from_lko", 2860, "capture", 940, "land", 2900, "takeoff", 3100, "return", 940, "landing_difficulty", 0.7, "escape_difficulty", 0.65, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", TRUE),
    "Vall", LEXICON("transfer_from_lko", 2540, "capture", 860, "land", 860, "takeoff", 860, "return", 860, "landing_difficulty", 0.5, "escape_difficulty", 0.28, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Tylo", LEXICON("transfer_from_lko", 2810, "capture", 1100, "land", 2270, "takeoff", 2270, "return", 1100, "landing_difficulty", 0.95, "escape_difficulty", 0.85, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Bop", LEXICON("transfer_from_lko", 2820, "capture", 900, "land", 230, "takeoff", 230, "return", 900, "landing_difficulty", 0.25, "escape_difficulty", 0.1, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Pol", LEXICON("transfer_from_lko", 2720, "capture", 800, "land", 130, "takeoff", 130, "return", 800, "landing_difficulty", 0.15, "escape_difficulty", 0.06, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Eeloo", LEXICON("transfer_from_lko", 2020, "capture", 680, "land", 620, "takeoff", 620, "return", 680, "landing_difficulty", 0.4, "escape_difficulty", 0.22, "has_surface", TRUE, "has_ore", TRUE, "has_oxygen", FALSE),
    "Sun", LEXICON("transfer_from_lko", 6000, "capture", 0, "land", 0, "takeoff", 0, "return", 0, "landing_difficulty", 1, "escape_difficulty", 1, "has_surface", FALSE, "has_ore", FALSE, "has_oxygen", FALSE)
).

GLOBAL AOSO_WORLD_BODY_CACHE IS LEXICON().

FUNCTION aoso_world_body_stat {
    PARAMETER body_name.
    PARAMETER key_name.
    PARAMETER default_value IS 0.
    IF AOSO_WORLD_KNOWN:HASKEY(body_name) {
        LOCAL known IS AOSO_WORLD_KNOWN[body_name].
        IF known:HASKEY(key_name) { RETURN known[key_name]. }
    }
    RETURN default_value.
}

FUNCTION aoso_world_body_describe {
    PARAMETER body_name.

    LOCAL body_ref IS BODY(body_name).
    LOCAL g_surf IS 0.
    IF body_ref:RADIUS > 0 {
        SET g_surf TO body_ref:MU / (body_ref:RADIUS * body_ref:RADIUS).
    }
    LOCAL atm_exists IS body_ref:ATM:EXISTS.
    LOCAL atm_height IS 0.
    LOCAL pressure_sl IS 0.
    IF atm_exists {
        SET atm_height TO body_ref:ATM:HEIGHT.
        SET pressure_sl TO body_ref:ATM:SEALEVELPRESSURE.
    }
    LOCAL soi_radius IS aoso_const_get("SOI_RADIUS_INFINITE").
    IF body_name <> SUN:NAME { SET soi_radius TO body_ref:SOIRADIUS. }
    LOCAL parent_name IS "".
    IF body_name <> SUN:NAME { SET parent_name TO body_ref:ORBIT:BODY:NAME. }

    LOCAL db IS aoso_body_database_get(body_name).
    LOCAL sma_val IS 0.
    LOCAL period_val IS 0.
    LOCAL ecc_val IS 0.
    IF db:HASKEY("SMA") { SET sma_val TO db["SMA"]. }
    IF db:HASKEY("PERIOD") { SET period_val TO db["PERIOD"]. }
    IF db:HASKEY("ECCENTRICITY") { SET ecc_val TO db["ECCENTRICITY"]. }

    RETURN LEXICON(
        "name", body_name,
        "mu", body_ref:MU,
        "radius", body_ref:RADIUS,
        "g_surf", g_surf,
        "soi", soi_radius,
        "parent", parent_name,
        "sma", sma_val,
        "period", period_val,
        "eccentricity", ecc_val,
        "atm", atm_exists,
        "atm_height", atm_height,
        "pressure_sl", pressure_sl,
        "has_surface", aoso_world_body_stat(body_name, "has_surface", TRUE),
        "has_ore", aoso_world_body_stat(body_name, "has_ore", TRUE),
        "has_oxygen", aoso_world_body_stat(body_name, "has_oxygen", FALSE),
        "landing_difficulty", aoso_world_body_stat(body_name, "landing_difficulty", 0.5),
        "escape_difficulty", aoso_world_body_stat(body_name, "escape_difficulty", 0.5),
        "land_dv", aoso_world_body_stat(body_name, "land", 800),
        "takeoff_dv", aoso_world_body_stat(body_name, "takeoff", 800),
        "capture_dv", aoso_world_body_stat(body_name, "capture", 400),
        "transfer_from_lko", aoso_world_body_stat(body_name, "transfer_from_lko", 1500),
        "return_dv", aoso_world_body_stat(body_name, "return", 800)
    ).
}

FUNCTION aoso_world_body {
    PARAMETER body_name.
    IF AOSO_WORLD_BODY_CACHE:HASKEY(body_name) { RETURN AOSO_WORLD_BODY_CACHE[body_name]. }
    LOCAL described IS aoso_world_body_describe(body_name).
    SET AOSO_WORLD_BODY_CACHE[body_name] TO described.
    RETURN described.
}

FUNCTION aoso_world_body_clear_cache {
    SET AOSO_WORLD_BODY_CACHE TO LEXICON().
}
