// AOSO/core/brain.ks
// Executive: drain events, refresh dirty models when quiet, debounce
// replans. Does not fly the ship. Flight controllers stay in their FSMs.
// Quiet windows: pad, landed, or a bound orbit with no imminent node.
// Ascent / atmosphere / burns never think.

GLOBAL AOSO_BRAIN IS LEXICON(
    "last_replan", 0,
    "replan_reason", "",
    "pending_replan", "",
    "last_think", 0,
    "last_body", "",
    "last_cert", 0,
    "hold", FALSE
).
GLOBAL AOSO_BRAIN_EVENTS IS LEXICON(
    "STAGE_COMPLETE", TRUE,
    "VEHICLE_CHANGED", TRUE,
    "PROFILE_UPDATED", TRUE,
    "CAPABILITY_CHANGED", TRUE,
    "SOI_CHANGED", TRUE,
    "ORBIT_ACHIEVED", TRUE,
    "ASCENT_SUCCESS", TRUE,
    "TAKEOFF_SUCCESS", TRUE,
    "REFUEL_SUCCESS", TRUE,
    "LANDING_SUCCESS", TRUE,
    "ENGINE_ANOMALY", TRUE,
    "MANEUVER_FAILED", TRUE,
    "MODEL_UPDATED", TRUE,
    "REPLAN_REQUESTED", TRUE,
    "CORRECT_REQUESTED", TRUE,
    "HOLD", TRUE,
    "UNEXPECTED_SOI", TRUE,
    "UNEXPECTED_PATCH", TRUE,
    "NAV_FALLBACK", TRUE,
    "CPU_LOAD_HIGH", TRUE,
    "CPU_LOAD_CRITICAL", TRUE,
    "PLAN_UPDATED", TRUE
).

FUNCTION aoso_brain_init {
    SET AOSO_BRAIN["last_replan"] TO 0.
    SET AOSO_BRAIN["replan_reason"] TO "".
    SET AOSO_BRAIN["pending_replan"] TO "".
    SET AOSO_BRAIN["last_think"] TO 0.
    SET AOSO_BRAIN["last_body"] TO SHIP:BODY:NAME.
    SET AOSO_BRAIN["last_cert"] TO 0.
    SET AOSO_BRAIN["hold"] TO FALSE.
    aoso_ctx_init().
    aoso_event_init().
}

FUNCTION aoso_brain_is_quiet {
    IF DEFINED AOSO_MANEUVER_BURNING {
        IF AOSO_MANEUVER_BURNING { RETURN FALSE. }
    }
    // Strategic planning must never yield while timewarp is advancing UT.
    // WAIT 0 during rails can jump minutes/hours and made SCAN look like
    // endless warp while the planner rebuilt the full tour in the background.
    IF WARP > 0 { RETURN FALSE. }
    IF WARPMODE <> "PHYSICS" { RETURN FALSE. }
    IF NOT KUNIVERSE:TIMEWARP:ISSETTLED { RETURN FALSE. }
    LOCAL st IS SHIP:STATUS.
    // Sit on the pad or on the surface and take as long as the math needs.
    IF st = "PRELAUNCH" { RETURN TRUE. }
    IF st = "LANDED" { RETURN TRUE. }
    IF st = "SPLASHED" { RETURN TRUE. }
    IF st = "FLYING" { RETURN FALSE. }
    IF st = "SUB_ORBITAL" { RETURN FALSE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT { RETURN FALSE. }
    }
    IF HASNODE {
        LOCAL lead IS aoso_config_get("BRAIN_THINK_LEAD_S", 600).
        IF NEXTNODE:ETA < lead { RETURN FALSE. }
        IF NEXTNODE:ETA < 0 { RETURN FALSE. }
    }
    RETURN TRUE.
}

FUNCTION aoso_brain_think_ok {
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 { RETURN FALSE. }
    }
    RETURN aoso_brain_is_quiet().
}

FUNCTION aoso_brain_wait_think {
    PARAMETER why.
    IF aoso_brain_think_ok() { RETURN TRUE. }

    // Never execute WAIT 0 while rails warp is active or while KSP is still
    // unpacking. The Minmus flight proved that a nominal 5-second real-time
    // wait can advance ~4900-49000 seconds of UT at high rails warp.
    // Drive the transition non-blockingly and let the owning FSM call again.
    IF WARP > 0 OR WARPMODE <> "PHYSICS" OR NOT KUNIVERSE:TIMEWARP:ISSETTLED {
        aoso_warp_ensure_physics_idle().

        RETURN FALSE.
    }

    aoso_log_info("BRAIN", "Planning pause: " + why + " (settled 1x, bounded wait).").

    LOCAL t0_rt IS KUNIVERSE:REALTIME.
    LOCAL max_s IS aoso_config_get("BRAIN_THINK_WAIT_S", 5).
    IF max_s > 8 { SET max_s TO 8. }
    IF max_s < 0 { SET max_s TO 0. }
    UNTIL aoso_brain_think_ok() {
        IF KUNIVERSE:REALTIME - t0_rt > max_s {
            aoso_log_warn("BRAIN", "Quiet wait expired (" + why + ") - calculating now at settled 1x.").
            RETURN FALSE.
        }

        WAIT 0.
    }
    aoso_log_info("BRAIN", "Quiet window open - " + why + ".").
    RETURN TRUE.
}

FUNCTION aoso_brain_on_event {
    PARAMETER ev.
    LOCAL etype IS ev["type"].
    IF etype = "STAGE_COMPLETE" {
        IF DEFINED AOSO_CACHE_VALID { SET AOSO_CACHE_VALID TO FALSE. }
        aoso_ctx_mark_vehicle().
        aoso_ctx_mark_topo().
    }
    IF etype = "VEHICLE_CHANGED" {
        IF DEFINED AOSO_CACHE_VALID { SET AOSO_CACHE_VALID TO FALSE. }
        IF DEFINED AOSO_INTERCEPT_EPOCH { SET AOSO_INTERCEPT_EPOCH TO AOSO_INTERCEPT_EPOCH + 1. }
        aoso_ctx_mark_vehicle().
        aoso_ctx_mark_topo().
    }
    IF etype = "PROFILE_UPDATED" { aoso_ctx_mark_budget(). }
    IF etype = "CAPABILITY_CHANGED" { aoso_ctx_mark_vehicle(). }
    IF etype = "SOI_CHANGED" {
        IF DEFINED AOSO_INTERCEPT_EPOCH { SET AOSO_INTERCEPT_EPOCH TO AOSO_INTERCEPT_EPOCH + 1. }
        aoso_ctx_mark_world().
        aoso_brain_consider_replan("soi").
    }
    IF etype = "ORBIT_ACHIEVED" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("orbit"). }
    IF etype = "ASCENT_SUCCESS" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("ascent"). }
    IF etype = "REFUEL_SUCCESS" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("refuel"). }
    IF etype = "LANDING_SUCCESS" { aoso_ctx_mark_world(). }
    IF etype = "TAKEOFF_SUCCESS" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("takeoff"). }
    IF etype = "ENGINE_ANOMALY" { aoso_ctx_mark_vehicle(). aoso_brain_consider_replan("engine"). }
    IF etype = "MANEUVER_FAILED" {
        IF DEFINED AOSO_INTERCEPT_EPOCH { SET AOSO_INTERCEPT_EPOCH TO AOSO_INTERCEPT_EPOCH + 1. }
        aoso_brain_consider_replan("maneuver_fail").
    }
    IF etype = "MODEL_UPDATED" {
        aoso_ctx_dirty("dirty_feas").
        aoso_ctx_dirty("dirty_opp").
        aoso_ctx_dirty("dirty_route").
        aoso_ctx_dirty("dirty_plan").
        aoso_brain_consider_replan("model " + ev["data"]).
    }
    IF etype = "REPLAN_REQUESTED" { aoso_brain_consider_replan(ev["data"]). }
    IF etype = "CORRECT_REQUESTED" { aoso_brain_request_correction(ev["data"], TRUE). }
    IF etype = "HOLD" {
        SET AOSO_BRAIN["hold"] TO TRUE.
        SET AOSO_BRAIN["pending_replan"] TO "".
        aoso_log_warn("BRAIN", "Safe hold: " + ev["data"]).
    }
    IF etype = "UNEXPECTED_SOI" OR etype = "UNEXPECTED_PATCH" {
        aoso_ctx_mark_world().
        IF aoso_brain_local_guidance_active() {
            aoso_brain_request_correction(etype + " " + ev["data"], FALSE).
        } ELSE {
            aoso_brain_consider_replan(etype + " " + ev["data"]).
        }
    }
    IF etype = "NAV_FALLBACK" {
        aoso_ctx_dirty("dirty_route").
        IF NOT aoso_brain_local_guidance_active() { aoso_brain_consider_replan("nav fallback " + ev["data"]). }
    }
    IF etype = "CPU_LOAD_HIGH" { aoso_log_warn("BRAIN", "CPU high: " + ev["data"]). }
    IF etype = "CPU_LOAD_CRITICAL" { aoso_log_warn("BRAIN", "CPU critical: " + ev["data"]). }
    IF etype = "PLAN_UPDATED" { aoso_ctx_mark_plan(). }
}

// Route correction events into the existing GOTO/rendezvous mid-course path.
// The brain only requests work; GOTO still owns node creation and execution.
FUNCTION aoso_brain_request_correction {
    PARAMETER reason.
    PARAMETER require_residual IS TRUE.
    LOCAL residual IS 0.
    LOCAL target_name IS "".
    IF DEFINED AOSO_LAST_RESULT {
        IF AOSO_LAST_RESULT:HASKEY("dv_error") { SET residual TO ABS(AOSO_LAST_RESULT["dv_error"]). }
        IF AOSO_LAST_RESULT:HASKEY("target") { SET target_name TO AOSO_LAST_RESULT["target"]. }
    }
    IF require_residual {
        IF residual < aoso_config_get("CORRECT_LOCAL_DV", 25) { RETURN FALSE. }
    }
    IF DEFINED AOSO_GOTO {
        LOCAL gs IS AOSO_GOTO["current"].
        IF gs <> "" AND gs <> "DONE" AND gs <> "ABORTED" {
            SET AOSO_GOTO["data"]["correct_requested"] TO TRUE.
            SET AOSO_GOTO["data"]["correct_cool_ut"] TO 0.
            aoso_log_info("BRAIN", "Requested existing GOTO correction: " + reason).
            RETURN TRUE.
        }
    }
    IF target_name = "" { SET target_name TO aoso_ctx_get("target", ""). }
    IF target_name = "" { RETURN FALSE. }
    IF target_name = SHIP:BODY:NAME { RETURN FALSE. }
    IF NOT SHIP:ORBIT:HASNEXTPATCH { RETURN FALSE. }
    LOCAL patch_name IS SHIP:ORBIT:NEXTPATCH:BODY:NAME.
    IF patch_name <> target_name { RETURN FALSE. }
    aoso_goto_start(target_name, TRUE).
    aoso_log_info("BRAIN", "Requested one existing GOTO mid-course for " + target_name + ": " + reason).
    RETURN TRUE.
}

FUNCTION aoso_brain_consider_replan {
    PARAMETER reason.
    SET AOSO_BRAIN["pending_replan"] TO reason.
}

// Local flight guidance owns the current leg. Model updates may dirty the
// strategic plan, but they must not tear down/rebuild the full tour in the
// middle of GOTO, polar insertion, site survey, deorbit, or descent.
FUNCTION aoso_brain_local_guidance_active {
    IF DEFINED AOSO_GOTO {
        LOCAL gs IS AOSO_GOTO["current"].
        IF gs <> "" AND gs <> "DONE" AND gs <> "ABORTED" { RETURN TRUE. }
    }
    IF DEFINED AOSO_TOUR {
        LOCAL ts IS AOSO_TOUR["current"].
        IF ts = "POLAR" OR ts = "SCAN" OR ts = "DEORBIT" OR ts = "DESCEND" {
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

FUNCTION aoso_brain_do_replan {
    PARAMETER reason.
    IF AOSO_BRAIN["hold"] { RETURN. }
    IF aoso_brain_local_guidance_active() { RETURN. }
    IF DEFINED AOSO_PLAN_LAST {
        IF DEFINED AOSO_CPU_LEVEL {
            IF AOSO_CPU_LEVEL >= 2 {
                IF NOT aoso_brain_is_quiet() { RETURN. }
            }
        }
        IF NOT aoso_brain_think_ok() { RETURN. }
        aoso_log_info("BRAIN", "Replanning (" + reason + ").").

        // Planner owns dependency synchronization; do not refresh the same
        // profile/budget twice in one replan.
        aoso_plan_build().
        SET AOSO_BRAIN["last_replan"] TO TIME:SECONDS.
        SET AOSO_BRAIN["replan_reason"] TO reason.
        SET AOSO_BRAIN["pending_replan"] TO "".
        aoso_ctx_clear_dirty("dirty_plan").
        aoso_ctx_clear_dirty("dirty_feas").
        aoso_ctx_clear_dirty("dirty_opp").
        aoso_ctx_clear_dirty("dirty_route").
        aoso_event_publish("PLAN_UPDATED", "brain", reason).
        aoso_decide("BRAIN", "replan", reason, AOSO_BRAIN["replan_reason"], "dv=" + ROUND(aoso_budget_get("mission_dv", 0), 0)).
    }
}

FUNCTION aoso_brain_refresh_dirty {
    IF NOT aoso_brain_think_ok() { RETURN. }
    IF aoso_ctx_is_dirty("dirty_topo") {
        IF NOT aoso_ctx_is_dirty("dirty_vehicle") {
            aoso_topo_refresh(FALSE).
        }
        aoso_ctx_clear_dirty("dirty_topo").
    }
    IF aoso_ctx_is_dirty("dirty_vehicle") {
        aoso_profile_refresh("brain_dirty").
        aoso_ctx_clear_dirty("dirty_vehicle").
        aoso_ctx_clear_dirty("dirty_cap").
        aoso_ctx_bump("rev_cap").
    }
    IF aoso_ctx_is_dirty("dirty_budget") {
        aoso_budget_refresh().
        aoso_ctx_clear_dirty("dirty_budget").
    }
}

FUNCTION aoso_brain_tick {
    LOCAL prev_body IS AOSO_BRAIN["last_body"].
    aoso_ctx_refresh_env().
    SET AOSO_CTX["quiet"] TO aoso_brain_is_quiet().
    IF AOSO_CTX["body"] <> prev_body {
        IF prev_body <> "" {
            aoso_event_publish("SOI_CHANGED", "brain", prev_body + "->" + AOSO_CTX["body"]).
        }
        SET AOSO_BRAIN["last_body"] TO AOSO_CTX["body"].
    }
    aoso_event_process(4).
    aoso_brain_refresh_dirty().
    IF AOSO_BRAIN["pending_replan"] <> "" {
        LOCAL debounce IS aoso_config_get("BRAIN_REPLAN_DEBOUNCE_S", 45).
        IF TIME:SECONDS - AOSO_BRAIN["last_replan"] >= debounce {
            aoso_brain_do_replan(AOSO_BRAIN["pending_replan"]).
        }
    }
    IF aoso_brain_is_quiet() {
        IF TIME:SECONDS - AOSO_BRAIN["last_cert"] >= 30 {
            aoso_cert_eval("grand_tour").
            aoso_assure_eval().
            SET AOSO_BRAIN["last_cert"] TO TIME:SECONDS.
        }
    }
    SET AOSO_BRAIN["last_think"] TO TIME:SECONDS.
}

FUNCTION aoso_brain_register_task {
    PARAMETER interval_s IS 2.
    aoso_sched_add("brain", interval_s, aoso_brain_tick@).
}
