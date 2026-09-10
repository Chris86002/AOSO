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

FUNCTION aoso_perf_time_to_apoapsis {
    RETURN aoso_orbit_eta_apoapsis().
}

FUNCTION aoso_perf_time_to_periapsis {
    RETURN ETA:PERIAPSIS.
}

// Seconds until the current stage's tracked propellant (everything but
// ElectricCharge pooled to this stage) is exhausted at the current mass flow
// rate of the ignited, non-flamed-out engines. Returns 0 if nothing is
// burning.
FUNCTION aoso_perf_stage_burn_time_remaining {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL total_flow IS 0.
    FOR e IN elist {
        IF e:IGNITION AND NOT e:FLAMEOUT { SET total_flow TO total_flow + e:MASSFLOW. }
    }
    IF total_flow <= 0 { RETURN 0. }

    LOCAL propellant_mass IS 0.
    FOR r IN STAGE:RESOURCES {
        IF r:NAME <> "ElectricCharge" { SET propellant_mass TO propellant_mass + (r:AMOUNT * r:DENSITY). }
    }
    RETURN propellant_mass / total_flow.
}

// Estimated burn time (s) to achieve a given delta-v with the currently
// ignited engines, via the constant-thrust rocket equation:
//   t = (m0 * Isp * g0 / F) * (1 - e^(-dv / (Isp * g0)))
// Uses current-atmosphere ISP/thrust since that is what will actually be
// burned; callers planning a vacuum burn should call this once on-orbit.
FUNCTION aoso_perf_burn_time_for_dv {
    PARAMETER dv.

    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
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

    RETURN (SHIP:MASS * ve / thrust_sum) * (1 - CONSTANT:E ^ (-dv / ve)).
}
