// AOSO/world/network.ks
// Connectivity of the current vessel to the rest of the Kerbol system:
// antenna present, home-SOI vs deep space, thick-atmosphere blackout
// risk. Stock kOS does not need CommNet to run, so "connected" here means
// "the ship has a transmitter and is not inside a reentry plasma."

FUNCTION aoso_world_in_home_soi {
    LOCAL home_name IS aoso_config_get("HOME_BODY", "Kerbin").
    IF SHIP:BODY:NAME = home_name { RETURN TRUE. }
    IF SHIP:BODY:NAME = SUN:NAME { RETURN FALSE. }
    RETURN SHIP:BODY:ORBIT:BODY:NAME = home_name.
}

FUNCTION aoso_world_blackout_risk {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    IF ALTITUDE > SHIP:BODY:ATM:HEIGHT { RETURN FALSE. }
    LOCAL described IS aoso_world_body(SHIP:BODY:NAME).
    IF described["pressure_sl"] < 0.5 { RETURN FALSE. }
    IF SHIP:VELOCITY:SURFACE:MAG < 800 { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_world_network_summary {
    LOCAL has_antenna IS FALSE.
    IF DEFINED AOSO_PROFILE {
        IF AOSO_PROFILE:HASKEY("navigation") {
            SET has_antenna TO AOSO_PROFILE["navigation"]["has_antenna"].
        }
    }
    IF NOT has_antenna {
        IF SHIP:CREW:LENGTH > 0 { SET has_antenna TO TRUE. }
    }
    RETURN LEXICON(
        "has_antenna", has_antenna,
        "in_home_soi", aoso_world_in_home_soi(),
        "blackout_risk", aoso_world_blackout_risk(),
        "body", SHIP:BODY:NAME
    ).
}
