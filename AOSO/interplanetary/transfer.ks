// AOSO/interplanetary/transfer.ks
// Heliocentric transfer-window math between two bodies that share the same
// parent (i.e. both orbit the same star directly, e.g. Kerbin -> Duna),
// generalizing nav/rendezvous.ks's phase-angle/wait-time approach from
// vessel-vs-target to body-vs-body. Assumes both bodies' orbits are
// near-circular and mutually coplanar for the transfer-time/dv estimates --
// the same simplification rendezvous.ks makes for target-radius/transfer
// time, and accurate enough for stock-system patched-conic planning. Full
// eccentric/inclined Lambert solving is out of scope here (see
// core/addons.ks's note on why Astrogator isn't driven directly). Builds
// only on nav/orbit.ks helpers -- no new stock suffixes.

// Sun-relative ("heliocentric") position of a body right now. Reuses
// nav/orbit.ks's parent-relative helper; valid for dep_body/arr_body only
// when both orbit the same star directly (checked by callers via
// aoso_interplanetary_share_parent).
FUNCTION aoso_interplanetary_heliocentric_position {
    PARAMETER body_ref.
    RETURN aoso_interplanetary_heliocentric_position_at(body_ref, TIME:SECONDS).
}

// Same geometry at an arbitrary universal time. This is the planner-facing
// equivalent of an ephemeris query: stock KSP's own Kepler propagation is
// authoritative, so AOSO does not carry a separate SPICE/n-body model.
FUNCTION aoso_interplanetary_heliocentric_position_at {
    PARAMETER body_ref.
    PARAMETER at_ut.
    RETURN aoso_orbit_position_at(body_ref, at_ut).
}

FUNCTION aoso_interplanetary_share_parent {
    PARAMETER dep_body.
    PARAMETER arr_body.
    RETURN dep_body:BODY:NAME = arr_body:BODY:NAME.
}

// Semi-major axis (m) of the Hohmann transfer ellipse between dep_body's and
// arr_body's (assumed near-circular) heliocentric orbits.
FUNCTION aoso_interplanetary_transfer_sma {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL r1 IS dep_body:ORBIT:SEMIMAJORAXIS.
    LOCAL r2 IS arr_body:ORBIT:SEMIMAJORAXIS.
    RETURN (r1 + r2) / 2.
}

// One-way transfer time (s): half the transfer ellipse's period.
FUNCTION aoso_interplanetary_transfer_time_s {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL mu IS dep_body:BODY:MU.
    LOCAL sma_t IS aoso_interplanetary_transfer_sma(dep_body, arr_body).
    RETURN CONSTANT:PI * SQRT(sma_t ^ 3 / mu).
}

// Signed heliocentric delta-v (m/s) needed at departure: positive means
// speed up (prograde, for an outer target), negative means slow down
// (retrograde, for an inner target). This is dep_body's own required
// velocity change, i.e. the hyperbolic-excess speed the ship must add on
// top of dep_body's orbital velocity once it leaves dep_body's SOI.
FUNCTION aoso_interplanetary_v_infinity_signed {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL mu IS dep_body:BODY:MU.
    LOCAL r1 IS dep_body:ORBIT:SEMIMAJORAXIS.
    LOCAL sma_t IS aoso_interplanetary_transfer_sma(dep_body, arr_body).
    LOCAL v_circ IS SQRT(mu / r1).
    LOCAL v_transfer IS SQRT(MAX(0, mu * (2 / r1 - 1 / sma_t))).
    RETURN v_transfer - v_circ.
}

// Signed phase angle (deg) from dep_body to arr_body around their shared
// parent, positive when arr_body is ahead of dep_body in the direction of
// dep_body's orbital motion. Mirrors nav/rendezvous.ks's
// aoso_rendezvous_phase_angle_deg, generalized to body-vs-body.
FUNCTION aoso_interplanetary_phase_angle_deg {
    PARAMETER dep_body.
    PARAMETER arr_body.
    RETURN aoso_interplanetary_phase_angle_deg_at(dep_body, arr_body, TIME:SECONDS).
}

FUNCTION aoso_interplanetary_phase_angle_deg_at {
    PARAMETER dep_body.
    PARAMETER arr_body.
    PARAMETER at_ut.
    LOCAL pos_dep IS aoso_interplanetary_heliocentric_position_at(dep_body, at_ut).
    LOCAL pos_arr IS aoso_interplanetary_heliocentric_position_at(arr_body, at_ut).
    LOCAL ang IS VANG(pos_dep, pos_arr).
    LOCAL na IS aoso_orbit_normal_at(dep_body, at_ut).
    IF VDOT(VCRS(pos_dep, pos_arr), na) < 0 { SET ang TO -ang. }
    RETURN ang.
}

// Phase angle (deg) arr_body must lead dep_body by, right now, for a
// departure today to arrive where arr_body will have coasted to.
FUNCTION aoso_interplanetary_required_phase_angle_deg {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL transfer_time IS aoso_interplanetary_transfer_time_s(dep_body, arr_body).
    LOCAL arr_travel_deg IS 360 * transfer_time / arr_body:ORBIT:PERIOD.
    RETURN 180 - arr_travel_deg.
}

// Seconds to wait until the current dep_body/arr_body phase angle reaches
// the required transfer-window phase angle. Returns -1 if the two bodies'
// periods are equal (phase angle never changes).
FUNCTION aoso_interplanetary_wait_time_to_window_s {
    PARAMETER dep_body.
    PARAMETER arr_body.
    RETURN aoso_interplanetary_wait_time_to_window_s_at(dep_body, arr_body, TIME:SECONDS).
}

FUNCTION aoso_interplanetary_synodic_s {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL dep_rate IS 1 / dep_body:ORBIT:PERIOD.
    LOCAL arr_rate IS 1 / arr_body:ORBIT:PERIOD.
    LOCAL rel IS ABS(dep_rate - arr_rate).
    IF rel <= 0 { RETURN 0. }
    RETURN 1 / rel.
}

FUNCTION aoso_interplanetary_wait_time_to_window_s_at {
    PARAMETER dep_body.
    PARAMETER arr_body.
    PARAMETER at_ut.
    LOCAL current_phase IS aoso_interplanetary_phase_angle_deg_at(dep_body, arr_body, at_ut).
    LOCAL required_phase IS aoso_interplanetary_required_phase_angle_deg(dep_body, arr_body).

    LOCAL dep_rate IS 360 / dep_body:ORBIT:PERIOD.
    LOCAL arr_rate IS 360 / arr_body:ORBIT:PERIOD.
    LOCAL relative_rate IS dep_rate - arr_rate.
    IF relative_rate = 0 { RETURN -1. }

    LOCAL wait_s IS -(current_phase - required_phase) / relative_rate.
    LOCAL syn_s IS 360 / ABS(relative_rate).
    UNTIL wait_s >= 0 {
        SET wait_s TO wait_s + syn_s.
    }
    UNTIL wait_s < syn_s {
        SET wait_s TO wait_s - syn_s.
    }
    RETURN wait_s.
}
