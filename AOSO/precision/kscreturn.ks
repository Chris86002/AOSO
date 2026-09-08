// AOSO/precision/kscreturn.ks
// Phase 9 (Precision KSC return) core: once return/return.ks has the ship
// safely orbiting HOME_BODY, this drives the final piece -- landing close
// to a specific site (KSC by default; core/config.ks's KSC_LAT/KSC_LNG) --
// instead of just "somewhere on the home body". Built on core/state.ks as
// its own machine (AOSO_PRECISION), the same pattern every other
// autonomous subsystem in this repo uses.
//
// Approach: precision/targeting.ks's ballistic ground-track predictor is
// exact only outside the atmosphere (see that file's header), so this
// module only ever tries to steer the *entry-interface* ground track close
// to the target, using two levers that are both cheap, reusable burns:
//   - a plane-align burn (nav/planechange.ks's dv formula, retargeted at
//     the body's equatorial plane instead of another orbitable) so the
//     ground track actually passes near the target latitude at all -- in
//     scope for near-equatorial targets like the stock KSC, same
//     "assumes near-circular orbits" style simplification
//     nav/rendezvous.ks documents for its own scope.
//   - choosing *which* apoapsis pass to burn the deorbit node at: delaying
//     the same deorbit burn by whole orbits doesn't change its dv or its
//     physical burn point (an unperturbed ellipse's apoapsis is a fixed
//     point in space), it only changes how far HOME_BODY has rotated
//     underneath by the time the resulting ellipse reaches the atmosphere
//     interface -- so precision/targeting.ks's predictor (which honors
//     planned nodes automatically, per kOS's own POSITIONAT docs) can just
//     be asked to score each candidate delay directly instead of this file
//     re-deriving any ground-track geometry itself.
// Once the ship actually reaches the atmosphere interface, this hands off
// to landing/descent.ks (and, on atmospheric bodies, landing/parachute.ks)
// for the powered/aerodynamic remainder -- the same handoff point
// return/return.ks documents for the exo-atmospheric portion of a return.

GLOBAL AOSO_PRECISION IS aoso_state_new_machine().

// Angle (deg, 0-90) between the ship's orbital plane and HOME_BODY's
// equator: 0 for either a prograde or retrograde equatorial orbit, 90 for a
// polar one. SHIP:ORBIT:INCLINATION alone can't distinguish "equatorial" at
// 0 deg from "equatorial" at 180 (retrograde), hence the fold below.
FUNCTION aoso_kscreturn_equatorial_offset_deg {
    LOCAL incl IS SHIP:ORBIT:INCLINATION.
    RETURN MIN(incl, 180 - incl).
}

FUNCTION aoso_kscreturn_needs_plane_align {
    RETURN aoso_kscreturn_equatorial_offset_deg() > aoso_config_get("PRECISION_INCLINATION_TOLERANCE_DEG", 1).
}

// Finds up to two upcoming times (seconds from now) at which SHIP crosses
// HOME_BODY's equatorial plane, mirroring nav/orbit.ks's
// aoso_orbit_relative_node_etas bisection exactly, except the reference
// plane's normal here is fixed (the body's own rotation axis,
// BODY:ANGULARVEL) instead of being derived from a second orbitable's
// live position/velocity.
FUNCTION aoso_kscreturn_equatorial_node_etas {
    PARAMETER samples IS 360.

    LOCAL nb IS SHIP:BODY:ANGULARVEL:NORMALIZED.
    LOCAL period IS SHIP:ORBIT:PERIOD.
    LOCAL now IS TIME:SECONDS.
    LOCAL dt IS period / samples.

    LOCAL etas IS LIST().
    LOCAL prev_t IS 0.
    LOCAL prev_val IS VDOT(aoso_orbit_position_at(SHIP, now), nb).

    LOCAL i IS 1.
    UNTIL i > samples OR etas:LENGTH >= 2 {
        LOCAL t IS i * dt.
        LOCAL val IS VDOT(aoso_orbit_position_at(SHIP, now + t), nb).

        IF (val >= 0 AND prev_val < 0) OR (val < 0 AND prev_val >= 0) {
            LOCAL lo IS prev_t.
            LOCAL hi IS t.
            LOCAL lo_val IS prev_val.
            LOCAL iter IS 0.
            UNTIL iter >= 20 {
                LOCAL mid IS (lo + hi) / 2.
                LOCAL mid_val IS VDOT(aoso_orbit_position_at(SHIP, now + mid), nb).
                IF (mid_val >= 0 AND lo_val < 0) OR (mid_val < 0 AND lo_val >= 0) {
                    SET hi TO mid.
                } ELSE {
                    SET lo TO mid.
                    SET lo_val TO mid_val.
                }
                SET iter TO iter + 1.
            }
            etas:ADD((lo + hi) / 2).
        }

        SET prev_t TO t.
        SET prev_val TO val.
        SET i TO i + 1.
    }
    RETURN etas.
}

// Adds a normal-direction node at the chosen equatorial crossing that
// rotates the ship's plane toward HOME_BODY's equator (prograde-equatorial,
// i.e. inclination -> 0 -- the sign resolution below always prefers that
// side, the same deterministic simplification nav/planechange.ks documents
// for its own numeric sign resolution). Returns 0 if already within
// tolerance_deg, or if no equatorial crossing was found within one orbit.
FUNCTION aoso_kscreturn_add_plane_align_node {
    PARAMETER node_index IS 0.
    PARAMETER tolerance_deg IS 0.
    IF tolerance_deg <= 0 { SET tolerance_deg TO aoso_config_get("PRECISION_INCLINATION_TOLERANCE_DEG", 1). }

    LOCAL offset IS aoso_kscreturn_equatorial_offset_deg().
    IF offset <= tolerance_deg {
        aoso_log_info("KSCRETURN", "Already within " + tolerance_deg + " deg of equatorial; no plane-align node added.").
        RETURN 0.
    }

    LOCAL etas IS aoso_kscreturn_equatorial_node_etas().
    IF etas:LENGTH = 0 OR node_index >= etas:LENGTH {
        aoso_log_warn("KSCRETURN", "No equatorial crossing found within one orbit.").
        RETURN 0.
    }

    LOCAL burn_eta IS etas[node_index].
    LOCAL t IS TIME:SECONDS + burn_eta.
    LOCAL r_vec IS aoso_orbit_position_at(SHIP, t).
    LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t).
    LOCAL na IS VCRS(r_vec, v_vec):NORMALIZED.
    LOCAL nb IS SHIP:BODY:ANGULARVEL:NORMALIZED.

    LOCAL dv_mag IS aoso_planechange_dv_for_angle(offset, v_vec:MAG).

    LOCAL na_plus IS VCRS(r_vec, v_vec + na * dv_mag):NORMALIZED.
    LOCAL na_minus IS VCRS(r_vec, v_vec - na * dv_mag):NORMALIZED.
    LOCAL sign IS 1.
    IF VANG(na_minus, nb) < VANG(na_plus, nb) { SET sign TO -1. }

    LOCAL nd IS NODE(t, 0, sign * dv_mag, 0).
    ADD nd.
    aoso_log_info("KSCRETURN", "Plane-align node added: dv=" + ROUND(sign * dv_mag, 1) +
        " m/s normal, closing " + ROUND(offset, 2) + " deg to equatorial.").
    RETURN nd.
}

// Predicted ground-track miss distance (m) from target_geo at the
// atmosphere interface, for a hypothetical deorbit burn delayed by
// delay_orbits whole orbits (0 = the very next apoapsis). Adds the
// candidate node just long enough for precision/targeting.ks to read its
// post-burn ground track, then removes it -- the caller re-adds whichever
// delay actually wins. Returns -1 if no ballistic crossing was found for
// this candidate.
FUNCTION aoso_kscreturn_evaluate_deorbit_delay {
    PARAMETER delay_orbits.
    PARAMETER target_pe_alt.
    PARAMETER target_geo.

    LOCAL dv IS aoso_hohmann_dv_at_apoapsis_for_periapsis(target_pe_alt).
    LOCAL burn_t IS TIME:SECONDS + ETA:APOAPSIS + delay_orbits * SHIP:ORBIT:PERIOD.
    LOCAL nd IS NODE(burn_t, 0, 0, dv).
    ADD nd.

    LOCAL horizon IS nd:ORBIT:ETA:PERIAPSIS.
    LOCAL miss IS aoso_targeting_predicted_miss_m(aoso_targeting_interface_alt(), horizon, target_geo).

    REMOVE nd.
    RETURN miss.
}

// Adds whichever deorbit node (among delay_orbits = 0..
// PRECISION_MAX_DEORBIT_DELAY_ORBITS) is predicted to bring the ship's
// entry-interface ground track closest to the target site, falling back to
// landing/deorbit.ks's plain immediate burn if the periapsis is already low
// enough (nothing to target) or if no candidate produced a valid
// prediction (still deorbits -- just without a distance guarantee).
FUNCTION aoso_kscreturn_add_best_deorbit_node {
    LOCAL target_pe_alt IS aoso_deorbit_target_periapsis_alt().

    IF PERIAPSIS <= target_pe_alt {
        aoso_log_info("KSCRETURN", "Periapsis already at/below target; delegating to landing/deorbit.ks.").
        RETURN aoso_deorbit_add_node(target_pe_alt, TRUE).
    }

    LOCAL target_geo IS aoso_targeting_site().
    LOCAL max_delay IS aoso_config_get("PRECISION_MAX_DEORBIT_DELAY_ORBITS", 3).

    LOCAL best_delay IS 0.
    LOCAL best_miss IS -1.
    LOCAL k IS 0.
    UNTIL k > max_delay {
        LOCAL miss IS aoso_kscreturn_evaluate_deorbit_delay(k, target_pe_alt, target_geo).
        IF miss >= 0 AND (best_miss < 0 OR miss < best_miss) {
            SET best_miss TO miss.
            SET best_delay TO k.
        }
        SET k TO k + 1.
    }

    LOCAL dv IS aoso_hohmann_dv_at_apoapsis_for_periapsis(target_pe_alt).
    LOCAL burn_t IS TIME:SECONDS + ETA:APOAPSIS + best_delay * SHIP:ORBIT:PERIOD.
    LOCAL nd IS NODE(burn_t, 0, 0, dv).
    ADD nd.

    IF best_miss >= 0 {
        aoso_log_info("KSCRETURN", "Deorbit node added: delay=" + best_delay + " orbit(s), predicted entry-interface miss=" +
            ROUND(best_miss, 0) + "m.").
    } ELSE {
        aoso_log_warn("KSCRETURN", "No ballistic entry-interface crossing found for any candidate; deorbiting immediately without a distance prediction.").
    }
    RETURN nd.
}

FUNCTION aoso_kscreturn_on_abort {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_state_transition(AOSO_PRECISION, "ABORTED").
}

FUNCTION aoso_kscreturn_plan_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.

    IF SHIP:STATUS <> "ORBITING" {
        aoso_log_error("KSCRETURN", "Ship must be in a stable orbit around " + SHIP:BODY:NAME + " before precision return can plan.").
        aoso_state_abort(AOSO_PRECISION).
        RETURN.
    }

    IF aoso_kscreturn_needs_plane_align() {
        aoso_state_transition(AOSO_PRECISION, "ALIGN").
    } ELSE {
        aoso_state_transition(AOSO_PRECISION, "DEORBIT").
    }
}

FUNCTION aoso_kscreturn_align_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    LOCAL nd IS aoso_kscreturn_add_plane_align_node().
    IF nd = 0 {
        aoso_state_transition(AOSO_PRECISION, "DEORBIT").
    }
}

FUNCTION aoso_kscreturn_align_execute {
    PARAMETER data.
    IF aoso_maneuver_execute_next() {
        aoso_state_transition(AOSO_PRECISION, "DEORBIT").
    }
}

FUNCTION aoso_kscreturn_deorbit_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.

    // Mirrors landing/deorbit.ks's own guard: periapsis already at/below
    // target means there is nothing to burn (a success, not a failure), so
    // this is checked before add_best_deorbit_node() rather than treating
    // its "0 = no node" and "0 = couldn't find a route" cases the same way.
    IF PERIAPSIS <= aoso_deorbit_target_periapsis_alt() {
        aoso_state_transition(AOSO_PRECISION, "HANDOFF").
        RETURN.
    }

    LOCAL nd IS aoso_kscreturn_add_best_deorbit_node().
    IF nd = 0 {
        aoso_state_abort(AOSO_PRECISION).
    }
}

FUNCTION aoso_kscreturn_deorbit_execute {
    PARAMETER data.
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_PRECISION).
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        aoso_state_transition(AOSO_PRECISION, "HANDOFF").
    }
}

// Hands off to landing/descent.ks as soon as the deorbit burn is done,
// rather than waiting to physically reach the atmosphere interface first --
// landing/descent.ks's own FREEFALL state already gates its suicide-burn
// trigger on radar altitude every tick, so it is safe to start immediately,
// and waiting would leave an airless-body landing (whose deorbit periapsis
// targets sea level directly, see landing/deorbit.ks) with no guidance
// running until right at impact. The predicted miss is logged here instead
// of measured, since the ship is still coasting above the interface at
// this point and precision/targeting.ks's ballistic prediction is exact
// there (see that file's header).
FUNCTION aoso_kscreturn_handoff_entry {
    PARAMETER data.
    LOCAL miss IS aoso_targeting_predicted_miss_m(aoso_targeting_interface_alt(), 0, aoso_targeting_site()).
    IF miss < 0 {
        aoso_log_warn("KSCRETURN", "Could not predict an entry-interface miss distance for this trajectory.").
    } ELSE IF miss <= aoso_config_get("PRECISION_LANDING_RADIUS", 150) {
        aoso_log_info("KSCRETURN", "Predicted entry-interface miss=" + ROUND(miss, 0) + "m -- within PRECISION_LANDING_RADIUS.").
    } ELSE {
        aoso_log_warn("KSCRETURN", "Predicted entry-interface miss=" + ROUND(miss, 0) + "m -- outside PRECISION_LANDING_RADIUS.").
    }
    aoso_descent_start().
    aoso_state_transition(AOSO_PRECISION, "DONE").
}

FUNCTION aoso_kscreturn_done_entry {
    PARAMETER data.
    aoso_log_info("KSCRETURN", "Precision return handed off to landing/descent.ks.").
}

FUNCTION aoso_kscreturn_aborted_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_log_error("KSCRETURN", "Precision KSC return aborted.").
}

FUNCTION aoso_kscreturn_define_states {
    aoso_state_define(AOSO_PRECISION, "PLAN", aoso_kscreturn_plan_entry@, 0, 0, 0, 0, aoso_kscreturn_on_abort@).
    aoso_state_define(AOSO_PRECISION, "ALIGN", aoso_kscreturn_align_entry@, aoso_kscreturn_align_execute@, 0, 0, 0, aoso_kscreturn_on_abort@).
    aoso_state_define(AOSO_PRECISION, "DEORBIT", aoso_kscreturn_deorbit_entry@, aoso_kscreturn_deorbit_execute@, 0, 0, 0, aoso_kscreturn_on_abort@).
    aoso_state_define(AOSO_PRECISION, "HANDOFF", aoso_kscreturn_handoff_entry@, 0, 0).
    aoso_state_define(AOSO_PRECISION, "DONE", aoso_kscreturn_done_entry@, 0, 0).
    aoso_state_define(AOSO_PRECISION, "ABORTED", aoso_kscreturn_aborted_entry@, 0, 0).
}

// Entry point: call once the ship is orbiting HOME_BODY (e.g. after
// return/return.ks's aoso_return_is_done() is TRUE) to arm precision
// return, then drive it every tick with aoso_kscreturn_update() (directly,
// or via aoso_kscreturn_register_task()).
FUNCTION aoso_kscreturn_start {
    aoso_kscreturn_define_states().
    SET AOSO_PRECISION["data"] TO LEXICON().
    aoso_state_transition(AOSO_PRECISION, "PLAN").
}

FUNCTION aoso_kscreturn_update {
    aoso_state_update(AOSO_PRECISION).
}

FUNCTION aoso_kscreturn_register_task {
    PARAMETER interval_s IS 0.1.
    aoso_sched_add("precision_return", interval_s, aoso_kscreturn_update@).
}

FUNCTION aoso_kscreturn_is_done {
    RETURN AOSO_PRECISION["current"] = "DONE".
}

FUNCTION aoso_kscreturn_is_aborted {
    RETURN AOSO_PRECISION["current"] = "ABORTED".
}
