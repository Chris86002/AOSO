// AOSO/nav/lambert.ks
// 0-revolution Lambert solver (Vallado universal-variable, original kOS).
// Given two position vectors around the same body and a time of flight,
// returns the inertial velocities at those points. Used by the porkchop
// intercept search. Not a copy of RSVP/PyKep; equations are textbook
// (Vallado / Curtis). kOS SIN/COS are degrees.

FUNCTION aoso_math_exp {
    PARAMETER x.
    IF x > 22 { RETURN 3.6e9. }
    IF x < -22 { RETURN 0. }
    RETURN CONSTANT:E ^ x.
}

FUNCTION aoso_math_sinh {
    PARAMETER x.
    LOCAL e_p IS aoso_math_exp(x).
    LOCAL e_m IS aoso_math_exp(0 - x).
    RETURN (e_p - e_m) / 2.
}

FUNCTION aoso_math_cosh {
    PARAMETER x.
    LOCAL e_p IS aoso_math_exp(x).
    LOCAL e_m IS aoso_math_exp(0 - x).
    RETURN (e_p + e_m) / 2.
}

FUNCTION aoso_lambert_c {
    PARAMETER z.
    IF z > 0.0001 {
        LOCAL root IS SQRT(z).
        RETURN (1 - COS(root * AOSO_CONST["RAD2DEG"])) / z.
    }
    IF z < -0.0001 {
        LOCAL root IS SQRT(0 - z).
        RETURN (aoso_math_cosh(root) - 1) / (0 - z).
    }
    RETURN 0.5.
}

FUNCTION aoso_lambert_s {
    PARAMETER z.
    IF z > 0.0001 {
        LOCAL root IS SQRT(z).
        LOCAL root3 IS root * root * root.
        RETURN (root - SIN(root * AOSO_CONST["RAD2DEG"])) / root3.
    }
    IF z < -0.0001 {
        LOCAL root IS SQRT(0 - z).
        LOCAL root3 IS root * root * root.
        RETURN (aoso_math_sinh(root) - root) / root3.
    }
    RETURN 1 / 6.
}

FUNCTION aoso_lambert_tof {
    PARAMETER radius1.
    PARAMETER radius2.
    PARAMETER A.
    PARAMETER z.
    PARAMETER mu.
    LOCAL c_z IS aoso_lambert_c(z).
    IF c_z <= 0.00000001 { RETURN -1. }
    LOCAL s_z IS aoso_lambert_s(z).
    LOCAL y_uni IS radius1 + radius2 - A * (1 - z * s_z) / SQRT(c_z).
    IF y_uni <= 1 { RETURN -1. }
    LOCAL x_uni IS SQRT(y_uni / c_z).
    RETURN (x_uni ^ 3 * s_z + A * SQRT(y_uni)) / SQRT(mu).
}

FUNCTION aoso_lambert_y {
    PARAMETER radius1.
    PARAMETER radius2.
    PARAMETER A.
    PARAMETER z.
    LOCAL c_z IS aoso_lambert_c(z).
    IF c_z <= 0.00000001 { RETURN -1. }
    LOCAL s_z IS aoso_lambert_s(z).
    RETURN radius1 + radius2 - A * (1 - z * s_z) / SQRT(c_z).
}

// Returns a lexicon: ok, vel1, vel2. vel1 is inertial velocity at pos1.
FUNCTION aoso_lambert_solve {
    PARAMETER pos1.
    PARAMETER pos2.
    PARAMETER tof_s.
    PARAMETER mu.
    PARAMETER long_way IS FALSE.

    LOCAL out IS LEXICON("ok", FALSE, "vel1", V(0, 0, 0), "vel2", V(0, 0, 0)).
    IF tof_s < 30 { RETURN out. }
    LOCAL radius1 IS pos1:MAG.
    LOCAL radius2 IS pos2:MAG.
    IF radius1 < 1 { RETURN out. }
    IF radius2 < 1 { RETURN out. }

    LOCAL dnu IS VANG(pos1, pos2).
    IF long_way { SET dnu TO 360 - dnu. }
    IF dnu < 2 { RETURN out. }
    IF dnu > 358 { RETURN out. }
    LOCAL s_nu IS SIN(dnu).
    IF ABS(s_nu) < 0.0008 { RETURN out. }
    LOCAL one_c IS 1 - COS(dnu).
    IF ABS(one_c) < 0.0008 { RETURN out. }
    LOCAL A IS s_nu * SQRT(radius1 * radius2 / one_c).

    LOCAL best_z IS 1.
    LOCAL best_err IS 1e99.
    LOCAL i IS 0.
    UNTIL i >= 28 {
        LOCAL z_try IS -24 + i * (62 / 27).
        IF ABS(z_try) < 0.05 { SET z_try TO 0.05. }
        LOCAL t_try IS aoso_lambert_tof(radius1, radius2, A, z_try, mu).
        IF t_try > 0 {
            LOCAL err IS ABS(t_try - tof_s).
            IF err < best_err {
                SET best_err TO err.
                SET best_z TO z_try.
            }
        }
        SET i TO i + 1.
    }
    IF best_err > tof_s * 0.5 { RETURN out. }

    LOCAL span IS 3.
    LOCAL k IS 0.
    UNTIL k >= 14 {
        LOCAL j IS 0.
        UNTIL j >= 7 {
            LOCAL z_try IS best_z + (j - 3) * span / 3.
            IF ABS(z_try) < 0.02 { SET z_try TO 0.02. }
            LOCAL t_try IS aoso_lambert_tof(radius1, radius2, A, z_try, mu).
            IF t_try > 0 {
                LOCAL err IS ABS(t_try - tof_s).
                IF err < best_err {
                    SET best_err TO err.
                    SET best_z TO z_try.
                }
            }
            SET j TO j + 1.
        }
        SET span TO span * 0.42.
        SET k TO k + 1.
    }

    IF best_err > tof_s * 0.08 { RETURN out. }

    LOCAL y_uni IS aoso_lambert_y(radius1, radius2, A, best_z).
    IF y_uni <= 1 { RETURN out. }
    LOCAL f_lag IS 1 - y_uni / radius1.
    LOCAL g_lag IS A * SQRT(y_uni / mu).
    IF ABS(g_lag) < 0.001 { RETURN out. }
    LOCAL gdot IS 1 - y_uni / radius2.
    LOCAL vel1 IS (pos2 - f_lag * pos1) / g_lag.
    LOCAL vel2 IS (gdot * pos2 - pos1) / g_lag.
    SET out["ok"] TO TRUE.
    SET out["vel1"] TO vel1.
    SET out["vel2"] TO vel2.
    RETURN out.
}

FUNCTION aoso_lambert_rel_pos {
    PARAMETER obj.
    PARAMETER t_ut.
    PARAMETER parent_body.
    RETURN POSITIONAT(obj, t_ut) - POSITIONAT(parent_body, t_ut).
}

// Ship orbital basis at t_ut -> node radial/normal/prograde from inertial dv.
FUNCTION aoso_lambert_dv_to_node_xyz {
    PARAMETER dv_vec.
    PARAMETER pos_b.
    PARAMETER vel_b.
    LOCAL nrm IS VCRS(pos_b, vel_b).
    IF nrm:MAG < 0.001 {
        RETURN LEXICON("radial", 0, "normal", 0, "prograde", dv_vec:MAG).
    }
    SET nrm TO nrm:NORMALIZED.
    LOCAL rad IS pos_b:NORMALIZED.
    LOCAL pgd IS VCRS(nrm, rad):NORMALIZED.
    RETURN LEXICON(
        "radial", VDOT(dv_vec, rad),
        "normal", VDOT(dv_vec, nrm),
        "prograde", VDOT(dv_vec, pgd)
    ).
}
