// AOSO/nav/cw.ks
// Clohessy-Wiltshire relative-motion guidance for close vessel rendezvous.
// Gross close-in only: same primary body, nominally 0.5-50 km. Docking RCS
// remains owned by advanced/docking.ks. Bodies are explicitly refused.

FUNCTION aoso_cw_target_vessel {
    PARAMETER target_orbitable.
    IF target_orbitable:ISTYPE("Body") { RETURN 0. }
    IF target_orbitable:ISTYPE("DockingPort") { RETURN target_orbitable:SHIP. }
    IF target_orbitable:ISTYPE("Vessel") { RETURN target_orbitable. }
    RETURN 0.
}

FUNCTION aoso_cw_omega {
    PARAMETER target_orbitable.
    LOCAL tgt_ves IS aoso_cw_target_vessel(target_orbitable).
    IF tgt_ves = 0 { RETURN 0. }
    IF tgt_ves:BODY:NAME <> SHIP:BODY:NAME { RETURN 0. }
    LOCAL sma IS tgt_ves:ORBIT:SEMIMAJORAXIS.
    IF sma <= 1 { RETURN 0. }
    LOCAL omega IS SQRT(SHIP:BODY:MU / (sma ^ 3)).
    IF tgt_ves:ORBIT:ECCENTRICITY > 0.08 {
        aoso_log_warn("NAV", "CW target eccentricity " + ROUND(tgt_ves:ORBIT:ECCENTRICITY, 3) +
            " > 0.08; using mean-motion omega anyway.").
    }
    RETURN omega.
}

FUNCTION aoso_cw_state_now {
    PARAMETER target_orbitable.
    LOCAL bad IS LEXICON("ok", FALSE, "x", 0, "y", 0, "z", 0,
        "ux", 0, "uy", 0, "uz", 0, "omega", 0, "range", 0).
    LOCAL tgt_ves IS aoso_cw_target_vessel(target_orbitable).
    IF tgt_ves = 0 { RETURN bad. }
    IF tgt_ves:BODY:NAME <> SHIP:BODY:NAME { RETURN bad. }

    LOCAL tgt_pos IS aoso_orbit_position_now(tgt_ves).
    LOCAL ship_pos IS aoso_orbit_position_now(SHIP).
    IF tgt_pos:MAG < 1 { RETURN bad. }
    LOCAL tgt_vel IS tgt_ves:VELOCITY:ORBIT.
    LOCAL ship_vel IS SHIP:VELOCITY:ORBIT.
    LOCAL xhat IS tgt_pos:NORMALIZED.
    LOCAL zhat IS VCRS(tgt_pos, tgt_vel).
    IF zhat:MAG < 0.001 { RETURN bad. }
    SET zhat TO zhat:NORMALIZED.
    LOCAL yhat IS VCRS(zhat, xhat).
    IF yhat:MAG < 0.001 { RETURN bad. }
    SET yhat TO yhat:NORMALIZED.

    LOCAL omega IS aoso_cw_omega(tgt_ves).
    IF omega < 1e-8 { RETURN bad. }
    LOCAL rel_pos IS ship_pos - tgt_pos.
    LOCAL rel_vel IS ship_vel - tgt_vel.
    LOCAL omega_vec IS zhat * omega.
    LOCAL vel_lvlh IS rel_vel - VCRS(omega_vec, rel_pos).

    RETURN LEXICON(
        "ok", TRUE,
        "x", VDOT(rel_pos, xhat),
        "y", VDOT(rel_pos, yhat),
        "z", VDOT(rel_pos, zhat),
        "ux", VDOT(vel_lvlh, xhat),
        "uy", VDOT(vel_lvlh, yhat),
        "uz", VDOT(vel_lvlh, zhat),
        "omega", omega,
        "range", rel_pos:MAG
    ).
}

FUNCTION aoso_cw_propagate {
    PARAMETER st.
    PARAMETER dt_s.
    LOCAL bad IS LEXICON("ok", FALSE, "x", 0, "y", 0, "z", 0,
        "ux", 0, "uy", 0, "uz", 0, "omega", 0, "range", 0).
    IF NOT st:ISTYPE("Lexicon") { RETURN bad. }
    IF NOT st:HASKEY("omega") { RETURN bad. }
    LOCAL omega IS st["omega"].
    IF omega < 1e-8 { RETURN bad. }

    LOCAL nt_rad IS omega * dt_s.
    LOCAL sval IS SIN(nt_rad * AOSO_CONST["RAD2DEG"]).
    LOCAL cval IS COS(nt_rad * AOSO_CONST["RAD2DEG"]).
    LOCAL x0 IS st["x"].
    LOCAL y0 IS st["y"].
    LOCAL z0 IS st["z"].
    LOCAL ux0 IS st["ux"].
    LOCAL uy0 IS st["uy"].
    LOCAL uz0 IS st["uz"].

    LOCAL xpos IS (4 - 3 * cval) * x0 + (sval / omega) * ux0 +
        (2 / omega) * (1 - cval) * uy0.
    LOCAL ypos IS 6 * (sval - nt_rad) * x0 + y0 +
        (2 / omega) * (cval - 1) * ux0 + (4 * sval / omega - 3 * dt_s) * uy0.
    LOCAL zpos IS z0 * cval + (uz0 / omega) * sval.

    LOCAL ux1 IS 3 * omega * sval * x0 + cval * ux0 + 2 * sval * uy0.
    LOCAL uy1 IS 6 * omega * (cval - 1) * x0 - 2 * sval * ux0 +
        (4 * cval - 3) * uy0.
    LOCAL uz1 IS 0 - omega * sval * z0 + cval * uz0.
    LOCAL range_m IS SQRT(xpos ^ 2 + ypos ^ 2 + zpos ^ 2).

    RETURN LEXICON("ok", TRUE, "x", xpos, "y", ypos, "z", zpos,
        "ux", ux1, "uy", uy1, "uz", uz1, "omega", omega, "range", range_m).
}

FUNCTION aoso_cw_impulse_to_intercept {
    PARAMETER st.
    PARAMETER tf_s.
    LOCAL bad IS LEXICON("ok", FALSE, "dvx", 0, "dvy", 0, "dvz", 0, "dv_mag", 0).
    IF NOT st:ISTYPE("Lexicon") { RETURN bad. }
    IF NOT st:HASKEY("omega") { RETURN bad. }
    LOCAL omega IS st["omega"].
    IF omega < 1e-8 { RETURN bad. }
    IF tf_s < 25 { RETURN bad. }

    LOCAL x0 IS st["x"].
    LOCAL y0 IS st["y"].
    LOCAL z0 IS st["z"].
    LOCAL ux0 IS st["ux"].
    LOCAL uy0 IS st["uy"].
    LOCAL uz0 IS st["uz"].
    LOCAL nt_rad IS omega * tf_s.
    LOCAL sval IS SIN(nt_rad * AOSO_CONST["RAD2DEG"]).
    LOCAL cval IS COS(nt_rad * AOSO_CONST["RAD2DEG"]).

    LOCAL dvz IS 0 - uz0.
    IF ABS(sval) > 1e-4 {
        LOCAL uzn IS 0 - omega * z0 * cval / sval.
        SET dvz TO uzn - uz0.
    } ELSE {
        IF ABS(z0) > 50 { RETURN bad. }
    }

    LOCAL phi_rv_xx IS sval / omega.
    LOCAL phi_rv_xy IS 2 * (1 - cval) / omega.
    LOCAL phi_rv_yx IS 2 * (cval - 1) / omega.
    LOCAL phi_rv_yy IS 4 * sval / omega - 3 * tf_s.
    LOCAL rhs_x IS 0 - ((4 - 3 * cval) * x0).
    LOCAL rhs_y IS 0 - (6 * (sval - nt_rad) * x0 + y0).
    LOCAL det IS phi_rv_xx * phi_rv_yy - phi_rv_xy * phi_rv_yx.
    IF ABS(det) < 1e-12 { RETURN bad. }

    LOCAL uxn IS (rhs_x * phi_rv_yy - phi_rv_xy * rhs_y) / det.
    LOCAL uyn IS (phi_rv_xx * rhs_y - rhs_x * phi_rv_yx) / det.
    LOCAL dvx IS uxn - ux0.
    LOCAL dvy IS uyn - uy0.
    LOCAL dv_mag IS SQRT(dvx ^ 2 + dvy ^ 2 + dvz ^ 2).
    RETURN LEXICON("ok", TRUE, "dvx", dvx, "dvy", dvy, "dvz", dvz, "dv_mag", dv_mag).
}

FUNCTION aoso_cw_impulse_to_match {
    PARAMETER st.
    LOCAL bad IS LEXICON("ok", FALSE, "dvx", 0, "dvy", 0, "dvz", 0, "dv_mag", 0).
    IF NOT st:ISTYPE("Lexicon") { RETURN bad. }
    IF NOT st:HASKEY("ok") { RETURN bad. }
    IF NOT st["ok"] { RETURN bad. }
    LOCAL dvx IS 0 - st["ux"].
    LOCAL dvy IS 0 - st["uy"].
    LOCAL dvz IS 0 - st["uz"].
    LOCAL dv_mag IS SQRT(dvx ^ 2 + dvy ^ 2 + dvz ^ 2).
    RETURN LEXICON("ok", TRUE, "dvx", dvx, "dvy", dvy, "dvz", dvz, "dv_mag", dv_mag).
}

FUNCTION aoso_cw_dv_to_node_xyz {
    PARAMETER dvx.
    PARAMETER dvy.
    PARAMETER dvz.
    PARAMETER target_orbitable.
    LOCAL tgt_ves IS aoso_cw_target_vessel(target_orbitable).
    IF tgt_ves = 0 {
        RETURN LEXICON("radial", 0, "normal", 0, "prograde", 0).
    }
    RETURN LEXICON("radial", dvx, "normal", dvz, "prograde", dvy).
}

FUNCTION aoso_cw_add_intercept_node {
    PARAMETER target_orbitable.
    PARAMETER tf_s IS 0.
    LOCAL tgt_ves IS aoso_cw_target_vessel(target_orbitable).
    IF tgt_ves = 0 { RETURN 0. }
    IF tgt_ves:BODY:NAME <> SHIP:BODY:NAME { RETURN 0. }

    LOCAL st IS aoso_cw_state_now(tgt_ves).
    IF NOT st["ok"] { RETURN 0. }
    LOCAL min_range IS aoso_config_get("CW_MIN_RANGE_M", 500).
    LOCAL max_range IS aoso_config_get("CW_MAX_RANGE_M", 50000).
    IF st["range"] < min_range { RETURN 0. }
    IF st["range"] > max_range { RETURN 0. }

    IF tf_s <= 0 { SET tf_s TO aoso_config_get("CW_DEFAULT_TF_S", 180). }
    IF tf_s < 25 { SET tf_s TO 25. }
    LOCAL imp IS aoso_cw_impulse_to_intercept(st, tf_s).
    IF NOT imp["ok"] { RETURN 0. }
    IF imp["dv_mag"] > aoso_config_get("CW_MAX_DV", 80) { RETURN 0. }

    LOCAL xyz IS aoso_cw_dv_to_node_xyz(imp["dvx"], imp["dvy"], imp["dvz"], tgt_ves).
    LOCAL nd IS NODE(TIME:SECONDS + 25, xyz["radial"], xyz["normal"], xyz["prograde"]).
    ADD nd.
    RETURN nd.
}

FUNCTION aoso_cw_add_match_node {
    PARAMETER target_orbitable.
    PARAMETER eta_s IS 30.
    LOCAL tgt_ves IS aoso_cw_target_vessel(target_orbitable).
    IF tgt_ves = 0 { RETURN 0. }
    IF tgt_ves:BODY:NAME <> SHIP:BODY:NAME { RETURN 0. }
    IF eta_s < 25 { SET eta_s TO 25. }

    LOCAL st IS aoso_cw_state_now(tgt_ves).
    IF NOT st["ok"] { RETURN 0. }
    LOCAL imp IS aoso_cw_impulse_to_match(st).
    IF NOT imp["ok"] { RETURN 0. }
    IF imp["dv_mag"] > aoso_config_get("CW_MAX_DV", 80) { RETURN 0. }

    LOCAL xyz IS aoso_cw_dv_to_node_xyz(imp["dvx"], imp["dvy"], imp["dvz"], tgt_ves).
    LOCAL nd IS NODE(TIME:SECONDS + eta_s, xyz["radial"], xyz["normal"], xyz["prograde"]).
    ADD nd.
    RETURN nd.
}
