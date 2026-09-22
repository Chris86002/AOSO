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
    IF c_z <= 0 { RETURN -1. }
    LOCAL y_over_c IS y_uni / c_z.
    IF y_over_c <= 0 { RETURN -1. }
    LOCAL x_uni IS SQRT(y_over_c).
    LOCAL raw IS x_uni ^ 3 * s_z + A * SQRT(y_uni).
    IF raw <= 0 { RETURN -1. }
    LOCAL t IS raw / SQRT(mu).
    IF t <= 0 { RETURN -1. }
    RETURN t.
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

    // 180 deg is the Hohmann singularity (sin=0). Use vis-viva in the
    // pos1-pos2 plane instead of skipping the cell.
    IF ABS(dnu - 180) < 2.5 {
        LOCAL sma_t IS (radius1 + radius2) / 2.
        IF sma_t < 1 { RETURN out. }
        LOCAL v_t IS SQRT(mu * (2 / radius1 - 1 / sma_t)).
        LOCAL nrm_h IS VCRS(pos1, pos2).
        IF nrm_h:MAG < 0.001 { SET nrm_h TO VCRS(pos1, V(0, 1, 0)). }
        IF nrm_h:MAG < 0.001 { RETURN out. }
        LOCAL pgd_h IS VCRS(nrm_h:NORMALIZED, pos1:NORMALIZED):NORMALIZED.
        SET out["ok"] TO TRUE.
        SET out["vel1"] TO pgd_h * v_t.
        SET out["vel2"] TO V(0, 0, 0).
        RETURN out.
    }

    LOCAL s_nu IS SIN(dnu).
    IF ABS(s_nu) < 0.0008 { RETURN out. }
    LOCAL one_c IS 1 - COS(dnu).
    IF ABS(one_c) < 0.0008 { RETURN out. }
    LOCAL A IS s_nu * SQRT(radius1 * radius2 / one_c).

    // Coarse universal-variable bracket, then secant on t(z)-tof.
    // Eight samples cover the useful zero-rev region without the old
    // 14x7 shrink search.
    LOCAL samples IS LIST().
    LOCAL best_z IS 1.
    LOCAL best_err IS 1e99.
    LOCAL best_i IS -1.
    LOCAL bracketed IS FALSE.
    LOCAL z_a IS 0.
    LOCAL z_b IS 0.
    LOCAL err_a IS 0.
    LOCAL err_b IS 0.
    LOCAL i IS 0.
    UNTIL i >= 8 {
        LOCAL z_try IS -20 + i * 8.
        IF ABS(z_try) < 0.02 { SET z_try TO 0.02. }
        LOCAL t_try IS aoso_lambert_tof(radius1, radius2, A, z_try, mu).
        IF t_try > 1 {
            LOCAL err_try IS t_try - tof_s.
            samples:ADD(LEXICON("z", z_try, "t", t_try, "err", err_try)).
            LOCAL sample_i IS samples:LENGTH - 1.
            IF ABS(err_try) < best_err {
                SET best_err TO ABS(err_try).
                SET best_z TO z_try.
                SET best_i TO sample_i.
            }
            IF samples:LENGTH >= 2 {
                LOCAL prev IS samples[samples:LENGTH - 2].
                IF NOT bracketed {
                    IF prev["err"] * err_try <= 0 {
                        SET bracketed TO TRUE.
                        SET z_a TO prev["z"].
                        SET err_a TO prev["err"].
                        SET z_b TO z_try.
                        SET err_b TO err_try.
                    }
                }
            }
        }
        SET i TO i + 1.
    }
    IF samples:LENGTH < 2 { RETURN out. }

    IF NOT bracketed {
        IF best_i < 0 { RETURN out. }
        LOCAL neighbor_i IS best_i - 1.
        IF neighbor_i < 0 { SET neighbor_i TO best_i + 1. }
        IF neighbor_i >= samples:LENGTH { SET neighbor_i TO best_i - 1. }
        IF neighbor_i < 0 { RETURN out. }
        SET z_a TO samples[neighbor_i]["z"].
        SET err_a TO samples[neighbor_i]["err"].
        SET z_b TO samples[best_i]["z"].
        SET err_b TO samples[best_i]["err"].
    }

    LOCAL k IS 0.
    UNTIL k >= 12 {
        IF ABS(err_b - err_a) < 1e-9 { SET k TO 12. }
        ELSE {
            LOCAL z_new IS z_b - err_b * (z_b - z_a) / (err_b - err_a).
            IF z_new < -24 { SET z_new TO -24. }
            IF z_new > 40 { SET z_new TO 40. }
            IF ABS(z_new) < 0.02 { SET z_new TO 0.02. }
            LOCAL t_new IS aoso_lambert_tof(radius1, radius2, A, z_new, mu).
            IF t_new > 1 {
                LOCAL err_new IS t_new - tof_s.
                IF ABS(err_new) < best_err {
                    SET best_err TO ABS(err_new).
                    SET best_z TO z_new.
                }
                IF bracketed {
                    IF err_a * err_new <= 0 {
                        SET z_b TO z_new.
                        SET err_b TO err_new.
                    } ELSE {
                        SET z_a TO z_new.
                        SET err_a TO err_new.
                    }
                } ELSE {
                    SET z_a TO z_b.
                    SET err_a TO err_b.
                    SET z_b TO z_new.
                    SET err_b TO err_new.
                }
            } ELSE {
                // Invalid universal-variable point: pull the next secant
                // endpoint toward the best valid coarse sample.
                SET z_a TO z_b.
                SET err_a TO err_b.
                SET z_b TO (z_b + best_z) / 2.
                IF ABS(z_b) < 0.02 { SET z_b TO 0.02. }
                LOCAL t_retry IS aoso_lambert_tof(radius1, radius2, A, z_b, mu).
                IF t_retry > 1 { SET err_b TO t_retry - tof_s. }
            }
            SET k TO k + 1.
        }
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
    SET out["z"] TO best_z.
    SET out["tof_err"] TO best_err.
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
