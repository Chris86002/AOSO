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
    IF data:HASKEY("via") {
        IF np = data["via"] { RETURN TRUE. }
    }
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

FUNCTION aoso_goto_ensure_transfer_action {
    PARAMETER data.
    PARAMETER target_name.

    IF target_name = "" { RETURN. }
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        // Retries/corrections for the same hop stay under the same action.
        // Never overwrite ASCENT/LANDING/etc. just to create a transfer.
        IF AOSO_ACTION_CUR["type"] = "TRANSFER" { RETURN. }
        RETURN.
    }

    LOCAL pred_g IS aoso_feas_transfer_cost(SHIP:BODY:NAME, target_name).
    LOCAL cap_g IS aoso_feas_body_stat(target_name, "capture", 0).
    LOCAL xfer_g IS aoso_project_xfer_only(pred_g, cap_g).
    SET data["pred_xfer"] TO xfer_g.
    SET data["pred_cap"] TO cap_g.
    LOCAL did_g IS aoso_decide("GOTO", "hop", target_name, "transfer",
        "pred=" + ROUND(xfer_g, 0), xfer_g).
    LOCAL act_g IS aoso_action_create(did_g, "TRANSFER", target_name, xfer_g).
    LOCAL win_g IS aoso_window_evaluate(SHIP:BODY:NAME, target_name).
    LOCAL pred_time_g IS 0.
    IF win_g:HASKEY("total_s") { SET pred_time_g TO win_g["total_s"]. }
    IF DEFINED AOSO_XP {
        SET pred_time_g TO aoso_xp_metric_apply("TRANSFER", target_name, "TIME", pred_time_g).
    }
    SET act_g["predicted_duration"] TO pred_time_g.
    aoso_action_begin(act_g).
    SET data["action_id"] TO did_g.
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
    aoso_warp_hard_stop().
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
    SET data["via"] TO "".
    IF hop:NAME <> SUN:NAME {
        IF hop:BODY:NAME = SHIP:BODY:NAME {
            LOCAL via_try IS aoso_assist_should_flyby(hop).
            IF via_try:ISTYPE("Body") { SET data["via"] TO via_try:NAME. }
        }
    }
    aoso_log_info("GOTO", "Next hop " + SHIP:BODY:NAME + " -> " + hop:NAME + " (goal " + goal:NAME + ").").

    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        IF aoso_goto_patch_is_ours(data, np) {
            IF np <> hop:NAME { SET data["hop"] TO np. }
            aoso_goto_ensure_transfer_action(data, np).
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
                    LOCAL soi_a IS hop_b:SOIRADIUS - hop_b:RADIUS.
                    IF pe_now > soi_a * 0.12 {
                        SET do_corr TO TRUE.
                    } ELSE {
                        IF eta_p < aoso_config_get("GOTO_CORRECT_WITHIN_S", 28800) { SET do_corr TO TRUE. }
                    }
                }
                IF do_corr {
                    IF ncorr < aoso_config_get("GOTO_CORRECT_MAX", 5) {
                        LOCAL ndc IS aoso_rendezvous_add_correction_node(hop_b).
                        IF ndc <> 0 {
                            SET data["corrected"] TO TRUE.
                            SET data["correct_count"] TO ncorr + 1.
                            aoso_log_info("GOTO", "Patch to " + np + " has a poor PE - mid-course correction " + data["correct_count"] + "/" + ROUND(aoso_config_get("GOTO_CORRECT_MAX", 5), 0) + ".").
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
        // A live patch to some other moon/planet is an obstruction, not a
        // valid leg. The old code accepted any patch while ESCAPING and could
        // turn a Minmus transfer into an accidental Mun flyby.
        IF SHIP:BODY:NAME <> SUN:NAME {
            IF np = SHIP:BODY:BODY:NAME {
                aoso_log_info("GOTO", "Existing escape patch to " + np + " - coasting.").
                SET data["burn_kind"] TO "coast".
                aoso_state_transition(AOSO_GOTO, "COAST").
                RETURN.
            }
        }
        aoso_log_warn("GOTO", "Ignoring unexpected patch to " + np +
            " while next hop is " + hop:NAME + " - rebuilding the intended route.").
    }

    LOCAL action_hop IS hop:NAME.
    IF data:HASKEY("via") {
        IF data["via"] <> "" { SET action_hop TO data["via"]. }
    }
    aoso_goto_ensure_transfer_action(data, action_hop).

    LOCAL rel_incl IS aoso_orbit_relative_inclination_deg(SHIP, hop).
    LOCAL match_plane IS TRUE.
    IF rel_incl > 2 {
        IF match_plane {
            LOCAL nd_pc IS aoso_planechange_add_node_for_target(hop).
            IF nd_pc <> 0 {
                IF aoso_addon_native_porkchop_available() {
                    aoso_log_info("GOTO", "Plane match first; native porkchop for " + hop:NAME +
                        " is deferred until this plane-change burn completes.").
                }
                SET data["burn_kind"] TO "plane".
                aoso_state_transition(AOSO_GOTO, "BURN").
                RETURN.
            }
        } ELSE {
            aoso_log_info("GOTO", "Skipping " + ROUND(rel_incl, 1) + " deg plane-match to " + hop:NAME + ".").
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
            IF aoso_addon_native_porkchop_available() {
                aoso_log_info("GOTO", "Building " + hop:NAME + " intercept with native porkchop available.").
            } ELSE {
                aoso_log_info("GOTO", "Building " + hop:NAME + " intercept with KerboScript porkchop fallback.").
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

    // Sibling planets sharing a parent (the Sun, usually). With native
    // v0.4+, departure time is no longer forced to the single Hohmann phase:
    // search departure-UT x flight-time and let stock patched conics validate
    // finalists. The analytic Hohmann path remains a safe no-addon/failure
    // fallback, never a second expensive duplicate search.
    IF hop:NAME <> SUN:NAME {
        IF hop:BODY:NAME = SHIP:BODY:BODY:NAME {
            IF aoso_addon_native_interplanetary_available() {
                LOCAL nd_np IS aoso_interplanetary_add_native_ejection_node(hop).
                IF nd_np:ISTYPE("Node") {
                    SET data["burn_kind"] TO "eject".
                    aoso_log_info("GOTO", "Using native planetary porkchop for " + hop:NAME +
                        "; stock patched-conic node accepted in " + ROUND(nd_np:ETA, 0) + "s.").
                    aoso_state_transition(AOSO_GOTO, "BURN").
                    RETURN.
                }
                aoso_log_warn("GOTO", "Native planetary search produced no validated " +
                    hop:NAME + " node; using analytic Hohmann fallback.").
            }

            LOCAL decision IS aoso_window_decide(SHIP:BODY, hop).
            LOCAL wait_s IS decision["wait_s"].
            IF wait_s < 0 { SET wait_s TO 0. }
            IF decision["action"] = "WAIT" {
                SET data["window_ut"] TO TIME:SECONDS + wait_s.
                SET data["burn_kind"] TO "eject".
                aoso_log_info("GOTO", "Hohmann fallback window to " + hop:NAME + ": wait " + ROUND(wait_s, 0) +
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
            IF data["burn_kind"] = "correct" {
                IF data:HASKEY("correct_count") {
                    IF data["correct_count"] > 0 {
                        SET data["correct_count"] TO data["correct_count"] - 1.
                    }
                }
                SET data["correct_cool_ut"] TO TIME:SECONDS + 8.
                aoso_log_warn("GOTO", "Mid-course " + burn_res + " - re-planning the intercept, not circularizing (that kills the transfer).").
                aoso_state_transition(AOSO_GOTO, "PLAN").
                RETURN.
            }
            IF data["burn_kind"] = "transfer" OR data["burn_kind"] = "assist" {
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
                aoso_log_info("GOTO", "Follow-up plane/mid-course node - burning it before coast.").
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
        LOCAL hop_name IS "".
        IF data:HASKEY("hop") { SET hop_name TO data["hop"]. }
        LOCAL expected_soi IS FALSE.
        IF SHIP:BODY:NAME = goal_name { SET expected_soi TO TRUE. }
        IF hop_name <> "" {
            IF SHIP:BODY:NAME = hop_name { SET expected_soi TO TRUE. }
        }
        IF data:HASKEY("via") {
            IF data["via"] <> "" {
                IF SHIP:BODY:NAME = data["via"] { SET expected_soi TO TRUE. }
            }
        }

        aoso_log_info("GOTO", "SOI change: " + data["depart_body"] + " -> " + SHIP:BODY:NAME + ".").
        aoso_event_publish("SOI_CHANGED", "goto", data["depart_body"] + "->" + SHIP:BODY:NAME).
        IF NOT expected_soi {
            aoso_log_warn("GOTO", "UNEXPECTED SOI: entered " + SHIP:BODY:NAME +
                " while routing to " + hop_name + " / goal " + goal_name +
                ". Recovering through PLAN; do not treat this as arrival/capture.").
            aoso_observe_anomaly("UNEXPECTED_SOI", "HIGH", 0, 1).
            IF DEFINED AOSO_EVENTS {
                aoso_event_publish("UNEXPECTED_SOI", "goto", data["depart_body"] + "->" + SHIP:BODY:NAME).
            }
        }
        IF hop_name <> "" {
            LOCAL ver_t IS aoso_verify_transfer(hop_name).
            aoso_log_info("GOTO", "Transfer verify vs " + hop_name + ": " + ver_t["status"] + " " + ver_t["reason"] + ".").
            LOCAL res_t IS aoso_result_make("TRANSFER", ver_t["status"], ver_t["reason"]).
            IF data:HASKEY("pred_xfer") { SET res_t["predicted_dv"] TO data["pred_xfer"]. }
            IF ver_t:HASKEY("patch_body") { SET res_t["anomalies"] TO ver_t["patch_body"]. }
            SET res_t TO aoso_verify_apply_result(res_t, ver_t).
            aoso_result_emit(res_t).
        }
        aoso_state_transition(AOSO_GOTO, "PLAN").
        RETURN.
    }

    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        SET data["retry_ut"] TO 0.

        // Never blindly warp into an unrelated SOI. This run's "Minmus"
        // trajectory changed to Mun; the old coast controller simply followed
        // the new NEXTPATCH and only noticed after entering Mun.
        IF NOT aoso_goto_patch_is_ours(data, np) {
            aoso_warp_hard_stop().
            aoso_steer_release().
            SET data["expect_body"] TO "".
            SET data["expect_ut"] TO 0.
            SET data["patch_lost_ut"] TO 0.
            SET data["corrected"] TO FALSE.
            SET data["correct_count"] TO 0.
            aoso_log_warn("GOTO", "Unexpected next SOI " + np +
                " while targeting " + data["hop"] + " / goal " + goal_name +
                " - stopping warp before entry.").
            aoso_observe_anomaly("UNEXPECTED_PATCH", "HIGH", 0, SHIP:ORBIT:NEXTPATCHETA).
            IF DEFINED AOSO_EVENTS {
                aoso_event_publish("UNEXPECTED_PATCH", "goto", np).
            }

            // First try to repair the existing transfer directly. For a
            // parent->moon hop this asks the correction solver to make the
            // intended moon the FIRST patch, not merely appear later in the
            // conic chain.
            IF data["hop"] <> "" {
                LOCAL intended IS BODY(data["hop"]).
                IF intended:ISTYPE("Body") {
                    IF intended:BODY:NAME = SHIP:BODY:NAME {
                        IF SHIP:ORBIT:NEXTPATCHETA > 150 {
                            LOCAL nd_avoid IS aoso_rendezvous_add_correction_node(intended).
                            IF nd_avoid <> 0 {
                                SET data["corrected"] TO TRUE.
                                SET data["correct_count"] TO 1.
                                SET data["burn_kind"] TO "correct".
                                aoso_log_info("GOTO", "Avoiding unintended " + np +
                                    " SOI with a correction back onto direct " + intended:NAME + " intercept.").
                                aoso_state_transition(AOSO_GOTO, "BURN").
                                RETURN.
                            }
                        }
                    }
                }
            }

            aoso_log_warn("GOTO", "Could not repair the unexpected " + np +
                " patch directly - rebuilding the intended route at 1x.").
            aoso_state_transition(AOSO_GOTO, "PLAN").
            RETURN.
        }

        aoso_goto_remember_patch(data, np, SHIP:ORBIT:NEXTPATCHETA).
        LOCAL ncorr IS 0.
        IF data:HASKEY("correct_count") { SET ncorr TO data["correct_count"]. }
        LOCAL hop_check IS BODY(np).
        LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
        LOCAL patch_pe IS aoso_rendezvous_orbit_pe(SHIP:ORBIT, hop_check).
        LOCAL patch_safe_floor IS MAX(5000, hop_check:RADIUS * 0.01).
        IF hop_check:ATM:EXISTS {
            SET patch_safe_floor TO hop_check:ATM:HEIGHT + 5000.
        }
        LOCAL want_correct IS FALSE.
        IF aoso_goto_patch_is_ours(data, np) {
            IF aoso_rendezvous_orbit_needs_correct(SHIP:ORBIT, hop_check) {
                LOCAL pe_now IS patch_pe.
                LOCAL correct_within IS aoso_config_get("GOTO_CORRECT_WITHIN_S", 28800).
                LOCAL soi_a IS hop_check:SOIRADIUS - hop_check:RADIUS.
                IF pe_now < 0 {
                    SET want_correct TO TRUE.
                } ELSE {
                    IF pe_now > soi_a * 0.12 {
                        SET want_correct TO TRUE.
                    } ELSE {
                        IF eta_p < correct_within { SET want_correct TO TRUE. }
                    }
                }
            }
        }
        IF want_correct {
            IF eta_p > 150 {
                IF ncorr < aoso_config_get("GOTO_CORRECT_MAX", 5) {
                    LOCAL cool IS 0.
                    IF data:HASKEY("correct_cool_ut") { SET cool TO data["correct_cool_ut"]. }
                    IF TIME:SECONDS >= cool {
                        // Correction search mutates a live maneuver node and
                        // yields while patched conics settle. Stop rails
                        // completely first or those WAIT 0s can age the new
                        // node by thousands of game seconds.
                        aoso_warp_hard_stop().
                        LOCAL ndc IS aoso_rendezvous_add_correction_node(hop_check).
                        IF ndc <> 0 {
                            SET data["correct_count"] TO ncorr + 1.
                            aoso_log_info("GOTO", "Patch PE is not a capture altitude - mid-course correction " + data["correct_count"] + "/" + ROUND(aoso_config_get("GOTO_CORRECT_MAX", 5), 0) + ".").
                            SET data["burn_kind"] TO "correct".
                            aoso_state_transition(AOSO_GOTO, "BURN").
                            RETURN.
                        }
                        SET data["correct_cool_ut"] TO TIME:SECONDS + 45.
                        aoso_log_warn("GOTO", "Mid-course tune failed for " + np + " - coasting (will not re-plan; that flickered warp).").
                    }
                }
            }
        }
        // Never stay on rails close to an SOI. KSP can take many real
        // seconds to unpack a large vessel; entering rails immediately before
        // an SOI crossing allowed Acacius to cross Minmus->Kerbin while still
        // packed and materialize deep in the atmosphere.
        LOCAL soi_cutoff IS aoso_config_get("WARP_SOI_RAILS_CUTOFF_S", 45).

        // A close, clearly unsafe target-body periapsis is a hard safety
        // condition. If correction did not produce a node above, stop here
        // rather than timewarping an on-rails vessel into atmosphere/terrain.
        IF eta_p < MAX(900, soi_cutoff) {
            IF patch_pe < patch_safe_floor {
                aoso_warp_hard_stop().
                aoso_throttle_set(0).
                aoso_steer_release().
                aoso_log_error("GOTO", "SOI SAFETY HOLD for " + np +
                    ": patch PE=" + ROUND(patch_pe, 0) + "m below floor=" +
                    ROUND(patch_safe_floor, 0) + "m at T-" + ROUND(eta_p, 0) + "s.").
                aoso_observe_anomaly("SOI_IMPACT", "CRITICAL", patch_safe_floor, patch_pe).
                IF DEFINED AOSO_EVENTS {
                    aoso_event_publish("HOLD", "goto", "unsafe SOI PE " + ROUND(patch_pe, 0)).
                }
                aoso_state_abort(AOSO_GOTO).
                RETURN.
            }
        }

        IF eta_p > 30 {
            LOCAL align_s IS aoso_maneuver_align_s().
            LOCAL coast_lead IS MAX(align_s, soi_cutoff).
            aoso_steer_release().
            LOCAL wst IS aoso_warp_approach(eta_p, coast_lead, aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
            aoso_ui_set("Coasting to " + np, "SOI " + aoso_hud_eta(eta_p) + "  " + aoso_warp_diag_txt()).
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
                LOCAL soi_lead_saved IS MAX(aoso_maneuver_align_s(), aoso_config_get("WARP_SOI_RAILS_CUTOFF_S", 45)).
                aoso_warp_approach(eta_saved, soi_lead_saved, aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10)).
                aoso_log_every(60, "GOTO", "No live patch, trusting " + expect_body + " SOI in " + ROUND(eta_saved, 0) + "s " + aoso_warp_diag_txt() + ".").
                aoso_ui_set("Trusting " + expect_body + " intercept", aoso_hud_eta(eta_saved) + "  " + aoso_warp_diag_txt()).
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
    aoso_warp_hard_stop().
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
        LOCAL safe_floor IS aoso_capture_safe_pe_floor(park).
        IF PERIAPSIS < safe_floor {
            // Never continue warping or mark the destination arrived while
            // the osculating conic intersects the body/terrain margin.
            aoso_warp_hard_stop().
            aoso_throttle_set(0).
            aoso_log_error("GOTO", "CAPTURE SAFETY HOLD at " + SHIP:BODY:NAME +
                ": PE=" + ROUND(PERIAPSIS, 0) + "m below safe floor " +
                ROUND(safe_floor, 0) + "m and no safe repair node was found.").
            aoso_observe_anomaly("CAPTURE_IMPACT", "CRITICAL", safe_floor, PERIAPSIS).
            IF DEFINED AOSO_EVENTS {
                aoso_event_publish("HOLD", "goto", "unsafe capture PE " + ROUND(PERIAPSIS, 0)).
            }
            aoso_state_abort(AOSO_GOTO).
            RETURN.
        }

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
    IF nd <> 0 {
        LOCAL safe_floor_node IS aoso_capture_safe_pe_floor(park).
        LOCAL node_pe IS nd:ORBIT:PERIAPSIS.
        IF node_pe < safe_floor_node {
            aoso_log_error("GOTO", "Rejected unsafe capture node at " + SHIP:BODY:NAME +
                ": node PE=" + ROUND(node_pe, 0) + "m floor=" +
                ROUND(safe_floor_node, 0) + "m.").
            REMOVE nd.
            aoso_warp_hard_stop().
            aoso_observe_anomaly("CAPTURE_NODE_UNSAFE", "CRITICAL", safe_floor_node, node_pe).
            IF DEFINED AOSO_EVENTS {
                aoso_event_publish("HOLD", "goto", "unsafe capture node PE " + ROUND(node_pe, 0)).
            }
            aoso_state_abort(AOSO_GOTO).
            RETURN.
        }

        LOCAL cap_pred IS aoso_feas_body_stat(SHIP:BODY:NAME, "capture", 0).
        LOCAL did_c IS aoso_decide("GOTO", "capture", SHIP:BODY:NAME, "burn",
            "pred=" + ROUND(cap_pred, 0), cap_pred).
        LOCAL act_c IS aoso_action_create(did_c, "CAPTURE", SHIP:BODY:NAME, cap_pred).
        LOCAL cap_time IS aoso_perf_burn_time_for_dv(cap_pred).
        IF DEFINED AOSO_XP {
            SET cap_time TO aoso_xp_metric_apply("CAPTURE", SHIP:BODY:NAME, "TIME", cap_time).
        }
        SET act_c["predicted_duration"] TO cap_time.
        aoso_action_begin(act_c).
    }
}

FUNCTION aoso_goto_close_capture_action {
    PARAMETER result_status.
    PARAMETER reason.
    IF NOT AOSO_ACTION_CUR:ISTYPE("Lexicon") { RETURN. }
    IF AOSO_ACTION_CUR["type"] <> "CAPTURE" { RETURN. }
    LOCAL expect_body IS AOSO_ACTION_CUR["target"].
    LOCAL res_c IS aoso_action_finish(result_status, reason).
    IF result_status = "SUCCESS" {
        LOCAL ver_c IS aoso_verify_capture(expect_body).
        SET res_c TO aoso_verify_apply_result(res_c, ver_c).
    }
    aoso_result_emit(res_c).
}

FUNCTION aoso_goto_capture_execute {
    PARAMETER data.
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_GOTO).
        RETURN.
    }
    IF NOT HASNODE {
        IF aoso_goto_orbit_is_parked() {
            aoso_goto_close_capture_action("SUCCESS", "parked").
            IF SHIP:BODY:NAME = data["goal"] {
                aoso_state_transition(AOSO_GOTO, "DONE").
            } ELSE {
                aoso_state_transition(AOSO_GOTO, "PLAN").
            }
        } ELSE {
            aoso_goto_close_capture_action("FAILED", "capture node lost").
            aoso_state_transition(AOSO_GOTO, "PLAN").
        }
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        LOCAL cap_res IS aoso_maneuver_last_result().
        IF cap_res = "missed" OR cap_res = "incomplete" {
            aoso_goto_close_capture_action("FAILED", "capture " + cap_res).
            LOCAL misses IS 0.
            IF data:HASKEY("capture_misses") { SET misses TO data["capture_misses"]. }
            SET data["capture_misses"] TO misses + 1.
            aoso_log_warn("GOTO", "Capture " + cap_res + " (" + data["capture_misses"] + "/4) - re-planning.").
            IF data["capture_misses"] >= 4 {
                aoso_warp_hard_stop().
                aoso_throttle_set(0).
                aoso_log_error("GOTO", "Capture missed 4x at " + SHIP:BODY:NAME +
                    " - SAFETY HOLD, not marking arrival. PE=" + ROUND(PERIAPSIS, 0) + "m.").
                aoso_observe_anomaly("CAPTURE_RETRY_LIMIT", "CRITICAL", 0, PERIAPSIS).
                IF DEFINED AOSO_EVENTS {
                    aoso_event_publish("HOLD", "goto", "capture retry limit at " + SHIP:BODY:NAME).
                }
                aoso_state_abort(AOSO_GOTO).
                RETURN.
            }
            aoso_state_transition(AOSO_GOTO, "PLAN").
            RETURN.
        }
        IF aoso_goto_orbit_is_parked() {
            aoso_goto_close_capture_action("SUCCESS", "parked after capture burn").
        } ELSE {
            aoso_goto_close_capture_action("PARTIAL", "capture adjustment complete; orbit not parked yet").
        }
        aoso_state_transition(AOSO_GOTO, "PLAN").
    } ELSE {
        IF HASNODE {
            LOCAL ndc IS NEXTNODE.
            aoso_ui_set("Capture burn T-" + aoso_hud_eta(ndc:ETA), ROUND(ndc:DELTAV:MAG, 1) + " m/s  " + aoso_warp_diag_txt()).
        }
    }
}

FUNCTION aoso_goto_done_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    aoso_steer_release().
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        IF AOSO_ACTION_CUR["type"] = "CAPTURE" {
            aoso_goto_close_capture_action("SUCCESS", "arrived").
        } ELSE {
            IF AOSO_ACTION_CUR["type"] = "TRANSFER" {
                LOCAL ver_t0 IS aoso_verify_transfer(data["goal"]).
                LOCAL res_t0 IS aoso_action_finish(ver_t0["status"], ver_t0["reason"]).
                SET res_t0 TO aoso_verify_apply_result(res_t0, ver_t0).
                aoso_result_emit(res_t0).
            }
        }
    }
    LOCAL ver_c IS aoso_verify_capture(data["goal"]).
    LOCAL ver_x IS aoso_verify_transfer(data["goal"]).
    aoso_log_info("GOTO", "Arrived at " + data["goal"] + " capture=" + ver_c["reason"] + " transfer=" + ver_x["reason"] + ".").
}

FUNCTION aoso_goto_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    aoso_throttle_set(0).
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        LOCAL typ IS AOSO_ACTION_CUR["type"].
        IF typ = "TRANSFER" OR typ = "CAPTURE" {
            LOCAL res_a IS aoso_action_finish("ABORTED", "goto aborted").
            aoso_result_emit(res_a).
        }
    }
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
    // TRANSFER begins in PLAN once the vessel is actually in flight and
    // the next hop is known. This avoids ASCENT overwriting it on launch
    // and gives every multi-hop SOI leg its own measured action.
    SET AOSO_GOTO["data"]["pred_xfer"] TO 0.
    SET AOSO_GOTO["data"]["pred_cap"] TO 0.
    SET AOSO_GOTO["data"]["action_id"] TO 0.
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
    LOCAL p_g IS 0.2.
    IF cur = "PLAN" { SET p_g TO 0.15. }
    IF cur = "WAIT" { SET p_g TO 0.25. }
    IF cur = "LAUNCH" { SET p_g TO 0.35. }
    IF cur = "BURN" { SET p_g TO 0.55. }
    IF cur = "COAST" { SET p_g TO 0.7. }
    IF cur = "CAPTURE" { SET p_g TO 0.85. }
    IF cur = "DONE" { SET p_g TO 1. }
    aoso_hb_set("goto", cur, p_g).
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
