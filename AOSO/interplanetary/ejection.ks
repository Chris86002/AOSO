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

// Find the parking-orbit burn point whose radius direction has the
// hyperbolic periapsis-to-asymptote angle required by a full 3-D v-infinity
// vector. This generalizes the old prograde/retrograde-only ejection geometry
// without adding any n-body model.
FUNCTION aoso_ejection_burn_ut_for_vinf {
    PARAMETER vinf_vec.
    PARAMETER desired_ut.
    PARAMETER r_peri.
    PARAMETER mu.

    LOCAL vinf_mag IS vinf_vec:MAG.
    IF vinf_mag < 0.01 { RETURN -1. }
    LOCAL e IS aoso_ejection_eccentricity(vinf_mag, r_peri, mu).
    LOCAL nu_inf IS aoso_ejection_asymptote_true_anomaly_deg(e).
    LOCAL vdir IS vinf_vec:NORMALIZED.

    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { RETURN -1. }
    LOCAL start_ut IS desired_ut - period * 0.5.
    IF start_ut < TIME:SECONDS + 30 { SET start_ut TO TIME:SECONDS + 30. }

    LOCAL best_ut IS start_ut.
    LOCAL best_err IS 999.
    LOCAL samples IS 180.
    LOCAL step IS period / samples.
    LOCAL i IS 0.
    UNTIL i > samples {
        LOCAL test_ut IS start_ut + i * step.
        LOCAL p IS aoso_orbit_position_at(SHIP, test_ut).
        IF p:MAG > 1 {
            LOCAL err IS ABS(VANG(p, vdir) - nu_inf).
            IF err < best_err {
                SET best_err TO err.
                SET best_ut TO test_ut.
            }
        }
        SET i TO i + 1.
    }

    // Local refinement around the best coarse sample.
    LOCAL refine IS step.
    LOCAL ri IS 0.
    UNTIL ri >= 8 {
        SET refine TO refine * 0.5.
        LOCAL t_minus IS best_ut - refine.
        LOCAL t_plus IS best_ut + refine.
        IF t_minus > TIME:SECONDS + 25 {
            LOCAL p_minus IS aoso_orbit_position_at(SHIP, t_minus).
            LOCAL e_minus IS ABS(VANG(p_minus, vdir) - nu_inf).
            IF e_minus < best_err {
                SET best_err TO e_minus.
                SET best_ut TO t_minus.
            }
        }
        LOCAL p_plus IS aoso_orbit_position_at(SHIP, t_plus).
        LOCAL e_plus IS ABS(VANG(p_plus, vdir) - nu_inf).
        IF e_plus < best_err {
            SET best_err TO e_plus.
            SET best_ut TO t_plus.
        }
        SET ri TO ri + 1.
    }

    IF best_err > aoso_config_get("INTERPLANETARY_EJECTION_GEOM_TOL_DEG", 2.5) {
        RETURN -1.
    }
    RETURN best_ut.
}

// Build one stock maneuver node from a native Lambert candidate. The node is
// accepted only if KSP's own patched conics show the requested target SOI;
// otherwise it is deleted. Native search proposes -- stock KSP still decides.
FUNCTION aoso_interplanetary_add_candidate_ejection_node {
    PARAMETER arr_body.
    PARAMETER cand.

    LOCAL dep_body IS SHIP:BODY.
    LOCAL vd IS aoso_interplanetary_candidate_vinf(dep_body, arr_body, cand).
    IF NOT vd["ok"] { RETURN 0. }

    LOCAL vinf_vec IS vd["vinf_out"].
    LOCAL vinf_mag IS vd["vinf_out_mag"].
    LOCAL mu IS dep_body:MU.
    LOCAL r_peri IS dep_body:RADIUS + MAX(1000, PERIAPSIS).
    LOCAL burn_ut IS aoso_ejection_burn_ut_for_vinf(vinf_vec, vd["dep_ut"], r_peri, mu).
    IF burn_ut < 0 { RETURN 0. }

    LOCAL p IS aoso_orbit_position_at(SHIP, burn_ut).
    LOCAL pdir IS p:NORMALIZED.
    LOCAL vdir IS vinf_vec:NORMALIZED.
    LOCAL h IS VCRS(pdir, vdir).
    IF h:MAG < 0.001 { RETURN 0. }
    SET h TO h:NORMALIZED.

    LOCAL req_dir IS VCRS(h, pdir):NORMALIZED.
    IF VDOT(req_dir, vdir) < 0 { SET req_dir TO 0 - req_dir. }

    LOCAL v_peri IS aoso_ejection_dv_for_v_infinity(vinf_mag, r_peri, mu).
    LOCAL req_vel IS req_dir * v_peri.
    LOCAL cur_vel IS aoso_orbit_velocity_at(SHIP, burn_ut).
    LOCAL dv_vec IS req_vel - cur_vel.
    LOCAL xyz IS aoso_lambert_dv_to_node_xyz(dv_vec, p, cur_vel).

    LOCAL nd IS NODE(burn_ut - TIME:SECONDS, xyz["radial"], xyz["normal"], xyz["prograde"]).
    ADD nd.
    aoso_rendezvous_settle_long().

    LOCAL pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, arr_body).
    IF pe < 0 {
        REMOVE nd.
        RETURN 0.
    }

    aoso_rendezvous_tune_pe(nd, arr_body).
    aoso_rendezvous_settle_long().
    SET pe TO aoso_rendezvous_orbit_pe(nd:ORBIT, arr_body).
    IF NOT aoso_rendezvous_pe_ok_value(pe, arr_body) {
        REMOVE nd.
        RETURN 0.
    }

    LOCAL burn_t IS aoso_perf_burn_time_for_dv(nd:DELTAV:MAG).
    LOCAL period IS aoso_orbit_period_s().
    IF period > 0 {
        LOCAL max_frac IS aoso_config_get("INTERPLANETARY_MAX_BURN_PERIOD_FRAC", 0.18).
        IF burn_t > period * max_frac {
            aoso_log_warn("EJECTION", "Native interplanetary node is too non-impulsive for this vessel: burn " +
                ROUND(burn_t, 0) + "s = " + ROUND(100 * burn_t / period, 1) +
                "% of parking period. Rejecting for precision.").
            REMOVE nd.
            RETURN 0.
        }
    }

    aoso_log_info("EJECTION", "Native planetary candidate validated by KSP: " +
        dep_body:NAME + " -> " + arr_body:NAME + "  dv=" + ROUND(nd:DELTAV:MAG, 1) +
        " m/s  PE=" + ROUND(pe, 0) + "m  depart T+" +
        ROUND(burn_ut - TIME:SECONDS, 0) + "s  TOF=" + ROUND(vd["tof"] / 21600, 1) + "d.").
    RETURN nd.
}

FUNCTION aoso_interplanetary_add_native_ejection_node {
    PARAMETER arr_body.
    LOCAL res IS aoso_interplanetary_native_search(arr_body).
    IF NOT res:ISTYPE("Lexicon") { RETURN 0. }
    IF NOT res["ok"] { RETURN 0. }

    LOCAL cands IS res["cands"].
    IF NOT cands:ISTYPE("List") { RETURN 0. }
    LOCAL n_try IS MIN(cands:LENGTH, aoso_config_get("INTERPLANETARY_VALIDATE_CANDIDATES", 8)).
    LOCAL i IS 0.
    UNTIL i >= n_try {
        LOCAL cand IS cands[i].
        aoso_ui_pulse("Validating planetary transfer",
            arr_body:NAME + " " + (i + 1) + "/" + n_try +
            "  est " + ROUND(cand["total_dv"], 0) + " m/s").
        LOCAL nd IS aoso_interplanetary_add_candidate_ejection_node(arr_body, cand).
        IF nd:ISTYPE("Node") {
            aoso_ui_clear().
            RETURN nd.
        }
        SET i TO i + 1.
        WAIT 0.
    }

    aoso_ui_clear().
    aoso_log_warn("EJECTION", "Native planetary porkchop had " + cands:LENGTH +
        " finalists but none survived stock patched-conic validation. Falling back to Hohmann window logic.").
    RETURN 0.
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
FUNCTION aoso_capture_safe_pe_floor {
    PARAMETER target_pe.
    LOCAL floor_pe IS MAX(5000, target_pe * 0.5).
    IF SHIP:BODY:ATM:EXISTS {
        SET floor_pe TO MAX(SHIP:BODY:ATM:HEIGHT + 5000, target_pe * 0.8).
    }
    RETURN floor_pe.
}

// Near-term PE adjust used before capture. The old one-sided hill climb
// minimized ABS(PE-target) without a collision constraint, so Minmus chose
// -30.9 km because it was numerically "closer" to +15 km than the previous
// +1,234 km graze. This search never accepts a candidate below a hard safe
// floor and refines around the best valid prograde/retrograde impulse.
FUNCTION aoso_capture_add_pe_adjust {
    PARAMETER target_pe.
    aoso_warp_hard_stop().

    LOCAL safe_floor IS aoso_capture_safe_pe_floor(target_pe).
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

    LOCAL best_dv IS 0.
    LOCAL best_pe IS nd:ORBIT:PERIAPSIS.
    LOCAL best_err IS 1E99.
    IF best_pe >= safe_floor {
        SET best_err TO ABS(best_pe - target_pe).
    }

    LOCAL step IS 128.
    LOCAL tol IS MAX(1000, target_pe * 0.1).
    LOCAL round_i IS 0.
    UNTIL round_i >= 22 {
        LOCAL center_dv IS best_dv.
        LOCAL round_dv IS best_dv.
        LOCAL round_pe IS best_pe.
        LOCAL round_err IS best_err.

        SET nd:PROGRADE TO center_dv - step.
        WAIT 0.
        LOCAL pe_minus IS nd:ORBIT:PERIAPSIS.
        IF pe_minus >= safe_floor {
            LOCAL err_minus IS ABS(pe_minus - target_pe).
            IF err_minus < round_err {
                SET round_err TO err_minus.
                SET round_dv TO center_dv - step.
                SET round_pe TO pe_minus.
            }
        }

        SET nd:PROGRADE TO center_dv + step.
        WAIT 0.
        LOCAL pe_plus IS nd:ORBIT:PERIAPSIS.
        IF pe_plus >= safe_floor {
            LOCAL err_plus IS ABS(pe_plus - target_pe).
            IF err_plus < round_err {
                SET round_err TO err_plus.
                SET round_dv TO center_dv + step.
                SET round_pe TO pe_plus.
            }
        }

        IF round_err < best_err {
            SET best_err TO round_err.
            SET best_dv TO round_dv.
            SET best_pe TO round_pe.
        } ELSE {
            SET step TO step * 0.5.
        }

        SET nd:PROGRADE TO best_dv.
        WAIT 0.

        IF best_err <= tol {
            IF step <= 4 { SET round_i TO 22. }
        }
        IF step < 0.5 { SET round_i TO 22. }
        SET round_i TO round_i + 1.
    }

    SET nd:PROGRADE TO best_dv.
    WAIT 0.
    LOCAL final_pe IS nd:ORBIT:PERIAPSIS.
    LOCAL final_err IS ABS(final_pe - target_pe).

    IF final_pe < safe_floor {
        aoso_log_error("EJECTION", "Rejected capture PE-adjust: candidate PE=" + ROUND(final_pe, 0) +
            "m below safe floor " + ROUND(safe_floor, 0) + "m.").
        REMOVE nd.
        RETURN 0.
    }
    IF final_err > tol {
        aoso_log_warn("EJECTION", "Rejected capture PE-adjust: best safe PE=" + ROUND(final_pe, 0) +
            "m is not close enough to target " + ROUND(target_pe, 0) + "m (tol " + ROUND(tol, 0) + "m).").
        REMOVE nd.
        RETURN 0.
    }
    IF nd:DELTAV:MAG < 0.5 {
        REMOVE nd.
        RETURN 0.
    }
    IF nd:DELTAV:MAG > 2500 {
        aoso_log_warn("EJECTION", "Rejected capture PE-adjust dv " + ROUND(nd:DELTAV:MAG, 0) +
            " m/s as unreasonable; holding current safe trajectory.").
        REMOVE nd.
        RETURN 0.
    }

    aoso_log_info("EJECTION", "Safe capture PE-adjust dv=" + ROUND(nd:PROGRADE, 1) +
        " m/s, PE " + ROUND(PERIAPSIS, 0) + " -> " + ROUND(final_pe, 0) +
        "m (floor " + ROUND(safe_floor, 0) + "m).").
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
        LOCAL safe_floor IS aoso_capture_safe_pe_floor(min_pe).
        aoso_log_info("EJECTION", "Capture at " + SHIP:BODY:NAME + ": raising periapsis to " +
            ROUND(min_pe, 0) + "m (now " + ROUND(PERIAPSIS, 0) +
            "m, safe floor " + ROUND(safe_floor, 0) + "m).").

        // If the current conic intersects the body/terrain margin, an
        // apoapsis burn is too late: impact happens first. Repair PE with a
        // near-term node whether the conic is hyperbolic or technically bound.
        IF aoso_orbit_is_hyperbolic() OR PERIAPSIS < safe_floor {
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
            LOCAL e_now IS SHIP:ORBIT:ECCENTRICITY.
            IF e_now < 0.18 {
                IF NOT aoso_orbit_is_hyperbolic() {
                    LOCAL etas_p IS aoso_orbit_equatorial_node_etas(SHIP).
                    LOCAL v_node IS 100000.
                    IF etas_p:LENGTH > 0 {
                        LOCAL v_vec_p IS aoso_orbit_velocity_at(SHIP, TIME:SECONDS + etas_p[0]).
                        SET v_node TO v_vec_p:MAG.
                    }
                    LOCAL dv_pl IS aoso_planechange_dv_for_angle(polar_err, v_node).
                    IF dv_pl < v_node * 0.4 {
                        aoso_log_info("EJECTION", "Polar capture at " + SHIP:BODY:NAME + ": plane-changing at the slow AN/DN (inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " e=" + ROUND(e_now, 2) + ").").
                        RETURN aoso_planechange_add_node_for_inclination(aoso_config_get("TOUR_POLAR_INCLINATION", 90), polar_tol).
                    }
                }
            }
            aoso_log_info("EJECTION", "Polar capture deferred at " + SHIP:BODY:NAME + " - circularize/bind first (e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 2) + "). A 230 m/s plane-change at v=180 unbound Minmus.").
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
