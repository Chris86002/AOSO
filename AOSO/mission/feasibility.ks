// AOSO/mission/feasibility.ks
// Mission feasibility engine. Before a destination is attempted, AOSO
// asks: can I reach it, orbit it, land, take off, refuel, return, abort?
// The answer is FEASIBLE, ORBIT_ONLY, or SKIP -- not "go to Duna because
// the itinerary says so."
//
// dV costs are the well-known stock map (LKO 80-100 km baseline), with a
// configurable margin (FEAS_DV_MARGIN, default 1.15). Transfer cost is
// path-adjusted for "already at a moon" / "already at the destination"
// so a reboot in Mun SOI does not charge another 860 m/s to "get there."
// Surface TWR uses engine MAXTHRUSTAT at that body's sea-level pressure
// so Eve/Tylo refuse landing when the ship cannot leave.
//
// This is the generic engine the grand tour used to inline as a TWR
// check. Every mission benefits from it, not just tour.ks.

GLOBAL AOSO_FEAS_LAST IS LEXICON().

GLOBAL AOSO_FEAS_DV IS LEXICON(
    "Kerbin", LEXICON("transfer_from_lko", 0, "capture", 0, "land", 900, "takeoff", 3400, "return", 0),
    "Mun", LEXICON("transfer_from_lko", 860, "capture", 310, "land", 580, "takeoff", 580, "return", 310),
    "Minmus", LEXICON("transfer_from_lko", 930, "capture", 160, "land", 180, "takeoff", 180, "return", 160),
    "Eve", LEXICON("transfer_from_lko", 1070, "capture", 1330, "land", 1200, "takeoff", 8000, "return", 1330),
    "Gilly", LEXICON("transfer_from_lko", 1740, "capture", 50, "land", 30, "takeoff", 30, "return", 50),
    "Moho", LEXICON("transfer_from_lko", 2760, "capture", 2410, "land", 870, "takeoff", 870, "return", 2410),
    "Duna", LEXICON("transfer_from_lko", 1060, "capture", 610, "land", 1450, "takeoff", 1450, "return", 360),
    "Ike", LEXICON("transfer_from_lko", 1330, "capture", 180, "land", 390, "takeoff", 390, "return", 180),
    "Dres", LEXICON("transfer_from_lko", 1640, "capture", 665, "land", 430, "takeoff", 430, "return", 665),
    "Jool", LEXICON("transfer_from_lko", 1920, "capture", 160, "land", 0, "takeoff", 0, "return", 160),
    "Laythe", LEXICON("transfer_from_lko", 2860, "capture", 940, "land", 2900, "takeoff", 3100, "return", 940),
    "Vall", LEXICON("transfer_from_lko", 2540, "capture", 860, "land", 860, "takeoff", 860, "return", 860),
    "Tylo", LEXICON("transfer_from_lko", 2810, "capture", 1100, "land", 2270, "takeoff", 2270, "return", 1100),
    "Bop", LEXICON("transfer_from_lko", 2820, "capture", 900, "land", 230, "takeoff", 230, "return", 900),
    "Pol", LEXICON("transfer_from_lko", 2720, "capture", 800, "land", 130, "takeoff", 130, "return", 800),
    "Eeloo", LEXICON("transfer_from_lko", 2020, "capture", 680, "land", 620, "takeoff", 620, "return", 680),
    "Sun", LEXICON("transfer_from_lko", 6000, "capture", 0, "land", 0, "takeoff", 0, "return", 0)
).

FUNCTION aoso_feas_body_stat {
    PARAMETER body_name.
    PARAMETER key_name.
    PARAMETER default_value IS 0.
    IF AOSO_FEAS_DV:HASKEY(body_name) {
        LOCAL entry IS AOSO_FEAS_DV[body_name].
        IF entry:HASKEY(key_name) { RETURN entry[key_name]. }
    }
    RETURN default_value.
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
            SET cost TO cost + aoso_feas_body_stat(to_name, "transfer_from_lko", 400).
        } ELSE {
            SET cost TO cost + aoso_feas_body_stat(to_name, "capture", 400).
        }
    } ELSE {
        SET cost TO cost + aoso_feas_body_stat(to_name, "transfer_from_lko", 800).
        SET cost TO cost + aoso_feas_body_stat(to_name, "capture", 200).
    }

    RETURN cost.
}

FUNCTION aoso_feas_step {
    PARAMETER step_name.
    PARAMETER dv_need.
    PARAMETER dv_have.
    PARAMETER passed.
    PARAMETER note IS "".
    RETURN LEXICON("name", step_name, "dv", dv_need, "available", dv_have, "pass", passed, "note", note).
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
    LOCAL has_isru IS aoso_profile_capable("can_isru").
    LOCAL has_heat IS FALSE.
    IF AOSO_PROFILE:HASKEY("mobility") {
        SET has_legs TO AOSO_PROFILE["mobility"]["has_legs"].
        SET has_chutes TO AOSO_PROFILE["mobility"]["has_parachutes"].
    }
    IF AOSO_PROFILE:HASKEY("mission_hw") {
        SET has_heat TO AOSO_PROFILE["mission_hw"]["has_heatshield"].
    }

    LOCAL dest_atmo IS FALSE.
    IF dest_name <> "Sun" {
        LOCAL dest_ref IS BODY(dest_name).
        IF dest_ref:ATM:EXISTS { SET dest_atmo TO TRUE. }
    }

    LOCAL can_reach IS mission_dv >= transfer_dv.
    LOCAL can_orbit IS FALSE.
    IF can_reach { SET can_orbit TO TRUE. }
    IF from_name = dest_name { SET can_reach TO TRUE. SET can_orbit TO TRUE. }

    LOCAL land_ok_hw IS FALSE.
    IF has_legs { SET land_ok_hw TO TRUE. }
    IF dest_atmo {
        IF has_chutes { SET land_ok_hw TO TRUE. }
    }

    LOCAL can_land IS FALSE.
    LOCAL land_note IS "".
    IF dest_name = "Jool" OR dest_name = "Sun" {
        SET land_note TO "no surface".
    } ELSE IF NOT land_ok_hw {
        SET land_note TO "no legs/chutes".
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

    LOCAL can_takeoff IS FALSE.
    LOCAL takeoff_note IS "".
    IF dest_name = "Jool" OR dest_name = "Sun" {
        SET takeoff_note TO "no surface".
    } ELSE IF surface_twr < min_twr {
        SET takeoff_note TO "surface TWR " + ROUND(surface_twr, 2) + " < " + min_twr.
    } ELSE IF takeoff_dv > mission_dv AND from_name <> dest_name {
        // takeoff is funded after landing; compare against remaining after
        // getting there, not the full mission_dv. Approximate: leftover
        // after transfer.
        LOCAL leftover IS mission_dv - transfer_dv.
        IF leftover < takeoff_dv {
            SET takeoff_note TO "takeoff " + ROUND(takeoff_dv, 0) + " > leftover " + ROUND(leftover, 0).
        } ELSE {
            SET can_takeoff TO TRUE.
            SET takeoff_note TO "TWR " + ROUND(surface_twr, 2).
        }
    } ELSE {
        SET can_takeoff TO TRUE.
        SET takeoff_note TO "TWR " + ROUND(surface_twr, 2).
    }

    LOCAL can_refuel IS FALSE.
    IF has_isru {
        IF dest_name <> "Jool" {
            IF dest_name <> "Sun" { SET can_refuel TO TRUE. }
        }
    }

    LOCAL can_return IS mission_dv >= return_dv.
    IF dest_name = home_name { SET can_return TO TRUE. }

    LOCAL can_abort IS aoso_budget_get("abort_dv", 0) > 0.

    LOCAL result_name IS "SKIP".
    LOCAL reason IS "".
    IF NOT can_reach {
        SET result_name TO "SKIP".
        SET reason TO "transfer " + ROUND(transfer_dv, 0) + " > mission dV " + ROUND(mission_dv, 0).
    } ELSE IF can_land AND can_takeoff {
        SET result_name TO "FEASIBLE".
        SET reason TO "land+takeoff ok".
    } ELSE {
        SET result_name TO "ORBIT_ONLY".
        IF NOT can_land {
            SET reason TO "orbit only: " + land_note.
        } ELSE {
            SET reason TO "orbit only: " + takeoff_note.
        }
    }

    LOCAL steps IS LIST().
    steps:ADD(aoso_feas_step("TRANSFER", transfer_dv, mission_dv, can_reach, "")).
    steps:ADD(aoso_feas_step("CAPTURE", capture_dv, mission_dv, can_orbit, "")).
    steps:ADD(aoso_feas_step("LAND", land_dv, mission_dv, can_land, land_note)).
    steps:ADD(aoso_feas_step("TAKEOFF", takeoff_dv, mission_dv, can_takeoff, takeoff_note)).
    steps:ADD(aoso_feas_step("REFUEL", 0, mission_dv, can_refuel, "")).
    steps:ADD(aoso_feas_step("RETURN", return_dv, mission_dv, can_return, "")).
    steps:ADD(aoso_feas_step("RESERVE", reserve_dv, mission_dv, mission_dv >= 0, "")).

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
    FOR step IN report["steps"] {
        LOCAL mark IS "FAIL".
        IF step["pass"] { SET mark TO "PASS". }
        LOCAL note_txt IS "".
        IF step["note"] <> "" { SET note_txt TO "  " + step["note"]. }
        aoso_log_info("FEAS", "  " + step["name"] + "  dv=" + ROUND(step["dv"], 0) +
            "  have=" + ROUND(step["available"], 0) + "  " + mark + note_txt).
    }
}

FUNCTION aoso_feas_result {
    PARAMETER dest_name.
    LOCAL report IS aoso_feas_evaluate(dest_name).
    RETURN report["result"].
}
