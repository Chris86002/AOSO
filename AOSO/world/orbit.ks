// AOSO/world/orbit.ks
// World-model snapshot of the ship's current orbit around the current
// body. Does not duplicate nav/orbit.ks's Lambert/node math -- this is
// "where am I?" for the planner, not "how do I get there?"

FUNCTION aoso_world_parking_alt {
    PARAMETER body_name IS SHIP:BODY:NAME.
    LOCAL described IS aoso_world_body(body_name).
    IF described["atm"] {
        RETURN MAX(aoso_config_get("PARKING_ORBIT_ALT", 100000), described["atm_height"] + 15000).
    }
    RETURN MAX(15000, described["radius"] * 0.08).
}

FUNCTION aoso_world_orbit_is_stable {
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "SPLASHED" { RETURN FALSE. }
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN FALSE. }
    IF PERIAPSIS < 2000 { RETURN FALSE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT + 5000 { RETURN FALSE. }
    }
    RETURN TRUE.
}

FUNCTION aoso_world_orbit_summary {
    LOCAL park IS aoso_world_parking_alt(SHIP:BODY:NAME).
    LOCAL hyperbolic IS aoso_orbit_is_hyperbolic().
    LOCAL apo_alt IS 0.
    LOCAL period_s IS 0.
    IF NOT hyperbolic {
        SET apo_alt TO APOAPSIS.
        SET period_s TO aoso_orbit_period_s().
    }
    RETURN LEXICON(
        "body", SHIP:BODY:NAME,
        "status", SHIP:STATUS,
        "apo", apo_alt,
        "peri", PERIAPSIS,
        "ecc", SHIP:ORBIT:ECCENTRICITY,
        "inclination", SHIP:ORBIT:INCLINATION,
        "period", period_s,
        "hyperbolic", hyperbolic,
        "altitude", ALTITUDE,
        "parking_alt", park,
        "stable", aoso_world_orbit_is_stable()
    ).
}
