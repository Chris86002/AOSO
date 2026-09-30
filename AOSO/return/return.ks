// AOSO/return/return.ks
// Phase 8 (Return): drives the ship home from anywhere in the stock system.
// Classifies the ship's current body relative to the configured HOME_BODY
// (core/config.ks) into one of three cases and dispatches the matching
// departure burn, chaining across however many SOI crossings the trip
// needs:
//   - already home                    -> nothing to do.
//   - a moon of home (Mun, Minmus...)  -> return/moonescape.ks straight at
//                                         home, aimed at a landing periapsis
//                                         for atmospheric bodies (a direct,
//                                         one-burn "free return"), or sea
//                                         level for airless ones, same
//                                         convention landing/deorbit.ks uses.
//   - a sun-orbiting peer of home
//     (Duna, Eve...)                  -> interplanetary/ejection.ks's
//                                         existing dep_body/arr_body burn.
//   - a moon of any other planet
//     (Ike...)                        -> return/moonescape.ks up to that
//                                         planet's parking orbit first; the
//                                         next PLAN cycle then sees a
//                                         sun-orbiting peer and takes the
//                                         interplanetary branch.
// Built on core/state.ks as its own machine (AOSO_RETURN), the same pattern
// flight/ascent.ks and landing/descent.ks use, so it can run standalone or
// alongside them. Burn execution is entirely delegated to
// flight/maneuver.ks's aoso_maneuver_execute_next() -- this file only ever
// decides *which* node to add next.

GLOBAL AOSO_RETURN IS aoso_state_new_machine().

FUNCTION aoso_return_claim_authority {
    aoso_auth_use("return").
    IF aoso_auth_owner("WARP") = "" { aoso_auth_acquire("return", "WARP", 2). }
    IF aoso_auth_owner("STEERING") = "" { aoso_auth_acquire("return", "STEERING", 2). }
    IF aoso_auth_owner("THROTTLE") = "" { aoso_auth_acquire("return", "THROTTLE", 2). }
}

FUNCTION aoso_return_begin_action {
    PARAMETER data.
    SET data["owns_action"] TO FALSE.
    SET data["clear_action"] TO FALSE.
    LOCAL parent_active IS AOSO_ACTION_CUR:ISTYPE("Lexicon").
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        IF AOSO_ACTION_CUR["type"] = "RETURN" {
            SET data["return_action"] TO AOSO_ACTION_CUR.
            SET data["owns_action"] TO TRUE.
            SET data["clear_action"] TO TRUE.
            RETURN.
        }
        aoso_log_info("RETURN", "Keeping parent action " + AOSO_ACTION_CUR["type"] + ".").
    }
    LOCAL projected IS aoso_project_return(aoso_project_state_current()).
    LOCAL pred_dv IS projected["last_cost"].
    LOCAL pred_time IS projected["last_duration"].
    LOCAL home_name IS aoso_return_home_body():NAME.
    LOCAL did IS aoso_decide("RETURN", "route home", home_name, "return controller", SHIP:BODY:NAME + "->" + home_name, pred_dv).
    LOCAL act_r IS aoso_action_create(did, "RETURN", home_name, pred_dv).
    SET act_r["predicted_duration"] TO pred_time.
    IF parent_active {
        aoso_action_begin_detached(act_r).
    } ELSE {
        aoso_action_begin(act_r).
        aoso_action_set_predicted_duration(pred_time).
        SET data["clear_action"] TO TRUE.
    }
    SET data["return_action"] TO act_r.
    SET data["owns_action"] TO TRUE.
}

FUNCTION aoso_return_emit_result {
    PARAMETER data.
    PARAMETER result_status.
    PARAMETER reason.
    IF NOT data:HASKEY("owns_action") { RETURN. }
    IF NOT data["owns_action"] { RETURN. }
    IF NOT data:HASKEY("return_action") { RETURN. }
    LOCAL act_r IS data["return_action"].
    LOCAL res_r IS aoso_result_from_action(act_r, result_status, reason).
    aoso_result_emit(res_r, data["clear_action"]).
    SET data["owns_action"] TO FALSE.
}

FUNCTION aoso_return_home_body {
    RETURN BODY(aoso_config_get("HOME_BODY", "Kerbin")).
}

FUNCTION aoso_return_is_home {
    RETURN SHIP:BODY:NAME = aoso_return_home_body():NAME.
}

// TRUE when SHIP:BODY orbits home directly (e.g. Mun/Minmus while home is
// Kerbin) -- one escape burn away from home itself.
FUNCTION aoso_return_is_moon_of_home {
    IF aoso_return_is_home() { RETURN FALSE. }
    RETURN SHIP:BODY:BODY:NAME = aoso_return_home_body():NAME.
}

// TRUE when SHIP:BODY shares home's own parent (e.g. Duna/Eve while home is
// Kerbin, both sun-orbiting) -- interplanetary/ejection.ks already handles
// this case directly.
FUNCTION aoso_return_shares_home_parent {
    IF aoso_return_is_home() { RETURN FALSE. }
    RETURN SHIP:BODY:BODY:NAME = aoso_return_home_body():BODY:NAME.
}

// Target periapsis altitude (m, around SHIP:BODY:BODY) for an escape burn
// aimed directly at home: deep enough to guarantee atmospheric entry for
// atmospheric bodies (mirroring landing/deorbit.ks's own convention), sea
// level for airless ones so landing/descent.ks's suicide-burn logic is
// guaranteed a trajectory that actually reaches the ground.
FUNCTION aoso_return_home_arrival_periapsis_alt {
    LOCAL home IS aoso_return_home_body().
    IF home:ATM:EXISTS {
        RETURN aoso_config_get("DEORBIT_PE_ALT", 30000).
    }
    RETURN 0.
}

// Adds whichever departure node gets the ship one hop closer to home, per
// the three-way classification above. Returns 0 (no node) if already home,
// or if the underlying burn helper couldn't find a valid solution.
FUNCTION aoso_return_add_departure_node {
    IF aoso_return_is_home() {
        aoso_log_info("RETURN", "Already at home body; nothing to depart.").
        RETURN 0.
    }

    IF aoso_return_shares_home_parent() {
        RETURN aoso_interplanetary_add_ejection_node(aoso_return_home_body()).
    }

    IF NOT aoso_moonescape_available() {
        aoso_log_error("RETURN", SHIP:BODY:NAME + " has no route toward " + aoso_return_home_body():NAME + ".").
        RETURN 0.
    }

    IF aoso_return_is_moon_of_home() {
        RETURN aoso_moonescape_add_escape_node(aoso_return_home_arrival_periapsis_alt()).
    }

    // Moon of some other planet (e.g. Ike): first hop up to that planet's
    // parking orbit; the next PLAN cycle continues from there.
    RETURN aoso_moonescape_add_escape_node(aoso_config_get("PARKING_ORBIT_ALT", 100000)).
}

FUNCTION aoso_return_on_abort {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_state_transition(AOSO_RETURN, "ABORTED").
}

FUNCTION aoso_return_plan_entry {
    PARAMETER data.
    aoso_throttle_set(0).

    IF aoso_return_is_home() {
        aoso_state_transition(AOSO_RETURN, "DONE").
        RETURN.
    }

    SET data["depart_body"] TO SHIP:BODY:NAME.
    LOCAL nd IS aoso_return_add_departure_node().
    IF nd = 0 {
        aoso_state_abort(AOSO_RETURN).
        RETURN.
    }
    aoso_state_transition(AOSO_RETURN, "BURN").
}

FUNCTION aoso_return_burn_execute {
    PARAMETER data.
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_RETURN).
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        LOCAL burn_res IS aoso_maneuver_last_result().
        IF burn_res = "missed" OR burn_res = "incomplete" {
            aoso_log_warn("RETURN", "Burn " + burn_res + " - re-planning.").
            aoso_state_transition(AOSO_RETURN, "PLAN").
            RETURN.
        }
        aoso_state_transition(AOSO_RETURN, "COAST").
    }
}

FUNCTION aoso_return_coast_entry {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_steer_release().
}

// Waits out the coast until either home is reached, or SHIP:BODY changes
// (an SOI crossing happened), at which point PLAN re-classifies from the new
// body -- this is what lets a moon-of-another-planet trip chain its
// intermediate hop straight into the interplanetary leg without any extra
// bookkeeping here.
FUNCTION aoso_return_coast_execute {
    PARAMETER data.
    IF aoso_return_is_home() {
        aoso_state_transition(AOSO_RETURN, "DONE").
        RETURN.
    }
    IF SHIP:BODY:NAME <> data["depart_body"] {
        aoso_state_transition(AOSO_RETURN, "PLAN").
    }
}

FUNCTION aoso_return_done_entry {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_steer_release().
    LOCAL ver_r IS aoso_verify_return(aoso_return_home_body():NAME).
    aoso_return_emit_result(data, ver_r["status"], ver_r["reason"]).
    aoso_auth_release_all("return").
    aoso_log_info("RETURN", "Home body " + aoso_return_home_body():NAME + " reached.").
}

FUNCTION aoso_return_aborted_entry {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_return_emit_result(data, "ABORTED", "return sequence aborted").
    aoso_auth_release_all("return").
    aoso_log_error("RETURN", "Return sequence aborted.").
}

FUNCTION aoso_return_define_states {
    aoso_state_define(AOSO_RETURN, "PLAN", aoso_return_plan_entry@, 0, 0, 0, 0, aoso_return_on_abort@).
    aoso_state_define(AOSO_RETURN, "BURN", 0, aoso_return_burn_execute@, 0, 0, 0, aoso_return_on_abort@).
    aoso_state_define(AOSO_RETURN, "COAST", aoso_return_coast_entry@, aoso_return_coast_execute@, 0, 0, 0, aoso_return_on_abort@).
    aoso_state_define(AOSO_RETURN, "DONE", aoso_return_done_entry@, 0, 0).
    aoso_state_define(AOSO_RETURN, "ABORTED", aoso_return_aborted_entry@, 0, 0).
}

// Entry point: call once to arm the return sequence, then drive it every
// tick with aoso_return_update(). Once aoso_return_is_done() is TRUE, the ship
// is inside the home body's SOI (and, for a direct moon-of-home departure,
// already lined up for landing/deorbit.ks + landing/descent.ks to finish the
// job with little or no further burn needed).
FUNCTION aoso_return_start {
    aoso_return_define_states().
    aoso_return_claim_authority().
    SET AOSO_RETURN["data"] TO LEXICON().
    aoso_return_begin_action(AOSO_RETURN["data"]).
    aoso_state_transition(AOSO_RETURN, "PLAN").
}

FUNCTION aoso_return_update {
    aoso_return_claim_authority().
    aoso_state_update(AOSO_RETURN).
}

FUNCTION aoso_return_is_done {
    RETURN AOSO_RETURN["current"] = "DONE".
}

FUNCTION aoso_return_is_aborted {
    RETURN AOSO_RETURN["current"] = "ABORTED".
}
