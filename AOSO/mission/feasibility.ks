// AOSO/mission/feasibility.ks
// Mission feasibility engine. Before a destination is attempted, AOSO
// asks: can I reach it, orbit it, land, take off, refuel, return, abort?
// The answer is FEASIBLE, ORBIT_ONLY, or SKIP -- not "go to Duna because
// the itinerary says so."
//
// dV costs and landing/escape difficulty live in world/body.ks so the
// vessel model and the world model feed one feasibility engine. Transfer
// cost is path-adjusted for "already at a moon" / "already at the
// destination" so a reboot in Mun SOI does not charge another 860 m/s.
// Surface TWR uses engine MAXTHRUSTAT at that body's sea-level pressure
// so Eve/Tylo refuse landing when the ship cannot leave.
//
// This is the generic engine the grand tour used to inline as a TWR
// check. Every mission benefits from it, not just tour.ks.

GLOBAL AOSO_FEAS_LAST IS LEXICON().

FUNCTION aoso_feas_body_stat {
    PARAMETER body_name.
    PARAMETER key_name.
    PARAMETER default_value IS 0.
    RETURN aoso_world_body_stat(body_name, key_name, default_value).
}

FUNCTION aoso_feas_planet_of {
    PARAMETER body_name.
    IF body_name = "Sun" { RETURN "Sun". }
    LOCAL entry IS aoso_body_database_get(body_name).
    IF NOT entry:HASKEY("PARENT") { RETURN body_name. }
    LOCAL parent_name IS entry["PARENT"].
    IF parent_name = "" { RETURN body_name. }
    IF parent_name = "Sun" { RETURN body_name. }
    RETURN parent_name.
}

FUNCTION aoso_feas_land_cost {
    PARAMETER body_name.
    LOCAL raw IS aoso_feas_body_stat(body_name, "land", 0).
    IF raw <= 0 { RETURN 0. }
    LOCAL has_chutes IS aoso_profile_capable("can_land").
    IF AOSO_PROFILE:HASKEY("mobility") {
        SET has_chutes TO AOSO_PROFILE["mobility"]["has_parachutes"].
    }
    LOCAL body_ref IS BODY(body_name).
    IF body_ref:ATM:EXISTS {
        IF has_chutes {
            IF body_name = "Eve" { RETURN 400. }
            IF body_name = "Laythe" { RETURN 400. }
            IF body_name = "Duna" { RETURN 400. }
            IF body_name = "Kerbin" { RETURN 150. }
            RETURN raw * 0.4.
        }
    }
    RETURN raw.
}

FUNCTION aoso_feas_takeoff_cost {
    PARAMETER body_name.
    RETURN aoso_feas_body_stat(body_name, "takeoff", 0).
}

FUNCTION aoso_feas_return_cost {
    PARAMETER body_name.
    LOCAL home_name IS aoso_config_get("HOME_BODY", "Kerbin").
    IF body_name = home_name { RETURN 0. }
    LOCAL raw IS aoso_feas_body_stat(body_name, "return", 0).
    IF raw > 0 { RETURN raw. }
    RETURN aoso_feas_body_stat(aoso_feas_planet_of(body_name), "return", 800).
}

FUNCTION aoso_feas_moon_from_parent {
    PARAMETER moon_name.
    LOCAL planet_name IS aoso_feas_planet_of(moon_name).
    IF moon_name = planet_name { RETURN 0. }
    LOCAL moon_lko IS aoso_feas_body_stat(moon_name, "transfer_from_lko", 400).
    LOCAL planet_lko IS aoso_feas_body_stat(planet_name, "transfer_from_lko", 1500).
    LOCAL hop IS moon_lko - planet_lko.
    IF hop < 250 {
        SET hop TO aoso_feas_body_stat(moon_name, "capture", 400) + 250.
    }
    RETURN hop.
}

FUNCTION aoso_feas_transfer_cost {
    PARAMETER from_name.
    PARAMETER to_name.
    IF from_name = to_name { RETURN 0. }

    LOCAL from_planet IS aoso_feas_planet_of(from_name).
    LOCAL to_planet IS aoso_feas_planet_of(to_name).
    LOCAL cost IS 0.

    IF from_name <> from_planet {
        SET cost TO cost + aoso_feas_body_stat(from_name, "return", 300).
    }

    IF from_planet <> to_planet {
        IF from_planet = "Kerbin" {
            SET cost TO cost + aoso_feas_body_stat(to_planet, "transfer_from_lko", 1500).
        } ELSE IF to_planet = "Kerbin" {
            SET cost TO cost + aoso_feas_body_stat(from_planet, "return", 1500).
        } ELSE {
            SET cost TO cost + aoso_feas_body_stat(from_planet, "return", 1500).
            SET cost TO cost + aoso_feas_body_stat(to_planet, "transfer_from_lko", 1500).
        }
        IF to_name <> to_planet {
            SET cost TO cost + aoso_feas_body_stat(to_planet, "capture", 200).
            SET cost TO cost + aoso_feas_moon_from_parent(to_name).
        } ELSE {
            SET cost TO cost + aoso_feas_body_stat(to_name, "capture", 400).
        }
    } ELSE {
        IF to_name <> to_planet {
            SET cost TO cost + aoso_feas_moon_from_parent(to_name).
            SET cost TO cost + aoso_feas_body_stat(to_name, "capture", 200).
        } ELSE {
            SET cost TO cost + aoso_feas_body_stat(to_name, "transfer_from_lko", 800).
            SET cost TO cost + aoso_feas_body_stat(to_name, "capture", 200).
        }
    }

    RETURN cost.
}

// Propellant mass in tonnes from live tank amounts or capacities.
FUNCTION aoso_feas_propellant_mass {
    PARAMETER use_capacity.
    LOCAL mass_t IS 0.
    FOR res_row IN SHIP:RESOURCES {
        LOCAL n IS res_row:NAME.
        LOCAL qty IS res_row:AMOUNT.
        IF use_capacity { SET qty TO res_row:CAPACITY. }
        IF n = "LiquidFuel" { SET mass_t TO mass_t + qty * 0.005. }
        IF n = "Oxidizer" { SET mass_t TO mass_t + qty * 0.005. }
        IF n = "MonoPropellant" { SET mass_t TO mass_t + qty * 0.004. }
        IF n = "XenonGas" { SET mass_t TO mass_t + qty * 0.0001. }
        IF n = "SolidFuel" { SET mass_t TO mass_t + qty * 0.0075. }
    }
    RETURN mass_t.
}

// Vacuum dV after ISRU fills tanks to REFUEL_TARGET_PCT. Scales the live
// rocket-equation dV by ln(m_full/m_dry) / ln(m_now/m_dry).
FUNCTION aoso_feas_full_tank_dv {
    LOCAL vac_now IS aoso_caps_get("dv_total_vac", 0).
    LOCAL fuel_now IS aoso_feas_propellant_mass(FALSE).
    LOCAL fuel_cap IS aoso_feas_propellant_mass(TRUE).
    IF fuel_now < 0.01 { RETURN vac_now. }
    IF fuel_cap <= fuel_now * 1.02 { RETURN vac_now. }
    LOCAL m_now IS SHIP:MASS.
    LOCAL m_dry IS m_now - fuel_now.
    IF m_dry < 0.1 { RETURN vac_now. }
    LOCAL fill IS aoso_config_get("REFUEL_TARGET_PCT", 95) / 100.
    LOCAL m_full IS m_dry + fuel_cap * fill.
    IF m_now <= m_dry { RETURN vac_now. }
    LOCAL ln_now IS LN(m_now / m_dry).
    IF ln_now < 0.01 { RETURN vac_now. }
    RETURN vac_now * LN(m_full / m_dry) / ln_now.
}

// TRUE when an ore body is cheap enough to reach with current mission dV
// so later hops can be priced against a full tank.
FUNCTION aoso_feas_can_refuel_enroute {
    PARAMETER mission_dv.
    PARAMETER margin.
    IF NOT aoso_profile_capable("can_isru") { RETURN FALSE. }
    IF aoso_world_has_ore(SHIP:BODY:NAME) { RETURN TRUE. }
    LOCAL stops IS LIST("Minmus", "Mun", "Gilly", "Ike", "Dres", "Pol", "Bop", "Vall", "Eeloo").
    FOR stop_name IN stops {
        IF aoso_world_has_ore(stop_name) {
            LOCAL c IS aoso_feas_transfer_cost(SHIP:BODY:NAME, stop_name) * margin.
            IF c <= mission_dv { RETURN TRUE. }
        }
    }
    RETURN FALSE.
}

FUNCTION aoso_feas_step {
    PARAMETER step_name.
    PARAMETER dv_need.
    PARAMETER dv_have.
    PARAMETER passed.
    // "note" is a kOS builtin (NOTE()), so the parameter cannot be named that.
    PARAMETER remark IS "".
    RETURN LEXICON("name", step_name, "dv", dv_need, "available", dv_have, "pass", passed, "note", remark).
}

FUNCTION aoso_feas_evaluate {
    PARAMETER dest_name.

    IF NOT AOSO_PROFILE:HASKEY("capabilities") {
        aoso_profile_refresh("feasibility").
    }
    IF NOT AOSO_BUDGET:HASKEY("mission_dv") {
        aoso_budget_refresh().
    }

    LOCAL margin IS aoso_config_get("FEAS_DV_MARGIN", 1.15).
    LOCAL min_twr IS aoso_config_get("TOUR_MIN_LAND_TWR", 1.4).
    LOCAL mission_dv IS aoso_budget_get("mission_dv", 0).
    LOCAL from_name IS SHIP:BODY:NAME.
    LOCAL home_name IS aoso_config_get("HOME_BODY", "Kerbin").

    LOCAL transfer_dv IS aoso_feas_transfer_cost(from_name, dest_name) * margin.
    LOCAL capture_dv IS 0.
    IF from_name <> dest_name {
        SET capture_dv TO aoso_feas_body_stat(dest_name, "capture", 0) * margin.
    }
    LOCAL land_dv IS aoso_feas_land_cost(dest_name) * margin.
    LOCAL takeoff_dv IS aoso_feas_takeoff_cost(dest_name) * margin.
    LOCAL return_dv IS aoso_feas_return_cost(dest_name) * margin.
    LOCAL reserve_dv IS aoso_budget_get("reserve_dv", 0).

    LOCAL surface_twr IS 0.
    IF dest_name <> "Sun" {
        IF dest_name <> "Jool" { SET surface_twr TO aoso_profile_surface_twr(dest_name). }
    }

    LOCAL has_legs IS FALSE.
    LOCAL has_chutes IS FALSE.
    LOCAL has_wheels IS FALSE.
    LOCAL has_isru IS aoso_profile_capable("can_isru").
    LOCAL has_heat IS FALSE.
    IF AOSO_PROFILE:HASKEY("mobility") {
        SET has_legs TO AOSO_PROFILE["mobility"]["has_legs"].
        SET has_chutes TO AOSO_PROFILE["mobility"]["has_parachutes"].
        IF AOSO_PROFILE["mobility"]:HASKEY("has_wheels") {
            SET has_wheels TO AOSO_PROFILE["mobility"]["has_wheels"].
        }
    }
    IF AOSO_PROFILE:HASKEY("mission_hw") {
        SET has_heat TO AOSO_PROFILE["mission_hw"]["has_heatshield"].
    }

    LOCAL dest_atmo IS FALSE.
    IF dest_name <> "Sun" {
        LOCAL dest_ref IS BODY(dest_name).
        IF dest_ref:ATM:EXISTS { SET dest_atmo TO TRUE. }
    }

    LOCAL can_refuel IS FALSE.
    IF has_isru {
        IF aoso_world_has_ore(dest_name) { SET can_refuel TO TRUE. }
    }

    LOCAL full_tank IS aoso_feas_full_tank_dv().
    LOCAL tank_mission IS full_tank - reserve_dv.
    IF tank_mission < 0 { SET tank_mission TO 0. }
    LOCAL hop_budget IS mission_dv.
    LOCAL isru_enroute IS aoso_feas_can_refuel_enroute(mission_dv, margin).
    IF isru_enroute {
        IF tank_mission > hop_budget { SET hop_budget TO tank_mission. }
    }
    IF can_refuel {
        IF tank_mission > hop_budget { SET hop_budget TO tank_mission. }
    }

    LOCAL parent_name IS aoso_feas_planet_of(dest_name).
    LOCAL reach_note IS "".
    LOCAL can_reach IS FALSE.
    IF hop_budget >= transfer_dv {
        SET can_reach TO TRUE.
        IF isru_enroute {
            SET reach_note TO "direct " + ROUND(transfer_dv, 0) + " <= tank " + ROUND(hop_budget, 0).
        } ELSE {
            SET reach_note TO "direct " + ROUND(transfer_dv, 0) + " <= mission " + ROUND(mission_dv, 0).
        }
    } ELSE {
        IF dest_name <> parent_name {
            IF has_isru {
                LOCAL parent_xfer IS aoso_feas_transfer_cost(from_name, parent_name) * margin.
                LOCAL moon_hop IS (aoso_feas_moon_from_parent(dest_name) + aoso_feas_body_stat(dest_name, "capture", 200)) * margin.
                IF parent_xfer <= hop_budget {
                    IF moon_hop <= hop_budget {
                        SET can_reach TO TRUE.
                        SET reach_note TO "via " + parent_name + " then ISRU hop " + ROUND(moon_hop, 0) + " <= tank " + ROUND(hop_budget, 0).
                    } ELSE {
                        SET reach_note TO "moon hop " + ROUND(moon_hop, 0) + " > tank " + ROUND(hop_budget, 0) + " even after ISRU at " + parent_name.
                    }
                } ELSE {
                    SET reach_note TO "parent " + parent_name + " " + ROUND(parent_xfer, 0) + " > tank " + ROUND(hop_budget, 0) + " even after ISRU".
                }
            } ELSE {
                SET reach_note TO "transfer " + ROUND(transfer_dv, 0) + " > mission dV " + ROUND(mission_dv, 0) + " (no ISRU)".
            }
        } ELSE {
            IF has_isru {
                SET reach_note TO "transfer " + ROUND(transfer_dv, 0) + " > ISRU tank " + ROUND(hop_budget, 0).
            } ELSE {
                SET reach_note TO "transfer " + ROUND(transfer_dv, 0) + " > mission dV " + ROUND(mission_dv, 0).
            }
        }
    }
    LOCAL can_orbit IS FALSE.
    IF can_reach { SET can_orbit TO TRUE. }
    IF from_name = dest_name { SET can_reach TO TRUE. SET can_orbit TO TRUE. }

    LOCAL land_ok_hw IS FALSE.
    IF has_legs { SET land_ok_hw TO TRUE. }
    IF has_wheels { SET land_ok_hw TO TRUE. }
    IF dest_atmo {
        IF has_chutes { SET land_ok_hw TO TRUE. }
    }

    LOCAL can_land IS FALSE.
    LOCAL land_note IS "".
    IF dest_name = "Jool" OR dest_name = "Sun" {
        SET land_note TO "no surface".
    } ELSE IF NOT land_ok_hw {
        SET land_note TO "no legs/wheels/chutes".
    } ELSE IF surface_twr < 1.05 {
        SET land_note TO "surface TWR " + ROUND(surface_twr, 2) + " < 1.05".
    } ELSE IF dest_atmo {
        IF dest_name = "Eve" {
            IF NOT has_heat {
                SET land_note TO "Eve reentry, no heat shield".
            } ELSE {
                SET can_land TO TRUE.
            }
        } ELSE {
            SET can_land TO TRUE.
        }
    } ELSE {
        SET can_land TO TRUE.
    }
    IF can_land { SET land_note TO "TWR " + ROUND(surface_twr, 2). }

    LOCAL takeoff_budget IS mission_dv.
    IF can_refuel {
        IF hop_budget > takeoff_budget { SET takeoff_budget TO hop_budget. }
    }
    LOCAL can_takeoff IS FALSE.
    LOCAL takeoff_note IS "".
    IF dest_name = "Jool" OR dest_name = "Sun" {
        SET takeoff_note TO "no surface".
    } ELSE IF surface_twr < min_twr {
        SET takeoff_note TO "surface TWR " + ROUND(surface_twr, 2) + " < " + min_twr.
    } ELSE IF takeoff_dv > takeoff_budget {
        SET takeoff_note TO "takeoff " + ROUND(takeoff_dv, 0) + " > budget " + ROUND(takeoff_budget, 0).
        IF can_refuel { SET takeoff_note TO takeoff_note + " even after ISRU". }
    } ELSE {
        SET can_takeoff TO TRUE.
        SET takeoff_note TO "TWR " + ROUND(surface_twr, 2).
        IF can_refuel { SET takeoff_note TO takeoff_note + " ISRU tank". }
    }

    LOCAL return_budget IS mission_dv.
    IF can_refuel {
        IF hop_budget > return_budget { SET return_budget TO hop_budget. }
    }
    LOCAL can_return IS FALSE.
    IF return_budget >= return_dv { SET can_return TO TRUE. }
    IF dest_name = home_name { SET can_return TO TRUE. }

    LOCAL can_abort IS aoso_budget_get("abort_dv", 0) > 0.

    LOCAL result_name IS "SKIP".
    LOCAL reason IS "".
    IF NOT can_reach {
        SET result_name TO "SKIP".
        SET reason TO reach_note.
    } ELSE IF can_land AND can_takeoff {
        SET result_name TO "FEASIBLE".
        SET reason TO "land+takeoff ok".
        IF can_refuel { SET reason TO reason + ", ISRU refuel to full tank". }
    } ELSE {
        SET result_name TO "ORBIT_ONLY".
        IF NOT can_land {
            SET reason TO "orbit only: " + land_note.
        } ELSE {
            SET reason TO "orbit only: " + takeoff_note.
        }
    }

    LOCAL steps IS LIST().
    steps:ADD(aoso_feas_step("TRANSFER", transfer_dv, hop_budget, can_reach, reach_note)).
    steps:ADD(aoso_feas_step("CAPTURE", capture_dv, hop_budget, can_orbit, "")).
    steps:ADD(aoso_feas_step("LAND", land_dv, hop_budget, can_land, land_note)).
    steps:ADD(aoso_feas_step("TAKEOFF", takeoff_dv, takeoff_budget, can_takeoff, takeoff_note)).
    steps:ADD(aoso_feas_step("REFUEL", 0, hop_budget, can_refuel, "")).
    steps:ADD(aoso_feas_step("RETURN", return_dv, return_budget, can_return, "")).
    steps:ADD(aoso_feas_step("RESERVE", reserve_dv, hop_budget, hop_budget >= 0, "")).

    LOCAL report IS LEXICON(
        "body", dest_name,
        "from", from_name,
        "result", result_name,
        "reason", reason,
        "can_reach", can_reach,
        "can_orbit", can_orbit,
        "can_land", can_land,
        "can_takeoff", can_takeoff,
        "can_refuel", can_refuel,
        "can_return", can_return,
        "can_abort", can_abort,
        "transfer_dv", transfer_dv,
        "capture_dv", capture_dv,
        "land_dv", land_dv,
        "takeoff_dv", takeoff_dv,
        "return_dv", return_dv,
        "reserve_dv", reserve_dv,
        "mission_dv", mission_dv,
        "full_tank_dv", full_tank,
        "hop_budget", hop_budget,
        "isru_enroute", isru_enroute,
        "surface_twr", surface_twr,
        "steps", steps,
        "at", TIME:SECONDS
    ).
    SET AOSO_FEAS_LAST TO report.
    RETURN report.
}

FUNCTION aoso_feas_cached {
    PARAMETER dest_name.
    IF AOSO_FEAS_LAST:HASKEY("body") {
        IF AOSO_FEAS_LAST["body"] = dest_name {
            IF AOSO_FEAS_LAST:HASKEY("at") {
                IF TIME:SECONDS - AOSO_FEAS_LAST["at"] < 10 { RETURN AOSO_FEAS_LAST. }
            }
        }
    }
    LOCAL report IS aoso_feas_evaluate(dest_name).
    SET AOSO_FEAS_LAST TO report.
    RETURN report.
}

FUNCTION aoso_feas_log_report {
    PARAMETER report.
    aoso_log_info("FEAS", report["body"] + " from " + report["from"] +
        "  RESULT=" + report["result"] + "  (" + report["reason"] + ")").
    FOR row IN report["steps"] {
        LOCAL mark IS "FAIL".
        IF row["pass"] { SET mark TO "PASS". }
        LOCAL extra IS "".
        IF row["note"] <> "" { SET extra TO "  " + row["note"]. }
        aoso_log_info("FEAS", "  " + row["name"] + "  dv=" + ROUND(row["dv"], 0) +
            "  have=" + ROUND(row["available"], 0) + "  " + mark + extra).
    }
}

FUNCTION aoso_feas_result {
    PARAMETER dest_name.
    LOCAL report IS aoso_feas_evaluate(dest_name).
    RETURN report["result"].
}
