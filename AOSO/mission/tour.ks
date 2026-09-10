// AOSO/mission/tour.ks
// Default autonomous mission: visit every stock planet and moon the
// vessel can actually reach, land and refuel where it needs propellant
// and can take off again. The itinerary is NOT a hard-coded list --
// mission/planner.ks classifies the ship, builds a capability matrix,
// scores CAN vs SHOULD, then a cluster-greedy route (Jool's moons are
// one interplanetary hop). Destination checks still go through
// mission/feasibility.ks: SKIP unreachable, ORBIT_ONLY rather than
// landing a ship that cannot leave.
// Built on core/state.ks as AOSO_TOUR, driving the existing goto / ascent /
// polar / scan / deorbit / descent / refuel / return / kscreturn machines as
// sub-steps the same way mission/mission.ks drives aoso_ascent_*.
// Landings go polar -> ground-track scan (landing/site.ks) -> deorbit to a
// periapsis above the highlands -> surface-velocity suicide burn. The old
// GOTO-capture -> PE=0 deorbit -> immediate descent skipped the scan and
// lithobraked into Mun.
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
    RETURN aoso_profile_surface_twr(body_name).
}

FUNCTION aoso_tour_landable {
    PARAMETER body_name.
    IF body_name = "Jool" OR body_name = "Sun" { RETURN FALSE. }
    LOCAL report IS aoso_feas_cached(body_name).
    IF report["can_land"] {
        IF report["can_takeoff"] { RETURN TRUE. }
    }
    aoso_log_info("TOUR", "Skipping landing on " + body_name + " (" + report["reason"] + ").").
    RETURN FALSE.
}

FUNCTION aoso_tour_should_refuel {
    PARAMETER body_name.
    LOCAL report IS aoso_feas_cached(body_name).
    IF NOT report["can_land"] { RETURN FALSE. }
    IF NOT report["can_takeoff"] { RETURN FALSE. }
    IF NOT report["can_refuel"] { RETURN FALSE. }
    LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
    LOCAL need IS aoso_config_get("TOUR_REFUEL_BELOW_PCT", 60).
    IF fuel_pct >= need {
        aoso_log_info("TOUR", "Fuel at " + ROUND(fuel_pct, 0) + "% - orbiting " + body_name + " without landing.").
        RETURN FALSE.
    }
    RETURN TRUE.
}

FUNCTION aoso_tour_orbit_is_stable {
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" { RETURN FALSE. }
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN FALSE. }
    IF PERIAPSIS < 2000 { RETURN FALSE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT + 5000 { RETURN FALSE. }
    }
    RETURN TRUE.
}

FUNCTION aoso_tour_is_polar {
    LOCAL tgt IS aoso_config_get("TOUR_POLAR_INCLINATION", 90).
    LOCAL tol IS aoso_config_get("TOUR_POLAR_TOLERANCE_DEG", 15).
    RETURN ABS(SHIP:ORBIT:INCLINATION - tgt) <= tol.
}

FUNCTION aoso_tour_is_impacting {
    IF SHIP:STATUS = "LANDED" { RETURN FALSE. }
    IF ETA:PERIAPSIS >= ETA:APOAPSIS { RETURN FALSE. }
    IF PERIAPSIS < 0 { RETURN TRUE. }
    IF NOT SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < aoso_config_get("DESCENT_SAFE_PE_ALT", 8000) { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_tour_opposite_site {
    PARAMETER lat.
    PARAMETER lng.
    LOCAL geo IS LATLNG(lat, lng).
    LOCAL ship_r IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL site_r IS geo:POSITION - SHIP:BODY:POSITION.
    RETURN VANG(ship_r, site_r) >= 140.
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
        aoso_log_info("TOUR", "Orbit reached - replanning the tour against remaining dV.").
        aoso_plan_build().
        LOCAL next_targets IS aoso_plan_targets().
        IF next_targets:LENGTH > 0 {
            SET data["targets"] TO next_targets.
            SET data["index"] TO 0.
        }
        aoso_state_transition(AOSO_TOUR, "GOTO").
    }
}

FUNCTION aoso_tour_goto_entry {
    PARAMETER data.
    aoso_profile_refresh("tour_goto").
    UNTIL FALSE {
        LOCAL name IS aoso_tour_current_name(data).
        IF name = "" {
            aoso_state_transition(AOSO_TOUR, "RETURN").
            RETURN.
        }
        LOCAL report IS aoso_feas_evaluate(name).
        aoso_feas_log_report(report).
        SET data["feas_result"] TO report["result"].
        IF report["result"] = "SKIP" {
            aoso_log_warn("TOUR", "Skipping " + name + " - " + report["reason"] + ".").
            SET data["index"] TO data["index"] + 1.
        } ELSE {
            aoso_goto_start(name).
            RETURN.
        }
    }
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
                aoso_state_transition(AOSO_TOUR, "POLAR").
            }
        } ELSE {
            aoso_tour_advance(data).
        }
    }
}

FUNCTION aoso_tour_polar_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_maneuver_clear_all().

    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_TOUR, "REFUEL").
        RETURN.
    }

    IF aoso_tour_is_impacting() {
        aoso_log_warn("TOUR", "Impact trajectory at " + SHIP:BODY:NAME + " - skipping polar/scan, suicide-burning.").
        aoso_descent_start().
        aoso_state_transition(AOSO_TOUR, "DESCEND").
        RETURN.
    }

    IF NOT aoso_tour_orbit_is_stable() {
        LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
        IF PERIAPSIS < park {
            aoso_log_info("TOUR", "Raising periapsis to " + ROUND(park, 0) + "m before polar capture.").
            LOCAL nd_pe IS aoso_hohmann_add_periapsis_change(park).
            IF nd_pe = 0 {
                aoso_descent_start().
                aoso_state_transition(AOSO_TOUR, "DESCEND").
            }
            RETURN.
        }
        aoso_log_info("TOUR", "Circularizing at periapsis before polar.").
        LOCAL nd_c IS aoso_hohmann_add_circularize_at_periapsis().
        IF nd_c = 0 {
            aoso_state_transition(AOSO_TOUR, "SCAN").
        }
        RETURN.
    }

    IF NOT aoso_tour_is_polar() {
        LOCAL tgt IS aoso_config_get("TOUR_POLAR_INCLINATION", 90).
        aoso_log_info("TOUR", "Plane-changing to polar (" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " -> " + tgt + " deg).").
        LOCAL nd_p IS aoso_planechange_add_node_for_inclination(tgt, aoso_config_get("TOUR_POLAR_TOLERANCE_DEG", 15)).
        IF nd_p = 0 {
            aoso_state_transition(AOSO_TOUR, "SCAN").
        }
        RETURN.
    }

    aoso_log_info("TOUR", "Polar parking established (inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " deg).").
    aoso_state_transition(AOSO_TOUR, "SCAN").
}

FUNCTION aoso_tour_polar_execute {
    PARAMETER data.
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF NOT HASNODE {
        aoso_state_transition(AOSO_TOUR, "POLAR").
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        LOCAL burn_res IS aoso_maneuver_last_result().
        IF burn_res = "missed" OR burn_res = "incomplete" {
            aoso_log_warn("TOUR", "Polar/stabilize " + burn_res + " - retrying.").
        }
        aoso_state_transition(AOSO_TOUR, "POLAR").
    }
}

FUNCTION aoso_tour_scan_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().

    LOCAL result IS aoso_landing_site_scan_orbit().
    IF result:ISTYPE("Lexicon") {
        SET data["site_lat"] TO result["lat"].
        SET data["site_lng"] TO result["lng"].
        SET data["site_score"] TO result["score"].
        aoso_log_info("TOUR", "Landing site lat=" + ROUND(result["lat"], 2) + " lng=" + ROUND(result["lng"], 2) +
            " slope=" + ROUND(result["slope"], 1) + " deg.").
    } ELSE {
        SET data["site_lat"] TO SHIP:GEOPOSITION:LAT.
        SET data["site_lng"] TO SHIP:GEOPOSITION:LNG.
        aoso_log_warn("TOUR", "Scan found nothing safer than the current ground track - landing near lat=" +
            ROUND(data["site_lat"], 2) + " lng=" + ROUND(data["site_lng"], 2) + ".").
        SET data["site_score"] TO 0.
    }
    SET data["deorbit_wait_since"] TO TIME:SECONDS.
}

FUNCTION aoso_tour_scan_execute {
    PARAMETER data.
    aoso_state_transition(AOSO_TOUR, "DEORBIT").
}

FUNCTION aoso_tour_deorbit_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_TOUR, "REFUEL").
        RETURN.
    }
    IF NOT data:HASKEY("deorbit_wait_since") {
        SET data["deorbit_wait_since"] TO TIME:SECONDS.
    }
}

FUNCTION aoso_tour_deorbit_execute {
    PARAMETER data.
    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_TOUR, "REFUEL").
        RETURN.
    }

    IF HASNODE {
        IF aoso_maneuver_execute_next() {
            LOCAL burn_res IS aoso_maneuver_last_result().
            IF burn_res = "missed" OR burn_res = "incomplete" {
                aoso_log_warn("TOUR", "Deorbit " + burn_res + " - retrying.").
                RETURN.
            }
            aoso_descent_start().
            aoso_state_transition(AOSO_TOUR, "DESCEND").
        }
        RETURN.
    }

    LOCAL have_site IS FALSE.
    IF data:HASKEY("site_score") {
        IF data["site_score"] >= 0 { SET have_site TO TRUE. }
    }

    LOCAL opposite IS FALSE.
    IF have_site {
        SET opposite TO aoso_tour_opposite_site(data["site_lat"], data["site_lng"]).
    }

    LOCAL waited IS TIME:SECONDS - data["deorbit_wait_since"].
    LOCAL period IS SHIP:ORBIT:PERIOD.
    IF period <= 0 { SET period TO 600. }

    IF have_site {
        IF NOT opposite {
            IF waited < period {
                IF WARP = 0 {
                    IF aoso_maneuver_can_warp() { SET WARP TO 3. }
                }
                RETURN.
            }
        }
    }

    SET WARP TO 0.
    LOCAL eta_s IS -1.
    IF opposite { SET eta_s TO aoso_maneuver_align_s(). }
    LOCAL nd IS aoso_deorbit_add_node(0, FALSE, eta_s).
    IF nd = 0 {
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
    aoso_state_define(AOSO_TOUR, "POLAR", aoso_tour_polar_entry@, aoso_tour_polar_execute@, 0, 0, 0, aoso_tour_on_abort@).
    aoso_state_define(AOSO_TOUR, "SCAN", aoso_tour_scan_entry@, aoso_tour_scan_execute@, 0, 0, 0, aoso_tour_on_abort@).
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
    IF targets:LENGTH = 0 {
        SET targets TO aoso_plan_targets().
        IF targets:LENGTH = 0 { SET targets TO aoso_tour_default_targets(). }
    }

    aoso_tour_define_states().
    SET AOSO_TOUR["data"] TO LEXICON("targets", targets, "index", 0, "site_lat", 0, "site_lng", 0, "site_score", -1, "deorbit_wait_since", 0).
    aoso_log_info("TOUR", "Grand tour armed: " + targets:LENGTH + " bodies (" + aoso_classify_name() + "), then KSC return.").
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
