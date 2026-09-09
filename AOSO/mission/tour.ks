// AOSO/mission/tour.ks
// Default autonomous mission: visit every stock planet and moon, land and
// refuel where the vehicle actually needs propellant and can take off
// again (ISRU drills + converter, surface TWR >= TOUR_MIN_LAND_TWR), then
// return to Kerbin and hand off to precision/kscreturn.ks for KSC.
// Built on core/state.ks as AOSO_TOUR, driving the existing goto / ascent /
// deorbit / descent / refuel / return / kscreturn machines as sub-steps
// the same way mission/mission.ks drives aoso_ascent_*.
//
// Gas giants (Jool) and the Sun are orbited, not landed. High-g / thick-
// atmosphere bodies the ship cannot leave (Eve, Tylo with TWR ~1) are
// visited in orbit only. A missing landing fails that stop and continues
// the tour rather than pretending the visit never happened.

GLOBAL AOSO_TOUR IS aoso_state_new_machine().

FUNCTION aoso_tour_default_targets {
    LOCAL names IS LIST("Mun", "Minmus", "Eve", "Gilly", "Moho", "Duna", "Ike", "Dres", "Jool", "Laythe", "Vall", "Tylo", "Bop", "Pol", "Eeloo").
    LOCAL out IS LIST().
    FOR n IN names {
        LOCAL e IS aoso_body_database_get(n).
        IF e:ISTYPE("Lexicon") {
            IF e:HASKEY("NAME") {
                IF e["NAME"] = n { out:ADD(n). }
            }
        }
    }
    RETURN out.
}

FUNCTION aoso_tour_surface_twr {
    PARAMETER body_name.
    LOCAL b IS BODY(body_name).
    LOCAL g IS b:MU / (b:RADIUS * b:RADIUS).
    LOCAL thrust IS SHIP:MAXTHRUST.
    IF thrust <= 0 { SET thrust TO SHIP:AVAILABLETHRUST. }
    IF SHIP:MASS <= 0 { RETURN 0. }
    IF g <= 0 { RETURN 0. }
    RETURN thrust / (SHIP:MASS * g).
}

FUNCTION aoso_tour_landable {
    PARAMETER body_name.
    IF body_name = "Jool" OR body_name = "Sun" { RETURN FALSE. }
    LOCAL twr IS aoso_tour_surface_twr(body_name).
    LOCAL min_twr IS aoso_config_get("TOUR_MIN_LAND_TWR", 1.4).
    IF twr < min_twr {
        aoso_log_info("TOUR", "Skipping landing on " + body_name + " (surface TWR " + ROUND(twr, 2) + " < " + min_twr + ").").
        RETURN FALSE.
    }
    RETURN TRUE.
}

FUNCTION aoso_tour_should_refuel {
    PARAMETER body_name.
    IF NOT aoso_tour_landable(body_name) { RETURN FALSE. }
    IF NOT aoso_refuel_available() { RETURN FALSE. }
    LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
    LOCAL need IS aoso_config_get("TOUR_REFUEL_BELOW_PCT", 60).
    IF fuel_pct >= need {
        aoso_log_info("TOUR", "Fuel at " + ROUND(fuel_pct, 0) + "% - orbiting " + body_name + " without landing.").
        RETURN FALSE.
    }
    RETURN TRUE.
}

FUNCTION aoso_tour_on_abort {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_state_transition(AOSO_TOUR, "ABORTED").
}

FUNCTION aoso_tour_current_name {
    PARAMETER data.
    IF data["index"] < 0 OR data["index"] >= data["targets"]:LENGTH { RETURN "". }
    RETURN data["targets"][data["index"]].
}

FUNCTION aoso_tour_advance {
    PARAMETER data.
    SET data["index"] TO data["index"] + 1.
    IF data["index"] >= data["targets"]:LENGTH {
        aoso_log_info("TOUR", "All bodies visited - returning home.").
        aoso_state_transition(AOSO_TOUR, "RETURN").
    } ELSE {
        aoso_log_info("TOUR", "Next body: " + aoso_tour_current_name(data) + " (" + (data["index"] + 1) + "/" + data["targets"]:LENGTH + ").").
        aoso_state_transition(AOSO_TOUR, "GOTO").
    }
}

FUNCTION aoso_tour_boot_entry {
    PARAMETER data.
    IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" {
        LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
        aoso_log_info("TOUR", "Launching from " + SHIP:BODY:NAME + " to begin the grand tour.").
        aoso_ascent_start(90, park).
        aoso_state_transition(AOSO_TOUR, "ASCEND").
    } ELSE {
        aoso_state_transition(AOSO_TOUR, "GOTO").
    }
}

FUNCTION aoso_tour_ascend_execute {
    PARAMETER data.
    aoso_ascent_update().
    IF aoso_ascent_is_aborted() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF aoso_ascent_is_done() {
        aoso_state_transition(AOSO_TOUR, "GOTO").
    }
}

FUNCTION aoso_tour_goto_entry {
    PARAMETER data.
    LOCAL name IS aoso_tour_current_name(data).
    IF name = "" {
        aoso_state_transition(AOSO_TOUR, "RETURN").
        RETURN.
    }
    aoso_goto_start(name).
}

FUNCTION aoso_tour_goto_execute {
    PARAMETER data.
    aoso_goto_update().
    IF aoso_goto_is_aborted() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF aoso_goto_is_done() {
        LOCAL name IS aoso_tour_current_name(data).
        IF aoso_tour_should_refuel(name) {
            IF SHIP:STATUS = "LANDED" {
                aoso_state_transition(AOSO_TOUR, "REFUEL").
            } ELSE {
                aoso_state_transition(AOSO_TOUR, "DEORBIT").
            }
        } ELSE {
            aoso_tour_advance(data).
        }
    }
}

FUNCTION aoso_tour_deorbit_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_TOUR, "REFUEL").
        RETURN.
    }
    LOCAL nd IS aoso_deorbit_add_node().
    IF nd = 0 {
        aoso_descent_start().
        aoso_state_transition(AOSO_TOUR, "DESCEND").
    }
}

FUNCTION aoso_tour_deorbit_execute {
    PARAMETER data.
    IF aoso_maneuver_execute_next() {
        aoso_descent_start().
        aoso_state_transition(AOSO_TOUR, "DESCEND").
    }
}

FUNCTION aoso_tour_descend_execute {
    PARAMETER data.
    aoso_descent_tick().
    IF aoso_descent_is_aborted() {
        aoso_log_warn("TOUR", "Landing aborted at " + SHIP:BODY:NAME + " - continuing the tour from orbit if possible.").
        IF SHIP:STATUS = "LANDED" {
            aoso_state_transition(AOSO_TOUR, "LAUNCH").
        } ELSE {
            aoso_tour_advance(data).
        }
        RETURN.
    }
    IF aoso_descent_is_landed() {
        aoso_state_transition(AOSO_TOUR, "REFUEL").
    }
}

FUNCTION aoso_tour_refuel_entry {
    PARAMETER data.
    IF NOT aoso_refuel_available() {
        aoso_log_info("TOUR", "No ISRU aboard - skipping refuel at " + SHIP:BODY:NAME + ".").
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
        RETURN.
    }
    IF SHIP:STATUS <> "LANDED" {
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
        RETURN.
    }
    LOCAL started IS aoso_refuel_start().
    IF NOT started {
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
    }
}

FUNCTION aoso_tour_refuel_execute {
    PARAMETER data.
    aoso_refuel_tick().
    IF aoso_refuel_is_aborted() {
        aoso_log_warn("TOUR", "Refuel aborted at " + SHIP:BODY:NAME + " - launching on remaining propellant.").
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
        RETURN.
    }
    IF aoso_refuel_is_done() {
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
    }
}

FUNCTION aoso_tour_launch_entry {
    PARAMETER data.
    LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
    aoso_log_info("TOUR", "Launching from " + SHIP:BODY:NAME + " toward parking " + ROUND(park, 0) + "m.").
    aoso_ascent_start(90, park).
}

FUNCTION aoso_tour_launch_execute {
    PARAMETER data.
    aoso_ascent_update().
    IF aoso_ascent_is_aborted() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF aoso_ascent_is_done() {
        aoso_tour_advance(data).
    }
}

FUNCTION aoso_tour_return_entry {
    PARAMETER data.
    aoso_return_start().
}

FUNCTION aoso_tour_return_execute {
    PARAMETER data.
    aoso_return_update().
    IF aoso_return_is_aborted() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF aoso_return_is_done() {
        aoso_state_transition(AOSO_TOUR, "KSC").
    }
}

FUNCTION aoso_tour_ksc_entry {
    PARAMETER data.
    SET WARP TO 0.
    IF SHIP:STATUS = "ORBITING" {
        aoso_kscreturn_start().
    } ELSE {
        aoso_log_info("TOUR", "Not in a stable Kerbin orbit - handing off to descent.").
        aoso_descent_start().
    }
}

FUNCTION aoso_tour_ksc_execute {
    PARAMETER data.
    IF AOSO_PRECISION["current"] <> "" {
        IF aoso_kscreturn_is_aborted() {
            aoso_state_abort(AOSO_TOUR).
            RETURN.
        }
        IF NOT aoso_kscreturn_is_done() {
            aoso_kscreturn_update().
            RETURN.
        }
        // kscreturn DONE already started descent in its handoff.
    }
    IF AOSO_DESCENT["current"] <> "" {
        aoso_descent_tick().
        IF aoso_descent_is_landed() {
            aoso_state_transition(AOSO_TOUR, "DONE").
            RETURN.
        }
        IF aoso_descent_is_aborted() {
            aoso_state_abort(AOSO_TOUR).
        }
        RETURN.
    }
    aoso_state_transition(AOSO_TOUR, "DONE").
}

FUNCTION aoso_tour_done_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_log_info("TOUR", "Grand tour complete.").
}

FUNCTION aoso_tour_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_log_error("TOUR", "Grand tour aborted at body index " + data["index"] + ".").
}

FUNCTION aoso_tour_define_states {
    aoso_state_define(AOSO_TOUR, "BOOT", aoso_tour_boot_entry@, 0, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "ASCEND", 0, aoso_tour_ascend_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "GOTO", aoso_tour_goto_entry@, aoso_tour_goto_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "DEORBIT", aoso_tour_deorbit_entry@, aoso_tour_deorbit_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "DESCEND", 0, aoso_tour_descend_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "REFUEL", aoso_tour_refuel_entry@, aoso_tour_refuel_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "LAUNCH", aoso_tour_launch_entry@, aoso_tour_launch_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "RETURN", aoso_tour_return_entry@, aoso_tour_return_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "KSC", aoso_tour_ksc_entry@, aoso_tour_ksc_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "DONE", aoso_tour_done_entry@, 0, 0).
    aoso_state_define(AOSO_TOUR, "ABORTED", aoso_tour_aborted_entry@, 0, 0).
}

FUNCTION aoso_tour_start {
    PARAMETER targets IS LIST().
    IF targets:LENGTH = 0 { SET targets TO aoso_tour_default_targets(). }

    aoso_tour_define_states().
    SET AOSO_TOUR["data"] TO LEXICON("targets", targets, "index", 0).
    aoso_log_info("TOUR", "Grand tour armed: " + targets:LENGTH + " bodies, then KSC return.").
    aoso_state_transition(AOSO_TOUR, "BOOT").
}

FUNCTION aoso_tour_update {
    aoso_state_update(AOSO_TOUR).
}

FUNCTION aoso_tour_is_done {
    RETURN AOSO_TOUR["current"] = "DONE".
}

FUNCTION aoso_tour_is_aborted {
    RETURN AOSO_TOUR["current"] = "ABORTED".
}
