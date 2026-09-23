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
// Landings go polar -> ground-track scan (landing/site.ks, then two
// confirm orbits) -> wait until the site is opposite -> deorbit to a
// periapsis above the highlands -> surface-velocity suicide burn. The old
// GOTO-capture -> PE=0 deorbit -> immediate descent skipped the scan and
// lithobraked into Mun. A one-tick scan plus a 120 s deorbit node dropped
// onto 100000x rails overshot Minmus by 360 s and never descended.
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

FUNCTION aoso_tour_landable {
    PARAMETER body_name.
    IF body_name = "Jool" OR body_name = "Sun" { RETURN FALSE. }
    LOCAL report IS aoso_feas_cached(body_name).
    IF report["result"] = "FEASIBLE" { RETURN TRUE. }
    aoso_log_info("TOUR", "Skipping landing on " + body_name + " (" + report["reason"] + ").").
    RETURN FALSE.
}

FUNCTION aoso_tour_should_refuel {
    PARAMETER body_name.
    LOCAL report IS aoso_feas_cached(body_name).
    IF report["result"] <> "FEASIBLE" { RETURN FALSE. }
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
    LOCAL tol IS aoso_config_get("TOUR_POLAR_TOLERANCE_DEG", 5).
    RETURN ABS(SHIP:ORBIT:INCLINATION - tgt) <= tol.
}

FUNCTION aoso_tour_is_impacting {
    IF SHIP:STATUS = "LANDED" { RETURN FALSE. }
    IF aoso_orbit_is_hyperbolic() {
        IF PERIAPSIS < 0 { RETURN TRUE. }
        RETURN FALSE.
    }
    IF ETA:PERIAPSIS >= aoso_orbit_eta_apoapsis() { RETURN FALSE. }
    IF PERIAPSIS < 0 { RETURN TRUE. }
    IF NOT SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < aoso_config_get("DESCENT_SAFE_PE_ALT", 8000) { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_tour_site_vang {
    PARAMETER lat.
    PARAMETER lng.
    LOCAL geo IS LATLNG(lat, lng).
    LOCAL ship_r IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL site_r IS geo:POSITION - SHIP:BODY:POSITION.
    RETURN VANG(ship_r, site_r).
}

FUNCTION aoso_tour_opposite_site {
    PARAMETER lat.
    PARAMETER lng.
    RETURN aoso_tour_site_vang(lat, lng) >= 115.
}

FUNCTION aoso_tour_on_abort {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_state_transition(AOSO_TOUR, "ABORTED").
}

FUNCTION aoso_tour_current_name {
    PARAMETER data.
    IF data["index"] < 0 OR data["index"] >= data["targets"]:LENGTH { RETURN "". }
    RETURN data["targets"][data["index"]].
}

FUNCTION aoso_tour_mark {
    PARAMETER data.
    PARAMETER body_name.
    PARAMETER mark_st.
    IF body_name = "" { RETURN. }
    IF NOT data:HASKEY("accomplished") {
        SET data["accomplished"] TO LEXICON().
    }
    SET data["accomplished"][body_name] TO mark_st.
    aoso_log_info("TOUR", body_name + " marked " + mark_st + ".").
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

FUNCTION aoso_tour_replan_remaining {
    PARAMETER data.
    IF DEFINED AOSO_BRAIN {
        aoso_brain_wait_think("tour replan").
    }
    aoso_log_info("TOUR", "Replanning remaining tour against current dV.").
    aoso_profile_refresh("tour_replan").
    aoso_plan_build().
    LOCAL next_targets IS aoso_plan_targets().
    IF next_targets:LENGTH > 0 {
        SET data["targets"] TO next_targets.
        SET data["index"] TO 0.
    }
}

FUNCTION aoso_tour_boot_entry {
    PARAMETER data.
    IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" {
        LOCAL dep IS aoso_depart_certify().
        IF dep["status"] = "NOT_READY" {
            aoso_log_warn("TOUR", "Pad/surface not ready: " + dep["reason"] + " - holding.").
            aoso_ui_set("HOLD", dep["reason"]).
            RETURN.
        }
        aoso_tour_replan_remaining(data).
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
        aoso_tour_replan_remaining(data).
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
            aoso_tour_mark(data, name, "SKIPPED").
            SET data["index"] TO data["index"] + 1.
        } ELSE {
            SET AOSO_WANT_POLAR TO FALSE.
            IF report["can_land"] {
                IF report["result"] <> "ORBIT_ONLY" {
                    SET AOSO_WANT_POLAR TO TRUE.
                }
            }
            aoso_goto_start(name).
            RETURN.
        }
    }
}

FUNCTION aoso_tour_goto_execute {
    PARAMETER data.
    IF aoso_goto_is_aborted() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF aoso_goto_is_done() {
        LOCAL name IS aoso_tour_current_name(data).

        // A grand-tour stop means LAND when the live feasibility model says
        // this vessel can land and leave again. Fuel percentage decides
        // whether surface ISRU runs after touchdown; it must not decide
        // whether the body is visited only from orbit.
        IF aoso_tour_landable(name) {
            IF SHIP:STATUS = "LANDED" {
                aoso_state_transition(AOSO_TOUR, "REFUEL").
            } ELSE {
                aoso_state_transition(AOSO_TOUR, "POLAR").
            }
        } ELSE {
            aoso_tour_mark(data, name, "ORBITED").
            aoso_tour_advance(data).
        }
    }
}

FUNCTION aoso_tour_polar_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_maneuver_clear_all().
    SET data["polar_warp_logged"] TO FALSE.

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
        LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
        LOCAL soi_a IS SHIP:BODY:SOIRADIUS - SHIP:BODY:RADIUS.
        LOCAL high_ap IS park * 18.
        IF high_ap < park * 8 { SET high_ap TO park * 8. }
        IF high_ap > soi_a * 0.28 { SET high_ap TO soi_a * 0.28. }
        LOCAL ap_now IS aoso_orbit_apoapsis_alt().
        IF SHIP:ORBIT:ECCENTRICITY < 0.2 {
            IF ap_now < high_ap * 0.7 {
                aoso_log_info("TOUR", "Raising AP to " + ROUND(high_ap, 0) + "m before polar plane-change (cheap at low speed, not 140 m/s at circular PE).").
                LOCAL nd_ap IS aoso_hohmann_add_apoapsis_change(high_ap).
                IF nd_ap = 0 {
                    aoso_state_transition(AOSO_TOUR, "SCAN").
                }
                RETURN.
            }
        }
        aoso_log_info("TOUR", "Plane-changing to polar (" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " -> " + tgt + " deg) at the slow node.").
        LOCAL nd_p IS aoso_planechange_add_node_for_inclination(tgt, aoso_config_get("TOUR_POLAR_TOLERANCE_DEG", 5)).
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
    LOCAL nd IS NEXTNODE.
    aoso_ui_set("Polar / stabilize T-" + aoso_hud_eta(nd:ETA), ROUND(nd:DELTAV:MAG, 1) + " m/s  " + aoso_warp_diag_txt()).
    IF NOT data["polar_warp_logged"] {
        aoso_log_info("TOUR", "Rails-warping " + ROUND(nd:ETA, 0) + "s to polar/stabilize burn (" + ROUND(nd:DELTAV:MAG, 1) + " m/s). Physics 2x until 10 s, then 1x.").
        SET data["polar_warp_logged"] TO TRUE.
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
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_ui_set("Scanning landing sites", SHIP:BODY:NAME + " polar inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1)).
    aoso_log_info("TOUR", "Scanning " + SHIP:BODY:NAME + " ground track for a landing site (inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + ").").

    LOCAL result IS aoso_landing_site_scan_orbit().
    IF result:ISTYPE("Lexicon") {
        SET data["site_lat"] TO result["lat"].
        SET data["site_lng"] TO result["lng"].
        SET data["site_score"] TO result["score"].
        SET data["site_alt"] TO result["alt"].
        LOCAL rough0 IS 0.
        IF result:HASKEY("roughness") { SET rough0 TO result["roughness"]. }
        SET data["site_roughness"] TO rough0.
        aoso_log_info("TOUR", "Landing site seed lat=" + ROUND(result["lat"], 2) +
            " lng=" + ROUND(result["lng"], 2) + " alt=" + ROUND(result["alt"], 0) +
            "m slope=" + ROUND(result["slope"], 1) + "deg rough=" +
            ROUND(rough0, 0) + "m score=" + ROUND(result["score"], 2) + ".").
        aoso_decide("TOUR", "site", ROUND(result["lat"], 2) + "/" + ROUND(result["lng"], 2), "scan", "score=" + ROUND(result["score"], 2) + " slope=" + ROUND(result["slope"], 1)).
    } ELSE {
        SET data["site_lat"] TO SHIP:GEOPOSITION:LAT.
        SET data["site_lng"] TO SHIP:GEOPOSITION:LNG.
        SET data["site_alt"] TO SHIP:GEOPOSITION:TERRAINHEIGHT.
        SET data["site_roughness"] TO aoso_landing_site_roughness_m(SHIP:GEOPOSITION).
        aoso_log_warn("TOUR", "Predictive scan found no safe candidate; using the current ground track as the live-survey seed near lat=" +
            ROUND(data["site_lat"], 2) + " lng=" + ROUND(data["site_lng"], 2) + ".").
        SET data["site_score"] TO aoso_landing_site_score(SHIP:GEOPOSITION).
    }

    LOCAL orbits IS aoso_config_get("LANDING_SCAN_ORBITS", 1).
    IF orbits < 1 { SET orbits TO 1. }
    IF orbits > 2 { SET orbits TO 2. }
    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { SET period TO 600. }
    LOCAL scan_span IS period * orbits.
    LOCAL scan_cap IS aoso_config_get("LANDING_SCAN_MAX_S", 7200).
    IF scan_cap > 0 {
        IF scan_span > scan_cap { SET scan_span TO scan_cap. }
    }
    SET data["scan_until"] TO TIME:SECONDS + scan_span.
    SET data["scan_next_sample"] TO TIME:SECONDS.
    SET data["scan_orbits"] TO orbits.
    aoso_log_info("TOUR", "Surveying up to " + ROUND(scan_span, 0) +
        "s of the polar ground track (" + orbits +
        " orbit max). Live overflight samples may replace the predicted seed when they score better.").
}

FUNCTION aoso_tour_scan_execute {
    PARAMETER data.
    LOCAL now IS TIME:SECONDS.
    IF data:HASKEY("scan_until") {
        IF now < data["scan_until"] {
            IF now >= data["scan_next_sample"] {
                LOCAL geo IS SHIP:GEOPOSITION.
                LOCAL sc IS aoso_landing_site_score(geo).
                IF sc >= 0 {
                    LOCAL improve IS FALSE.
                    IF data["site_score"] < 0 { SET improve TO TRUE. }
                    IF sc < data["site_score"] { SET improve TO TRUE. }
                    IF improve {
                        LOCAL old_sc IS data["site_score"].
                        SET data["site_lat"] TO geo:LAT.
                        SET data["site_lng"] TO geo:LNG.
                        SET data["site_alt"] TO geo:TERRAINHEIGHT.
                        SET data["site_score"] TO sc.
                        SET data["site_roughness"] TO aoso_landing_site_roughness_m(geo).
                        aoso_log_info("TOUR", "Live polar overflight improved landing site: score " +
                            ROUND(old_sc, 2) + " -> " + ROUND(sc, 2) + " lat=" +
                            ROUND(geo:LAT, 2) + " lng=" + ROUND(geo:LNG, 2) +
                            " alt=" + ROUND(geo:TERRAINHEIGHT, 0) + "m rough=" +
                            ROUND(data["site_roughness"], 0) + "m.").
                    } ELSE {
                        aoso_log_every(80, "TOUR", "Overflight sample lat=" + ROUND(geo:LAT, 2) +
                            " lng=" + ROUND(geo:LNG, 2) + " score=" + ROUND(sc, 2) +
                            " best=" + ROUND(data["site_score"], 2) + ".").
                    }
                }
                SET data["scan_next_sample"] TO now + 25.
            }
            LOCAL left IS data["scan_until"] - now.
            aoso_ui_set("Scanning landing sites", aoso_hud_eta(left) + "  " + data["scan_orbits"] + " orbit confirm  " + aoso_warp_diag_txt()).
            aoso_steer_release().
            aoso_warp_approach(left, 15, 8).
            RETURN.
        }
    }
    IF WARP > 0 OR WARPMODE <> "PHYSICS" OR NOT KUNIVERSE:TIMEWARP:ISSETTLED {
        aoso_warp_hard_stop().
        RETURN.
    }
    SET data["deorbit_wait_since"] TO TIME:SECONDS.
    LOCAL final_rough IS 0.
    IF data:HASKEY("site_roughness") { SET final_rough TO data["site_roughness"]. }
    aoso_log_info("TOUR", "Polar survey complete. Selected site lat=" +
        ROUND(data["site_lat"], 2) + " lng=" + ROUND(data["site_lng"], 2) +
        " score=" + ROUND(data["site_score"], 2) + " rough=" +
        ROUND(final_rough, 0) + "m AP=" + ROUND(APOAPSIS, 0) +
        " PE=" + ROUND(PERIAPSIS, 0) + " inc=" +
        ROUND(SHIP:ORBIT:INCLINATION, 1) + " - timing deorbit/descent next.").
    aoso_state_transition(AOSO_TOUR, "DEORBIT").
}

FUNCTION aoso_tour_deorbit_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
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
        aoso_ui_set("Deorbit burn", aoso_warp_diag_txt()).
        IF aoso_maneuver_execute_next() {
            LOCAL burn_res IS aoso_maneuver_last_result().
            IF burn_res = "missed" OR burn_res = "incomplete" {
                aoso_log_warn("TOUR", "Deorbit " + burn_res + " - retrying. AP=" + ROUND(APOAPSIS, 0) + " PE=" + ROUND(PERIAPSIS, 0) +
                    " alt=" + ROUND(ALTITUDE, 0) + " " + aoso_warp_diag_txt() + ".").
                RETURN.
            }
            aoso_log_info("TOUR", "Deorbit complete. AP=" + ROUND(APOAPSIS, 0) + " PE=" + ROUND(PERIAPSIS, 0) +
                " alt=" + ROUND(ALTITUDE, 0) + " vs=" + ROUND(VERTICALSPEED, 1) + " - handing to descent.").
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
    LOCAL site_ang IS 0.
    LOCAL opp_txt IS "NO".
    IF have_site {
        SET site_ang TO aoso_tour_site_vang(data["site_lat"], data["site_lng"]).
        IF NOT data:HASKEY("deorbit_ang_peak") { SET data["deorbit_ang_peak"] TO site_ang. }
        IF site_ang > data["deorbit_ang_peak"] { SET data["deorbit_ang_peak"] TO site_ang. }
        LOCAL falling IS FALSE.
        IF data:HASKEY("deorbit_ang_last") {
            IF site_ang < data["deorbit_ang_last"] - 1.5 {
                IF data["deorbit_ang_peak"] >= 115 { SET falling TO TRUE. }
            }
        }
        SET data["deorbit_ang_last"] TO site_ang.
        IF site_ang >= 115 {
            SET opposite TO TRUE.
            SET opp_txt TO "YES".
        }
        IF falling {
            SET opposite TO TRUE.
            SET opp_txt TO "PEAK".
        }
    }

    LOCAL waited IS TIME:SECONDS - data["deorbit_wait_since"].
    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { SET period TO 600. }
    IF waited >= period * 1.05 {
        SET opposite TO TRUE.
        SET opp_txt TO "TIMEOUT".
    }

    IF have_site {
        IF NOT opposite {
            LOCAL guess IS period * 0.2.
            IF site_ang >= 90 { SET guess TO period * 0.08. }
            IF site_ang >= 110 { SET guess TO 25. }
            IF guess < 20 { SET guess TO 20. }
            aoso_ui_set("Waiting for site over horizon", "ang=" + ROUND(site_ang, 0) + "  " + aoso_warp_diag_txt()).
            IF NOT data:HASKEY("deorbit_warp_logged") {
                aoso_log_info("TOUR", "Rails-warping until the landing site is opposite before deorbit (up to ~" + ROUND(period, 0) + "s). site lat=" +
                    ROUND(data["site_lat"], 2) + " lng=" + ROUND(data["site_lng"], 2) + " ship lat=" +
                    ROUND(SHIP:GEOPOSITION:LAT, 2) + " lng=" + ROUND(SHIP:GEOPOSITION:LNG, 2) + " ang=" + ROUND(site_ang, 0) + " deg.").
                SET data["deorbit_warp_logged"] TO TRUE.
            }
            aoso_log_every(45, "TOUR", "Deorbit wait opposite=NO ang=" + ROUND(site_ang, 0) + " deg peak=" + ROUND(data["deorbit_ang_peak"], 0) + " ship=" +
                ROUND(SHIP:GEOPOSITION:LAT, 1) + "/" + ROUND(SHIP:GEOPOSITION:LNG, 1) + " site=" +
                ROUND(data["site_lat"], 1) + "/" + ROUND(data["site_lng"], 1) + " waited=" + ROUND(waited, 0) +
                "s period=" + ROUND(period, 0) + "s " + aoso_warp_diag_txt() + ".").
            aoso_steer_release().
            aoso_warp_approach(guess, 20, 10).
            RETURN.
        }
    }

    // Dropping out of 100000x rails onto a 120 s node overshoots by
    // minutes (Acacius missed the first Minmus deorbit by 360 s). Stay
    // here until warp is actually idle, then place the node.
    IF WARP > 0 {
        aoso_log_every(8, "TOUR", "Deorbit settling " + aoso_warp_diag_txt() + " opposite=" + opp_txt + " ang=" + ROUND(site_ang, 0) + " deg before placing node.").
        SET WARP TO 0.
        RETURN.
    }

    LOCAL eta_s IS -1.
    IF opposite { SET eta_s TO aoso_maneuver_align_s(). }
    aoso_log_info("TOUR", "Placing deorbit node opposite=" + opp_txt + " ang=" + ROUND(site_ang, 0) +
        " deg eta=" + ROUND(eta_s, 0) + "s AP=" + ROUND(APOAPSIS, 0) + " PE=" + ROUND(PERIAPSIS, 0) +
        " " + aoso_warp_diag_txt() + ".").
    LOCAL nd IS aoso_deorbit_add_node(0, FALSE, eta_s).
    IF nd = 0 {
        aoso_log_info("TOUR", "No deorbit burn needed (PE already " + ROUND(PERIAPSIS, 0) + "m) - descent now.").
        aoso_descent_start().
        aoso_state_transition(AOSO_TOUR, "DESCEND").
    }
}

FUNCTION aoso_tour_descend_execute {
    PARAMETER data.
    IF aoso_descent_is_aborted() {
        aoso_log_warn("TOUR", "Landing aborted at " + SHIP:BODY:NAME + " - continuing the tour from orbit if possible.").
        IF SHIP:STATUS = "LANDED" {
            aoso_tour_mark(data, SHIP:BODY:NAME, "LANDED").
            aoso_state_transition(AOSO_TOUR, "LAUNCH").
        } ELSE {
            aoso_tour_mark(data, aoso_tour_current_name(data), "ORBITED").
            aoso_tour_advance(data).
        }
        RETURN.
    }
    IF aoso_descent_is_landed() {
        aoso_tour_mark(data, aoso_tour_current_name(data), "LANDED").
        aoso_state_transition(AOSO_TOUR, "REFUEL").
    }
}

FUNCTION aoso_tour_refuel_entry {
    PARAMETER data.
    LOCAL surf IS aoso_surface_begin().
    IF surf["phase"] = "HOLD" {
        aoso_log_warn("TOUR", "Surface hold before ISRU: " + surf["reason"] + ".").
        aoso_ui_set("HOLD", surf["reason"]).
        RETURN.
    }
    IF surf["phase"] = "LAUNCH" {
        aoso_log_info("TOUR", "No ISRU needed at " + SHIP:BODY:NAME + " (" + surf["reason"] + ").").
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
        RETURN.
    }
    aoso_log_info("TOUR", "Surface executive: " + surf["phase"] + " " + surf["reason"] + ".").
}

FUNCTION aoso_tour_refuel_execute {
    PARAMETER data.
    LOCAL surf IS aoso_surface_update().
    IF surf["phase"] = "HOLD" {
        aoso_ui_set("HOLD", surf["reason"]).
        aoso_log_every(20, "TOUR", "Surface hold: " + surf["reason"] + ".").
        RETURN.
    }
    IF surf["phase"] = "LAUNCH" {
        aoso_state_transition(AOSO_TOUR, "LAUNCH").
    }
}

FUNCTION aoso_tour_launch_entry {
    PARAMETER data.
    SET data["depart_ok"] TO FALSE.
}

FUNCTION aoso_tour_launch_execute {
    PARAMETER data.
    IF NOT data:HASKEY("depart_ok") { SET data["depart_ok"] TO FALSE. }
    IF NOT data["depart_ok"] {
        IF NOT aoso_surface_stable() {
            aoso_ui_set("HOLD", "waiting for surface stability").
            aoso_log_every(20, "TOUR", "Holding launch - surface not stable.").
            RETURN.
        }
        LOCAL dep IS aoso_depart_certify().
        IF dep["status"] = "NOT_READY" {
            aoso_ui_set("HOLD", dep["reason"]).
            aoso_log_every(20, "TOUR", "Departure not ready: " + dep["reason"] + ".").
            RETURN.
        }
        SET data["depart_ok"] TO TRUE.
        LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
        aoso_log_info("TOUR", "Launching from " + SHIP:BODY:NAME + " toward parking " + ROUND(park, 0) + "m (" + dep["status"] + ").").
        aoso_ascent_start(90, park).
    }
    aoso_ascent_update().
    IF aoso_ascent_is_aborted() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF aoso_ascent_is_done() {
        aoso_tour_mark(data, SHIP:BODY:NAME, "COMPLETED").
        aoso_tour_replan_remaining(data).
        aoso_state_transition(AOSO_TOUR, "GOTO").
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
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_log_info("TOUR", "Grand tour complete.").
}

FUNCTION aoso_tour_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_log_error("TOUR", "Grand tour aborted at body index " + data["index"] + ".").
}

FUNCTION aoso_tour_define_states {
    aoso_state_define(AOSO_TOUR, "BOOT", aoso_tour_boot_entry@, aoso_tour_boot_entry@, 0, 0, 0, aoso_tour_on_abort@).
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
    SET AOSO_TOUR["data"] TO LEXICON("targets", targets, "index", 0, "site_lat", 0, "site_lng", 0, "site_alt", 0, "site_score", -1, "deorbit_wait_since", 0, "polar_warp_logged", FALSE, "scan_until", 0, "scan_next_sample", 0, "scan_orbits", 1, "accomplished", LEXICON(), "depart_ok", FALSE).
    aoso_log_info("TOUR", "Grand tour armed: " + targets:LENGTH + " bodies (" + aoso_classify_name() + "), then KSC return.").
    aoso_decide("TOUR", "arm", "" + targets:LENGTH, aoso_classify_name(), "n=" + targets:LENGTH).
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
