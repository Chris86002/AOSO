// AOSO/mission/mission.ks
// Phase 10 (Mission layer): the top-level orchestrator that chains every
// previous phase's independent subsystem into a single autonomous mission,
// exactly what flight/ascent.ks's own header calls "the mission-level
// machine a later phase adds" and landing/deorbit.ks's aoso_deorbit_execute
// wrapper was left in place for -- a later phase inserting mission-state
// transitions without touching every call site.
//
// A mission is just an ordered LIST of "steps" (AOSO_MISSION_PLAN), each a
// small lexicon of callbacks: start/update/is_done/is_aborted(optional).
// This mirrors the start/update/is_done/is_aborted interface every FSM
// module in this repo already exposes (flight/ascent.ks, landing/descent.ks,
// refuel/isru.ks, return/return.ks, precision/kscreturn.ks) -- a step just
// wraps whichever module's own functions with aoso_mission_step(), or one of
// the aoso_mission_step_*() presets below. Modules that only expose a single
// "add a node" helper (nav/hohmann.ks, nav/planechange.ks,
// nav/rendezvous.ks, interplanetary/ejection.ks, landing/deorbit.ks) are
// wrapped through aoso_mission_step_burn(), which polls
// flight/maneuver.ks's aoso_maneuver_execute_next() -- the same generic burn
// executor every one of those modules already delegates to -- until the
// node is gone.
//
// Built on core/state.ks as its own machine (AOSO_MISSION), the same
// pattern every other autonomous subsystem in this repo uses, so it can run
// standalone or alongside a lower-level machine that a step's start/update
// callbacks happen to drive directly (e.g. AOSO_ASCENT while an ASCEND step
// is active).

GLOBAL AOSO_MISSION IS aoso_state_new_machine().
GLOBAL AOSO_MISSION_PLAN IS LIST().

// Shared scratch lexicon for aoso_mission_step_burn() steps -- see there.
GLOBAL AOSO_MISSION_BURN_STATE IS LEXICON("ok", TRUE, "done", FALSE).

// --- Plan construction --------------------------------------------------

FUNCTION aoso_mission_step {
    PARAMETER name.
    PARAMETER start_fn.
    PARAMETER update_fn.
    PARAMETER is_done_fn.
    PARAMETER is_aborted_fn IS 0.

    RETURN LEXICON(
        "name", name,
        "start", start_fn,
        "update", update_fn,
        "is_done", is_done_fn,
        "is_aborted", is_aborted_fn
    ).
}

FUNCTION aoso_mission_plan_clear {
    SET AOSO_MISSION_PLAN TO LIST().
}

FUNCTION aoso_mission_plan_add {
    PARAMETER mission_step.
    AOSO_MISSION_PLAN:ADD(mission_step).
    RETURN mission_step.
}

// --- Generic "add a node, burn it" step (see file header) ---------------

FUNCTION aoso_mission_burn_start {
    PARAMETER add_node_fn.
    SET AOSO_MISSION_BURN_STATE TO LEXICON("ok", TRUE, "done", FALSE).
    LOCAL nd IS add_node_fn:CALL().
    IF nd = 0 { SET AOSO_MISSION_BURN_STATE["ok"] TO FALSE. }
}

FUNCTION aoso_mission_burn_update {
    SET AOSO_MISSION_BURN_STATE["done"] TO aoso_maneuver_execute_next().
}

FUNCTION aoso_mission_burn_is_done {
    RETURN AOSO_MISSION_BURN_STATE["done"].
}

FUNCTION aoso_mission_burn_is_aborted {
    RETURN NOT AOSO_MISSION_BURN_STATE["ok"].
}

// add_node_fn: a 0-argument delegate that adds a node and returns it (or 0
// on failure), e.g. aoso_hohmann_transfer_to_altitude@:BIND(100000) or
// aoso_interplanetary_add_ejection_node@:BIND(Duna). A 0 return is treated
// as an immediate abort, mirroring every FSM module's own "nd = 0" guard.
FUNCTION aoso_mission_step_burn {
    PARAMETER name.
    PARAMETER add_node_fn.
    RETURN aoso_mission_step(name, aoso_mission_burn_start@:BIND(add_node_fn), aoso_mission_burn_update@, aoso_mission_burn_is_done@, aoso_mission_burn_is_aborted@).
}

// --- Presets over existing subsystems ------------------------------------

FUNCTION aoso_mission_step_ascend {
    PARAMETER launch_heading IS 90.
    PARAMETER target_apo IS 0.
    RETURN aoso_mission_step("ASCEND", aoso_ascent_start@:BIND(launch_heading, target_apo), aoso_ascent_update@, aoso_ascent_is_done@, aoso_ascent_is_aborted@).
}

FUNCTION aoso_mission_step_transfer_to_altitude {
    PARAMETER target_alt.
    RETURN aoso_mission_step_burn("TRANSFER_TO_ALT:" + ROUND(target_alt, 0), aoso_hohmann_transfer_to_altitude@:BIND(target_alt)).
}

FUNCTION aoso_mission_step_circularize_far_apsis {
    RETURN aoso_mission_step_burn("CIRCULARIZE", aoso_hohmann_add_circularize_at_far_apsis@).
}

FUNCTION aoso_mission_step_plane_change {
    PARAMETER target_orbitable.
    RETURN aoso_mission_step_burn("PLANE_CHANGE", aoso_planechange_add_node_for_target@:BIND(target_orbitable)).
}

FUNCTION aoso_mission_step_rendezvous_phasing {
    PARAMETER target_orbitable IS TARGET.
    RETURN aoso_mission_step_burn("RENDEZVOUS_PHASING", aoso_rendezvous_add_phasing_transfer_node@:BIND(target_orbitable)).
}

FUNCTION aoso_mission_step_interplanetary_transfer {
    PARAMETER arr_body.
    RETURN aoso_mission_step_burn("TRANSFER:" + arr_body:NAME, aoso_interplanetary_add_ejection_node@:BIND(arr_body)).
}

FUNCTION aoso_mission_step_capture {
    PARAMETER target_apo_alt.
    RETURN aoso_mission_step_burn("CAPTURE", aoso_interplanetary_add_capture_node@:BIND(target_apo_alt)).
}

FUNCTION aoso_mission_step_deorbit {
    RETURN aoso_mission_step_burn("DEORBIT", aoso_deorbit_add_node@).
}

FUNCTION aoso_mission_step_descend {
    RETURN aoso_mission_step("DESCEND", aoso_descent_start@, aoso_descent_tick@, aoso_descent_is_landed@, aoso_descent_is_aborted@).
}

FUNCTION aoso_mission_step_refuel {
    PARAMETER target_names IS LIST("LiquidFuel", "Oxidizer").
    RETURN aoso_mission_step("REFUEL", aoso_refuel_start@:BIND(target_names), aoso_refuel_tick@, aoso_refuel_is_done@, aoso_refuel_is_aborted@).
}

FUNCTION aoso_mission_step_return {
    RETURN aoso_mission_step("RETURN", aoso_return_start@, aoso_return_update@, aoso_return_is_done@, aoso_return_is_aborted@).
}

FUNCTION aoso_mission_step_precision_return {
    RETURN aoso_mission_step("PRECISION_RETURN", aoso_kscreturn_start@, aoso_kscreturn_update@, aoso_kscreturn_is_done@, aoso_kscreturn_is_aborted@).
}

// Phase 11 (Advanced): final-approach/docking, assuming a prior step (e.g.
// aoso_mission_step_rendezvous_phasing) has already set TARGET to the
// docking port to dock with.
FUNCTION aoso_mission_step_dock {
    RETURN aoso_mission_step("DOCK", aoso_docking_start@, aoso_docking_update@, aoso_docking_is_done@, aoso_docking_is_aborted@).
}

// --- Runner ---------------------------------------------------------------

// (Re)starts whichever step is at plan_index: logs it, invokes its start
// callback, and checkpoints the new position. Shared by both the RUNNING
// state's entry (first step) and its execute (every later step), so
// advancing the plan never needs a same-named re-transition hack.
//
// Unlike "is_aborted" (aoso_mission_step's is_aborted_fn IS 0 default makes
// it genuinely optional), "start" is a required PARAMETER for every step --
// every aoso_mission_step_*() preset in this file always supplies a real
// delegate for it. Calling it unconditionally (rather than gating on an
// ISTYPE("Delegate") check it would always pass anyway) guarantees a step's
// start callback -- e.g. flight/ascent.ks's aoso_ascent_start, which is what
// actually locks the throttle and ignites the engines for an ASCEND step --
// always runs when its step begins, instead of the mission FSM silently
// sitting in a step whose subsystem was never armed.
FUNCTION aoso_mission_start_step_at {
    PARAMETER plan_index.
    PARAMETER data.

    SET data["index"] TO plan_index.
    IF plan_index >= AOSO_MISSION_PLAN:LENGTH {
        aoso_state_transition(AOSO_MISSION, "DONE").
        RETURN.
    }

    LOCAL mission_step IS AOSO_MISSION_PLAN[plan_index].
    aoso_log_info("MISSION", "Step " + (plan_index + 1) + "/" + AOSO_MISSION_PLAN:LENGTH + ": " + mission_step["name"]).
    mission_step["start"]:CALL().
    aoso_checkpoints_save(plan_index, mission_step["name"]).
}

FUNCTION aoso_mission_on_abort {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_state_transition(AOSO_MISSION, "ABORTED").
}

FUNCTION aoso_mission_running_entry {
    PARAMETER data.
    aoso_mission_start_step_at(data["index"], data).
}

FUNCTION aoso_mission_running_execute {
    PARAMETER data.
    IF data["index"] >= AOSO_MISSION_PLAN:LENGTH {
        aoso_state_transition(AOSO_MISSION, "DONE").
        RETURN.
    }
    LOCAL mission_step IS AOSO_MISSION_PLAN[data["index"]].

    mission_step["update"]:CALL().

    IF mission_step["is_aborted"]:ISTYPE("Delegate") AND mission_step["is_aborted"]:CALL() {
        aoso_log_error("MISSION", "Step aborted: " + mission_step["name"]).
        aoso_state_abort(AOSO_MISSION).
        RETURN.
    }

    IF mission_step["is_done"]:CALL() {
        aoso_log_info("MISSION", "Step complete: " + mission_step["name"]).
        aoso_mission_start_step_at(data["index"] + 1, data).
    }
}

FUNCTION aoso_mission_done_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    aoso_log_info("MISSION", "Mission plan complete (" + AOSO_MISSION_PLAN:LENGTH + " step(s)).").
    aoso_checkpoints_clear().
}

FUNCTION aoso_mission_aborted_entry {
    PARAMETER data.
    LOCK THROTTLE TO 0.
    aoso_log_error("MISSION", "Mission aborted at step " + (data["index"] + 1) + "/" + AOSO_MISSION_PLAN:LENGTH + ".").
}

FUNCTION aoso_mission_define_states {
    aoso_state_define(AOSO_MISSION, "RUNNING", aoso_mission_running_entry@, aoso_mission_running_execute@, 0, 0, 0, aoso_mission_on_abort@).
    aoso_state_define(AOSO_MISSION, "DONE", aoso_mission_done_entry@, 0, 0).
    aoso_state_define(AOSO_MISSION, "ABORTED", aoso_mission_aborted_entry@, 0, 0).
}

// Entry point: build AOSO_MISSION_PLAN first (aoso_mission_plan_add /
// aoso_mission_step_*), then call once to arm the mission runner, then
// drive it every tick with aoso_mission_update() (directly, or via
// aoso_mission_register_task()). resume_from_checkpoint TRUE skips straight
// to the step index recorded by mission/checkpoints.ks's last
// aoso_checkpoints_save() call (e.g. after a reload/scene-change) instead
// of always restarting the whole plan from step 0 -- the caller is
// responsible for re-adding the *same* plan first, since a KOSDelegate
// can't itself survive a JSON round trip (see checkpoints.ks's header).
// resume_from_checkpoint FALSE (the default, and what main.ks's own
// no-mission-plan.ks fallback uses) instead discards any checkpoint left
// over from an earlier attempt, since this run isn't going to honor it and
// leaving it on disk would just have it reported as "loaded" again on the
// next fresh boot too.
FUNCTION aoso_mission_start {
    PARAMETER resume_from_checkpoint IS FALSE.

    aoso_mission_define_states().

    LOCAL start_index IS 0.
    IF resume_from_checkpoint AND DEFINED aoso_checkpoints_available {
        IF aoso_checkpoints_available() {
            LOCAL idx IS aoso_checkpoints_step_index().
            IF idx >= 0 AND idx < AOSO_MISSION_PLAN:LENGTH { SET start_index TO idx. }
        }
    } ELSE {
        // Starting a brand-new run rather than resuming one: a checkpoint
        // saved by an earlier attempt no longer corresponds to this run, so
        // drop it now instead of leaving it on disk to be reloaded and
        // reported as "available" by core/boot.ks's own aoso_checkpoints_load()
        // on a later boot that also isn't resuming.
        aoso_checkpoints_clear().
    }

    SET AOSO_MISSION["data"] TO LEXICON("index", start_index).
    IF AOSO_MISSION_PLAN:LENGTH = 0 {
        aoso_state_transition(AOSO_MISSION, "DONE").
        RETURN.
    }
    aoso_state_transition(AOSO_MISSION, "RUNNING").
}

FUNCTION aoso_mission_update {
    aoso_state_update(AOSO_MISSION).
}

FUNCTION aoso_mission_register_task {
    PARAMETER interval_s IS 0.05.
    aoso_sched_add("mission", interval_s, aoso_mission_update@).
}

FUNCTION aoso_mission_is_done {
    RETURN AOSO_MISSION["current"] = "DONE".
}

FUNCTION aoso_mission_is_aborted {
    RETURN AOSO_MISSION["current"] = "ABORTED".
}

FUNCTION aoso_mission_current_step_name {
    IF AOSO_MISSION["current"] <> "RUNNING" { RETURN AOSO_MISSION["current"]. }
    LOCAL idx IS AOSO_MISSION["data"]["index"].
    IF idx < 0 OR idx >= AOSO_MISSION_PLAN:LENGTH { RETURN "". }
    RETURN AOSO_MISSION_PLAN[idx]["name"].
}
