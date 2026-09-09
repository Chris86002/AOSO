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

// TRUE when we should circularize/capture around the body we are in now,
// rather than keep going. Intentional ejections (ESCAPING with a patch to
// the parent) must NOT capture -- that was eating Kerbin->Duna transfers.
FUNCTION aoso_goto_should_capture {
    PARAMETER data.

    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" { RETURN FALSE. }
    IF SHIP:BODY:NAME = SUN:NAME { RETURN FALSE. }

    LOCAL should_stop IS FALSE.
    IF SHIP:BODY:NAME = data["goal"] {
        SET should_stop TO TRUE.
    } ELSE {
        LOCAL g IS BODY(data["goal"]).
        IF g:NAME <> SUN:NAME {
            IF g:BODY:NAME = SHIP:BODY:NAME { SET should_stop TO TRUE. }
        }
    }

    IF NOT should_stop {
        IF SHIP:STATUS = "ESCAPING" { RETURN FALSE. }
        IF SHIP:ORBIT:HASNEXTPATCH { RETURN FALSE. }
        IF PERIAPSIS < 0 { RETURN TRUE. }
        RETURN FALSE.
    }

    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN TRUE. }
    IF PERIAPSIS < 0 { RETURN TRUE. }
    IF SHIP:STATUS = "ESCAPING" { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION aoso_goto_patch_body_name {
    IF NOT SHIP:ORBIT:HASNEXTPATCH { RETURN "". }
    RETURN SHIP:ORBIT:NEXTPATCH:BODY:NAME.
}

FUNCTION aoso_goto_on_abort {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_maneuver_clear_all().
    aoso_state_transition(AOSO_GOTO, "ABORTED").
}

FUNCTION aoso_goto_plan_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_maneuver_clear_all().

    LOCAL goal IS BODY(data["goal"]).
    SET data["depart_body"] TO SHIP:BODY:NAME.

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

    LOCAL hop IS aoso_goto_next_hop_body(goal).
    SET data["hop"] TO hop:NAME.
    aoso_log_info("GOTO", "Next hop " + SHIP:BODY:NAME + " -> " + hop:NAME + " (goal " + goal:NAME + ").").

    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        IF np = goal:NAME OR np = hop:NAME {
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
    IF rel_incl > 2 {
        LOCAL nd_pc IS aoso_planechange_add_node_for_target(hop).
        IF nd_pc <> 0 {
            SET data["burn_kind"] TO "plane".
            aoso_state_transition(AOSO_GOTO, "BURN").
            RETURN.
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
    IF hop:NAME <> SUN:NAME {
        IF hop:BODY:NAME = SHIP:BODY:NAME {
            LOCAL nd_m IS aoso_rendezvous_add_phasing_transfer_node(hop).
            IF nd_m = 0 {
                aoso_state_abort(AOSO_GOTO).
                RETURN.
            }
            SET data["burn_kind"] TO "transfer".
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
            LOCAL wait_s IS aoso_interplanetary_wait_time_to_window_s(SHIP:BODY, hop).
            IF wait_s < 0 { SET wait_s TO 0. }
            IF wait_s > 20 {
                SET data["window_ut"] TO TIME:SECONDS + wait_s.
                SET data["burn_kind"] TO "eject".
                aoso_log_info("GOTO", "Transfer window to " + hop:NAME + " in " + ROUND(wait_s, 0) + "s.").
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
    IF TIME:SECONDS >= data["window_ut"] - 8 {
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
    IF WARP = 0 {
        IF aoso_maneuver_can_warp() {
            WARPTO(data["window_ut"] - 5).
        }
    }
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
        IF data["burn_kind"] = "plane" {
            aoso_state_transition(AOSO_GOTO, "PLAN").
        } ELSE {
            aoso_state_transition(AOSO_GOTO, "COAST").
        }
    }
}

FUNCTION aoso_goto_coast_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    SET data["coast_since"] TO TIME:SECONDS.
}

FUNCTION aoso_goto_coast_execute {
    PARAMETER data.
    LOCAL goal_name IS data["goal"].

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
        aoso_log_info("GOTO", "SOI change: " + data["depart_body"] + " -> " + SHIP:BODY:NAME + ".").
        aoso_state_transition(AOSO_GOTO, "PLAN").
        RETURN.
    }

    LOCAL np IS aoso_goto_patch_body_name().
    IF np <> "" {
        LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
        IF eta_p > 30 {
            IF WARP = 0 {
                IF aoso_maneuver_can_warp() {
                    WARPTO(TIME:SECONDS + eta_p - 20).
                }
            }
        } ELSE {
            SET WARP TO 0.
        }
        RETURN.
    }

    LOCAL coasted IS TIME:SECONDS - data["coast_since"].
    LOCAL give_up IS MAX(SHIP:ORBIT:PERIOD, 3600) * 1.5.
    IF coasted > give_up {
        SET WARP TO 0.
        aoso_log_warn("GOTO", "Coast produced no encounter after " + ROUND(coasted, 0) + "s - re-planning.").
        aoso_state_transition(AOSO_GOTO, "PLAN").
        RETURN.
    }

    IF WARP = 0 {
        IF aoso_maneuver_can_warp() {
            SET WARP TO MIN(5, aoso_config_get("MAX_WARP_FACTOR", 6)).
        }
    }
}

FUNCTION aoso_goto_capture_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    LOCAL park IS aoso_goto_parking_alt(SHIP:BODY).
    LOCAL nd IS aoso_interplanetary_add_capture_node(park).
    IF nd = 0 {
        aoso_log_warn("GOTO", "No capture node; continuing from current orbit.").
        IF SHIP:BODY:NAME = data["goal"] {
            aoso_state_transition(AOSO_GOTO, "DONE").
        } ELSE {
            aoso_state_transition(AOSO_GOTO, "PLAN").
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
        IF SHIP:BODY:NAME = data["goal"] {
            aoso_state_transition(AOSO_GOTO, "DONE").
        } ELSE {
            aoso_state_transition(AOSO_GOTO, "PLAN").
        }
        RETURN.
    }
    IF aoso_maneuver_execute_next() {
        IF SHIP:BODY:NAME = data["goal"] {
            aoso_state_transition(AOSO_GOTO, "DONE").
        } ELSE {
            aoso_state_transition(AOSO_GOTO, "PLAN").
        }
    }
}

FUNCTION aoso_goto_done_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_log_info("GOTO", "Arrived at " + data["goal"] + ".").
}

FUNCTION aoso_goto_aborted_entry {
    PARAMETER data.
    SET WARP TO 0.
    LOCK THROTTLE TO 0.
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
    SET AOSO_GOTO["data"] TO LEXICON("goal", body_name, "hop", "", "burn_kind", "", "depart_body", SHIP:BODY:NAME, "window_ut", 0, "coast_since", 0).
    aoso_log_info("GOTO", "Navigating to " + body_name + ".").
    aoso_state_transition(AOSO_GOTO, "PLAN").
}

FUNCTION aoso_goto_update {
    aoso_state_update(AOSO_GOTO).
}

FUNCTION aoso_goto_is_done {
    RETURN AOSO_GOTO["current"] = "DONE".
}

FUNCTION aoso_goto_is_aborted {
    RETURN AOSO_GOTO["current"] = "ABORTED".
}
