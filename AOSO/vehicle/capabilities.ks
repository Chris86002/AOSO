// AOSO/vehicle/capabilities.ks
// Derived flight capabilities: thrust-to-weight and a current-stage delta-v
// estimate. This intentionally only estimates the *active* stage, not the
// whole remaining mission -- a correct multi-stage dV breakdown needs to
// simulate stage separations part-by-part, which this project does not
// attempt to reproduce (see core/addons.ks for the same reasoning about not
// guessing at MechJeb/KER internals). Ascent/guidance code that needs a
// closer answer should call aoso_capabilities_refresh() again after each
// staging event so the estimate always reflects the vessel as it is now.

GLOBAL AOSO_CAPS IS LEXICON().

FUNCTION aoso_capabilities_refresh {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.

    LOCAL lit IS LIST().
    FOR e IN elist {
        IF e:IGNITION AND NOT e:FLAMEOUT { lit:ADD(e). }
    }

    LOCAL g IS SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
    LOCAL twr IS 0.
    IF SHIP:MASS > 0 { SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * g). }

    LOCAL wet_mass IS SHIP:MASS.
    LOCAL propellant_mass IS 0.
    FOR r IN STAGE:RESOURCES {
        IF r:NAME <> "ElectricCharge" {
            SET propellant_mass TO propellant_mass + (r:AMOUNT * r:DENSITY).
        }
    }
    LOCAL dry_mass IS wet_mass - propellant_mass.
    IF dry_mass <= 0 { SET dry_mass TO wet_mass. } // no tracked propellant left/no tanks

    LOCAL thrust_sum IS 0.
    LOCAL isp_now_weighted IS 0.
    LOCAL isp_vac_weighted IS 0.
    FOR e IN lit {
        SET thrust_sum TO thrust_sum + e:MAXTHRUST.
        SET isp_now_weighted TO isp_now_weighted + (e:ISP * e:MAXTHRUST).
        SET isp_vac_weighted TO isp_vac_weighted + (e:VACUUMISP * e:MAXTHRUST).
    }

    LOCAL isp_now IS 0.
    LOCAL isp_vac IS 0.
    LOCAL dv_now IS 0.
    LOCAL dv_vac IS 0.
    IF thrust_sum > 0 AND dry_mass > 0 AND wet_mass > dry_mass {
        SET isp_now TO isp_now_weighted / thrust_sum.
        SET isp_vac TO isp_vac_weighted / thrust_sum.
        LOCAL mass_ratio_ln IS LN(wet_mass / dry_mass).
        SET dv_now TO isp_now * AOSO_CONST["G0"] * mass_ratio_ln.
        SET dv_vac TO isp_vac * AOSO_CONST["G0"] * mass_ratio_ln.
    }

    SET AOSO_CAPS TO LEXICON(
        "twr", twr,
        "active_engine_count", lit:LENGTH,
        "available_thrust", SHIP:AVAILABLETHRUST,
        "max_thrust", SHIP:MAXTHRUST,
        "wet_mass", wet_mass,
        "dry_mass_est", dry_mass,
        "dv_current_stage", dv_now,
        "dv_current_stage_vac", dv_vac,
        "refreshed_at", TIME:SECONDS
    ).

    aoso_log_debug("CAPS", "TWR=" + ROUND(twr, 2) + " dV(stage)=" + ROUND(dv_now, 0) +
        " dV(stage,vac)=" + ROUND(dv_vac, 0)).

    RETURN AOSO_CAPS.
}

FUNCTION aoso_caps_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_CAPS:HASKEY(key) { RETURN AOSO_CAPS[key]. }
    RETURN default_value.
}
