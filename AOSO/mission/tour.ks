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

// Ship-site angle at which the deorbit burn should ignite. Near-circular
// periapsis is ~180 deg from the burn, and align eats several degrees, so
// 115 deg (the old threshold) lit the engine tens of degrees early.
FUNCTION aoso_tour_deorbit_target_ang {
    PARAMETER period_s.
    PARAMETER align_s.
    LOCAL cap IS aoso_config_get("DEORBIT_ALIGN_CAP_DEG", 40).
    LOCAL floor_ang IS aoso_config_get("DEORBIT_OPPOSITE_MIN_DEG", 150).
    IF period_s < 1 { SET period_s TO 1. }
    IF align_s < 0 { SET align_s TO 0. }
    LOCAL lead_deg IS align_s * 360 / period_s.
    IF lead_deg > cap { SET lead_deg TO cap. }
    IF lead_deg < 0 { SET lead_deg TO 0. }
    LOCAL target IS 180 - lead_deg.
    IF target < floor_ang { SET target TO floor_ang. }
    IF target > 179 { SET target TO 179. }
    RETURN target.
}

FUNCTION aoso_tour_opposite_site {
    PARAMETER lat.
    PARAMETER lng.
    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { SET period TO 600. }
    LOCAL target IS aoso_tour_deorbit_target_ang(period, aoso_maneuver_align_s()).
    RETURN aoso_tour_site_vang(lat, lng) >= target.
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
        // Pad only: sit in BOOT until the systems board is green and the
        // operator commits. Do the plan once, then wait. Later LANDED
        // hops are not blocked (aoso_launch_blocked is PRELAUNCH-only).
        IF aoso_launch_blocked() {
            IF NOT data:HASKEY("hold_planned") { SET data["hold_planned"] TO FALSE. }
            aoso_launch_depart_refresh(2).
            IF NOT data["hold_planned"] {
                IF AOSO_LAUNCH_DEPART:HASKEY("status") {
                    IF AOSO_LAUNCH_DEPART["status"] = "NOT_READY" {

                        RETURN.
                    }
                }
                aoso_tour_replan_remaining(data).
                aoso_cert_eval("grand_tour").
                aoso_assure_eval().
                aoso_launch_depart_refresh(0).
                SET data["hold_planned"] TO TRUE.
                SET AOSO_LAUNCH_PREP_DONE TO TRUE.
            }

            RETURN.
        }
        LOCAL dep IS aoso_depart_certify().
        IF dep["status"] = "NOT_READY" {
            aoso_log_warn("TOUR", "Pad/surface not ready: " + dep["reason"] + " - holding.").

            RETURN.
        }
        IF NOT data:HASKEY("hold_planned") { SET data["hold_planned"] TO FALSE. }
        LOCAL skip_replan IS data["hold_planned"].
        IF AOSO_LAUNCH_PREP_DONE {
            IF AOSO_PLAN_LAST:HASKEY("built_at") { SET skip_replan TO TRUE. }
        }
        IF NOT skip_replan {
            aoso_tour_replan_remaining(data).
        }
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
    SET data["polar_warp_logged"] TO FALSE.
    SET data["polar_ready"] TO FALSE.
    aoso_throttle_set(0).
    // Do not SET WARP here. clear_all drops to physics 1x on its own and
    // returns FALSE on the tick it changes warp, so REMOVE cannot run
    // against an unsettled patched-conic solver.
    IF NOT aoso_maneuver_clear_all() {
        aoso_log_every(10, "POLAR_IDLE", "Polar entry waiting for physics 1x before node changes.").
        SET AOSO_TOUR["need_entry"] TO TRUE.
        RETURN.
    }
    SET data["polar_ready"] TO TRUE.

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

    // A non-impacting hyperbolic flyby is not a landing setup. The Minmus
    // failure run reached e=5.94 with PE=14.7 km, was falsely marked arrived,
    // then started FREEFALL from >2,000 km. Refuse that state explicitly.
    IF aoso_orbit_is_hyperbolic() {
        aoso_warp_stop().
        aoso_log_error("TOUR", "Refusing POLAR/LANDING at " + SHIP:BODY:NAME +
            ": orbit is still hyperbolic (e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) +
            " PE=" + ROUND(PERIAPSIS, 0) + "m). Capture must bind first.").
        IF DEFINED AOSO_EVENTS {
            aoso_event_publish("HOLD", "tour", "unbound arrival at " + SHIP:BODY:NAME).
        }
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }

    IF NOT aoso_tour_orbit_is_stable() {
        LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
        IF PERIAPSIS < park {
            aoso_log_info("TOUR", "Raising periapsis to " + ROUND(park, 0) + "m before polar capture.").
            LOCAL nd_pe IS aoso_hohmann_add_periapsis_change(park).
            IF nd_pe = 0 {
                aoso_warp_stop().
                aoso_log_error("TOUR", "Could not create periapsis stabilization node at " +
                    SHIP:BODY:NAME + " - SAFE HOLD; stabilization failure is not permission to descend.").
                IF DEFINED AOSO_EVENTS {
                    aoso_event_publish("HOLD", "tour", "periapsis stabilization failed").
                }
                aoso_state_abort(AOSO_TOUR).
            }
            RETURN.
        }
        aoso_log_info("TOUR", "Circularizing at periapsis before polar.").
        LOCAL nd_c IS aoso_hohmann_add_circularize_at_periapsis().
        IF nd_c = 0 {
            aoso_warp_stop().
            aoso_log_error("TOUR", "Could not create stabilization/circularization node at " +
                SHIP:BODY:NAME + " - SAFE HOLD; survey requires a bound stable orbit.").
            IF DEFINED AOSO_EVENTS {
                aoso_event_publish("HOLD", "tour", "circularization failed").
            }
            aoso_state_abort(AOSO_TOUR).
        }
        RETURN.
    }

    IF NOT aoso_tour_is_polar() {
        LOCAL tgt IS aoso_config_get("TOUR_POLAR_INCLINATION", 90).
        LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
        LOCAL high_ap IS aoso_capture_high_ap(park).
        LOCAL ap_now IS aoso_orbit_apoapsis_alt().
        // Any eccentricity. A 15 km circle (ecc ~0) and a leftover capture
        // ellipse both need the slow node near the survey apoapsis. Do not
        // plane-change at circular periapsis, and do not SCAN until polar.
        LOCAL ap_off IS FALSE.
        IF ap_now < high_ap * 0.7 { SET ap_off TO TRUE. }
        IF ap_now > high_ap * 1.35 { SET ap_off TO TRUE. }
        IF ap_off {
            aoso_log_info("TOUR", "Setting AP to " + ROUND(high_ap, 0) + "m before polar plane-change (now " + ROUND(ap_now, 0) + "m, inc " + ROUND(SHIP:ORBIT:INCLINATION, 1) + " deg). Not scanning until the orbit is polar.").
            LOCAL nd_ap IS aoso_hohmann_add_apoapsis_change(high_ap).
            IF nd_ap = 0 {
                aoso_log_warn_every(15, "POLAR_AP", "Could not set apoapsis before the polar plane-change at " + SHIP:BODY:NAME + " (inc " + ROUND(SHIP:ORBIT:INCLINATION, 1) + " deg). Not scanning an equatorial orbit.").
                SET data["polar_ready"] TO FALSE.
                SET AOSO_TOUR["need_entry"] TO TRUE.
            }
            RETURN.
        }
        aoso_log_info("TOUR", "Plane-changing to polar (" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " -> " + tgt + " deg) at the slow node.").
        LOCAL pe_min IS aoso_capture_safe_pe_floor(park).
        LOCAL dive_pe IS aoso_config_get("DESCENT_SAFE_PE_ALT", 8000).
        IF NOT SHIP:BODY:ATM:EXISTS {
            IF pe_min < dive_pe { SET pe_min TO dive_pe. }
        }
        LOCAL nd_p IS aoso_planechange_add_node_for_inclination(tgt, aoso_config_get("TOUR_POLAR_TOLERANCE_DEG", 5), pe_min).
        IF nd_p = 0 {
            aoso_log_warn_every(15, "POLAR_NODE", "No polar plane-change node yet at " + SHIP:BODY:NAME + " (inc " + ROUND(SHIP:ORBIT:INCLINATION, 1) + " deg). Not scanning until inclination is near " + ROUND(tgt, 0) + " deg.").
            SET data["polar_ready"] TO FALSE.
            SET AOSO_TOUR["need_entry"] TO TRUE.
        }
        RETURN.
    }

    aoso_log_info("TOUR", "Polar parking established (inc=" + ROUND(SHIP:ORBIT:INCLINATION, 1) + " deg).").
    aoso_state_transition(AOSO_TOUR, "SCAN").
}

FUNCTION aoso_tour_polar_execute {
    PARAMETER data.
    IF data:HASKEY("polar_ready") {
        IF NOT data["polar_ready"] { RETURN. }
    }
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_TOUR).
        RETURN.
    }
    IF NOT HASNODE {
        aoso_state_transition(AOSO_TOUR, "POLAR").
        RETURN.
    }
    LOCAL nd IS NEXTNODE.

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
        LOCAL verified0 IS FALSE.
        IF result:HASKEY("verified") { SET verified0 TO result["verified"]. }
        SET data["site_verified"] TO verified0.
        LOCAL ver_txt IS "no".
        IF verified0 { SET ver_txt TO "yes". }
        aoso_log_info("TOUR", "Landing site seed lat=" + ROUND(result["lat"], 2) +
            " lng=" + ROUND(result["lng"], 2) + " alt=" + ROUND(result["alt"], 0) +
            "m slope=" + ROUND(result["slope"], 1) + "deg rough=" +
            ROUND(rough0, 0) + "m score=" + ROUND(result["score"], 2) +
            " verified=" + ver_txt + ".").
        IF NOT verified0 {
            aoso_log_warn("TOUR", "Predicted site is unloaded terrain. A live overflight will replace it.").
        }
        aoso_decide("TOUR", "site", ROUND(result["lat"], 2) + "/" + ROUND(result["lng"], 2), "scan", "score=" + ROUND(result["score"], 2) + " slope=" + ROUND(result["slope"], 1) + " verified=" + ver_txt).
    } ELSE {
        SET data["site_lat"] TO SHIP:GEOPOSITION:LAT.
        SET data["site_lng"] TO SHIP:GEOPOSITION:LNG.
        SET data["site_alt"] TO SHIP:GEOPOSITION:TERRAINHEIGHT.
        SET data["site_roughness"] TO aoso_landing_site_roughness_m(SHIP:GEOPOSITION).
        SET data["site_verified"] TO TRUE.
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
        " orbit max). An unloaded prediction loses to the first safe overflight; verified samples then keep the better score.").
}

FUNCTION aoso_tour_scan_execute {
    PARAMETER data.
    LOCAL now IS TIME:SECONDS.
    IF data:HASKEY("scan_until") {
        IF now < data["scan_until"] {
            IF now >= data["scan_next_sample"] {
                LOCAL geo IS SHIP:GEOPOSITION.
                LOCAL sc IS aoso_landing_site_score(geo).
                IF NOT data:HASKEY("site_verified") { SET data["site_verified"] TO FALSE. }
                IF NOT data["site_verified"] {
                    LOCAL seed_geo IS LATLNG(data["site_lat"], data["site_lng"]).
                    IF aoso_landing_site_near_ship(seed_geo) {
                        LOCAL seed_sc IS aoso_landing_site_score(seed_geo).
                        IF seed_sc >= 0 {
                            LOCAL old_seed IS data["site_score"].
                            SET data["site_alt"] TO seed_geo:TERRAINHEIGHT.
                            SET data["site_score"] TO seed_sc.
                            SET data["site_roughness"] TO aoso_landing_site_roughness_m(seed_geo).
                            SET data["site_verified"] TO TRUE.
                            aoso_log_info("TOUR", "Rescored predicted site under the ship: score " +
                                ROUND(old_seed, 2) + " -> " + ROUND(seed_sc, 2) +
                                " lat=" + ROUND(seed_geo:LAT, 2) + " lng=" + ROUND(seed_geo:LNG, 2) +
                                " alt=" + ROUND(seed_geo:TERRAINHEIGHT, 0) + "m rough=" +
                                ROUND(data["site_roughness"], 0) + "m verified=yes.").
                        }
                    }
                }
                IF sc >= 0 {
                    LOCAL was_verified IS data["site_verified"].
                    LOCAL take IS FALSE.
                    IF data["site_score"] < 0 { SET take TO TRUE. }
                    ELSE IF NOT was_verified { SET take TO TRUE. }
                    ELSE IF sc + 0.05 < data["site_score"] { SET take TO TRUE. }
                    IF take {
                        LOCAL old_sc IS data["site_score"].
                        SET data["site_lat"] TO geo:LAT.
                        SET data["site_lng"] TO geo:LNG.
                        SET data["site_alt"] TO geo:TERRAINHEIGHT.
                        SET data["site_score"] TO sc.
                        SET data["site_roughness"] TO aoso_landing_site_roughness_m(geo).
                        SET data["site_verified"] TO TRUE.
                        IF was_verified {
                            aoso_log_info("TOUR", "Live polar overflight improved landing site: score " +
                                ROUND(old_sc, 2) + " -> " + ROUND(sc, 2) + " lat=" +
                                ROUND(geo:LAT, 2) + " lng=" + ROUND(geo:LNG, 2) +
                                " alt=" + ROUND(geo:TERRAINHEIGHT, 0) + "m rough=" +
                                ROUND(data["site_roughness"], 0) + "m.").
                        } ELSE {
                            aoso_log_info("TOUR", "Live overflight replaced unloaded site prediction: score " +
                                ROUND(old_sc, 2) + " -> " + ROUND(sc, 2) + " lat=" +
                                ROUND(geo:LAT, 2) + " lng=" + ROUND(geo:LNG, 2) +
                                " alt=" + ROUND(geo:TERRAINHEIGHT, 0) + "m rough=" +
                                ROUND(data["site_roughness"], 0) + "m.").
                        }
                    } ELSE {
                        aoso_log_every(80, "TOUR", "Overflight sample lat=" + ROUND(geo:LAT, 2) +
                            " lng=" + ROUND(geo:LNG, 2) + " score=" + ROUND(sc, 2) +
                            " best=" + ROUND(data["site_score"], 2) + " verified=" + data["site_verified"] + ".").
                    }
                }
                SET data["scan_next_sample"] TO now + 25.
            }
            LOCAL left IS data["scan_until"] - now.

            aoso_steer_release().
            aoso_warp_approach(left, 15, 8).
            RETURN.
        }
    }
    IF NOT aoso_warp_ensure_physics_idle() {
        RETURN.
    }
    SET data["deorbit_wait_since"] TO TIME:SECONDS.
    LOCAL final_rough IS 0.
    IF data:HASKEY("site_roughness") { SET final_rough TO data["site_roughness"]. }
    IF NOT data:HASKEY("site_verified") { SET data["site_verified"] TO FALSE. }
    LOCAL ver_txt IS "no".
    IF data["site_verified"] { SET ver_txt TO "yes". }
    aoso_log_info("TOUR", "Polar survey complete. Selected site lat=" +
        ROUND(data["site_lat"], 2) + " lng=" + ROUND(data["site_lng"], 2) +
        " score=" + ROUND(data["site_score"], 2) + " rough=" +
        ROUND(final_rough, 0) + "m verified=" + ver_txt + " AP=" + ROUND(APOAPSIS, 0) +
        " PE=" + ROUND(PERIAPSIS, 0) + " inc=" +
        ROUND(SHIP:ORBIT:INCLINATION, 1) + " - timing deorbit/descent next.").
    IF NOT data["site_verified"] {
        aoso_log_warn("TOUR", "Survey ended on an unverified site. Deorbit will use the prediction anyway.").
    }
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

    LOCAL waited IS TIME:SECONDS - data["deorbit_wait_since"].
    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { SET period TO 600. }
    LOCAL align_s IS aoso_maneuver_align_s().
    LOCAL target_ang IS aoso_tour_deorbit_target_ang(period, align_s).

    LOCAL opposite IS FALSE.
    LOCAL site_ang IS 0.
    LOCAL opp_txt IS "NO".
    IF have_site {
        SET site_ang TO aoso_tour_site_vang(data["site_lat"], data["site_lng"]).
        IF NOT data:HASKEY("deorbit_ang_peak") { SET data["deorbit_ang_peak"] TO site_ang. }
        IF site_ang > data["deorbit_ang_peak"] { SET data["deorbit_ang_peak"] TO site_ang. }
        // A polar survey ellipse never reaches 179. This Minmus pass crested
        // at 129 (ship -18/83 vs site 29/-152). The 150 deg floor never
        // armed, so TIMEOUT burned at 75 deg. A 2 deg drop is too twitchy
        // on the same pass: 113 fell only to 106 and then climbed to 129,
        // and a polar passage peaked at 68. On a fat ellipse, commit once
        // the high-water mark has cleared 100 and fallen 12 deg (129 -> 116
        // fires; 113 -> 106 and 68 do not). A round orbit keeps the 150/2
        // gate. Reaching the 179 target still wins on the YES path.
        LOCAL falling IS FALSE.
        LOCAL floor_ang IS aoso_config_get("DEORBIT_OPPOSITE_MIN_DEG", 150).
        LOCAL drop_ang IS 2.
        IF SHIP:ORBIT:ECCENTRICITY >= 0.25 {
            SET floor_ang TO 100.
            SET drop_ang TO 12.
        }
        IF data["deorbit_ang_peak"] >= floor_ang {
            IF site_ang < data["deorbit_ang_peak"] - drop_ang { SET falling TO TRUE. }
        }
        IF site_ang >= target_ang {
            SET opposite TO TRUE.
            SET opp_txt TO "YES".
        }
        IF falling {
            SET opposite TO TRUE.
            SET opp_txt TO "PEAK".
        }
    }

    IF waited >= period * 1.05 {
        SET opposite TO TRUE.
        SET opp_txt TO "TIMEOUT".
    }

    IF have_site {
        IF NOT opposite {
            LOCAL guess IS period * (target_ang - site_ang) / 360.
            IF guess < 20 { SET guess TO 20. }

            IF NOT data:HASKEY("deorbit_warp_logged") {
                aoso_log_info("TOUR", "Rails-warping until the landing site is opposite before deorbit (up to ~" + ROUND(period, 0) + "s). site lat=" +
                    ROUND(data["site_lat"], 2) + " lng=" + ROUND(data["site_lng"], 2) + " ship lat=" +
                    ROUND(SHIP:GEOPOSITION:LAT, 2) + " lng=" + ROUND(SHIP:GEOPOSITION:LNG, 2) + " ang=" + ROUND(site_ang, 0) +
                    " target=" + ROUND(target_ang, 0) + " align=" + ROUND(align_s, 0) + "s.").
                SET data["deorbit_warp_logged"] TO TRUE.
            }
            aoso_log_every(45, "TOUR", "Deorbit wait opposite=NO ang=" + ROUND(site_ang, 0) + " deg target=" + ROUND(target_ang, 0) +
                " peak=" + ROUND(data["deorbit_ang_peak"], 0) + " ship=" +
                ROUND(SHIP:GEOPOSITION:LAT, 1) + "/" + ROUND(SHIP:GEOPOSITION:LNG, 1) + " site=" +
                ROUND(data["site_lat"], 1) + "/" + ROUND(data["site_lng"], 1) + " waited=" + ROUND(waited, 0) +
                "s period=" + ROUND(period, 0) + "s " + aoso_warp_diag_txt() + ".").
            aoso_steer_release().
            aoso_warp_approach(guess, 20, 10).
            RETURN.
        }
    }

    // Dropping out of rails onto a short node overshoots. A 1000x drop
    // still advanced 78s after WARP already read 0, so a 50s node was
    // missed by 54s. Remember the UT of the drop and only place once a
    // later tick moves a few seconds — one rails flush cannot put ETA
    // negative.
    IF WARP > 0 {
        aoso_log_every(8, "TOUR", "Deorbit settling " + aoso_warp_diag_txt() + " opposite=" + opp_txt + " ang=" + ROUND(site_ang, 0) + " deg before placing node.").
        SET data["deorbit_settle_ut"] TO TIME:SECONDS.
        SET WARP TO 0.
        RETURN.
    }
    IF data:HASKEY("deorbit_settle_ut") {
        LOCAL jumped IS TIME:SECONDS - data["deorbit_settle_ut"].
        SET data["deorbit_settle_ut"] TO TIME:SECONDS.
        IF jumped > 3 {
            aoso_log_every(8, "TOUR", "Deorbit waiting out rails flush (" + ROUND(jumped, 0) + "s) before placing node. opposite=" + opp_txt + " ang=" + ROUND(site_ang, 0) + " " + aoso_warp_diag_txt() + ".").
            SET WARP TO 0.
            RETURN.
        }
        data:REMOVE("deorbit_settle_ut").
    }

    LOCAL eta_s IS -1.
    IF opposite { SET eta_s TO aoso_maneuver_align_s(). }
    // The node dv is the apoapsis Hohmann value. Lighting it 50s from a
    // crest near periapsis barely lowers PE (this pass: -10.5 m/s, PE
    // 133878 -> 36652, target 3677). On a fat ellipse put the burn at
    // apoapsis. If this apo is already inside the align window, take the
    // next one so the node is not born missed.
    IF opposite {
        IF SHIP:ORBIT:ECCENTRICITY >= 0.25 {
            IF NOT aoso_orbit_is_hyperbolic() {
                LOCAL eta_apo IS aoso_orbit_eta_apoapsis().
                IF eta_apo < align_s + 20 {
                    IF period > align_s + 80 { SET eta_apo TO eta_apo + period. }
                }
                SET eta_s TO eta_apo.
            }
        }
    }
    aoso_log_info("TOUR", "Placing deorbit node opposite=" + opp_txt + " ang=" + ROUND(site_ang, 0) +
        " deg target=" + ROUND(target_ang, 0) + " align=" + ROUND(align_s, 0) +
        "s eta=" + ROUND(eta_s, 0) + "s AP=" + ROUND(APOAPSIS, 0) + " PE=" + ROUND(PERIAPSIS, 0) +
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

            aoso_log_every(20, "TOUR", "Holding launch - surface not stable.").
            RETURN.
        }
        LOCAL dep IS aoso_depart_certify().
        IF dep["status"] = "NOT_READY" {

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
    SET AOSO_TOUR["data"] TO LEXICON("targets", targets, "index", 0, "site_lat", 0, "site_lng", 0, "site_alt", 0, "site_score", -1, "site_verified", FALSE, "deorbit_wait_since", 0, "polar_warp_logged", FALSE, "scan_until", 0, "scan_next_sample", 0, "scan_orbits", 1, "accomplished", LEXICON(), "depart_ok", FALSE).
    aoso_log_info("TOUR", "Grand tour armed: " + targets:LENGTH + " bodies (" + aoso_classify_name() + "), then KSC return.").
    aoso_decide("TOUR", "arm", "" + targets:LENGTH, aoso_classify_name(), "n=" + targets:LENGTH).
    aoso_state_transition(AOSO_TOUR, "BOOT").
}

FUNCTION aoso_tour_update {
    aoso_state_update(AOSO_TOUR).
    LOCAL st IS AOSO_TOUR["current"].
    IF st = "SCAN" OR st = "POLAR" OR st = "DEORBIT" {
        LOCAL prog IS 0.
        IF st = "SCAN" {
            SET prog TO ABS(SHIP:GEOPOSITION:LAT) / 90.
        } ELSE IF st = "POLAR" {
            SET prog TO SHIP:ORBIT:INCLINATION / 180.
        } ELSE IF AOSO_TOUR["data"]:HASKEY("site_lat") {
            SET prog TO aoso_tour_site_vang(AOSO_TOUR["data"]["site_lat"], AOSO_TOUR["data"]["site_lng"]) / 180.
        }
        IF prog < 0 { SET prog TO 0. }
        IF prog > 1 { SET prog TO 1. }
        aoso_hb_set("tour", st, prog).
    }
}

FUNCTION aoso_tour_is_done {
    RETURN AOSO_TOUR["current"] = "DONE".
}

FUNCTION aoso_tour_is_aborted {
    RETURN AOSO_TOUR["current"] = "ABORTED".
}
