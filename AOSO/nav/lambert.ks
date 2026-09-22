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
    IF y_uni <= 0.01 { RETURN -1. }
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

FUNCTION aoso_lambert_try_z {
    PARAMETER radius1.
    PARAMETER radius2.
    PARAMETER A.
    PARAMETER z.
    PARAMETER mu.
    PARAMETER tof_s.
    IF ABS(z) < 0.02 { SET z TO 0.02. }
    LOCAL t_try IS aoso_lambert_tof(radius1, radius2, A, z, mu).
    IF t_try <= 1 { RETURN LEXICON("ok", FALSE, "z", z, "t", -1, "err", 1e99). }
    RETURN LEXICON("ok", TRUE, "z", z, "t", t_try, "err", t_try - tof_s).
}

FUNCTION aoso_lambert_visviva_180 {
    PARAMETER pos1.
    PARAMETER pos2.
    PARAMETER mu.
    PARAMETER tof_s IS 0.
    LOCAL out IS LEXICON("ok", FALSE, "vel1", V(0, 0, 0), "vel2", V(0, 0, 0), "src", "ks").
    LOCAL radius1 IS pos1:MAG.
    LOCAL radius2 IS pos2:MAG.
    LOCAL sma_h IS (radius1 + radius2) / 2.
    IF sma_h < 1 { RETURN out. }
    LOCAL sma_t IS sma_h.
    IF tof_s > 30 {
        LOCAL tof_pi IS tof_s / CONSTANT:PI.
        LOCAL sma_tof IS (tof_pi * tof_pi * mu) ^ (1 / 3).
        IF sma_tof > sma_h { SET sma_t TO sma_tof. }
    }
    LOCAL vis1 IS mu * (2 / radius1 - 1 / sma_t).
    LOCAL vis2 IS mu * (2 / radius2 - 1 / sma_t).
    IF vis1 <= 0 { RETURN out. }
    IF vis2 <= 0 { RETURN out. }
    LOCAL nrm_h IS VCRS(pos1, pos2).
    IF nrm_h:MAG < 0.001 { SET nrm_h TO VCRS(pos1, V(0, 1, 0)). }
    IF nrm_h:MAG < 0.001 { SET nrm_h TO VCRS(pos1, V(0, 0, 1)). }
    IF nrm_h:MAG < 0.001 { RETURN out. }
    SET nrm_h TO nrm_h:NORMALIZED.
    LOCAL pgd_h IS VCRS(nrm_h, pos1:NORMALIZED):NORMALIZED.
    LOCAL pgd_2 IS VCRS(nrm_h, pos2:NORMALIZED):NORMALIZED.
    SET out["ok"] TO TRUE.
    SET out["vel1"] TO pgd_h * SQRT(vis1).
    SET out["vel2"] TO pgd_2 * SQRT(vis2).
    SET out["z"] TO 0.
    LOCAL tof_act IS CONSTANT:PI * SQRT((sma_t ^ 3) / mu).
    SET out["tof_err"] TO ABS(tof_act - tof_s).
    RETURN out.
}

FUNCTION aoso_lambert_tof_tol {
    PARAMETER tof_s.
    LOCAL frac IS 0.001.
    IF DEFINED AOSO_CONFIG {
        SET frac TO aoso_config_get("LAMBERT_TOF_TOL", 0.001).
    }
    IF frac < 0.0002 { SET frac TO 0.0002. }
    IF frac > 0.01 { SET frac TO 0.01. }
    LOCAL tol IS tof_s * frac.
    IF tol < 0.25 { SET tol TO 0.25. }
    IF tol > 8 { SET tol TO 8. }
    RETURN tol.
}

// Returns a lexicon: ok, vel1, vel2. vel1 is inertial velocity at pos1.
// Pure KerboScript oracle / fallback. Native math goes through
// aoso_lambert_solve.
FUNCTION aoso_lambert_solve_ks {
    PARAMETER pos1.
    PARAMETER pos2.
    PARAMETER tof_s.
    PARAMETER mu.
    PARAMETER long_way IS FALSE.

    LOCAL out IS LEXICON("ok", FALSE, "vel1", V(0, 0, 0), "vel2", V(0, 0, 0), "src", "ks").
    IF tof_s < 30 { RETURN out. }
    LOCAL radius1 IS pos1:MAG.
    LOCAL radius2 IS pos2:MAG.
    IF radius1 < 1 { RETURN out. }
    IF radius2 < 1 { RETURN out. }

    LOCAL dnu IS VANG(pos1, pos2).
    IF long_way { SET dnu TO 360 - dnu. }
    IF dnu < 2 { RETURN out. }
    IF dnu > 358 { RETURN out. }

    // Exactly 180 deg is the Hohmann singularity (A=0). Keep a narrow
    // vis-viva fallback; a 2.5 deg band used to swallow 0.7/1.3x TOF
    // seeds and return a Hohmann speed for the wrong flight time.
    IF ABS(dnu - 180) < 0.45 {
        RETURN aoso_lambert_visviva_180(pos1, pos2, mu, tof_s).
    }

    LOCAL s_nu IS SIN(dnu).
    IF ABS(s_nu) < 0.0008 { RETURN aoso_lambert_visviva_180(pos1, pos2, mu, tof_s). }
    LOCAL one_c IS 1 - COS(dnu).
    IF ABS(one_c) < 0.0008 { RETURN out. }
    LOCAL A IS s_nu * SQRT(radius1 * radius2 / one_c).

    // Dense 0-rev z grid. Old step-8 sampling skipped z~2.5 (90 deg
    // circular) and z~pi^2 (Hohmann) and then accepted 8% TOF error.
    LOCAL z_grid IS LIST(-28, -18, -10, -5, -2, 0.4, 1.2, 2.5, 4, 6.5, 9, 13, 18, 24, 30, 36).
    LOCAL samples IS LIST().
    LOCAL best_z IS 1.
    LOCAL best_err IS 1e99.
    LOCAL bracketed IS FALSE.
    LOCAL z_a IS 0.
    LOCAL z_b IS 0.
    LOCAL err_a IS 0.
    LOCAL err_b IS 0.
    LOCAL gi IS 0.
    UNTIL gi >= z_grid:LENGTH {
        LOCAL samp IS aoso_lambert_try_z(radius1, radius2, A, z_grid[gi], mu, tof_s).
        IF samp["ok"] {
            samples:ADD(samp).
            IF ABS(samp["err"]) < best_err {
                SET best_err TO ABS(samp["err"]).
                SET best_z TO samp["z"].
            }
            IF samples:LENGTH >= 2 {
                LOCAL prev IS samples[samples:LENGTH - 2].
                IF NOT bracketed {
                    IF prev["err"] * samp["err"] <= 0 {
                        SET bracketed TO TRUE.
                        SET z_a TO prev["z"].
                        SET err_a TO prev["err"].
                        SET z_b TO samp["z"].
                        SET err_b TO samp["err"].
                    }
                }
            }
        }
        SET gi TO gi + 1.
    }

    IF NOT bracketed {
        // Local densify around the best coarse sample, then try to bracket.
        LOCAL li IS 0.
        UNTIL li >= 9 {
            LOCAL z_try IS best_z - 4 + li.
            LOCAL samp2 IS aoso_lambert_try_z(radius1, radius2, A, z_try, mu, tof_s).
            IF samp2["ok"] {
                IF ABS(samp2["err"]) < best_err {
                    SET best_err TO ABS(samp2["err"]).
                    SET best_z TO samp2["z"].
                }
                samples:ADD(samp2).
                IF samples:LENGTH >= 2 {
                    LOCAL prev2 IS samples[samples:LENGTH - 2].
                    IF NOT bracketed {
                        IF prev2["err"] * samp2["err"] <= 0 {
                            SET bracketed TO TRUE.
                            SET z_a TO prev2["z"].
                            SET err_a TO prev2["err"].
                            SET z_b TO samp2["z"].
                            SET err_b TO samp2["err"].
                        }
                    }
                }
            }
            SET li TO li + 1.
        }
    }

    IF NOT bracketed { RETURN out. }

    LOCAL k IS 0.
    UNTIL k >= 28 {
        LOCAL z_mid IS (z_a + z_b) / 2.
        LOCAL samp_m IS aoso_lambert_try_z(radius1, radius2, A, z_mid, mu, tof_s).
        IF samp_m["ok"] {
            IF ABS(samp_m["err"]) < best_err {
                SET best_err TO ABS(samp_m["err"]).
                SET best_z TO samp_m["z"].
            }
            IF err_a * samp_m["err"] <= 0 {
                SET z_b TO samp_m["z"].
                SET err_b TO samp_m["err"].
            } ELSE {
                SET z_a TO samp_m["z"].
                SET err_a TO samp_m["err"].
            }
        } ELSE {
            SET z_a TO (z_a + 3 * z_b) / 4.
        }
        IF ABS(z_b - z_a) < 1e-7 { SET k TO 28. }
        ELSE { SET k TO k + 1. }
    }

    // Secant polish on the tight bracket.
    LOCAL p IS 0.
    UNTIL p >= 8 {
        IF ABS(err_b - err_a) < 1e-12 { SET p TO 8. }
        ELSE {
            LOCAL z_new IS z_b - err_b * (z_b - z_a) / (err_b - err_a).
            IF z_new < -36 { SET z_new TO -36. }
            IF z_new > 39 { SET z_new TO 39. }
            LOCAL samp_n IS aoso_lambert_try_z(radius1, radius2, A, z_new, mu, tof_s).
            IF samp_n["ok"] {
                IF ABS(samp_n["err"]) < best_err {
                    SET best_err TO ABS(samp_n["err"]).
                    SET best_z TO samp_n["z"].
                }
                SET z_a TO z_b.
                SET err_a TO err_b.
                SET z_b TO samp_n["z"].
                SET err_b TO samp_n["err"].
            }
            SET p TO p + 1.
        }
    }

    IF best_err > aoso_lambert_tof_tol(tof_s) { RETURN out. }

    LOCAL y_uni IS aoso_lambert_y(radius1, radius2, A, best_z).
    IF y_uni <= 0.01 { RETURN out. }
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

// Stable public API. Native math is optional; the pure KerboScript solver
// remains the acceptance oracle and fallback when the DLL is absent,
// returns a non-solution, or misses the requested time of flight.
FUNCTION aoso_lambert_solve {
    PARAMETER pos1.
    PARAMETER pos2.
    PARAMETER tof_s.
    PARAMETER mu.
    PARAMETER long_way IS FALSE.

    LOCAL native_obj IS aoso_addon_native().
    IF NOT native_obj:ISTYPE("Scalar") {
        IF native_obj:HASSUFFIX("LAMBERT") {
            LOCAL native_sol IS native_obj:LAMBERT(pos1, pos2, tof_s, mu, long_way).
            IF native_sol:ISTYPE("Lexicon") {
                IF native_sol:HASKEY("ok") {
                    IF native_sol["ok"] {
                        LOCAL native_use IS FALSE.
                        IF native_sol:HASKEY("tof_err") {
                            IF native_sol["tof_err"] <= aoso_lambert_tof_tol(tof_s) {
                                SET native_use TO TRUE.
                            }
                        }
                        IF native_use { RETURN native_sol. }
                    }
                }
            }
        }
    }
    RETURN aoso_lambert_solve_ks(pos1, pos2, tof_s, mu, long_way).
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
