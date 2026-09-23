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
    "last_cert", 0
).

FUNCTION aoso_brain_init {
    SET AOSO_BRAIN["last_replan"] TO 0.
    SET AOSO_BRAIN["replan_reason"] TO "".
    SET AOSO_BRAIN["pending_replan"] TO "".
    SET AOSO_BRAIN["last_think"] TO 0.
    SET AOSO_BRAIN["last_body"] TO SHIP:BODY:NAME.
    SET AOSO_BRAIN["last_cert"] TO 0.
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

    // Never wait for CPU/quiet-state while rails warp is still advancing UT.
    // A WAIT 0 at high rails warp can jump hundreds of game seconds and
    // made a freshly-created correction node thousands of seconds stale.
    IF WARP > 0 { aoso_warp_hard_stop(). }

    aoso_log_info("BRAIN", "Planning pause: " + why + " (1x, bounded wait).").
    aoso_ui_set("Thinking", why + "  1x bounded wait").
    LOCAL t0_rt IS KUNIVERSE:REALTIME.
    LOCAL max_s IS aoso_config_get("BRAIN_THINK_WAIT_S", 5).
    IF max_s > 8 { SET max_s TO 8. }
    IF max_s < 0 { SET max_s TO 0. }
    UNTIL aoso_brain_think_ok() {
        IF KUNIVERSE:REALTIME - t0_rt > max_s {
            aoso_log_warn("BRAIN", "Quiet wait expired (" + why + ") - calculating now at 1x.").
            RETURN FALSE.
        }
        IF DEFINED AOSO_HUD_READY {
            IF AOSO_HUD_READY {
                IF OPCODESLEFT > 200 { aoso_hud_fast_tick(). }
            }
        }
        WAIT 0.
    }
    aoso_log_info("BRAIN", "Quiet window open - " + why + ".").
    RETURN TRUE.
}

FUNCTION aoso_brain_on_event {
    PARAMETER ev.
    LOCAL etype IS ev["type"].
    IF etype = "STAGE_COMPLETE" { aoso_ctx_mark_vehicle(). aoso_ctx_mark_topo(). }
    IF etype = "VEHICLE_CHANGED" { aoso_ctx_mark_vehicle(). aoso_ctx_mark_topo(). }
    IF etype = "PROFILE_UPDATED" { aoso_ctx_mark_budget(). }
    IF etype = "CAPABILITY_CHANGED" { aoso_ctx_mark_vehicle(). }
    IF etype = "SOI_CHANGED" { aoso_ctx_mark_world(). aoso_brain_consider_replan("soi"). }
    IF etype = "ORBIT_ACHIEVED" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("orbit"). }
    IF etype = "ASCENT_SUCCESS" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("ascent"). }
    IF etype = "REFUEL_SUCCESS" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("refuel"). }
    IF etype = "LANDING_SUCCESS" { aoso_ctx_mark_world(). }
    IF etype = "TAKEOFF_COMPLETE" { aoso_ctx_mark_budget(). aoso_brain_consider_replan("takeoff"). }
    IF etype = "ENGINE_ANOMALY" { aoso_ctx_mark_vehicle(). aoso_brain_consider_replan("engine"). }
    IF etype = "MANEUVER_FAILED" { aoso_brain_consider_replan("maneuver_fail"). }
    IF etype = "MODEL_UPDATED" {
        aoso_ctx_dirty("dirty_feas").
        aoso_ctx_dirty("dirty_opp").
        aoso_ctx_dirty("dirty_route").
        aoso_ctx_dirty("dirty_plan").
        aoso_brain_consider_replan("model " + ev["data"]).
    }
    IF etype = "REPLAN_REQUESTED" { aoso_brain_consider_replan(ev["data"]). }
    IF etype = "CORRECT_REQUESTED" { aoso_log_info("BRAIN", "Local correction indicated: " + ev["data"]). }
    IF etype = "HOLD" { aoso_log_warn("BRAIN", "Safe hold: " + ev["data"]). }
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
    IF aoso_brain_local_guidance_active() { RETURN. }
    IF DEFINED AOSO_PLAN_LAST {
        IF DEFINED AOSO_CPU_LEVEL {
            IF AOSO_CPU_LEVEL >= 2 {
                IF NOT aoso_brain_is_quiet() { RETURN. }
            }
        }
        IF NOT aoso_brain_think_ok() { RETURN. }
        aoso_log_info("BRAIN", "Replanning (" + reason + ").").
        aoso_ui_set("Replanning", reason).
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
