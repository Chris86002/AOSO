// AOSO/nav/rendezvous.ks
// Phasing/transfer-window math for closing with a targeted vessel: current
// vs. required phase angle, wait time until the transfer window opens, and
// a prograde transfer node timed to that window. Assumes near-circular
// orbits for the target-radius/transfer-time estimates, consistent with the
// same simplification vehicle/capabilities.ks makes for single-stage dV
// (a full arbitrary-eccentricity solver is out of scope here). Precision
// final-approach/docking burns are handled by advanced/docking.ks (Phase
// 11) once this has closed the gap; this file only covers the "get into
// the same orbit, near the target" nav problem.

FUNCTION aoso_rendezvous_available {
    RETURN HASTARGET.
}

// TARGET:POSITION (and any orbitable's :POSITION) is already relative to the
// active vessel, so no subtraction is needed to get ship-relative position.
FUNCTION aoso_rendezvous_relative_position {
    PARAMETER target_orbitable IS TARGET.
    RETURN target_orbitable:POSITION.
}

FUNCTION aoso_rendezvous_distance {
    PARAMETER target_orbitable IS TARGET.
    RETURN aoso_rendezvous_relative_position(target_orbitable):MAG.
}

FUNCTION aoso_rendezvous_relative_speed {
    PARAMETER target_orbitable IS TARGET.
    RETURN (target_orbitable:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT):MAG.
}

// Signed phase angle (deg) from ship to target around the body, positive
// when the target is ahead of the ship in the direction of the ship's
// orbital motion.
FUNCTION aoso_rendezvous_phase_angle_deg {
    PARAMETER target_orbitable IS TARGET.
    LOCAL pos_ship IS aoso_orbit_position_now(SHIP).
    LOCAL pos_target IS aoso_orbit_position_now(target_orbitable).
    LOCAL ang IS VANG(pos_ship, pos_target).
    LOCAL na IS aoso_orbit_normal_now(SHIP).
    IF VDOT(VCRS(pos_ship, pos_target), na) < 0 { SET ang TO -ang. }
    RETURN ang.
}

// Classic Hohmann phase-angle-at-departure formula: how far ahead the
// target needs to be (deg) right now for a transfer burn today to arrive
// where the target will have coasted to.
FUNCTION aoso_rendezvous_required_phase_angle_deg {
    PARAMETER target_orbitable IS TARGET.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r1 IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL r2 IS target_orbitable:ORBIT:SEMIMAJORAXIS.
    LOCAL sma_t IS (r1 + r2) / 2.
    LOCAL transfer_time IS CONSTANT:PI * SQRT(sma_t ^ 3 / mu).
    LOCAL target_travel_deg IS 360 * transfer_time / target_orbitable:ORBIT:PERIOD.
    RETURN 180 - target_travel_deg.
}

// Seconds to wait until the current phase angle reaches the required
// transfer-window phase angle. Returns -1 if ship and target orbital periods
// are equal (phase angle never changes, so a transfer window never arrives
// without first changing altitude).
FUNCTION aoso_rendezvous_wait_time_to_transfer_s {
    PARAMETER target_orbitable IS TARGET.
    LOCAL current_phase IS aoso_rendezvous_phase_angle_deg(target_orbitable).
    LOCAL required_phase IS aoso_rendezvous_required_phase_angle_deg(target_orbitable).

    LOCAL ship_rate IS 360 / SHIP:ORBIT:PERIOD.
    LOCAL target_rate IS 360 / target_orbitable:ORBIT:PERIOD.
    LOCAL relative_rate IS ship_rate - target_rate.
    IF relative_rate = 0 { RETURN -1. }

    LOCAL wait_s IS -(current_phase - required_phase) / relative_rate.
    UNTIL wait_s >= 0 {
        SET wait_s TO wait_s + (360 / ABS(relative_rate)).
    }
    RETURN wait_s.
}

// Adds a prograde transfer node timed to the next transfer window, sized to
// raise/lower the ship onto a Hohmann transfer ellipse meeting the target's
// (assumed near-circular) altitude. Returns 0 if no window can be computed
// (see aoso_rendezvous_wait_time_to_transfer_s).
FUNCTION aoso_rendezvous_add_phasing_transfer_node {
    PARAMETER target_orbitable IS TARGET.

    LOCAL wait_s IS aoso_rendezvous_wait_time_to_transfer_s(target_orbitable).
    IF wait_s < 0 {
        aoso_log_warn("RENDEZVOUS", "Ship and target periods match; no transfer window exists.").
        RETURN 0.
    }

    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r1 IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL r2 IS target_orbitable:ORBIT:SEMIMAJORAXIS.
    LOCAL sma_t IS (r1 + r2) / 2.

    LOCAL v_now IS aoso_orbit_speed_at_radius(SHIP, r1).
    LOCAL v_transfer IS SQRT(MAX(0, mu * (2 / r1 - 1 / sma_t))).
    LOCAL dv IS v_transfer - v_now.

    LOCAL nd IS NODE(TIME:SECONDS + wait_s, 0, 0, dv).
    ADD nd.
    aoso_log_info("RENDEZVOUS", "Phasing transfer node added: dv=" + ROUND(dv, 1) +
        " m/s in " + ROUND(wait_s, 0) + "s.").
    RETURN nd.
}
