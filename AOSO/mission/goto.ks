// AOSO/mission/goto.ks
// Navigate SHIP to a named body, one hop at a time, reusing the existing
// burn helpers (rendezvous phasing for moons of the current body,
// moonescape toward a parent, interplanetary ejection toward a sibling
// planet, capture at arrival). Mirrors return/return.ks's "classify and
// take one hop, then re-plan after the SOI change" loop, but toward an
// arbitrary goal instead of HOME_BODY.
//
// Interplanetary hops wait for the transfer window (interplanetary/
// transfer.ks) before adding the ejection node -- ejection.ks sizes the
// burn geometry, it does not pick the pass. Never capture around the Sun.

GLOBAL AOSO_GOTO IS aoso_state_new_machine().
GLOBAL AOSO_WANT_POLAR IS FALSE.

FUNCTION aoso_goto_parking_alt {
    PARAMETER b.
    IF b:ATM:EXISTS {
        RETURN MAX(aoso_config_get("PARKING_ORBIT_ALT", 100000), b:ATM:HEIGHT + 15000).
    }
    RETURN MAX(15000, b:RADIUS * 0.08).
}

// Next body to travel toward: the current body's parent, a moon of here,
// a sibling planet, or the parent of a foreign moon. Climbing moons first
// keeps Mun->Minmus and Pol->Eeloo as "escape, then transfer" rather than
// trying to solve a moon-to-moon Lambert in one burn.
FUNCTION aoso_goto_next_hop_body {
    PARAMETER goal.

    LOCAL here IS SHIP:BODY.
    IF here:NAME = goal:NAME { RETURN goal. }

    IF goal:NAME <> SUN:NAME {
        IF goal:BODY:NAME = here:NAME { RETURN goal. }
    }

    IF here:NAME <> SUN:NAME {
        IF here:BODY:NAME = goal:NAME { RETURN goal. }
    }

    // On a moon: climb to the parent unless the goal *is* that parent.
    IF here:NAME <> SUN:NAME {
        IF here:BODY:NAME <> SUN:NAME {
            RETURN here:BODY.
        }
    }

    // On a sun-orbiting body (or already around the Sun). Goal is a moon
    // of another planet -> that planet first.
    IF goal:NAME <> SUN:NAME {
        IF goal:BODY:NAME <> SUN:NAME {
            RETURN goal:BODY.
        }
    }

    RETURN goal.
}

FUNCTION aoso_goto_orbit_is_parked {
    LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
    IF SHIP:ORBIT:ECCENTRICITY >= 0.12 { RETURN FALSE. }
    IF PERIAPSIS < 0 { RETURN FALSE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT + 5000 { RETURN FALSE. }
    } ELSE {
        IF PERIAPSIS < park * 0.45 { RETURN FALSE. }
    }
    LOCAL soi_a IS SHIP:BODY:SOIRADIUS - SHIP:BODY:RADIUS.
    IF PERIAPSIS > soi_a * 0.2 { RETURN FALSE. }
    IF PERIAPSIS > park * 4 { RETURN FALSE. }
    RETURN TRUE.
}

// TRUE when we should circularize/capture around the body we are in now.
// Never recapture the *departure* body after a moon-transfer burn — that
// turned a 80×49 000 km Minmus miss into a 2.5-day warp to raise Kerbin PE
// by 0.5 m/s. Capture at the hop/goal after the SOI change, at periapsis.
FUNCTION aoso_goto_should_capture {
    PARAMETER data.

    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" { RETURN FALSE. }
    IF SHIP:BODY:NAME = SUN:NAME { RETURN FALSE. }
    IF data:HASKEY("skip_capture") {
        IF data["skip_capture"] { RETURN FALSE. }
    }

    IF data:HASKEY("depart_body") {
        IF SHIP:BODY:NAME = data["depart_body"] {
            // Negative PE on the departure body is often a patched-conics
            // lie after a moon intercept (Acacius PE=-148 km at 33 000 km
            // still 35 h from PE, then recaptured Kerbin and killed Minmus).
            // Only recapture if we are actually about to hit the air.
            IF PERIAPSIS < 0 {
                IF data:HASKEY("expect_ut") {
                    IF data["expect_ut"] > TIME:SECONDS + 60 { RETURN FALSE. }
                }
                LOCAL pe_eta IS 9E9.
                IF NOT aoso_orbit_is_hyperbolic() { SET pe_eta TO ETA:PERIAPSIS. }
                LOCAL danger IS 80000.
                IF SHIP:BODY:ATM:EXISTS { SET danger TO SHIP:BODY:ATM:HEIGHT + 25000. }
                IF pe_eta < 480 {
                    IF ALTITUDE < danger { RETURN TRUE. }
                }
            }
            RETURN FALSE.
        }
    }

    LOCAL should_stop IS FALSE.
    IF SHIP:BODY:NAME = data["goal"] {
        SET should_stop TO TRUE.
    } ELSE {
        LOCAL g IS BODY(data["goal"]).
        IF g:NAME <> SUN:NAME {
            IF g:BODY:NAME = SHIP:BODY:NAME { SET should_stop TO TRUE. }
        }
    }

    IF should_stop {
        IF aoso_goto_orbit_is_parked() { RETURN FALSE. }
        RETURN TRUE.
    }

    IF SHIP:STATUS = "ESCAPING" { RETURN FALSE. }
    IF SHIP:ORBIT:HASNEXTPATCH { RETURN FALSE. }
    IF PERIAPSIS < 0 { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION aoso_goto_patch_body_name {
    IF NOT SHIP:ORBIT:HASNEXTPATCH { RETURN "". }
    RETURN SHIP:ORBIT:NEXTPATCH:BODY:NAME.
}

FUNCTION aoso_goto_patch_is_ours {
    PARAMETER data.
    PARAMETER np.
    IF np = "" { RETURN FALSE. }
    IF np = data["goal"] { RETURN TRUE. }
    IF np = data["hop"] { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION aoso_goto_remember_patch {
    PARAMETER data.
    PARAMETER np.
    PARAMETER eta_s.
    IF NOT aoso_goto_patch_is_ours(data, np) { RETURN. }
    SET data["expect_body"] TO np.
    SET data["expect_ut"] TO TIME:SECONDS + eta_s.
    SET data["patch_lost_ut"] TO 0.
    SET data["last_patch_ut"] TO TIME:SECONDS.
}

FUNCTION aoso_goto_on_abort {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_maneuver_clear_all().
    aoso_state_transition(AOSO_GOTO, "ABORTED").
}

FUNCTION aoso_goto_plan_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_maneuver_clear_all().
    aoso_ui_pulse("Planning hop", "Next body toward " + data["goal"]).

    LOCAL goal IS BODY(data["goal"]).

    IF SHIP:BODY:NAME = goal:NAME {
        IF aoso_goto_should_capture(data) {
            aoso_state_transition(AOSO_GOTO, "CAPTURE").
            RETURN.
        }
        aoso_log_info("GOTO", "Already at " + goal:NAME + ".").
        aoso_state_transition(AOSO_GOTO, "DONE").
        RETURN.
    }

    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" {
        aoso_log_info("GOTO", "Landed on " + SHIP:BODY:NAME + " - launching before the next hop.").
        aoso_ascent_start(90, aoso_goto_parking_alt(SHIP:BODY)).
        SET data["burn_kind"] TO "launch".
        aoso_state_transition(AOSO_GOTO, "LAUNCH").
        RETURN.
    }

    IF aoso_goto_should_capture(data) {
        aoso_state_transition(AOSO_GOTO, "CAPTURE").
        RETURN.
    }

    SET data["depart_body"] TO SHIP:BODY:NAME.

    LOCAL hop IS aoso_goto_next_hop_body(goal).
    SET data["hop"] TO hop:NAME.
    aoso_log_info("GOTO", "Next hop " + SHIP:BODY:NAME + " -> " + hop:NAME + " (goal " + goal:NAME + ").").

    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        LOCAL patch_ours IS FALSE.
        IF np = goal:NAME { SET patch_ours TO TRUE. }
        IF np = hop:NAME { SET patch_ours TO TRUE. }
        IF patch_ours {
            aoso_goto_remember_patch(data, np, SHIP:ORBIT:NEXTPATCHETA).
            LOCAL hop_b IS BODY(np).
            IF aoso_rendezvous_orbit_needs_correct(SHIP:ORBIT, hop_b) {
                LOCAL ncorr IS 0.
                IF data:HASKEY("correct_count") { SET ncorr TO data["correct_count"]. }
                LOCAL pe_now IS aoso_rendezvous_orbit_pe(SHIP:ORBIT, hop_b).
                LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
                LOCAL do_corr IS FALSE.
                IF pe_now < 0 { SET do_corr TO TRUE. }
                ELSE {
                    IF eta_p < aoso_config_get("GOTO_CORRECT_WITHIN_S", 28800) { SET do_corr TO TRUE. }
                }
                IF do_corr {
                    IF ncorr < 3 {
                        SET data["corrected"] TO TRUE.
                        SET data["correct_count"] TO ncorr + 1.
                        LOCAL ndc IS aoso_rendezvous_add_correction_node(hop_b).
                        IF ndc <> 0 {
                            aoso_log_info("GOTO", "Patch to " + np + " has a poor PE - mid-course correction " + data["correct_count"] + "/3.").
                            SET data["burn_kind"] TO "correct".
                            aoso_state_transition(AOSO_GOTO, "BURN").
                            RETURN.
                        }
                    }
                } ELSE {
                    aoso_log_info("GOTO", "Patch to " + np + " PE=" + ROUND(pe_now, 0) + "m is a far-out graze - coasting until " + ROUND(aoso_config_get("GOTO_CORRECT_WITHIN_S", 28800) / 3600, 1) + "h of SOI before correcting (conics lie at this range).").
                }
            }
            aoso_log_info("GOTO", "Existing patch to " + np + " - coasting.").
            SET data["burn_kind"] TO "coast".
            aoso_state_transition(AOSO_GOTO, "COAST").
            RETURN.
        }
        IF SHIP:STATUS = "ESCAPING" {
            aoso_log_info("GOTO", "Already escaping toward " + np + " - coasting.").
            SET data["burn_kind"] TO "coast".
            aoso_state_transition(AOSO_GOTO, "COAST").
            RETURN.
        }
        IF SHIP:BODY:NAME <> SUN:NAME {
            IF np = SHIP:BODY:BODY:NAME {
                aoso_log_info("GOTO", "Existing escape patch to " + np + " - coasting.").
                SET data["burn_kind"] TO "coast".
                aoso_state_transition(AOSO_GOTO, "COAST").
                RETURN.
            }
        }
    }

    LOCAL rel_incl IS aoso_orbit_relative_inclination_deg(SHIP, hop).
    LOCAL match_plane IS TRUE.
    IF AOSO_WANT_POLAR { SET match_plane TO FALSE. }
    IF aoso_addon_available("ASTROGATOR") { SET match_plane TO FALSE. }
    IF rel_incl > 2 {
        IF match_plane {
            LOCAL nd_pc IS aoso_planechange_add_node_for_target(hop).
            IF nd_pc <> 0 {
                SET data["burn_kind"] TO "plane".
                aoso_state_transition(AOSO_GOTO, "BURN").
                RETURN.
            }
        } ELSE {
            LOCAL why IS "polar arrival".
            IF aoso_addon_available("ASTROGATOR") { SET why TO "Astrogator will own the intercept/plane". }
            aoso_log_info("GOTO", "Skipping " + ROUND(rel_incl, 1) + " deg plane-match to " + hop:NAME + " (" + why + ").").
        }
    }

    // Around the Sun: Hohmann to the hop body's solar altitude, then coast
    // for an encounter. Never try planetary ejection from solar orbit.
    IF SHIP:BODY:NAME = SUN:NAME {
        IF hop:NAME = SUN:NAME {
            aoso_log_error("GOTO", "Refusing to capture around the Sun.").
            aoso_state_abort(AOSO_GOTO).
            RETURN.
        }
        LOCAL hop_alt IS hop:ORBIT:SEMIMAJORAXIS - SHIP:BODY:RADIUS.
        LOCAL nd_s IS aoso_hohmann_transfer_to_altitude(hop_alt).
        IF nd_s = 0 {
            aoso_state_abort(AOSO_GOTO).
            RETURN.
        }
        SET data["burn_kind"] TO "solar".
        aoso_state_transition(AOSO_GOTO, "BURN").
        RETURN.
    }

    // Moon of the current body: Hohmann phasing transfer into its SOI.
    // If an inner moon flyby saves dV (or fuel is tight), intercept that
    // moon first and do not capture -- same pattern as a Mun pump to Minmus.
    IF hop:NAME <> SUN:NAME {
        IF hop:BODY:NAME = SHIP:BODY:NAME {
            LOCAL kind IS "transfer".
            LOCAL via IS aoso_assist_should_flyby(hop).
            IF via:ISTYPE("Body") {
                SET hop TO via.
                SET data["hop"] TO hop:NAME.
                SET kind TO "assist".
            }
            LOCAL nd_m IS aoso_rendezvous_add_phasing_transfer_node(hop).
            IF nd_m = 0 {
                IF SHIP:ORBIT:HASNEXTPATCH {
                    IF SHIP:ORBIT:NEXTPATCH:BODY:NAME = hop:NAME {
                        SET data["burn_kind"] TO kind.
                        SET data["retry_ut"] TO 0.
                        aoso_state_transition(AOSO_GOTO, "COAST").
                        RETURN.
                    }
                }
                LOCAL period IS aoso_orbit_period_s().
                IF period < 90 { SET period TO 90. }
                SET data["retry_ut"] TO TIME:SECONDS + period.
                aoso_log_warn("GOTO", "No " + hop:NAME + " intercept this window - warping one orbit (" + ROUND(period, 0) + "s) and retrying. Will not burn a blind Hohmann.").
                SET data["burn_kind"] TO "coast".
                aoso_state_transition(AOSO_GOTO, "COAST").
                RETURN.
            }
            SET data["burn_kind"] TO kind.
            SET data["retry_ut"] TO 0.
            aoso_maneuver_clear_apo_cap().
            aoso_maneuver_set_cut_body(hop:NAME).
            aoso_state_transition(AOSO_GOTO, "BURN").
            RETURN.
        }
    }

    // Escape toward parent.
    IF SHIP:BODY:NAME <> SUN:NAME {
        IF hop:NAME = SHIP:BODY:BODY:NAME {
            LOCAL nd_e IS aoso_moonescape_add_escape_node(aoso_goto_parking_alt(hop)).
            IF nd_e = 0 {
                aoso_state_abort(AOSO_GOTO).
                RETURN.
            }
            SET data["burn_kind"] TO "escape".
            aoso_state_transition(AOSO_GOTO, "BURN").
            RETURN.
        }
    }

    // Sibling planets sharing a parent (the Sun, usually).
    IF hop:NAME <> SUN:NAME {
        IF hop:BODY:NAME = SHIP:BODY:BODY:NAME {
            LOCAL decision IS aoso_window_decide(SHIP:BODY, hop).
            LOCAL wait_s IS decision["wait_s"].
            IF wait_s < 0 { SET wait_s TO 0. }
            IF decision["action"] = "WAIT" {
                SET data["window_ut"] TO TIME:SECONDS + wait_s.
                SET data["burn_kind"] TO "eject".
                aoso_log_info("GOTO", "Window to " + hop:NAME + ": wait " + ROUND(wait_s, 0) +
                    "s  eff=" + decision["efficiency"] + "  best dV=" + decision["best_dv"] +
                    "  now dV=" + decision["now_dv"] + "  (" + decision["why"] + ").").
                aoso_state_transition(AOSO_GOTO, "WAIT").
                RETURN.
            }
            LOCAL nd_j IS aoso_interplanetary_add_ejection_node(hop).
            IF nd_j = 0 {
                aoso_state_abort(AOSO_GOTO).
                RETURN.
            }
            SET data["burn_kind"] TO "eject".
            aoso_state_transition(AOSO_GOTO, "BURN").
            RETURN.
        }
    }

    aoso_log_error("GOTO", "No hop from " + SHIP:BODY:NAME + " toward " + goal:NAME + ".").
    aoso_state_abort(AOSO_GOTO).
}

FUNCTION aoso_goto_wait_execute {
    PARAMETER data.
    IF NOT data:HASKEY("window_ut") {
        aoso_state_transition(AOSO_GOTO, "PLAN").
        RETURN.
    }
    IF NOT data:HASKEY("hop") {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    IF data["hop"] = "" {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    LOCAL align_s IS aoso_maneuver_align_s().
    IF TIME:SECONDS >= data["window_ut"] - align_s {
        SET WARP TO 0.
        LOCAL hop IS BODY(data["hop"]).
        LOCAL nd IS aoso_interplanetary_add_ejection_node(hop).
        IF nd = 0 {
            aoso_state_abort(AOSO_GOTO).
            RETURN.
        }
        aoso_state_transition(AOSO_GOTO, "BURN").
        RETURN.
    }
    LOCAL wait_eta IS data["window_ut"] - TIME:SECONDS.
    LOCAL wst IS aoso_warp_approach(wait_eta, align_s, aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
}

FUNCTION aoso_goto_launch_execute {
    PARAMETER data.
    aoso_ascent_update().
    IF aoso_ascent_is_aborted() {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    IF aoso_ascent_is_done() {
        aoso_state_transition(AOSO_GOTO, "PLAN").
    }
}

FUNCTION aoso_goto_burn_execute {
    PARAMETER data.
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        LOCAL burn_res IS aoso_maneuver_last_result().
        IF burn_res = "missed" OR burn_res = "incomplete" {
            IF data["burn_kind"] = "transfer" OR data["burn_kind"] = "assist" OR data["burn_kind"] = "correct" {
                IF NOT aoso_orbit_is_hyperbolic() {
                    IF SHIP:ORBIT:ECCENTRICITY > 0.08 {
                        IF NOT aoso_goto_orbit_is_parked() {
                            LOCAL floor_pe IS 8000.
                            IF SHIP:BODY:ATM:EXISTS { SET floor_pe TO SHIP:BODY:ATM:HEIGHT + 5000. }
                            IF PERIAPSIS > floor_pe {
                                aoso_log_warn("GOTO", "Burn " + burn_res + " left e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + " AP=" + ROUND(APOAPSIS, 0) + "m - circularizing at apo before retrying intercept.").
                                LOCAL nd_fix IS aoso_maneuver_add_circularize_at_apoapsis().
                                IF nd_fix <> 0 {
                                    SET data["burn_kind"] TO "circ".
                                    aoso_state_transition(AOSO_GOTO, "BURN").
                                    RETURN.
                                }
                            }
                        }
                    }
                }
            }
            aoso_log_warn("GOTO", "Burn " + burn_res + " - re-planning for the next pass.").
            aoso_state_transition(AOSO_GOTO, "PLAN").
            RETURN.
        }
        IF data["burn_kind"] = "plane" OR data["burn_kind"] = "circ" {
            aoso_state_transition(AOSO_GOTO, "PLAN").
        } ELSE {
            IF HASNODE {
                aoso_log_info("GOTO", "Astrogator left a follow-up node - burning it before coast.").
                SET data["burn_kind"] TO "plane".
                aoso_state_transition(AOSO_GOTO, "BURN").
                RETURN.
            }
            LOCAL npb IS aoso_goto_patch_body_name().
            IF npb <> "" {
                aoso_goto_remember_patch(data, npb, SHIP:ORBIT:NEXTPATCHETA).
            }
            aoso_state_transition(AOSO_GOTO, "COAST").
        }
    }
}

FUNCTION aoso_goto_coast_entry {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_steer_release().
    SET data["coast_since"] TO TIME:SECONDS.
    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        aoso_goto_remember_patch(data, np, SHIP:ORBIT:NEXTPATCHETA).
        SET data["retry_ut"] TO 0.
        RETURN.
    }
    IF data:HASKEY("expect_ut") {
        IF data["expect_ut"] > TIME:SECONDS + 90 {
            aoso_log_info("GOTO", "No live patch after the burn - trusting " + data["expect_body"] + " intercept in " + ROUND(data["expect_ut"] - TIME:SECONDS, 0) + "s (KSP conics often hide it until closer).").
            RETURN.
        }
    }
    IF data["retry_ut"] <= 0 {
        LOCAL period IS aoso_orbit_period_s().
        IF period < 90 { SET period TO 90. }
        IF period > 180 { SET period TO 180. }
        SET data["retry_ut"] TO TIME:SECONDS + period.
        aoso_log_info("GOTO", "No patch after the burn - warping " + ROUND(period, 0) + "s then re-planning.").
    }
}

FUNCTION aoso_goto_coast_execute {
    PARAMETER data.
    IF NOT data:HASKEY("goal") {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    LOCAL goal_name IS data["goal"].
    IF NOT data:HASKEY("depart_body") { SET data["depart_body"] TO SHIP:BODY:NAME. }

    IF SHIP:BODY:NAME = goal_name {
        SET WARP TO 0.
        IF aoso_goto_should_capture(data) {
            aoso_state_transition(AOSO_GOTO, "CAPTURE").
        } ELSE {
            aoso_state_transition(AOSO_GOTO, "DONE").
        }
        RETURN.
    }

    IF SHIP:BODY:NAME <> data["depart_body"] {
        SET WARP TO 0.
        SET data["corrected"] TO FALSE.
        SET data["correct_count"] TO 0.
        SET data["last_patch_ut"] TO 0.
        SET data["expect_body"] TO "".
        SET data["expect_ut"] TO 0.
        SET data["patch_lost_ut"] TO 0.
        SET data["capture_fails"] TO 0.
        SET data["skip_capture"] TO FALSE.
        aoso_log_info("GOTO", "SOI change: " + data["depart_body"] + " -> " + SHIP:BODY:NAME + ".").
        aoso_state_transition(AOSO_GOTO, "PLAN").
        RETURN.
    }

    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        SET data["retry_ut"] TO 0.
        aoso_goto_remember_patch(data, np, SHIP:ORBIT:NEXTPATCHETA).
        LOCAL ncorr IS 0.
        IF data:HASKEY("correct_count") { SET ncorr TO data["correct_count"]. }
        LOCAL hop_check IS BODY(np).
        LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
        LOCAL want_correct IS FALSE.
        IF aoso_goto_patch_is_ours(data, np) {
            IF aoso_rendezvous_orbit_needs_correct(SHIP:ORBIT, hop_check) {
                LOCAL pe_now IS aoso_rendezvous_orbit_pe(SHIP:ORBIT, hop_check).
                LOCAL correct_within IS aoso_config_get("GOTO_CORRECT_WITHIN_S", 28800).
                // Far-out grazes are a conics lie. Only correct a lithobrake
                // immediately, or a graze once we are inside ~8 h of SOI.
                IF pe_now < 0 {
                    SET want_correct TO TRUE.
                } ELSE {
                    IF eta_p < correct_within { SET want_correct TO TRUE. }
                }
            }
        }
        IF want_correct {
            IF eta_p > 150 {
                IF ncorr < 3 {
                    SET WARP TO 0.
                    aoso_log_info("GOTO", "Patch PE is not a capture altitude - mid-course correction.").
                    aoso_state_transition(AOSO_GOTO, "PLAN").
                    RETURN.
                }
            }
        }
        IF eta_p > 30 {
            LOCAL align_s IS aoso_maneuver_align_s().
            aoso_steer_release().
            LOCAL wst IS aoso_warp_approach(eta_p, align_s, aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
            aoso_ui_set("Coasting to " + np, "SOI " + aoso_hud_eta(eta_p) + "  " + aoso_hud_warp_txt()).
        } ELSE {
            SET WARP TO 0.
        }
        RETURN.
    }

    // No live patch. KSP often hides a moon intercept until the ship is
    // closer; a 25 s grace dies in one rails jump and then we recaptured
    // Kerbin. If we already locked an intercept, keep flying to that UT.
    LOCAL expect_body IS "".
    LOCAL expect_ut IS 0.
    IF data:HASKEY("expect_body") { SET expect_body TO data["expect_body"]. }
    IF data:HASKEY("expect_ut") { SET expect_ut TO data["expect_ut"]. }
    LOCAL now IS TIME:SECONDS.
    LOCAL trust_after IS aoso_config_get("GOTO_PATCH_TRUST_S", 600).
    IF expect_body <> "" {
        IF expect_ut > now - trust_after {
            IF NOT data:HASKEY("patch_lost_ut") { SET data["patch_lost_ut"] TO 0. }
            IF data["patch_lost_ut"] <= 0 {
                SET data["patch_lost_ut"] TO now.
                aoso_log_info("GOTO", "Patch to " + expect_body + " dropped (KSP conics flicker) - trusting intercept in " + ROUND(expect_ut - now, 0) + "s.").
            }
            LOCAL lost_for IS now - data["patch_lost_ut"].
            LOCAL flicker_s IS aoso_config_get("GOTO_PATCH_FLICKER_S", 45).
            LOCAL eta_saved IS expect_ut - now.
            IF lost_for < flicker_s {
                aoso_warp_set_physics_cruise().
                aoso_ui_set("Re-checking " + expect_body + " patch", "physics so conics can catch up  T-" + aoso_hud_eta(eta_saved)).
                RETURN.
            }
            IF eta_saved > 30 {
                aoso_steer_release().
                aoso_warp_approach(eta_saved, aoso_maneuver_align_s(), aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
                aoso_log_every(60, "GOTO", "No live patch, trusting " + expect_body + " SOI in " + ROUND(eta_saved, 0) + "s " + aoso_warp_diag_txt() + ".").
                aoso_ui_set("Trusting " + expect_body + " intercept", aoso_hud_eta(eta_saved) + "  " + aoso_hud_warp_txt()).
            } ELSE {
                SET WARP TO 0.
                aoso_ui_set("Waiting on " + expect_body + " SOI", "conics still empty").
            }
            RETURN.
        }
    }

    IF data:HASKEY("retry_ut") {
        IF data["retry_ut"] > 0 {
            LOCAL retry_left IS data["retry_ut"] - TIME:SECONDS.
            IF retry_left <= 8 {
                SET WARP TO 0.
                SET data["retry_ut"] TO 0.
                aoso_log_info("GOTO", "Retry window reached - re-planning intercept.").
                aoso_state_transition(AOSO_GOTO, "PLAN").
                RETURN.
            }
            LOCAL wst2 IS aoso_warp_approach(retry_left, 20, aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
            RETURN.
        }
    }

    LOCAL coasted IS TIME:SECONDS - data["coast_since"].
    IF coasted > 120 {
        SET WARP TO 0.
        aoso_log_warn("GOTO", "No encounter after burn - re-planning.").
        aoso_state_transition(AOSO_GOTO, "PLAN").
        RETURN.
    }
    RETURN.
}

FUNCTION aoso_goto_capture_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
    aoso_log_info("GOTO", "Capturing at " + SHIP:BODY:NAME + " periapsis (Oberth) park=" + ROUND(park, 0) + "m PE=" + ROUND(PERIAPSIS, 0) + "m.").
    IF AOSO_WANT_POLAR {
        aoso_log_info("GOTO", "Landing planned - capture will go polar (inc now " + ROUND(SHIP:ORBIT:INCLINATION, 1) + " deg) instead of a later circular plane-change.").
        aoso_ui_set("Polar capture at PE", SHIP:BODY:NAME + " inc " + ROUND(SHIP:ORBIT:INCLINATION, 1) + " -> 90").
    } ELSE {
        aoso_ui_set("Capture at periapsis", SHIP:BODY:NAME + " park " + ROUND(park, 0) + "m").
    }
    LOCAL nd IS aoso_interplanetary_add_capture_node(park).
    IF nd = 0 {
        LOCAL fails IS 0.
        IF data:HASKEY("capture_fails") { SET fails TO data["capture_fails"]. }
        SET data["capture_fails"] TO fails + 1.
        aoso_log_warn("GOTO", "No capture node (try " + data["capture_fails"] + "/3); continuing from current orbit.").
        IF data["capture_fails"] >= 3 {
            SET data["skip_capture"] TO TRUE.
            IF SHIP:BODY:NAME = data["goal"] {
                aoso_log_warn("GOTO", "Capture failed 3x at goal " + data["goal"] + " - marking arrived.").
                aoso_state_transition(AOSO_GOTO, "DONE").
            } ELSE {
                aoso_log_warn("GOTO", "Capture failed 3x at " + SHIP:BODY:NAME + " - skipping capture and re-planning the hop.").
                aoso_state_transition(AOSO_GOTO, "PLAN").
            }
            RETURN.
        }
        IF aoso_goto_orbit_is_parked() {
            IF SHIP:BODY:NAME = data["goal"] {
                aoso_state_transition(AOSO_GOTO, "DONE").
            } ELSE {
                aoso_state_transition(AOSO_GOTO, "PLAN").
            }
        } ELSE {
            IF SHIP:BODY:NAME = data["goal"] {
                aoso_log_warn("GOTO", "At " + SHIP:BODY:NAME + " but PE=" + ROUND(PERIAPSIS, 0) + "m is not parked - will retry next tick.").
                aoso_state_transition(AOSO_GOTO, "PLAN").
            } ELSE {
                aoso_state_transition(AOSO_GOTO, "PLAN").
            }
        }
    }
}

FUNCTION aoso_goto_capture_execute {
    PARAMETER data.
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    IF NOT HASNODE {
        IF aoso_goto_orbit_is_parked() {
            IF SHIP:BODY:NAME = data["goal"] {
                aoso_state_transition(AOSO_GOTO, "DONE").
            } ELSE {
                aoso_state_transition(AOSO_GOTO, "PLAN").
            }
        } ELSE {
            aoso_state_transition(AOSO_GOTO, "PLAN").
        }
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        LOCAL cap_res IS aoso_maneuver_last_result().
        IF cap_res = "missed" OR cap_res = "incomplete" {
            aoso_log_warn("GOTO", "Capture " + cap_res + " - re-planning.").
            aoso_state_transition(AOSO_GOTO, "PLAN").
            RETURN.
        }
        aoso_state_transition(AOSO_GOTO, "PLAN").
    } ELSE {
        IF HASNODE {
            LOCAL ndc IS NEXTNODE.
            aoso_ui_set("Capture burn T-" + aoso_hud_eta(ndc:ETA), ROUND(ndc:DELTAV:MAG, 1) + " m/s  " + aoso_hud_warp_txt()).
        }
    }
}

FUNCTION aoso_goto_done_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_log_info("GOTO", "Arrived at " + data["goal"] + ".").
}

FUNCTION aoso_goto_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_log_error("GOTO", "Goto " + data["goal"] + " aborted.").
}

FUNCTION aoso_goto_define_states {
    aoso_state_define(AOSO_GOTO, "PLAN", aoso_goto_plan_entry@, 0, 0, 0, 0, aoso_goto_on_abort@).
    aoso_state_define(AOSO_GOTO, "WAIT", 0, aoso_goto_wait_execute@, 0, 0, 0, aoso_goto_on_abort@).
    aoso_state_define(AOSO_GOTO, "LAUNCH", 0, aoso_goto_launch_execute@, 0, 0, 0, aoso_goto_on_abort@).
    aoso_state_define(AOSO_GOTO, "BURN", 0, aoso_goto_burn_execute@, 0, 0, 0, aoso_goto_on_abort@).
    aoso_state_define(AOSO_GOTO, "COAST", aoso_goto_coast_entry@, aoso_goto_coast_execute@, 0, 0, 0, aoso_goto_on_abort@).
    aoso_state_define(AOSO_GOTO, "CAPTURE", aoso_goto_capture_entry@, aoso_goto_capture_execute@, 0, 0, 0, aoso_goto_on_abort@).
    aoso_state_define(AOSO_GOTO, "DONE", aoso_goto_done_entry@, 0, 0).
    aoso_state_define(AOSO_GOTO, "ABORTED", aoso_goto_aborted_entry@, 0, 0).
}

FUNCTION aoso_goto_start {
    PARAMETER body_name.
    aoso_goto_define_states().
    SET AOSO_GOTO["data"] TO LEXICON("goal", body_name, "hop", "", "burn_kind", "", "depart_body", SHIP:BODY:NAME, "window_ut", 0, "coast_since", 0, "retry_ut", 0, "corrected", FALSE, "correct_count", 0, "last_patch_ut", 0, "expect_body", "", "expect_ut", 0, "patch_lost_ut", 0, "capture_fails", 0, "skip_capture", FALSE).
    aoso_log_info("GOTO", "Navigating to " + body_name + ".").
    // Do not run PLAN on the tour/mission stack - that blew kOS's 3000-slot
    // argument stack at aoso_goto_update (Acacius). Queue it; the sibling
    // "goto" scheduler task runs PLAN from a shallow stack next tick.
    aoso_state_queue(AOSO_GOTO, "PLAN").
    aoso_sched_add("goto", 0, aoso_goto_update@).
}

FUNCTION aoso_goto_poll {
    RETURN.
}

FUNCTION aoso_goto_task_pending_entry {
    IF NOT AOSO_GOTO:HASKEY("need_entry") { RETURN FALSE. }
    RETURN AOSO_GOTO["need_entry"].
}

FUNCTION aoso_goto_update {
    IF AOSO_GOTO["current"] = "" { RETURN. }
    LOCAL cur IS AOSO_GOTO["current"].
    IF NOT aoso_goto_task_pending_entry() {
        IF cur = "DONE" {
            aoso_sched_remove("goto").
            RETURN.
        }
        IF cur = "ABORTED" {
            aoso_sched_remove("goto").
            RETURN.
        }
    }
    aoso_state_update(AOSO_GOTO).
    SET cur TO AOSO_GOTO["current"].
    IF NOT aoso_goto_task_pending_entry() {
        IF cur = "DONE" { aoso_sched_remove("goto"). }
        IF cur = "ABORTED" { aoso_sched_remove("goto"). }
    }
}

FUNCTION aoso_goto_is_done {
    RETURN AOSO_GOTO["current"] = "DONE".
}

FUNCTION aoso_goto_is_aborted {
    RETURN AOSO_GOTO["current"] = "ABORTED".
}
