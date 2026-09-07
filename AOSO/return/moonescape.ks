// AOSO/return/moonescape.ks
// Phase 8 (Return) foundation: patched-conic SOI-escape burn from a moon
// (any body whose :BODY is itself orbited, e.g. Mun/Minmus/Ike) back toward
// its own parent body, aimed at a target periapsis altitude around that
// parent. This is the one-level-down mirror of
// interplanetary/ejection.ks's departure burn: instead of matching a
// heliocentric transfer window between two sun-orbiting peers, the "transfer"
// here is a direct Hohmann-style descent from the moon's own orbital radius
// (around its parent) down to target_periapsis_alt, computed the same way
// nav/hohmann.ks sizes any other apsis change. Reuses every one of
// interplanetary/ejection.ks's burn-point/rotation helpers (they only ever
// operate on SHIP/SHIP:BODY, never on the interplanetary-specific dep/arr
// bodies), so this file only adds the v_infinity calculation that's specific
// to "escape toward my own parent" instead of "escape toward a transfer
// window partner".

// Signed hyperbolic-excess speed (m/s, relative to SHIP:BODY) needed so that,
// once the ship leaves SHIP:BODY's SOI, its resulting orbit around
// SHIP:BODY:BODY matches the speed a direct Hohmann descent from
// SHIP:BODY's own orbital radius down to target_periapsis_alt would have at
// that radius -- i.e. the same vis-viva relation
// interplanetary/transfer.ks's aoso_interplanetary_v_infinity_signed uses,
// with SHIP:BODY standing in for the departure body and target_periapsis_alt
// standing in for the arrival radius. Negative (the usual case, since a
// moon's own circular speed exceeds the speed needed on a descending
// ellipse) means the departure asymptote points against SHIP:BODY's orbital
// motion around its parent.
FUNCTION aoso_moonescape_v_infinity_signed {
    PARAMETER target_periapsis_alt.

    LOCAL moon IS SHIP:BODY.
    LOCAL parent IS moon:BODY.
    LOCAL mu IS parent:MU.
    LOCAL r1 IS moon:ORBIT:SEMIMAJORAXIS.
    LOCAL r2 IS parent:RADIUS + target_periapsis_alt.
    LOCAL sma_t IS (r1 + r2) / 2.

    LOCAL v_circ IS SQRT(mu / r1).
    LOCAL v_transfer IS SQRT(MAX(0, mu * (2 / r1 - 1 / sma_t))).
    RETURN v_transfer - v_circ.
}

// TRUE if SHIP:BODY has a distinct parent to escape toward (FALSE for the
// edge case of a body directly orbiting the star, or any body that reports
// itself as its own parent).
FUNCTION aoso_moonescape_available {
    RETURN SHIP:BODY:BODY:NAME <> SHIP:BODY:NAME.
}

// Adds a prograde/retrograde escape node on SHIP's current orbit around
// SHIP:BODY, sized and placed (via interplanetary/ejection.ks's shared
// geometry helpers) to leave SHIP:BODY's SOI aimed at target_periapsis_alt
// around SHIP:BODY:BODY. Returns 0 if no distinct parent exists to escape
// toward, or if no valid burn point is found within one orbit.
FUNCTION aoso_moonescape_add_escape_node {
    PARAMETER target_periapsis_alt.

    IF NOT aoso_moonescape_available() {
        IF DEFINED aoso_log_error {
            aoso_log_error("MOONESCAPE", SHIP:BODY:NAME + " has no distinct parent body to escape toward.").
        }
        RETURN 0.
    }

    LOCAL moon IS SHIP:BODY.
    LOCAL v_inf_signed IS aoso_moonescape_v_infinity_signed(target_periapsis_alt).
    LOCAL v_inf_mag IS ABS(v_inf_signed).
    LOCAL mu IS moon:MU.
    LOCAL r_peri IS moon:RADIUS + PERIAPSIS.

    LOCAL moon_prograde_dir IS aoso_orbit_velocity_at(moon, TIME:SECONDS):NORMALIZED.
    LOCAL target_dir IS moon_prograde_dir * (CHOOSE 1 IF v_inf_signed >= 0 ELSE -1).

    LOCAL e IS aoso_ejection_eccentricity(v_inf_mag, r_peri, mu).
    LOCAL nu_inf_deg IS aoso_ejection_asymptote_true_anomaly_deg(e).
    LOCAL na IS aoso_orbit_normal_now(SHIP).
    LOCAL periapsis_dir IS aoso_ejection_rotate_vector(target_dir, na, -nu_inf_deg).

    LOCAL burn_eta IS aoso_ejection_burn_eta_for_direction(periapsis_dir).
    IF burn_eta < 0 {
        IF DEFINED aoso_log_warn {
            aoso_log_warn("MOONESCAPE", "No valid escape burn point found within one orbit.").
        }
        RETURN 0.
    }

    LOCAL v_peri IS aoso_ejection_dv_for_v_infinity(v_inf_mag, r_peri, mu).
    LOCAL v_now IS aoso_orbit_speed_at_radius(SHIP, r_peri).
    LOCAL dv IS v_peri - v_now.

    LOCAL nd IS NODE(TIME:SECONDS + burn_eta, 0, 0, dv).
    ADD nd.
    IF DEFINED aoso_log_info {
        aoso_log_info("MOONESCAPE", "Escape node added: dv=" + ROUND(dv, 1) + " m/s, leaving " +
            moon:NAME + " for " + moon:BODY:NAME + " in " + ROUND(burn_eta, 0) + "s.").
    }
    RETURN nd.
}
