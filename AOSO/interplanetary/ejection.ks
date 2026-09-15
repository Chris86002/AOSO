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
    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { RETURN -1. }
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
    aoso_ejection_seek_arrival(nd, arr_body).
    aoso_log_info("EJECTION", "Ejection node added: dv=" + ROUND(nd:PROGRADE, 1) + " m/s, v_inf=" +
        ROUND(v_inf_mag, 1) + " m/s, in " + ROUND(nd:ETA, 0) + "s.").
    RETURN nd.
}

// After a Hohmann-geometry ejection, walk extra parking orbits so patched
// conics actually show the destination (same idea as the moon seek).
FUNCTION aoso_ejection_seek_arrival {
    PARAMETER nd.
    PARAMETER arr_body.
    IF aoso_rendezvous_orbit_pe(nd:ORBIT, arr_body) >= 0 {
        aoso_rendezvous_tune_pe(nd, arr_body).
        RETURN TRUE.
    }
    LOCAL period IS aoso_orbit_period_s().
    IF period < 60 { RETURN FALSE. }
    LOCAL t0 IS nd:ETA.
    LOCAL i IS 1.
    UNTIL i > 10 {
        SET nd:ETA TO t0 + (i * period).
        IF aoso_rendezvous_orbit_pe(nd:ORBIT, arr_body) >= 0 {
            aoso_rendezvous_tune_pe(nd, arr_body).
            RETURN TRUE.
        }
        SET i TO i + 1.
    }
    SET nd:ETA TO t0.
    RETURN FALSE.
}

FUNCTION aoso_capture_pe_too_high {
    PARAMETER park.
    LOCAL soi_a IS SHIP:BODY:SOIRADIUS - SHIP:BODY:RADIUS.
    IF PERIAPSIS > park * 3 { RETURN TRUE. }
    IF PERIAPSIS > soi_a * 0.2 { RETURN TRUE. }
    RETURN FALSE.
}

// Hill-climb a near-term prograde/retro node until nd:ORBIT periapsis is
// the parking altitude. Works on hyperbolas (no apoapsis to burn at).
FUNCTION aoso_capture_add_pe_adjust {
    PARAMETER target_pe.
    LOCAL eta_b IS 40.
    IF ETA:PERIAPSIS > 25 {
        SET eta_b TO ETA:PERIAPSIS * 0.25.
        IF eta_b < 20 { SET eta_b TO 20. }
        IF eta_b > 90 { SET eta_b TO 90. }
    } ELSE {
        SET eta_b TO 15.
    }
    IF HASNODE { RETURN 0. }
    LOCAL nd IS NODE(TIME:SECONDS + eta_b, 0, 0, 0).
    ADD nd.
    LOCAL step IS 25.
    LOCAL best_err IS ABS(nd:ORBIT:PERIAPSIS - target_pe).
    LOCAL round_i IS 0.
    UNTIL round_i >= 12 {
        LOCAL orig IS nd:PROGRADE.
        SET nd:PROGRADE TO orig - step.
        WAIT 0.
        LOCAL err IS ABS(nd:ORBIT:PERIAPSIS - target_pe).
        IF err < best_err {
            SET best_err TO err.
        } ELSE {
            SET nd:PROGRADE TO orig + step.
            WAIT 0.
            SET err TO ABS(nd:ORBIT:PERIAPSIS - target_pe).
            IF err < best_err {
                SET best_err TO err.
            } ELSE {
                SET nd:PROGRADE TO orig.
                SET step TO step * 0.5.
            }
        }
        IF best_err < 800 { 
            SET round_i TO 12.
        } ELSE {
            SET round_i TO round_i + 1.
        }
    }
    IF nd:DELTAV:MAG < 0.5 {
        REMOVE nd.
        RETURN 0.
    }
    IF nd:DELTAV:MAG > 2500 {
        aoso_log_warn("EJECTION", "PE-adjust dv " + ROUND(nd:DELTAV:MAG, 0) + " m/s is too large - circularizing at current PE instead.").
        REMOVE nd.
        RETURN aoso_hohmann_add_circularize_at_periapsis().
    }
    aoso_log_info("EJECTION", "Capture PE-adjust dv=" + ROUND(nd:PROGRADE, 1) + " m/s, PE " + ROUND(PERIAPSIS, 0) + " -> " + ROUND(nd:ORBIT:PERIAPSIS, 0) + "m.").
    RETURN nd.
}

FUNCTION aoso_capture_want_polar {
    IF DEFINED AOSO_WANT_POLAR {
        RETURN AOSO_WANT_POLAR.
    }
    RETURN FALSE.
}

FUNCTION aoso_capture_polar_err {
    RETURN ABS(SHIP:ORBIT:INCLINATION - aoso_config_get("TOUR_POLAR_INCLINATION", 90)).
}

FUNCTION aoso_capture_high_ap {
    PARAMETER park.
    LOCAL soi_a IS SHIP:BODY:SOIRADIUS - SHIP:BODY:RADIUS.
    LOCAL hi IS park * 18.
    IF hi < park * 8 { SET hi TO park * 8. }
    IF hi > soi_a * 0.28 { SET hi TO soi_a * 0.28. }
    RETURN hi.
}

// Capture/insertion once inside arr_body's SOI. A grazing flyby
// (Minmus patchPE at the SOI edge) must LOWER periapsis first; circularizing
// there leaves a barely-bound orbit. Hyperbolas have no apoapsis, so PE is
// set with a near-term vis-viva node, then we circularize at PE.
//
// If the tour will land, polar is done HERE rather than as a 140 m/s
// normal after circularizing at 15 km (that was 142 m/s at v=143 and
// wrecked the orbit). Cheap path: bind a high ellipse at PE (Oberth),
// plane-change at the slow AN/DN near AP, then circularize.
FUNCTION aoso_interplanetary_add_capture_node {
    PARAMETER target_apo_alt.
    LOCAL min_pe IS target_apo_alt.
    IF SHIP:BODY:ATM:EXISTS {
        LOCAL atm_floor IS SHIP:BODY:ATM:HEIGHT + 15000.
        IF min_pe < atm_floor { SET min_pe TO atm_floor. }
    } ELSE {
        IF min_pe < 5000 { SET min_pe TO 5000. }
    }

    IF PERIAPSIS < min_pe {
        aoso_log_info("EJECTION", "Capture at " + SHIP:BODY:NAME + ": raising periapsis to " + ROUND(min_pe, 0) + "m (now " + ROUND(PERIAPSIS, 0) + "m).").
        IF aoso_orbit_is_hyperbolic() {
            RETURN aoso_capture_add_pe_adjust(min_pe).
        }
        RETURN aoso_hohmann_add_periapsis_change(min_pe).
    }
    IF aoso_capture_pe_too_high(min_pe) {
        aoso_log_info("EJECTION", "Capture at " + SHIP:BODY:NAME + ": lowering periapsis from " + ROUND(PERIAPSIS, 0) + "m to " + ROUND(min_pe, 0) + "m (Oberth is cheaper at a low PE).").
        LOCAL nd_pe IS aoso_capture_add_pe_adjust(min_pe).
        IF nd_pe <> 0 { RETURN nd_pe. }
    }

    LOCAL want_polar IS aoso_capture_want_polar().
    LOCAL polar_err IS aoso_capture_polar_err().
    LOCAL polar_tol IS aoso_config_get("TOUR_POLAR_TOLERANCE_DEG", 15).
    LOCAL high_ap IS aoso_capture_high_ap(min_pe).

    IF want_polar {
        IF polar_err > polar_tol {
            LOCAL have_high_ap IS FALSE.
            IF NOT aoso_orbit_is_hyperbolic() {
                IF aoso_orbit_apoapsis_alt() >= high_ap * 0.7 { SET have_high_ap TO TRUE. }
            }
            IF have_high_ap {
                aoso_log_info("EJECTION", "Polar capture at " + SHIP:BODY:NAME + ": plane-changing at the slow AN/DN (inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 2) + ").").
                RETURN aoso_planechange_add_node_for_inclination(aoso_config_get("TOUR_POLAR_INCLINATION", 90), polar_tol).
            }
            aoso_log_info("EJECTION", "Polar capture at " + SHIP:BODY:NAME + " PE: binding AP to " + ROUND(high_ap, 0) + "m first so the plane change is cheap at apoapsis (inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + ").").
            RETURN aoso_hohmann_add_apoapsis_change(high_ap).
        }
    }

    LOCAL circ_dv IS aoso_hohmann_circularize_dv_at_periapsis().
    LOCAL burn_t IS aoso_perf_burn_time_for_dv(ABS(circ_dv)).
    IF burn_t > 45 {
        LOCAL soi_a IS SHIP:BODY:SOIRADIUS - SHIP:BODY:RADIUS.
        LOCAL cap_ap IS min_pe * 6.
        IF cap_ap < min_pe * 2 { SET cap_ap TO min_pe * 2. }
        IF cap_ap > soi_a * 0.35 { SET cap_ap TO soi_a * 0.35. }
        LOCAL need_bind IS FALSE.
        IF aoso_orbit_is_hyperbolic() { SET need_bind TO TRUE. }
        IF NOT need_bind {
            IF SHIP:ORBIT:ECCENTRICITY > 0.45 {
                IF aoso_orbit_apoapsis_alt() > cap_ap * 1.2 { SET need_bind TO TRUE. }
            }
        }
        IF need_bind {
            aoso_log_info("EJECTION", "Oberth capture at " + SHIP:BODY:NAME + " PE: binding AP to " + ROUND(cap_ap, 0) + "m first (full circularize would take " + ROUND(burn_t, 0) + "s and miss the PE peak).").
            RETURN aoso_hohmann_add_apoapsis_change(cap_ap).
        }
    }
    aoso_log_info("EJECTION", "Capture at " + SHIP:BODY:NAME + ": circularizing at periapsis " + ROUND(PERIAPSIS, 0) + "m (Oberth - cheapest insertion).").
    RETURN aoso_hohmann_add_circularize_at_periapsis().
}
