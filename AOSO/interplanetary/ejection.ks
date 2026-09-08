// AOSO/interplanetary/ejection.ks
// Patched-conic ejection burn: sizes and times the escape burn from a
// parking orbit around SHIP:BODY using the hyperbolic-excess speed computed
// by interplanetary/transfer.ks, plus a capture-node helper for arrival.
// Like nav/planechange.ks, the burn *point* on the current orbit is
// resolved numerically (bisection-search for where the ship's position
// direction matches the required outgoing-asymptote direction) rather than
// via a fragile analytic AN/DN-style sign convention. Scope: this only
// solves the burn *geometry* for the ejection itself; picking *which*
// orbital pass to eject on (matching the heliocentric transfer window from
// transfer.ks) is left to the caller, consistent with rendezvous.ks's
// stance that precision timing/final-approach refinement (see
// advanced/docking.ks, Phase 11) belongs to a later phase.

// Eccentricity of the departure hyperbola with periapsis r_peri (m) and
// hyperbolic excess speed v_inf (m/s) around a body of gravitational
// parameter mu.
FUNCTION aoso_ejection_eccentricity {
    PARAMETER v_inf.
    PARAMETER r_peri.
    PARAMETER mu.
    RETURN 1 + (r_peri * v_inf ^ 2) / mu.
}

// Speed (m/s) at r_peri on a hyperbola that reaches excess speed v_inf at
// infinity, via vis-viva with the hyperbola's negative semi-major axis
// folded in (SQRT(v_inf^2 + 2*mu/r)) -- the standard patched-conic
// departure-burn formula.
FUNCTION aoso_ejection_dv_for_v_infinity {
    PARAMETER v_inf.
    PARAMETER r_peri.
    PARAMETER mu.
    RETURN SQRT(v_inf ^ 2 + 2 * mu / r_peri).
}

// True anomaly (deg) at which the departure hyperbola's radius reaches
// infinity, i.e. the angle (from periapsis, in the direction of motion) at
// which the ship's outbound velocity becomes parallel to the outgoing
// asymptote direction: 1 + e*cos(nu)=0 => nu = ARCCOS(-1/e).
FUNCTION aoso_ejection_asymptote_true_anomaly_deg {
    PARAMETER e.
    RETURN ARCCOS(-1 / e).
}

// Rodrigues' rotation formula: rotates vector vec by angle_deg around unit
// axis, right-handed (matching nav/orbit.ks's VCRS(position, velocity)
// normal convention used throughout this repo).
FUNCTION aoso_ejection_rotate_vector {
    PARAMETER vec.
    PARAMETER axis.
    PARAMETER angle_deg.
    LOCAL k IS axis:NORMALIZED.
    LOCAL c IS COS(angle_deg).
    LOCAL s IS SIN(angle_deg).
    RETURN vec * c + VCRS(k, vec) * s + k * VDOT(k, vec) * (1 - c).
}

// Finds the soonest time (seconds from now, within one orbit of SHIP) at
// which SHIP's predicted position direction (around SHIP:BODY) matches
// target_dir, by bisecting sign changes of VDOT(VCRS(target_dir, position),
// normal) -- which is zero whenever the position is parallel *or*
// antiparallel to target_dir -- and keeping only the aligned (parallel)
// root. Returns -1 if no aligned crossing is found within one period.
FUNCTION aoso_ejection_burn_eta_for_direction {
    PARAMETER target_dir.
    PARAMETER samples IS 360.

    LOCAL dir IS target_dir:NORMALIZED.
    LOCAL na IS aoso_orbit_normal_now(SHIP).
    LOCAL period IS SHIP:ORBIT:PERIOD.
    LOCAL now IS TIME:SECONDS.
    LOCAL dt IS period / samples.

    LOCAL prev_t IS 0.
    LOCAL prev_val IS VDOT(VCRS(dir, aoso_orbit_position_at(SHIP, now)), na).

    LOCAL i IS 1.
    UNTIL i > samples {
        LOCAL t IS i * dt.
        LOCAL val IS VDOT(VCRS(dir, aoso_orbit_position_at(SHIP, now + t)), na).

        IF (val >= 0 AND prev_val < 0) OR (val < 0 AND prev_val >= 0) {
            LOCAL lo IS prev_t.
            LOCAL hi IS t.
            LOCAL lo_val IS prev_val.
            LOCAL iter IS 0.
            UNTIL iter >= 20 {
                LOCAL mid IS (lo + hi) / 2.
                LOCAL mid_val IS VDOT(VCRS(dir, aoso_orbit_position_at(SHIP, now + mid)), na).
                IF (mid_val >= 0 AND lo_val < 0) OR (mid_val < 0 AND lo_val >= 0) {
                    SET hi TO mid.
                } ELSE {
                    SET lo TO mid.
                    SET lo_val TO mid_val.
                }
                SET iter TO iter + 1.
            }

            LOCAL root_t IS (lo + hi) / 2.
            IF VDOT(aoso_orbit_position_at(SHIP, now + root_t), dir) > 0 {
                RETURN root_t.
            }
        }

        SET prev_t TO t.
        SET prev_val TO val.
        SET i TO i + 1.
    }
    RETURN -1.
}

// Adds a prograde ejection node on SHIP's current orbit around SHIP:BODY,
// sized and placed to leave SHIP:BODY's SOI with the hyperbolic excess
// velocity interplanetary/transfer.ks computes for a dep_body=SHIP:BODY ->
// arr_body transfer. Assumes a near-circular parking orbit (burn radius
// taken as periapsis), matching nav/rendezvous.ks's near-circular
// simplification. Returns 0 if the two bodies are already at matching
// heliocentric orbits (no burn needed) or if no valid burn point is found.
FUNCTION aoso_interplanetary_add_ejection_node {
    PARAMETER arr_body.

    LOCAL dep_body IS SHIP:BODY.
    LOCAL v_inf_signed IS aoso_interplanetary_v_infinity_signed(dep_body, arr_body).
    LOCAL v_inf_mag IS ABS(v_inf_signed).

    IF v_inf_mag < 0.01 {
        aoso_log_info("EJECTION", "Departure/arrival bodies already orbit-matched; no ejection burn needed.").
        RETURN 0.
    }

    LOCAL mu IS dep_body:MU.
    LOCAL r_peri IS dep_body:RADIUS + PERIAPSIS.

    LOCAL dep_prograde_dir IS aoso_orbit_velocity_at(dep_body, TIME:SECONDS):NORMALIZED.
    LOCAL target_dir IS dep_prograde_dir * (CHOOSE 1 IF v_inf_signed >= 0 ELSE -1).

    LOCAL e IS aoso_ejection_eccentricity(v_inf_mag, r_peri, mu).
    LOCAL nu_inf_deg IS aoso_ejection_asymptote_true_anomaly_deg(e).
    LOCAL na IS aoso_orbit_normal_now(SHIP).
    LOCAL periapsis_dir IS aoso_ejection_rotate_vector(target_dir, na, -nu_inf_deg).

    LOCAL burn_eta IS aoso_ejection_burn_eta_for_direction(periapsis_dir).
    IF burn_eta < 0 {
        aoso_log_warn("EJECTION", "No valid ejection burn point found within one orbit.").
        RETURN 0.
    }

    LOCAL v_peri IS aoso_ejection_dv_for_v_infinity(v_inf_mag, r_peri, mu).
    LOCAL v_now IS aoso_orbit_speed_at_radius(SHIP, r_peri).
    LOCAL dv IS v_peri - v_now.

    LOCAL nd IS NODE(TIME:SECONDS + burn_eta, 0, 0, dv).
    ADD nd.
    aoso_log_info("EJECTION", "Ejection node added: dv=" + ROUND(dv, 1) + " m/s, v_inf=" +
        ROUND(v_inf_mag, 1) + " m/s, in " + ROUND(burn_eta, 0) + "s.").
    RETURN nd.
}

// Capture/insertion burn once inside arr_body's SOI (SHIP:BODY = arr_body,
// arriving on a hyperbolic or high-apoapsis trajectory): lowers apoapsis to
// target_apo_alt at the current periapsis. Reuses nav/hohmann.ks's generic
// apoapsis-change helper, which is already vis-viva-general enough to size
// a capture burn correctly (positive hyperbolic "apoapsis" included) --
// same reuse relationship hohmann.ks has with flight/maneuver.ks.
FUNCTION aoso_interplanetary_add_capture_node {
    PARAMETER target_apo_alt.
    LOCAL nd IS aoso_hohmann_add_apoapsis_change(target_apo_alt).
    aoso_log_info("EJECTION", "Capture node added at " + SHIP:BODY:NAME + ", target apo=" +
        ROUND(target_apo_alt, 0) + "m.").
    RETURN nd.
}
