// AOSO/nav/planechange.ks
// Inclination-matching maneuver: builds a normal-only node at whichever
// upcoming relative-node crossing (see nav/orbit.ks) is sooner, sized with
// the standard combined plane-change formula (2*v*sin(dTheta/2)) evaluated
// at that crossing's predicted speed. The sign of the normal component is
// resolved numerically -- by testing which of +normal/-normal actually
// reduces the angle to the target plane -- rather than trusting an
// AN-vs-DN sign convention that cannot be verified without a live KSP/kOS
// session, per this repo's stance on not guessing at unverifiable behavior.

// Delta-v magnitude (m/s) for a pure inclination change of angle_deg at
// speed_ms, keeping orbital speed constant.
FUNCTION aoso_planechange_dv_for_angle {
    PARAMETER angle_deg.
    PARAMETER speed_ms.
    RETURN 2 * speed_ms * SIN(angle_deg / 2).
}

// Adds a normal-direction node at the chosen relative-node crossing
// (node_index 0 = sooner crossing, 1 = the other one within one period) that
// rotates the vessel's orbital plane to match target_orbitable's. Returns 0
// (no node added) if already within tolerance_deg of co-planar, or if no
// relative node could be found within one orbit.
FUNCTION aoso_planechange_add_node_for_target {
    PARAMETER target_orbitable.
    PARAMETER node_index IS 0.
    PARAMETER tolerance_deg IS 0.05.

    LOCAL rel_incl IS aoso_orbit_relative_inclination_deg(SHIP, target_orbitable).
    IF rel_incl < tolerance_deg {
        aoso_log_info("PLANECHANGE", "Already co-planar within " + tolerance_deg + " deg; no node added.").
        RETURN 0.
    }

    LOCAL etas IS aoso_orbit_relative_node_etas(SHIP, target_orbitable).
    IF etas:LENGTH = 0 OR node_index >= etas:LENGTH {
        aoso_log_warn("PLANECHANGE", "No relative node found within one orbit.").
        RETURN 0.
    }

    LOCAL burn_eta IS etas[node_index].
    LOCAL t IS TIME:SECONDS + burn_eta.
    LOCAL r_vec IS aoso_orbit_position_at(SHIP, t).
    LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t).
    LOCAL na IS VCRS(r_vec, v_vec):NORMALIZED.
    LOCAL nb IS aoso_orbit_normal_now(target_orbitable).

    LOCAL dv_mag IS aoso_planechange_dv_for_angle(rel_incl, v_vec:MAG).

    // Numerically resolve the burn sign: whichever candidate post-burn
    // normal ends up closer to the target's normal is the correct one.
    LOCAL na_plus IS VCRS(r_vec, v_vec + na * dv_mag):NORMALIZED.
    LOCAL na_minus IS VCRS(r_vec, v_vec - na * dv_mag):NORMALIZED.
    LOCAL sign IS 1.
    IF VANG(na_minus, nb) < VANG(na_plus, nb) { SET sign TO -1. }

    LOCAL nd IS NODE(t, 0, sign * dv_mag, 0).
    ADD nd.
    aoso_log_info("PLANECHANGE", "Plane-change node added: dv=" + ROUND(sign * dv_mag, 1) +
        " m/s normal, closing " + ROUND(rel_incl, 2) + " deg relative inclination.").
    RETURN nd.
}

// Adds a normal-direction node at the next equatorial crossing that rotates
// SHIP's inclination toward target_inc_deg (90 = polar). Sign is resolved
// the same way aoso_planechange_add_node_for_target does: whichever of
// +/- normal leaves |inclination - target| smaller. Returns 0 if already
// within tolerance, hyperbolic, or no equatorial node was found.
FUNCTION aoso_planechange_add_node_for_inclination {
    PARAMETER target_inc_deg IS 90.
    PARAMETER tolerance_deg IS 15.

    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    IF aoso_orbit_period_s() <= 0 { RETURN 0. }

    LOCAL nb IS SHIP:BODY:ANGULARVEL:NORMALIZED.
    LOCAL inc_now IS VANG(aoso_orbit_normal_now(SHIP), nb).
    LOCAL err IS ABS(inc_now - target_inc_deg).
    IF err <= tolerance_deg {
        aoso_log_info("PLANECHANGE", "Already within " + tolerance_deg + " deg of inclination " + target_inc_deg + " (now " + ROUND(inc_now, 1) + ").").
        RETURN 0.
    }

    LOCAL etas IS aoso_orbit_equatorial_node_etas(SHIP).
    IF etas:LENGTH = 0 {
        aoso_log_warn("PLANECHANGE", "No equatorial crossing found within one orbit.").
        RETURN 0.
    }

    LOCAL burn_eta IS etas[0].
    LOCAL t IS TIME:SECONDS + burn_eta.
    LOCAL r_vec IS aoso_orbit_position_at(SHIP, t).
    LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t).
    LOCAL na IS VCRS(r_vec, v_vec):NORMALIZED.
    LOCAL d_inc IS ABS(target_inc_deg - VANG(na, nb)).
    LOCAL dv_mag IS aoso_planechange_dv_for_angle(d_inc, v_vec:MAG).

    LOCAL na_plus IS VCRS(r_vec, v_vec + na * dv_mag):NORMALIZED.
    LOCAL na_minus IS VCRS(r_vec, v_vec - na * dv_mag):NORMALIZED.
    LOCAL err_plus IS ABS(VANG(na_plus, nb) - target_inc_deg).
    LOCAL err_minus IS ABS(VANG(na_minus, nb) - target_inc_deg).
    LOCAL sign IS 1.
    IF err_minus < err_plus { SET sign TO -1. }

    LOCAL nd IS NODE(t, 0, sign * dv_mag, 0).
    ADD nd.
    aoso_log_info("PLANECHANGE", "Inclination node added: dv=" + ROUND(sign * dv_mag, 1) +
        " m/s normal, " + ROUND(inc_now, 1) + " -> " + ROUND(target_inc_deg, 0) + " deg.").
    RETURN nd.
}
