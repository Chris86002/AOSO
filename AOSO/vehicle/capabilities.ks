// AOSO/vehicle/capabilities.ks
// Thrust-to-weight plus delta-v. Current-stage dV (STAGE:RESOURCES, lit
// engines) is still what ascent/abort code wants tick-to-tick. The same
// refresh now also walks every remaining engine layer and estimates the
// *whole remaining vehicle* vacuum dV by the rocket equation, so the
// vehicle-intelligence layer (profile / budget / feasibility) can plan a
// tour against usable mission dV instead of pretending the active stage
// is the ship.
//
// Stage layers reuse vehicle/parts.ks's DECOUPLEDIN model: higher
// DECOUPLEDIN separates first (boosters), -1 is the never-jettisoned
// core. Propellant mass on a layer is (part MASS - DRYMASS) of every
// non-ElectricCharge resource on parts that drop in that stage. After a
// layer burns, its dry hardware is dropped and the next layer's wet mass
// is whatever remains. This is still an estimate -- fuel lines that cross
// stages and asparagus plumbing are not simulated part-by-part -- but it
// is the remaining vehicle, not just the active stage.

GLOBAL AOSO_CAPS IS LEXICON().

FUNCTION aoso_capabilities_is_propellant {
    PARAMETER res_name.
    IF res_name = "ElectricCharge" { RETURN FALSE. }
    IF res_name = "Ore" { RETURN FALSE. }
    IF res_name = "Ablator" { RETURN FALSE. }
    IF res_name = "IntakeAir" { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_capabilities_refresh {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL plist IS LIST().
    LIST PARTS IN plist.

    LOCAL lit IS LIST().
    FOR e IN elist {
        IF e:IGNITION AND NOT e:FLAMEOUT { lit:ADD(e). }
    }

    LOCAL g_now IS SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
    LOCAL twr IS 0.
    IF SHIP:MASS > 0 { SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * g_now). }

    LOCAL wet_mass IS SHIP:MASS.
    LOCAL propellant_mass IS 0.
    FOR res_item IN STAGE:RESOURCES {
        IF aoso_capabilities_is_propellant(res_item:NAME) {
            SET propellant_mass TO propellant_mass + (res_item:AMOUNT * res_item:DENSITY).
        }
    }
    LOCAL dry_mass IS wet_mass - propellant_mass.
    IF dry_mass <= 0 { SET dry_mass TO wet_mass. }

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

    LOCAL breakdown IS aoso_capabilities_stage_breakdown(plist, elist).
    LOCAL dv_total_vac IS breakdown["dv_total_vac"].
    LOCAL dv_unusable IS breakdown["dv_unusable"].
    LOCAL fuel_types IS breakdown["fuel_types"].

    SET AOSO_CAPS TO LEXICON(
        "twr", twr,
        "active_engine_count", lit:LENGTH,
        "available_thrust", SHIP:AVAILABLETHRUST,
        "max_thrust", SHIP:MAXTHRUST,
        "wet_mass", wet_mass,
        "dry_mass_est", dry_mass,
        "dv_current_stage", dv_now,
        "dv_current_stage_vac", dv_vac,
        "dv_total_vac", dv_total_vac,
        "dv_unusable", dv_unusable,
        "isp_now", isp_now,
        "isp_vac", isp_vac,
        "stages", breakdown["stages"],
        "fuel_types", fuel_types,
        "refreshed_at", TIME:SECONDS
    ).

    aoso_log_debug("CAPS", "TWR=" + ROUND(twr, 2) + " dV(stage)=" + ROUND(dv_now, 0) +
        " dV(all,vac)=" + ROUND(dv_total_vac, 0) + " unusable=" + ROUND(dv_unusable, 0)).

    RETURN AOSO_CAPS.
}

// Walk every remaining engine/part layer and estimate vacuum dV of the
// whole stack. Returns a lexicon of stages (boosters first) plus totals.
FUNCTION aoso_capabilities_stage_breakdown {
    PARAMETER plist.
    PARAMETER elist.

    LOCAL groups IS LEXICON().
    LOCAL fuel_types IS LIST().

    FOR p IN plist {
        LOCAL dkey IS "" + p:DECOUPLEDIN.
        IF NOT groups:HASKEY(dkey) {
            SET groups[dkey] TO LEXICON(
                "decoupled_in", p:DECOUPLEDIN,
                "engines", 0,
                "thrust_vac", 0,
                "isp_vac_weighted", 0,
                "prop_mass", 0,
                "dry_mass", 0,
                "wet_mass", 0
            ).
        }
        SET groups[dkey]["wet_mass"] TO groups[dkey]["wet_mass"] + p:MASS.
        SET groups[dkey]["dry_mass"] TO groups[dkey]["dry_mass"] + p:DRYMASS.
        FOR res_item IN p:RESOURCES {
            IF aoso_capabilities_is_propellant(res_item:NAME) {
                SET groups[dkey]["prop_mass"] TO groups[dkey]["prop_mass"] + (res_item:AMOUNT * res_item:DENSITY).
                LOCAL already IS FALSE.
                FOR ft IN fuel_types {
                    IF ft = res_item:NAME { SET already TO TRUE. }
                }
                IF NOT already {
                    IF res_item:AMOUNT > 0 { fuel_types:ADD(res_item:NAME). }
                }
            }
        }
    }

    FOR e IN elist {
        LOCAL dkey IS "" + e:DECOUPLEDIN.
        IF NOT groups:HASKEY(dkey) {
            SET groups[dkey] TO LEXICON(
                "decoupled_in", e:DECOUPLEDIN,
                "engines", 0,
                "thrust_vac", 0,
                "isp_vac_weighted", 0,
                "prop_mass", 0,
                "dry_mass", 0,
                "wet_mass", 0
            ).
        }
        LOCAL thrust_vac IS e:MAXTHRUSTAT(0).
        LOCAL isp_here IS e:VACUUMISP.
        SET groups[dkey]["engines"] TO groups[dkey]["engines"] + 1.
        SET groups[dkey]["thrust_vac"] TO groups[dkey]["thrust_vac"] + thrust_vac.
        SET groups[dkey]["isp_vac_weighted"] TO groups[dkey]["isp_vac_weighted"] + (isp_here * thrust_vac).
    }

    LOCAL unsorted IS LIST().
    FOR k IN groups:KEYS { unsorted:ADD(groups[k]). }
    LOCAL layers IS LIST().
    UNTIL unsorted:LENGTH = 0 {
        LOCAL best_idx IS 0.
        FOR i IN RANGE(0, unsorted:LENGTH) {
            IF unsorted[i]["decoupled_in"] > unsorted[best_idx]["decoupled_in"] { SET best_idx TO i. }
        }
        layers:ADD(unsorted[best_idx]).
        unsorted:REMOVE(best_idx).
    }

    LOCAL remaining_mass IS SHIP:MASS.
    IF remaining_mass <= 0 { SET remaining_mass TO 0.001. }
    LOCAL dv_total_vac IS 0.
    LOCAL dv_unusable IS 0.

    FOR i IN RANGE(0, layers:LENGTH) {
        LOCAL layer IS layers[i].
        LOCAL d IS layer["decoupled_in"].
        LOCAL role IS "STAGE".
        IF d < 0 {
            SET role TO "CORE".
        } ELSE IF i = 0 {
            SET role TO "BOOSTER".
        }
        SET layer["role"] TO role.

        LOCAL isp_vac IS 0.
        IF layer["thrust_vac"] > 0 {
            SET isp_vac TO layer["isp_vac_weighted"] / layer["thrust_vac"].
        }
        SET layer["isp_vac"] TO isp_vac.

        LOCAL prop_mass IS layer["prop_mass"].
        IF prop_mass > remaining_mass * 0.9 { SET prop_mass TO remaining_mass * 0.9. }

        LOCAL dv_here IS 0.
        LOCAL usable IS FALSE.
        IF layer["engines"] > 0 AND prop_mass > 0.01 AND isp_vac > 0 {
            LOCAL mass_after IS remaining_mass - prop_mass.
            IF mass_after < remaining_mass * 0.05 { SET mass_after TO remaining_mass * 0.05. }
            IF mass_after < 0.001 { SET mass_after TO 0.001. }
            IF remaining_mass > mass_after {
                SET dv_here TO isp_vac * AOSO_CONST["G0"] * LN(remaining_mass / mass_after).
            }
            SET remaining_mass TO mass_after.
            LOCAL twr_here IS 0.
            IF remaining_mass > 0 {
                SET twr_here TO layer["thrust_vac"] / (remaining_mass * AOSO_CONST["G0"]).
            }
            SET layer["twr_vac"] TO twr_here.
            IF twr_here >= 0.12 { SET usable TO TRUE. }
            SET dv_total_vac TO dv_total_vac + dv_here.
            IF NOT usable { SET dv_unusable TO dv_unusable + dv_here. }
        } ELSE {
            SET layer["twr_vac"] TO 0.
        }
        SET layer["dv_vac"] TO dv_here.
        SET layer["usable"] TO usable.

        IF d >= 0 {
            SET remaining_mass TO remaining_mass - layer["dry_mass"].
            IF remaining_mass < 0.001 { SET remaining_mass TO 0.001. }
        }
    }

    RETURN LEXICON(
        "stages", layers,
        "dv_total_vac", dv_total_vac,
        "dv_unusable", dv_unusable,
        "fuel_types", fuel_types
    ).
}

FUNCTION aoso_caps_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_CAPS:HASKEY(key) { RETURN AOSO_CAPS[key]. }
    RETURN default_value.
}
