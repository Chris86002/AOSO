// AOSO/vehicle/performance.ks
// Pure-kOS equivalents of the readouts Kerbal Engineer normally supplies, so
// the rest of AOSO never has a hard dependency on KER (see core/addons.ks).
// Every figure here is derived only from stock kOS suffixes.

// Instantaneous thrust-to-weight ratio at the current altitude/body, usable
// as a cheap one-off check (e.g. before deciding to stage) without needing a
// full aoso_capabilities_refresh().
FUNCTION aoso_perf_twr {
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL g IS SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
    RETURN SHIP:AVAILABLETHRUST / (SHIP:MASS * g).
}

// Estimated burn time (s) to achieve a given delta-v with the currently
// ignited engines, via the constant-thrust rocket equation:
//   t = (m0 * Isp * g0 / F) * (1 - e^(-dv / (Isp * g0)))
// Uses current-atmosphere ISP/thrust since that is what will actually be
// burned; callers planning a vacuum burn should call this once on-orbit.
FUNCTION aoso_perf_burn_time_for_dv {
    PARAMETER dv.

    LOCAL elist IS aoso_parts_engines().
    LOCAL thrust_sum IS 0.
    LOCAL isp_weighted IS 0.
    FOR e IN elist {
        IF e:IGNITION AND NOT e:FLAMEOUT {
            SET thrust_sum TO thrust_sum + e:MAXTHRUST.
            SET isp_weighted TO isp_weighted + (e:ISP * e:MAXTHRUST).
        }
    }
    IF thrust_sum <= 0 { RETURN 0. }

    LOCAL isp IS isp_weighted / thrust_sum.
    LOCAL ve IS isp * AOSO_CONST["G0"].
    IF ve <= 0 { RETURN 0. }

    LOCAL analytical IS (SHIP:MASS * ve / thrust_sum) * (1 - CONSTANT:E ^ (-dv / ve)).
    IF DEFINED AOSO_XP {
        RETURN aoso_xp_metric_apply("MANEUVER", SHIP:BODY:NAME, "BURN_TIME", analytical).
    }
    RETURN analytical.
}

// Live aero. SHIP:Q is always available (Kerbin-atm units). Drag force
// prefers MechJeb VESSEL:DRAG (kN); else accelerometer residual minus
// thrust. -1 means "unknown", not zero drag.
FUNCTION aoso_aero_q {
    RETURN SHIP:Q.
}

FUNCTION aoso_aero_aoa {
    LOCAL mj_aoa IS aoso_addon_mj_aoa().
    IF mj_aoa > -900 { RETURN mj_aoa. }
    LOCAL pitch IS MAX(0, MIN(90, 90 - VANG(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR))).
    LOCAL fpa IS 90.
    LOCAL vel IS SHIP:VELOCITY:SURFACE.
    IF vel:MAG >= 1 {
        SET fpa TO MAX(0, MIN(90, 90 - VANG(SHIP:UP:VECTOR, vel))).
    }
    RETURN pitch - fpa.
}

FUNCTION aoso_aero_drag_kn {
    LOCAL mj_d IS aoso_addon_mj_drag_kn().
    IF mj_d >= 0 { RETURN mj_d. }
    LOCAL acc IS SHIP:SENSORS:ACC.
    IF acc:MAG < 0.05 { RETURN -1. }
    LOCAL mass_t IS SHIP:MASS.
    IF mass_t <= 0 { RETURN -1. }
    LOCAL thrust_now IS SHIP:THRUST.
    LOCAL thrust_acc IS SHIP:FACING:FOREVECTOR * (thrust_now / mass_t).
    LOCAL aero_acc IS acc - thrust_acc.
    LOCAL vel IS SHIP:VELOCITY:SURFACE.
    IF vel:MAG < 1 { RETURN aero_acc:MAG * mass_t. }
    RETURN ABS(VDOT(aero_acc, vel:NORMALIZED)) * mass_t.
}

FUNCTION aoso_aero_drag_source {
    LOCAL mj_d IS aoso_addon_mj_drag_kn().
    IF mj_d >= 0 { RETURN "MechJeb". }
    IF SHIP:SENSORS:ACC:MAG >= 0.05 { RETURN "accelerometer". }
    RETURN "Q-only".
}
