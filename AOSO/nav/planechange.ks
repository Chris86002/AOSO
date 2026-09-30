// AOSO/nav/planechange.ks
// Inclination-matching maneuver. Builds a constant-speed turn at a relative
// AN/DN crossing. Sign is chosen by adding a trial NODE and reading
// nd:ORBIT inclination+LAN - not VCRS(r,v) - because kOS NODE:NORMAL
// follows KSP's v cross r convention, the opposite of VCRS(r,v). Acacius's
// Minmus 6 deg burn used the VCRS sign and opened the plane to 12 deg.

FUNCTION aoso_planechange_dv_for_angle {
    PARAMETER angle_deg.
    PARAMETER speed_ms.
    RETURN 2 * speed_ms * SIN(angle_deg / 2).
}

// Relative inclination is a transfer objective only in one central-body
// frame. A Minmus parking orbit cannot match Kerbin's solar orbit.
FUNCTION aoso_planechange_same_primary {
    PARAMETER primary_a.
    PARAMETER primary_b.
    RETURN primary_a = primary_b.
}

FUNCTION aoso_planechange_turn_components {
    PARAMETER angle_deg.
    PARAMETER speed_ms.
    RETURN LEXICON("normal", speed_ms * SIN(angle_deg),
        "prograde", speed_ms * (COS(angle_deg) - 1)).
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
    IF NOT aoso_planechange_same_primary(SHIP:BODY:NAME, target_orbitable:BODY:NAME) {
        aoso_log_warn("PLANECHANGE", "Refusing transfer plane match across different central bodies.").
        RETURN.
    }
    LOCAL rel IS aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).
    IF rel < 0.15 { RETURN. }

    LOCAL t_ut IS TIME:SECONDS + nd:ETA.
    LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t_ut).
    LOCAL dv_mag IS aoso_planechange_dv_for_angle(rel, v_vec:MAG).
    LOCAL orig IS nd:NORMAL.

    SET nd:NORMAL TO orig + dv_mag.
    aoso_yield().
    LOCAL rel_p IS aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).
    SET nd:NORMAL TO orig - dv_mag.
    aoso_yield().
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

    IF NOT aoso_planechange_same_primary(SHIP:BODY:NAME, target_orbitable:BODY:NAME) {
        aoso_log_warn("PLANECHANGE", "Refusing dedicated plane match across different central bodies.").
        RETURN 0.
    }
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    LOCAL pe_min IS aoso_config_get("DESCENT_SAFE_PE_ALT", 8000).
    IF SHIP:BODY:ATM:EXISTS {
        SET pe_min TO MAX(pe_min, SHIP:BODY:ATM:HEIGHT + 5000).
    }

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

    LOCAL best_ut IS 0.
    LOCAL best_normal IS 0.
    LOCAL best_prograde IS 0.
    LOCAL best_rel IS rel_incl.
    LOCAL found IS FALSE.
    LOCAL ei IS 0.
    UNTIL ei >= etas:LENGTH {
        LOCAL burn_eta IS etas[ei].
        IF burn_eta > 25 {
            LOCAL t_ut IS TIME:SECONDS + burn_eta.
            LOCAL v_vec IS aoso_orbit_velocity_at(SHIP, t_ut).
            LOCAL turn IS aoso_planechange_turn_components(rel_incl, v_vec:MAG).
            LOCAL dv_mag IS turn["normal"].
            LOCAL dv_pro IS turn["prograde"].

            LOCAL nd_try IS NODE(t_ut, 0, 0, dv_pro).
            ADD nd_try.
            SET nd_try:NORMAL TO dv_mag.
            aoso_yield().
            LOCAL rel_p IS aoso_orbit_rel_inc_from_orbit(nd_try:ORBIT, target_orbitable).
            LOCAL safe_p IS FALSE.
            IF nd_try:ORBIT:ECCENTRICITY < 1 {
                IF nd_try:ORBIT:PERIAPSIS >= pe_min {
                    IF nd_try:ORBIT:APOAPSIS + SHIP:BODY:RADIUS < SHIP:BODY:SOIRADIUS {
                        SET safe_p TO TRUE.
                    }
                }
            }
            SET nd_try:NORMAL TO -dv_mag.
            aoso_yield().
            LOCAL rel_m IS aoso_orbit_rel_inc_from_orbit(nd_try:ORBIT, target_orbitable).
            LOCAL safe_m IS FALSE.
            IF nd_try:ORBIT:ECCENTRICITY < 1 {
                IF nd_try:ORBIT:PERIAPSIS >= pe_min {
                    IF nd_try:ORBIT:APOAPSIS + SHIP:BODY:RADIUS < SHIP:BODY:SOIRADIUS {
                        SET safe_m TO TRUE.
                    }
                }
            }
            REMOVE nd_try.

            LOCAL use_n IS 0.
            LOCAL use_rel IS best_rel.
            IF safe_p {
                IF rel_p < use_rel {
                    SET use_n TO dv_mag.
                    SET use_rel TO rel_p.
                }
            }
            IF safe_m {
                IF rel_m < use_rel {
                    SET use_n TO -dv_mag.
                    SET use_rel TO rel_m.
                }
            }
            IF use_rel < best_rel {
                SET best_rel TO use_rel.
                SET best_ut TO t_ut.
                SET best_normal TO use_n.
                SET best_prograde TO dv_pro.
                SET found TO TRUE.
            }
        }
        SET ei TO ei + 1.
    }

    IF NOT found {
        aoso_log_warn("PLANECHANGE", "No safe bound AN/DN reduced relative inclination (now " + ROUND(rel_incl, 2) + " deg) - deferring to transfer planning.").
        RETURN 0.
    }

    IF best_ut <= TIME:SECONDS + 25 { RETURN 0. }
    LOCAL nd IS NODE(best_ut, 0, best_normal, best_prograde).
    ADD nd.
    aoso_yield().
    LOCAL final_safe IS FALSE.
    IF nd:ORBIT:ECCENTRICITY < 1 {
        IF nd:ORBIT:PERIAPSIS >= pe_min {
            IF nd:ORBIT:APOAPSIS + SHIP:BODY:RADIUS < SHIP:BODY:SOIRADIUS {
                IF aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable) < rel_incl {
                    SET final_safe TO TRUE.
                }
            }
        }
    }
    IF NOT final_safe {
        REMOVE nd.
        aoso_log_warn("PLANECHANGE", "Final plane-match node failed bound-orbit verification; deferring to transfer planning.").
        RETURN 0.
    }
    aoso_log_info("PLANECHANGE", "Plane-change node added: dv=" + ROUND(best_normal, 1) +
        " m/s normal, prograde=" + ROUND(best_prograde, 1) +
        " m/s, closing " + ROUND(rel_incl, 2) + " -> " + ROUND(best_rel, 2) + " deg relative inclination; bound orbit verified.").
    RETURN nd.
}

// kOS NODE:NORMAL is KSP's v×r, the opposite of VCRS(r,v). Returns +1 or -1
// for the NODE:NORMAL sign of a constant-speed inclination burn (normal
// magnitude dv_n, prograde dv_pro). Used when patched conics do not move
// between the two trial signs — the Acacius Minmus burn that trusted the
// first +NORMAL candidate and never left 10 deg.
FUNCTION aoso_planechange_normal_sign {
    PARAMETER burn_eta.
    PARAMETER dv_n.
    PARAMETER dv_pro.
    PARAMETER target_inc_deg.

    LOCAL t_ut IS TIME:SECONDS + burn_eta.
    LOCAL pos_b IS aoso_orbit_position_at(SHIP, t_ut).
    LOCAL vel_b IS aoso_orbit_velocity_at(SHIP, t_ut).
    LOCAL h_now IS VCRS(pos_b, vel_b).
    IF h_now:MAG < 1 { RETURN 1. }
    IF vel_b:MAG < 0.5 { RETURN 1. }
    LOCAL north_u IS aoso_orbit_north(SHIP:BODY).
    LOCAL h_north IS VDOT(h_now, north_u).
    LOCAL h_eq IS h_now - (north_u * h_north).
    LOCAL h_eq_hat IS h_eq.
    IF h_eq:MAG > h_now:MAG * 0.02 {
        SET h_eq_hat TO h_eq:NORMALIZED.
    } ELSE {
        LOCAL node_x IS VCRS(north_u, pos_b).
        IF node_x:MAG < 1 { RETURN 1. }
        SET h_eq_hat TO node_x:NORMALIZED.
    }
    LOCAL h_des IS (h_eq_hat * SIN(target_inc_deg)) + (north_u * COS(target_inc_deg)).
    LOCAL h_hat IS h_now:NORMALIZED.
    LOCAL v_hat IS vel_b:NORMALIZED.
    // Physical +h is r×v. Positive NODE:NORMAL is the opposite direction.
    LOCAL h_plus IS VCRS(pos_b, vel_b + (v_hat * dv_pro) + (h_hat * dv_n)).
    LOCAL h_minus IS VCRS(pos_b, vel_b + (v_hat * dv_pro) - (h_hat * dv_n)).
    LOCAL ang_p IS 180.
    LOCAL ang_m IS 180.
    IF h_plus:MAG > 1 { SET ang_p TO VANG(h_plus, h_des). }
    IF h_minus:MAG > 1 { SET ang_m TO VANG(h_minus, h_des). }
    IF ang_p <= ang_m { RETURN -1. }
    RETURN 1.
}

// Constant-speed plane change: normal = v*sin(dInc), prograde = v*(cos(dInc)-1).
// A pure normal of 2*v*sin(dInc/2) from 10 deg to 90 deg does not finish the
// inclination change, and the same burn at the fast node can dive periapsis.
// Returns a lexicon ok/pro/nrm. ok FALSE means do not burn this crossing.
FUNCTION aoso_planechange_choose_normal {
    PARAMETER burn_eta.
    PARAMETER target_inc_deg.
    PARAMETER err_now.
    PARAMETER pe_min.

    LOCAL pick IS LEXICON().
    pick:ADD("ok", FALSE).
    pick:ADD("pro", 0).
    pick:ADD("nrm", 0).

    LOCAL t_ut IS TIME:SECONDS + burn_eta.
    LOCAL vel_b IS aoso_orbit_velocity_at(SHIP, t_ut).
    LOCAL spd_b IS vel_b:MAG.
    IF spd_b < 0.5 { RETURN pick. }
    LOCAL dv_n IS spd_b * SIN(err_now).
    LOCAL dv_p IS spd_b * (COS(err_now) - 1).
    IF dv_n < 0.05 { RETURN pick. }

    LOCAL nd_try IS NODE(t_ut, 0, dv_n, dv_p).
    ADD nd_try.
    aoso_yield().
    LOCAL inc_p IS nd_try:ORBIT:INCLINATION.
    LOCAL err_p IS ABS(inc_p - target_inc_deg).
    LOCAL pe_p IS nd_try:ORBIT:PERIAPSIS.
    LOCAL ecc_p IS nd_try:ORBIT:ECCENTRICITY.
    SET nd_try:NORMAL TO -dv_n.
    SET nd_try:PROGRADE TO dv_p.
    aoso_yield().
    LOCAL inc_m IS nd_try:ORBIT:INCLINATION.
    LOCAL err_m IS ABS(inc_m - target_inc_deg).
    LOCAL pe_m IS nd_try:ORBIT:PERIAPSIS.
    LOCAL ecc_m IS nd_try:ORBIT:ECCENTRICITY.
    REMOVE nd_try.

    LOCAL inc_ship IS SHIP:ORBIT:INCLINATION.
    LOCAL stale IS FALSE.
    IF ABS(inc_p - inc_ship) < 0.15 {
        IF ABS(inc_m - inc_ship) < 0.15 { SET stale TO TRUE. }
    }

    IF stale {
        LOCAL sgn IS aoso_planechange_normal_sign(burn_eta, dv_n, dv_p, target_inc_deg).
        LOCAL nd_geo IS NODE(t_ut, 0, sgn * dv_n, dv_p).
        ADD nd_geo.
        aoso_yield().
        LOCAL pe_g IS nd_geo:ORBIT:PERIAPSIS.
        LOCAL ecc_g IS nd_geo:ORBIT:ECCENTRICITY.
        LOCAL inc_g IS nd_geo:ORBIT:INCLINATION.
        REMOVE nd_geo.
        LOCAL geo_ok IS TRUE.
        IF ecc_g >= 1 { SET geo_ok TO FALSE. }
        IF pe_g < pe_min { SET geo_ok TO FALSE. }
        IF NOT geo_ok {
            IF ABS(inc_g - inc_ship) < 0.15 {
                IF PERIAPSIS >= pe_min { SET geo_ok TO TRUE. }
            }
        }
        IF geo_ok {
            aoso_log_info("PLANECHANGE", "Patched conics did not move inclination; geometric normal sign " + sgn + " at eta " + ROUND(burn_eta, 0) + "s.").
            SET pick["ok"] TO TRUE.
            SET pick["pro"] TO dv_p.
            SET pick["nrm"] TO sgn * dv_n.
        } ELSE {
            aoso_log_warn_every(15, "INC_PE", "Geometric plane-change at eta " + ROUND(burn_eta, 0) + "s would drop PE to " + ROUND(pe_g, 0) + "m. Skipping this node.").
        }
        RETURN pick.
    }

    LOCAL use_n IS 0.
    LOCAL use_err IS err_now.
    LOCAL ok_p IS FALSE.
    IF ecc_p < 1 {
        IF pe_p >= pe_min {
            IF err_p <= err_now - 1 { SET ok_p TO TRUE. }
        }
    }
    LOCAL ok_m IS FALSE.
    IF ecc_m < 1 {
        IF pe_m >= pe_min {
            IF err_m <= err_now - 1 { SET ok_m TO TRUE. }
        }
    }
    IF ok_p {
        SET use_n TO dv_n.
        SET use_err TO err_p.
    }
    IF ok_m {
        LOCAL take_m IS FALSE.
        IF NOT ok_p { SET take_m TO TRUE. }
        IF err_m < use_err { SET take_m TO TRUE. }
        IF take_m {
            SET use_n TO -dv_n.
            SET use_err TO err_m.
        }
    }
    IF use_n = 0 {
        aoso_log_warn_every(15, "INC_SIGN", "Neither normal sign at eta " + ROUND(burn_eta, 0) + "s improved inclination without dropping PE (err " + ROUND(err_p, 1) + " / " + ROUND(err_m, 1) + " deg, PE " + ROUND(pe_p, 0) + " / " + ROUND(pe_m, 0) + "m).").
        RETURN pick.
    }
    SET pick["ok"] TO TRUE.
    SET pick["pro"] TO dv_p.
    SET pick["nrm"] TO use_n.
    RETURN pick.
}

FUNCTION aoso_planechange_add_node_for_inclination {
    PARAMETER target_inc_deg IS 90.
    PARAMETER tolerance_deg IS 5.
    PARAMETER pe_floor IS -1.

    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    LOCAL period_s IS aoso_orbit_period_s().
    IF period_s <= 0 { RETURN 0. }

    LOCAL inc_now IS SHIP:ORBIT:INCLINATION.
    LOCAL err IS ABS(inc_now - target_inc_deg).
    IF err <= tolerance_deg {
        aoso_log_info("PLANECHANGE", "Already within " + tolerance_deg + " deg of inclination " + target_inc_deg + " (now " + ROUND(inc_now, 1) + ").").
        RETURN 0.
    }

    LOCAL pe_min IS pe_floor.
    IF pe_min < 0 {
        SET pe_min TO 5000.
        IF SHIP:BODY:ATM:EXISTS {
            SET pe_min TO SHIP:BODY:ATM:HEIGHT + 5000.
        } ELSE {
            LOCAL dive_pe IS aoso_config_get("DESCENT_SAFE_PE_ALT", 8000).
            IF pe_min < dive_pe { SET pe_min TO dive_pe. }
        }
    }

    LOCAL etas IS aoso_orbit_equatorial_node_etas(SHIP).
    IF etas:LENGTH = 0 {
        aoso_log_warn("PLANECHANGE", "No equatorial crossing found within one orbit.").
        RETURN 0.
    }

    LOCAL eta_slow IS -1.
    LOCAL spd_slow IS 0.
    LOCAL eta_fast IS -1.
    LOCAL spd_fast IS 0.
    IF etas:LENGTH > 0 {
        SET eta_slow TO etas[0].
        SET spd_slow TO aoso_orbit_velocity_at(SHIP, TIME:SECONDS + eta_slow):MAG.
    }
    IF etas:LENGTH > 1 {
        SET eta_fast TO etas[1].
        SET spd_fast TO aoso_orbit_velocity_at(SHIP, TIME:SECONDS + eta_fast):MAG.
        IF spd_fast < spd_slow - 0.5 {
            LOCAL swap_eta IS eta_slow.
            LOCAL swap_spd IS spd_slow.
            SET eta_slow TO eta_fast.
            SET spd_slow TO spd_fast.
            SET eta_fast TO swap_eta.
            SET spd_fast TO swap_spd.
        }
    }

    // A crossing under 40 s is the one we are leaving. Push the slow node
    // a full period rather than burning the fast node at periapsis.
    LOCAL orig_spd IS spd_slow.
    IF eta_slow < 40 {
        LOCAL use_fast IS FALSE.
        IF eta_fast >= 40 {
            IF spd_fast <= orig_spd * 1.15 { SET use_fast TO TRUE. }
        }
        IF use_fast {
            SET eta_slow TO eta_fast.
            SET spd_slow TO spd_fast.
            SET eta_fast TO -1.
        } ELSE {
            SET eta_slow TO eta_slow + period_s.
        }
    }

    LOCAL pick IS aoso_planechange_choose_normal(eta_slow, target_inc_deg, err, pe_min).
    IF NOT pick["ok"] {
        IF eta_fast >= 40 {
            IF spd_fast <= orig_spd * 1.15 {
                SET pick TO aoso_planechange_choose_normal(eta_fast, target_inc_deg, err, pe_min).
                IF pick["ok"] {
                    SET eta_slow TO eta_fast.
                    SET spd_slow TO spd_fast.
                }
            }
        }
    }
    IF NOT pick["ok"] { RETURN 0. }

    LOCAL nd IS NODE(TIME:SECONDS + eta_slow, 0, pick["nrm"], pick["pro"]).
    ADD nd.
    aoso_yield().
    LOCAL inc_pred IS nd:ORBIT:INCLINATION.
    LOCAL err_pred IS ABS(inc_pred - target_inc_deg).
    IF err_pred > err + 2 {
        REMOVE nd.
        aoso_log_warn("PLANECHANGE", "Removed inclination node: predicted inc " + ROUND(inc_pred, 1) + " is worse than " + ROUND(inc_now, 1) + " (want " + ROUND(target_inc_deg, 0) + ").").
        RETURN 0.
    }
    IF nd:ORBIT:ECCENTRICITY >= 1 {
        REMOVE nd.
        aoso_log_warn("PLANECHANGE", "Removed inclination node: predicted orbit is unbound.").
        RETURN 0.
    }
    LOCAL pe_pred IS nd:ORBIT:PERIAPSIS.
    IF pe_pred < pe_min {
        IF ABS(inc_pred - inc_now) >= 0.15 {
            REMOVE nd.
            aoso_log_warn("PLANECHANGE", "Removed inclination node: predicted PE " + ROUND(pe_pred, 0) + "m is below " + ROUND(pe_min, 0) + "m.").
            RETURN 0.
        }
    }
    aoso_log_info("PLANECHANGE", "Inclination node added: dv=" + ROUND(nd:DELTAV:MAG, 1) +
        " m/s at v=" + ROUND(spd_slow, 1) + " m/s, " + ROUND(inc_now, 1) + " -> pred " +
        ROUND(inc_pred, 1) + " deg (want " + ROUND(target_inc_deg, 0) + ").").
    RETURN nd.
}
