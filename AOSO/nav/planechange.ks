// AOSO/nav/planechange.ks
// Inclination-matching maneuver. Builds a normal-only node at a relative
// AN/DN crossing. Sign is chosen by adding a trial NODE and reading
// nd:ORBIT inclination+LAN - not VCRS(r,v) - because kOS NODE:NORMAL
// follows KSP's v cross r convention, the opposite of VCRS(r,v). Acacius's
// Minmus 6 deg burn used the VCRS sign and opened the plane to 12 deg.

FUNCTION aoso_planechange_dv_for_angle {
    PARAMETER angle_deg.
    PARAMETER speed_ms.
    RETURN 2 * speed_ms * SIN(angle_deg / 2).
}

FUNCTION aoso_planechange_merge_etas {
    PARAMETER etas.
    PARAMETER extra.
    LOCAL ei IS 0.
    UNTIL ei >= extra:LENGTH {
        LOCAL cand IS extra[ei].
        LOCAL dup IS FALSE.
        LOCAL ji IS 0.
        UNTIL ji >= etas:LENGTH {
            IF ABS(etas[ji] - cand) < 40 { SET dup TO TRUE. }
            SET ji TO ji + 1.
        }
        IF NOT dup {
            IF cand > 20 { etas:ADD(cand). }
        }
        SET ei TO ei + 1.
    }
    RETURN etas.
}

// Set nd:NORMAL so the predicted orbit is closer to target's plane.
// Used both for a dedicated plane-change node and to seed a Hohmann
// transfer with the leftover inclination.
FUNCTION aoso_planechange_apply_to_node {
    PARAMETER nd.
    PARAMETER target_orbitable.
    LOCAL rel IS aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).
    IF rel < 0.15 { RETURN. }

    LOCAL t_ut IS TIME:SECONDS + nd:ETA.
    LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t_ut).
    LOCAL dv_mag IS aoso_planechange_dv_for_angle(rel, v_vec:MAG).
    LOCAL orig IS nd:NORMAL.

    SET nd:NORMAL TO orig + dv_mag.
    WAIT 0.
    LOCAL rel_p IS aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).
    SET nd:NORMAL TO orig - dv_mag.
    WAIT 0.
    LOCAL rel_m IS aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).

    LOCAL picked IS orig.
    LOCAL rel_best IS rel.
    IF rel_p < rel_best {
        SET picked TO orig + dv_mag.
        SET rel_best TO rel_p.
    }
    IF rel_m < rel_best {
        SET picked TO orig - dv_mag.
        SET rel_best TO rel_m.
    }
    SET nd:NORMAL TO picked.
    IF rel_best < rel - 0.05 {
        aoso_log_info("PLANECHANGE", "Node normal " + ROUND(nd:NORMAL, 1) + " m/s, rel_inc " + ROUND(rel, 2) + " -> " + ROUND(rel_best, 2) + " deg.").
    } ELSE {
        SET nd:NORMAL TO orig.
    }
}

FUNCTION aoso_planechange_add_node_for_target {
    PARAMETER target_orbitable.
    PARAMETER node_index IS 0.
    PARAMETER tolerance_deg IS 0.05.

    LOCAL rel_incl IS aoso_orbit_relative_inclination_deg(SHIP, target_orbitable).
    IF rel_incl < tolerance_deg {
        aoso_log_info("PLANECHANGE", "Already co-planar within " + tolerance_deg + " deg; no node added.").
        RETURN 0.
    }

    LOCAL etas IS aoso_orbit_relative_node_etas(SHIP, target_orbitable, 180).
    SET etas TO aoso_planechange_merge_etas(etas, aoso_orbit_lan_node_etas(target_orbitable)).
    IF etas:LENGTH = 0 {
        aoso_log_warn("PLANECHANGE", "No relative node found within two orbits.").
        RETURN 0.
    }

    LOCAL best_eta IS 0.
    LOCAL best_normal IS 0.
    LOCAL best_rel IS rel_incl.
    LOCAL found IS FALSE.
    LOCAL ei IS 0.
    UNTIL ei >= etas:LENGTH {
        LOCAL burn_eta IS etas[ei].
        IF burn_eta > 25 {
            LOCAL t_ut IS TIME:SECONDS + burn_eta.
            LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t_ut).
            LOCAL dv_mag IS aoso_planechange_dv_for_angle(rel_incl, v_vec:MAG).

            LOCAL nd_try IS NODE(t_ut, 0, 0, 0).
            ADD nd_try.
            SET nd_try:NORMAL TO dv_mag.
            WAIT 0.
            LOCAL rel_p IS aoso_orbit_rel_inc_from_orbit(nd_try:ORBIT, target_orbitable).
            SET nd_try:NORMAL TO -dv_mag.
            WAIT 0.
            LOCAL rel_m IS aoso_orbit_rel_inc_from_orbit(nd_try:ORBIT, target_orbitable).
            REMOVE nd_try.

            LOCAL use_n IS dv_mag.
            LOCAL use_rel IS rel_p.
            IF rel_m < rel_p {
                SET use_n TO -dv_mag.
                SET use_rel TO rel_m.
            }
            IF use_rel < best_rel {
                SET best_rel TO use_rel.
                SET best_eta TO burn_eta.
                SET best_normal TO use_n.
                SET found TO TRUE.
            }
        }
        SET ei TO ei + 1.
    }

    IF NOT found {
        aoso_log_warn("PLANECHANGE", "No AN/DN reduced relative inclination (now " + ROUND(rel_incl, 2) + " deg) - will fold into the transfer.").
        RETURN 0.
    }

    LOCAL nd IS NODE(TIME:SECONDS + best_eta, 0, best_normal, 0).
    ADD nd.
    aoso_log_info("PLANECHANGE", "Plane-change node added: dv=" + ROUND(best_normal, 1) +
        " m/s normal, closing " + ROUND(rel_incl, 2) + " -> " + ROUND(best_rel, 2) + " deg relative inclination.").
    RETURN nd.
}

FUNCTION aoso_planechange_add_node_for_inclination {
    PARAMETER target_inc_deg IS 90.
    PARAMETER tolerance_deg IS 15.

    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    IF aoso_orbit_period_s() <= 0 { RETURN 0. }

    LOCAL inc_now IS SHIP:ORBIT:INCLINATION.
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

    LOCAL best_eta IS 0.
    LOCAL best_normal IS 0.
    LOCAL best_err IS err.
    LOCAL best_spd IS 1000000000.
    LOCAL found IS FALSE.
    LOCAL ei IS 0.
    UNTIL ei >= etas:LENGTH {
        LOCAL burn_eta IS etas[ei].
        IF burn_eta > 25 {
            LOCAL t_ut IS TIME:SECONDS + burn_eta.
            LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t_ut).
            LOCAL dv_mag IS aoso_planechange_dv_for_angle(err, v_vec:MAG).

            LOCAL nd_try IS NODE(t_ut, 0, 0, 0).
            ADD nd_try.
            SET nd_try:NORMAL TO dv_mag.
            WAIT 0.
            LOCAL err_p IS ABS(nd_try:ORBIT:INCLINATION - target_inc_deg).
            SET nd_try:NORMAL TO -dv_mag.
            WAIT 0.
            LOCAL err_m IS ABS(nd_try:ORBIT:INCLINATION - target_inc_deg).
            REMOVE nd_try.

            LOCAL use_n IS dv_mag.
            LOCAL use_err IS err_p.
            IF err_m < err_p {
                SET use_n TO -dv_mag.
                SET use_err TO err_m.
            }
            LOCAL better IS FALSE.
            IF NOT found { SET better TO TRUE. }
            IF use_err < best_err - 1 { SET better TO TRUE. }
            IF NOT better {
                IF use_err <= best_err + 2 {
                    IF v_vec:MAG < best_spd - 1 { SET better TO TRUE. }
                }
            }
            IF better {
                SET best_err TO use_err.
                SET best_eta TO burn_eta.
                SET best_normal TO use_n.
                SET best_spd TO v_vec:MAG.
                SET found TO TRUE.
            }
        }
        SET ei TO ei + 1.
    }

    IF NOT found { RETURN 0. }

    LOCAL nd IS NODE(TIME:SECONDS + best_eta, 0, best_normal, 0).
    ADD nd.
    WAIT 0.
    aoso_log_info("PLANECHANGE", "Inclination node added: dv=" + ROUND(best_normal, 1) +
        " m/s normal at v=" + ROUND(best_spd, 1) + " m/s, " + ROUND(inc_now, 1) + " -> pred " +
        ROUND(nd:ORBIT:INCLINATION, 1) + " deg (want " + ROUND(target_inc_deg, 0) + ").").
    RETURN nd.
}
