// AOSO/nav/hohmann.ks
// Generic altitude-change (Hohmann-style) maneuvers, generalizing
// flight/maneuver.ks's apoapsis-only circularize helper to either apsis so
// later phases (interplanetary, landing, refuel/return) can raise or lower
// an orbit to any target altitude with two burns instead of each writing
// its own vis-viva math. Node execution still goes through the shared
// aoso_maneuver_execute_next() burn executor.

// Delta-v (m/s, signed) at periapsis needed to raise/lower apoapsis to
// target_apo_alt, keeping periapsis fixed.
FUNCTION aoso_hohmann_dv_at_periapsis_for_apoapsis {
    PARAMETER target_apo_alt.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + PERIAPSIS.
    LOCAL r_target_apo IS SHIP:BODY:RADIUS + target_apo_alt.
    LOCAL sma_new IS (radius + r_target_apo) / 2.
    LOCAL v_new IS SQRT(MAX(0, mu * (2 / radius - 1 / sma_new))).
    LOCAL v_now IS aoso_orbit_speed_at_radius(radius, SHIP).
    RETURN v_new - v_now.
}

// Delta-v (m/s, signed) at apoapsis needed to raise/lower periapsis to
// target_peri_alt, keeping apoapsis fixed.
FUNCTION aoso_hohmann_dv_at_apoapsis_for_periapsis {
    PARAMETER target_peri_alt.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + APOAPSIS.
    LOCAL r_target_peri IS SHIP:BODY:RADIUS + target_peri_alt.
    LOCAL sma_new IS (radius + r_target_peri) / 2.
    LOCAL v_new IS SQRT(MAX(0, mu * (2 / radius - 1 / sma_new))).
    LOCAL v_now IS aoso_orbit_speed_at_radius(radius, SHIP).
    RETURN v_new - v_now.
}

FUNCTION aoso_hohmann_add_apoapsis_change {
    PARAMETER target_apo_alt.
    LOCAL dv IS aoso_hohmann_dv_at_periapsis_for_apoapsis(target_apo_alt).
    LOCAL nd IS NODE(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, dv).
    ADD nd.
    IF DEFINED aoso_log_info {
        aoso_log_info("HOHMANN", "Apoapsis-change node added: dv=" + ROUND(dv, 1) + " m/s at periapsis, target apo=" + ROUND(target_apo_alt, 0) + "m.").
    }
    RETURN nd.
}

FUNCTION aoso_hohmann_add_periapsis_change {
    PARAMETER target_peri_alt.
    LOCAL dv IS aoso_hohmann_dv_at_apoapsis_for_periapsis(target_peri_alt).
    LOCAL nd IS NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dv).
    ADD nd.
    IF DEFINED aoso_log_info {
        aoso_log_info("HOHMANN", "Periapsis-change node added: dv=" + ROUND(dv, 1) + " m/s at apoapsis, target peri=" + ROUND(target_peri_alt, 0) + "m.").
    }
    RETURN nd.
}

// First burn of a full two-burn transfer to a circular orbit at target_alt:
// changes whichever apsis is currently on the far side of target_alt,
// leaving the near apsis where the vessel already is. Call
// aoso_hohmann_add_circularize_at_far_apsis() after this node executes to
// complete the transfer.
FUNCTION aoso_hohmann_transfer_to_altitude {
    PARAMETER target_alt.
    LOCAL r_now IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL r_target IS SHIP:BODY:RADIUS + target_alt.

    IF r_target > r_now {
        RETURN aoso_hohmann_add_apoapsis_change(target_alt).
    }
    RETURN aoso_hohmann_add_periapsis_change(target_alt).
}

// Delta-v (m/s, signed) at periapsis to circularize, mirroring
// flight/maneuver.ks's aoso_maneuver_circularize_dv_at_apoapsis().
FUNCTION aoso_hohmann_circularize_dv_at_periapsis {
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + PERIAPSIS.
    LOCAL v_circ IS SQRT(mu / radius).
    LOCAL v_now IS aoso_orbit_speed_at_radius(radius, SHIP).
    RETURN v_circ - v_now.
}

FUNCTION aoso_hohmann_add_circularize_at_periapsis {
    LOCAL dv IS aoso_hohmann_circularize_dv_at_periapsis().
    LOCAL nd IS NODE(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, dv).
    ADD nd.
    IF DEFINED aoso_log_info {
        aoso_log_info("HOHMANN", "Circularization node added: dv=" + ROUND(dv, 1) + " m/s at periapsis.").
    }
    RETURN nd.
}

// Second burn of the two-burn transfer: circularizes at whichever apsis is
// now further from the body (the one aoso_hohmann_transfer_to_altitude()
// raised/lowered towards the target altitude). Reuses flight/maneuver.ks's
// apoapsis circularizer so the two phases share one implementation.
FUNCTION aoso_hohmann_add_circularize_at_far_apsis {
    IF APOAPSIS > PERIAPSIS {
        RETURN aoso_maneuver_add_circularize_at_apoapsis().
    }
    RETURN aoso_hohmann_add_circularize_at_periapsis().
}
