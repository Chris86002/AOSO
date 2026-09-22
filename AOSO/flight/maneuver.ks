// AOSO/flight/maneuver.ks
// Generic maneuver-node creation and execution. Pure vis-viva/kOS-native
// NODE math -- no MechJeb/Astrogator dependency (see core/addons.ks) -- so
// every later phase (orbital nav, interplanetary, return) can reuse
// aoso_maneuver_execute_next() as its burn executor instead of each writing
// its own throttle/steering loop.
//
// Burn execution: short burns (circularization) lock facing at ignition so
// a TWR jump cannot hunt NEXTNODE:BURNVECTOR. Long burns (Mun 840 m/s)
// follow the live marker until a few seconds remain, then lock and feather.
// Acacius's 104 s Mun burn locked at ignition, staged, and left the marker;
// the intercept missed. Feathering used to start at 2 m/s remaining -- at
// TWR ~1 that is a fraction of a tick -- so the cut always arrived late.
// After rails warp we physics-2x through the align window, then 1x for
// the last ~10 s. Physics 4x left Acacius 40 deg off the circ node (no RCS,
// 44 m, lander-can wheels) and four "missed" retries then an off-axis lock
// that feather-cut at 28 m/s remaining (82x62 km, peri still in atmosphere).

GLOBAL AOSO_MANEUVER_LOCK IS V(0, 0, 0).
GLOBAL AOSO_MANEUVER_BURNING IS FALSE.
GLOBAL AOSO_MANEUVER_LAST_REMAINING IS 0.
GLOBAL AOSO_MANEUVER_START_DV IS 0.
GLOBAL AOSO_MANEUVER_BURN_STARTED_AT IS 0.
GLOBAL AOSO_MANEUVER_PREDICTED_TIME IS 0.
GLOBAL AOSO_MANEUVER_RESULT IS "ok".
GLOBAL AOSO_MANEUVER_NO_THRUST_TICKS IS 0.
GLOBAL AOSO_MANEUVER_APO_CAP IS -1.
GLOBAL AOSO_MANEUVER_CUT_BODY IS "".
GLOBAL AOSO_WARP_LAST_KEY IS "".
GLOBAL AOSO_WARP_LAST_RT IS -1.

FUNCTION aoso_maneuver_reset_exec {
    SET AOSO_MANEUVER_BURNING TO FALSE.
    SET AOSO_MANEUVER_LOCK TO V(0, 0, 0).
    SET AOSO_MANEUVER_LAST_REMAINING TO 0.
    SET AOSO_MANEUVER_START_DV TO 0.
    SET AOSO_MANEUVER_BURN_STARTED_AT TO 0.
    SET AOSO_MANEUVER_PREDICTED_TIME TO 0.
    SET AOSO_MANEUVER_NO_THRUST_TICKS TO 0.
    aoso_staging_reset_relight().
    IF DEFINED AOSO_STAGING_BURN_RECOVERY {
        aoso_staging_reset_burn_guard().
    }
}

FUNCTION aoso_maneuver_set_apo_cap {
    PARAMETER apo_alt.
    SET AOSO_MANEUVER_APO_CAP TO apo_alt.
}

FUNCTION aoso_maneuver_set_cut_body {
    PARAMETER body_name.
    SET AOSO_MANEUVER_CUT_BODY TO body_name.
}

FUNCTION aoso_maneuver_clear_apo_cap {
    SET AOSO_MANEUVER_APO_CAP TO -1.
    SET AOSO_MANEUVER_CUT_BODY TO "".
}

FUNCTION aoso_maneuver_last_result {
    RETURN AOSO_MANEUVER_RESULT.
}

FUNCTION aoso_maneuver_align_s {
    LOCAL s IS aoso_config_get("MANEUVER_ALIGN_S", 50).
    IF DEFINED AOSO_TOPO {
        LOCAL lead IS aoso_topo_turn_lead_s().
        IF lead > s { SET s TO lead. }
    }
    IF s < 35 { SET s TO 35. }
    RETURN s.
}

FUNCTION aoso_maneuver_can_warp {
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH" { RETURN FALSE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT + 1000 { RETURN FALSE. }
    }
    RETURN TRUE.
}

// TRUE when periapsis is still inside the atmosphere (plus an optional
// margin). Circularization must not give up or feather-cut in that state.
FUNCTION aoso_maneuver_peri_unsafe {
    PARAMETER margin IS 0.
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    RETURN PERIAPSIS < SHIP:BODY:ATM:HEIGHT + margin.
}

// kOS will not switch RAILS/PHYSICS while WARP>0, and WARPTO is a no-op
// in physics warp. Drop to 0, wait a tick, then set the mode.
FUNCTION aoso_warp_force_rails {
    IF WARPMODE = "RAILS" { RETURN. }
    SET WARP TO 0.
    aoso_yield_hud().
    SET WARPMODE TO "RAILS".
    aoso_yield_hud().
}

FUNCTION aoso_warp_force_physics {
    IF WARPMODE = "PHYSICS" { RETURN. }
    SET WARP TO 0.
    aoso_yield_hud().
    SET WARPMODE TO "PHYSICS".
    aoso_yield_hud().
}

// kOS PHYSICS WARP: 1=2x, 2=3x, 3=4x. Config is the multiplier (2 = 2x).
FUNCTION aoso_warp_physics_index {
    LOCAL mult IS aoso_config_get("WARP_PHYSICS_CRUISE", 2).
    LOCAL widx IS ROUND(mult, 0) - 1.
    IF widx < 1 { SET widx TO 1. }
    IF widx > 3 { SET widx TO 3. }
    RETURN widx.
}

FUNCTION aoso_warp_set_physics_cruise {
    IF SHIP:STATUS = "PRELAUNCH" {
        SET WARP TO 0.
        RETURN.
    }
    aoso_warp_force_physics().
    LOCAL widx IS aoso_warp_physics_index().
    IF WARP <> widx { SET WARP TO widx. }
}

FUNCTION aoso_warp_stop {
    IF WARP > 0 { SET WARP TO 0. }
}

// WAIT 0 while rails is still running advances UT by hours. Capture
// planning did that and then "missed" a 40 s node by 28000 s forever.
FUNCTION aoso_warp_hard_stop {
    IF WARP > 0 { SET WARP TO 0. }
    WAIT 0.
    IF WARP > 0 {
        SET WARP TO 0.
        WAIT 0.
    }
    IF WARP > 0 { SET WARP TO 0. }
}

FUNCTION aoso_warp_rate_txt {
    IF WARP <= 0 { RETURN "1x". }
    IF WARPMODE = "PHYSICS" {
        IF WARP = 1 { RETURN "PHYS 2x". }
        IF WARP = 2 { RETURN "PHYS 3x". }
        IF WARP = 3 { RETURN "PHYS 4x". }
        RETURN "PHYS idx" + WARP.
    }
    IF WARP = 1 { RETURN "RAILS 5x". }
    IF WARP = 2 { RETURN "RAILS 10x". }
    IF WARP = 3 { RETURN "RAILS 50x". }
    IF WARP = 4 { RETURN "RAILS 100x". }
    IF WARP = 5 { RETURN "RAILS 1000x". }
    IF WARP = 6 { RETURN "RAILS 10000x". }
    IF WARP = 7 { RETURN "RAILS 100000x". }
    RETURN "RAILS idx" + WARP.
}

FUNCTION aoso_warp_diag_txt {
    LOCAL steer IS "OFF".
    IF DEFINED AOSO_STEER_MODE { SET steer TO AOSO_STEER_MODE. }
    RETURN aoso_warp_rate_txt() + " steer=" + steer.
}

FUNCTION aoso_warp_report {
    PARAMETER phase.
    PARAMETER eta_s.
    PARAMETER detail IS "".

    LOCAL key IS phase + "|" + WARPMODE + "|" + WARP.
    LOCAL now_rt IS KUNIVERSE:REALTIME.
    LOCAL every_s IS aoso_config_get("WARP_STATUS_REAL_S", 30).
    LOCAL changed IS FALSE.
    IF key <> AOSO_WARP_LAST_KEY { SET changed TO TRUE. }
    IF AOSO_WARP_LAST_RT < 0 { SET changed TO TRUE. }

    LOCAL periodic IS FALSE.
    IF AOSO_WARP_LAST_RT >= 0 {
        IF now_rt - AOSO_WARP_LAST_RT >= every_s { SET periodic TO TRUE. }
    }
    IF NOT changed AND NOT periodic { RETURN. }

    SET AOSO_WARP_LAST_KEY TO key.
    SET AOSO_WARP_LAST_RT TO now_rt.
    LOCAL msg IS phase + " T-" + ROUND(MAX(0, eta_s), 0) + "s  " + aoso_warp_diag_txt().
    IF detail <> "" { SET msg TO msg + "  " + detail. }

    // Console stays operational: print every actual phase/rate/mode change.
    // Long-coast heartbeat repeats remain in aoso_log.txt but no longer bury
    // the useful state transitions in the terminal.
    IF changed {
        aoso_log_info("WARP", msg + ".").
    } ELSE {
        aoso_log_info_quiet("WARP", msg + ".").
    }
}

// Rails when the event is still far. Physics 2x while SAS points.
// 1x only for the last WARP_CRUCIAL_S (burns, SOI, suicide). Physics 4x
// (WARP=3) slewed Acacius 40 deg off a circ node; 2x is the cruise floor.
// LOCK STEERING makes WARPTO a no-op — and WAIT 0 cancels WARPTO anyway,
// so this is SET WARP only, stepped down early. Warp 7 until lead+180
// overshot a 11 h Minmus mid-course by 360 s and then sat 1x never-aligned.
// Returns "rails" / "physics" / "now" / "hold".
FUNCTION aoso_warp_approach {
    PARAMETER eta_s.
    PARAMETER rails_lead_s.
    PARAMETER physics_until_s IS -1.

    LOCAL crucial_s IS aoso_config_get("WARP_CRUCIAL_S", 10).
    IF physics_until_s < 0 {
        SET physics_until_s TO aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10).
    }
    IF physics_until_s < crucial_s { SET physics_until_s TO crucial_s. }

    IF eta_s <= physics_until_s {
        SET WARP TO 0.
        aoso_warp_report("PRECISION", eta_s, "1x inside T-" + ROUND(physics_until_s, 0) + "s").
        RETURN "now".
    }
    IF NOT aoso_maneuver_can_warp() {
        IF SHIP:STATUS = "PRELAUNCH" {
            SET WARP TO 0.
            aoso_warp_report("HOLD", eta_s, "pad").
            RETURN "hold".
        }
        aoso_warp_set_physics_cruise().
        aoso_warp_report("CRUISE", eta_s, "physics-only region").
        RETURN "physics".
    }

    LOCAL want IS aoso_warp_rails_want(eta_s, rails_lead_s).
    IF want <= 0 {
        aoso_warp_set_physics_cruise().
        aoso_warp_report("ALIGN", eta_s, "precision lead T-" + ROUND(rails_lead_s, 0) + "s").
        RETURN "physics".
    }
    IF AOSO_STEER_MODE <> "OFF" { aoso_steer_release(). }
    IF WARPMODE <> "RAILS" {
        aoso_warp_hard_stop().
        SET WARPMODE TO "RAILS".
        WAIT 0.
    }
    IF WARP <> want { SET WARP TO want. }
    aoso_warp_report("COAST", eta_s, "precision lead T-" + ROUND(rails_lead_s, 0) + "s").
    RETURN "rails".
}

// Delta-v (m/s, signed) needed at the current apoapsis to circularize:
// target circular speed minus the vessel's actual speed there, derived from
// the current orbit's semi-major axis via vis-viva.
FUNCTION aoso_maneuver_circularize_dv_at_apoapsis {
    IF aoso_orbit_is_hyperbolic() { RETURN 0. }
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + APOAPSIS.
    LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.

    LOCAL v_circ IS SQRT(mu / radius).
    LOCAL v_now IS SQRT(MAX(0, mu * (2 / radius - 1 / sma))).

    RETURN v_circ - v_now.
}

FUNCTION aoso_maneuver_add_circularize_at_apoapsis {
    IF aoso_orbit_is_hyperbolic() {
        aoso_log_warn("MANEUVER", "No apoapsis on a hyperbola - circularizing at periapsis instead.").
        RETURN aoso_hohmann_add_circularize_at_periapsis().
    }
    LOCAL dv IS aoso_maneuver_circularize_dv_at_apoapsis().
    LOCAL nd IS NODE(TIME:SECONDS + aoso_orbit_eta_apoapsis(), 0, 0, dv).
    ADD nd.
    aoso_log_info("MANEUVER", "Circularization node added: dv=" + ROUND(dv, 1) + " m/s at apoapsis.").
    RETURN nd.
}

// Same vis-viva circularization but at the current radius, for when we
// already passed apoapsis (ETA:AP jumped a full period) and waiting would
// put periapsis back in the atmosphere.
FUNCTION aoso_maneuver_add_circularize_here {
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL v_circ IS SQRT(mu / radius).
    LOCAL v_now IS SQRT(MAX(0, mu * (2 / radius - 1 / sma))).
    LOCAL dv IS v_circ - v_now.
    LOCAL nd IS NODE(TIME:SECONDS + 30, 0, 0, dv).
    ADD nd.
    aoso_log_info("MANEUVER", "Circularization node added: dv=" + ROUND(dv, 1) + " m/s now (past apoapsis).").
    RETURN nd.
}

FUNCTION aoso_maneuver_has_pending {
    RETURN HASNODE.
}

// Instantaneous acceleration (m/s^2) available from currently ignited
// engines. Used to convert remaining dv into a burn-time so feathering
// starts ~MANEUVER_FEATHER_S seconds out instead of at a fixed 2 m/s.
FUNCTION aoso_maneuver_current_accel {
    IF SHIP:MASS <= 0 { RETURN 0. }
    RETURN SHIP:AVAILABLETHRUST / SHIP:MASS.
}

// Tapers throttle so remaining dv is killed in roughly MANEUVER_FEATHER_S
// seconds. Full throttle while remaining burn time is above that window;
// linear fade after. Recalculated every tick so a mid-burn staging/relight
// that jumps TWR still feathers instead of overshooting.
FUNCTION aoso_maneuver_throttle_for_dv {
    PARAMETER remaining_dv.

    LOCAL accel IS aoso_maneuver_current_accel().
    IF accel <= 0 { RETURN 0. }
    IF remaining_dv <= 0.05 { RETURN 0. }

    LOCAL t_remain IS remaining_dv / accel.
    LOCAL feather_s IS AOSO_CONFIG["MANEUVER_FEATHER_S"].
    IF t_remain > feather_s { RETURN 1.0. }
    RETURN MAX(0.05, t_remain / feather_s).
}

FUNCTION aoso_maneuver_tick_guard {
    PARAMETER remaining_dv.
    PARAMETER wanted_throttle.
    IF wanted_throttle <= 0 { RETURN 0. }
    IF DEFINED AOSO_PHYS_DT {
        // measured at the start of this physics-tick control slice
    } ELSE {
        RETURN wanted_throttle.
    }
    LOCAL dt IS AOSO_PHYS_DT.
    IF dt <= 0 { RETURN wanted_throttle. }
    LOCAL gap_limit IS aoso_config_get("MANEUVER_GAP_CUT_S", 0.12).
    IF dt > gap_limit { RETURN 0. }
    LOCAL accel IS aoso_maneuver_current_accel().
    IF accel <= 0.05 { RETURN wanted_throttle. }
    LOCAL next_tick_dv IS accel * dt * wanted_throttle.
    LOCAL guard_n IS aoso_config_get("MANEUVER_TICK_GUARD", 0.8).
    IF guard_n < 0.2 { SET guard_n TO 0.2. }
    IF guard_n > 1 { SET guard_n TO 1. }
    LOCAL allowed IS remaining_dv * guard_n.
    IF next_tick_dv <= allowed { RETURN wanted_throttle. }
    LOCAL cap IS allowed / (accel * dt).
    IF cap < 0.01 { SET cap TO 0.01. }
    IF cap > wanted_throttle { SET cap TO wanted_throttle. }
    RETURN cap.
}

FUNCTION aoso_maneuver_finish_node {
    PARAMETER nd.
    PARAMETER reason.
    LOCAL left IS AOSO_MANEUVER_LAST_REMAINING.
    LOCAL start_dv IS AOSO_MANEUVER_START_DV.
    LOCAL burn_started IS AOSO_MANEUVER_BURN_STARTED_AT.
    LOCAL burn_pred IS AOSO_MANEUVER_PREDICTED_TIME.
    LOCAL burn_actual IS 0.
    IF burn_started > 0 { SET burn_actual TO MAX(0, TIME:SECONDS - burn_started). }
    LOCAL burn_used IS start_dv - left.
    IF burn_used < 0 { SET burn_used TO 0. }

    LOCAL parent_type IS "".
    LOCAL owns_action IS FALSE.
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        IF AOSO_ACTION_CUR:HASKEY("type") { SET parent_type TO AOSO_ACTION_CUR["type"]. }
        IF parent_type = "MANEUVER" { SET owns_action TO TRUE. }
    }

    SET WARP TO 0.
    aoso_yield_hud().
    SET WARPMODE TO "RAILS".
    aoso_throttle_set(0).
    RCS OFF.
    aoso_steer_release().
    IF HASNODE { REMOVE nd. }
    aoso_maneuver_reset_exec().
    aoso_maneuver_clear_apo_cap().

    IF reason = "missed" { SET AOSO_MANEUVER_RESULT TO "missed". }
    ELSE {
        IF reason = "no thrust" OR reason = "incomplete" { SET AOSO_MANEUVER_RESULT TO "incomplete". }
        ELSE {
            IF reason = "feather cut" {
                IF aoso_maneuver_peri_unsafe(2000) { SET AOSO_MANEUVER_RESULT TO "incomplete". }
                ELSE { SET AOSO_MANEUVER_RESULT TO "ok". }
            } ELSE { SET AOSO_MANEUVER_RESULT TO "ok". }
        }
    }

    aoso_log_info("MANEUVER", "Node executed (" + reason + ").").
    aoso_observe_event("BURN", "INFO", reason,
        "left=" + ROUND(left, 2) + " used=" + ROUND(burn_used, 2) +
        " pred_t=" + ROUND(burn_pred, 2) + " act_t=" + ROUND(burn_actual, 2)).

    LOCAL failed IS AOSO_MANEUVER_RESULT <> "ok".
    IF parent_type <> "" {
        IF parent_type <> "MANEUVER" {
            IF parent_type <> "ASCENT" AND parent_type <> "TAKEOFF" {
                aoso_action_add_actual_dv(burn_used).
            }
            IF start_dv > 0 { aoso_xp_record("MANEUVER", SHIP:BODY:NAME, start_dv, burn_used, failed). }
            IF burn_pred > 0 { aoso_xp_record_metric("MANEUVER", SHIP:BODY:NAME, "BURN_TIME", burn_pred, burn_actual, failed). }
        }
    }

    IF owns_action {
        LOCAL res_m IS aoso_result_make("MANEUVER", "SUCCESS", reason).
        IF failed { SET res_m["status"] TO "FAILED". }
        SET res_m["predicted_dv"] TO start_dv.
        SET res_m["actual_dv"] TO burn_used.
        SET res_m["predicted_duration"] TO burn_pred.
        LOCAL ver_m IS aoso_verify_maneuver(AOSO_MANEUVER_RESULT).
        SET res_m TO aoso_verify_apply_result(res_m, ver_m).
        aoso_result_emit(res_m).
    }

    aoso_warp_deadline_clear("node").
    aoso_auth_release_all("maneuver").
    aoso_auth_use("").
    IF reason = "missed" {
        aoso_observe_anomaly("BURN_MISSED", "HIGH", 0, left).
    } ELSE {
        IF reason = "incomplete" OR reason = "no thrust" {
            aoso_observe_anomaly("BURN_INCOMPLETE", "HIGH", 0, left).
        }
    }
}

// Non-blocking: call once per scheduler tick (or in a tight WAIT 0 loop).
// Warps out on rails, then stays at 1x with ~2 minutes to point before
// ignition. Long burns follow the live node marker (Mun 840 m/s); short
// burns lock facing at ignition so a TWR jump cannot hunt — unless we
// had to light off-axis, in which case we follow the marker so a 30 deg
// error cannot zero remaining_along and feather-cut with 28 m/s left.
// Stage even if throttle is already 0. If the node is already in the
// past and periapsis is safe, finish as missed so the caller can replan.
// A periapsis still in atmosphere never gives up: light off-axis and
// keep burning until peri is out of the air.
// Returns TRUE once there is no pending node left, FALSE while in progress.
FUNCTION aoso_maneuver_execute_next {
    IF NOT HASNODE {
        IF AOSO_MANEUVER_BURNING { aoso_maneuver_reset_exec(). }
        RETURN TRUE.
    }

    aoso_auth_use("maneuver").
    LOCAL nd IS NEXTNODE.
    LOCAL remaining_vec IS nd:BURNVECTOR.
    LOCAL remaining IS remaining_vec:MAG.
    LOCAL hb_p IS 0.
    LOCAL hb_st IS "WAIT".
    IF AOSO_MANEUVER_BURNING {
        SET hb_st TO "BURN".
        IF AOSO_MANEUVER_START_DV > 0.1 { SET hb_p TO 1 - remaining / AOSO_MANEUVER_START_DV. }
    } ELSE {
        IF nd:ETA > 0 { SET hb_p TO 1 - nd:ETA / (nd:ETA + 3600). }
    }
    IF hb_p < 0 { SET hb_p TO 0. }
    IF hb_p > 1 { SET hb_p TO 1. }
    aoso_hb_set("maneuver", hb_st, hb_p).

    IF remaining < 0.08 {
        IF aoso_maneuver_peri_unsafe(2000) {
            aoso_maneuver_finish_node(nd, "incomplete").
            RETURN TRUE.
        }
        aoso_maneuver_finish_node(nd, "complete").
        RETURN TRUE.
    }

    // If KSP/kOS did not hand control back for a coarse physics interval,
    // never keep carrying the throttle command from the stale tick. The
    // command can only be corrected after execution resumes, so cut now,
    // re-sample the live node, and resume on the next stable tick.
    IF AOSO_MANEUVER_BURNING {
        LOCAL gap_limit IS aoso_config_get("MANEUVER_GAP_CUT_S", 0.12).
        IF DEFINED AOSO_PHYS_DT {
            IF AOSO_PHYS_DT > gap_limit {
                aoso_throttle_set(0).
                SET AOSO_MANEUVER_LOCK TO remaining_vec.
                SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
                LOCAL wall_gap IS 0.
                IF DEFINED AOSO_WALL_DT { SET wall_gap TO AOSO_WALL_DT. }
                aoso_observe_event("BURN_GAP", "WARN", "recover",
                    "game_dt=" + ROUND(AOSO_PHYS_DT, 4) +
                    " wall_dt=" + ROUND(wall_gap, 4) +
                    " left=" + ROUND(remaining, 2) +
                    " stg=" + STAGE:NUMBER).
                RETURN FALSE.
            }
        }
    }

    IF NOT AOSO_MANEUVER_BURNING {
        IF WARP > 0 {
            IF nd:ETA < 90 {
                aoso_warp_hard_stop().
            }
        }
        LOCAL peri_unsafe IS aoso_maneuver_peri_unsafe(0).
        // Stale node: a transfer has no "next pass". Small overshoot still
        // burns; a node minutes in the past is a miss so goto can replan now.
        IF nd:ETA < -25 {
            aoso_log_warn("MANEUVER", "Missed node (ETA=" + ROUND(nd:ETA, 1) + "s) - retry next pass.").
            aoso_maneuver_finish_node(nd, "missed").
            RETURN TRUE.
        }
        IF nd:ETA < -8 {
            IF NOT peri_unsafe {
                aoso_log_warn("MANEUVER", "Missed node (ETA=" + ROUND(nd:ETA, 1) + "s) - retry next pass.").
                aoso_maneuver_finish_node(nd, "missed").
                RETURN TRUE.
            }
        }

        LOCAL burn_time IS aoso_perf_burn_time_for_dv(remaining).
        LOCAL ignite_lead IS burn_time / 2.
        LOCAL align_s IS aoso_maneuver_align_s().
        LOCAL warp_lead IS ignite_lead + align_s.
        LOCAL physics_until IS ignite_lead + aoso_config_get("MANEUVER_PHYSICS_UNTIL_S", 10).
        IF nd:ETA > 0 {
            aoso_warp_deadline_set("node", TIME:SECONDS + nd:ETA).
        }
        aoso_auth_acquire("maneuver", "STEERING", 3).
        aoso_auth_acquire("maneuver", "THROTTLE", 3).
        aoso_auth_acquire("maneuver", "WARP", 2).
        aoso_auth_use("maneuver").
        // Equal prio cannot preempt. Ascent circularize must
        // aoso_ascent_yield_burn() before calling us or throttle stays 0.

        // Do not LOCK STEERING until the align window. Rails WARPTO is a
        // no-op while steering is locked, which is why the 8 m/s Minmus
        // mid-course sat 18 hours at 1x/physics instead of rails.
        IF nd:ETA > warp_lead + 5 {
            IF NOT peri_unsafe {
                aoso_steer_release().
                RCS OFF.
                aoso_warp_request(nd:ETA, warp_lead, physics_until).
                aoso_throttle_set(0).
                RETURN FALSE.
            }
        }

        aoso_steer_prepare_for_burn().
        RCS ON.
        aoso_steer_to_vector(remaining_vec).

        LOCAL wstate IS aoso_warp_request(nd:ETA, warp_lead, physics_until).
        IF wstate = "rails" OR wstate = "physics" {
            aoso_throttle_set(0).
            RETURN FALSE.
        }
        SET WARP TO 0.

        aoso_staging_auto_check().
        IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

        LOCAL must_burn IS FALSE.
        IF peri_unsafe {
            IF nd:ETA < 2 { SET must_burn TO TRUE. }
        }
        IF nd:ETA <= 0 { SET must_burn TO TRUE. }

        IF nd:ETA > ignite_lead + 1 {
            IF NOT must_burn {
                aoso_throttle_set(0).
                RETURN FALSE.
            }
        }

        LOCAL err_deg IS aoso_steer_error_deg(remaining_vec).
        LOCAL off_axis IS FALSE.
        LOCAL align_ok IS 12.
        IF nd:ETA < ignite_lead { SET align_ok TO 18. }
        IF must_burn { SET align_ok TO 25. }
        IF NOT aoso_steer_is_aligned(remaining_vec, align_ok) {
            IF NOT must_burn {
                IF nd:ETA < -8 {
                    aoso_log_warn("MANEUVER", "Never aligned in time - retry next pass.").
                    aoso_maneuver_finish_node(nd, "missed").
                    RETURN TRUE.
                }
                aoso_throttle_set(0).
                RETURN FALSE.
            }
            IF err_deg > 35 {
                aoso_log_warn("MANEUVER", "Never aligned in time - retry next pass.").
                aoso_maneuver_finish_node(nd, "missed").
                RETURN TRUE.
            }
            SET off_axis TO TRUE.
            aoso_log_warn("MANEUVER", "Lighting off-axis (" + ROUND(err_deg, 0) + " deg).").
        }

        IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }

        SET WARP TO 0.
        SET AOSO_MANEUVER_LOCK TO remaining_vec.
        // A new burn must never inherit a pre-cut/recovery latch from an
        // earlier maneuver or a transient staging check.
        aoso_staging_reset_burn_guard().
        SET AOSO_MANEUVER_BURNING TO TRUE.
        SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
        SET AOSO_MANEUVER_START_DV TO remaining.
        SET AOSO_MANEUVER_BURN_STARTED_AT TO TIME:SECONDS.
        SET AOSO_MANEUVER_PREDICTED_TIME TO burn_time.
        SET AOSO_MANEUVER_NO_THRUST_TICKS TO 0.
        aoso_staging_reset_relight().
        SET AOSO_MANEUVER_RESULT TO "ok".
        LOCAL accel0 IS aoso_maneuver_current_accel().
        LOCAL t0 IS burn_time.
        IF t0 <= 0 {
            IF accel0 > 0.05 { SET t0 TO remaining / accel0. }
        }
        aoso_observe_event("BURN", "INFO", "start", "dv=" + ROUND(remaining, 1) + " t=" + ROUND(t0, 1)).
        IF NOT AOSO_ACTION_CUR:ISTYPE("Lexicon") {
            LOCAL did_i IS aoso_decide("MANEUVER", "ignite", "burn", "node",
                "dv=" + ROUND(remaining, 1) + " t=" + ROUND(t0, 1), remaining).
            LOCAL act_i IS aoso_action_create(did_i, "MANEUVER", SHIP:BODY:NAME, remaining).
            SET act_i["predicted_duration"] TO t0.
            aoso_action_begin(act_i).
        } ELSE {
            aoso_observe_event("DECIDE", "INFO", "MANEUVER",
                "embedded ignite dv=" + ROUND(remaining, 1) + " t=" + ROUND(t0, 1)).
        }
        LOCAL follow IS FALSE.
        IF t0 > AOSO_CONFIG["MANEUVER_FOLLOW_ABOVE_S"] { SET follow TO TRUE. }
        // Pure-normal / huge-vs-orbital-speed burns must lock. Following the
        // live marker on the 142 m/s Minmus polar (v=143 m/s) turned 15x15 km
        // into 980x15 km and only reached 74 deg.
        IF ABS(nd:NORMAL) > ABS(nd:PROGRADE) + ABS(nd:RADIALOUT) + 5 { SET follow TO FALSE. }
        IF remaining > SHIP:VELOCITY:ORBIT:MAG * 0.35 { SET follow TO FALSE. }
        // Off-axis circularization must follow the marker. Locking the 30 deg
        // error zeroed remaining_along and feather-cut with 28 m/s left
        // (Acacius 82x62 km, peri still in atmosphere).
        IF off_axis { SET follow TO TRUE. }
        IF peri_unsafe { SET follow TO TRUE. }
        IF follow {
            aoso_log_info("MANEUVER", "Burn started, following node, remaining=" + ROUND(remaining, 1) + " m/s.").
        } ELSE {
            SET AOSO_MANEUVER_LOCK TO SHIP:FACING:FOREVECTOR.
            aoso_log_info("MANEUVER", "Burn lock engaged, remaining=" + ROUND(remaining, 1) + " m/s.").
        }
    }

    IF SHIP:AVAILABLETHRUST <= 0 {
        aoso_staging_auto_check().
        aoso_staging_ensure_thrust().
        IF SHIP:AVAILABLETHRUST <= 0 {
            LOCAL waiting IS FALSE.
            IF TIME:SECONDS < AOSO_STAGING_SPOOL_UNTIL { SET waiting TO TRUE. }
            IF TIME:SECONDS < AOSO_STAGING_COOLDOWN_UNTIL { SET waiting TO TRUE. }
            IF AOSO_STAGING_PENDING_RELIGHT { SET waiting TO TRUE. }
            IF waiting {
                aoso_throttle_set(0).
                RETURN FALSE.
            }
            SET AOSO_MANEUVER_NO_THRUST_TICKS TO AOSO_MANEUVER_NO_THRUST_TICKS + 1.
            LOCAL patience IS AOSO_CONFIG["MANEUVER_NO_THRUST_TICKS"].
            IF AOSO_MANEUVER_NO_THRUST_TICKS < patience {
                aoso_throttle_set(0).
                RETURN FALSE.
            }
            aoso_maneuver_finish_node(nd, "no thrust").
            RETURN TRUE.
        }
    }
    SET AOSO_MANEUVER_NO_THRUST_TICKS TO 0.
    aoso_staging_auto_check().

    // Mid-burn STAGE() is deliberately two-phase: staging.ks first
    // commands zero throttle for one physics tick, then stages. Keep the
    // command at zero until relight/spool is complete and we have observed
    // a normal-size control tick again.
    IF aoso_staging_burn_guard_active() {
        aoso_throttle_set(0).
        SET AOSO_MANEUVER_LOCK TO remaining_vec.
        SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
        RETURN FALSE.
    }

    IF AOSO_MANEUVER_CUT_BODY <> "" {
        LOCAL cur_orb IS SHIP:ORBIT.
        LOCAL patch_i IS 0.
        LOCAL got_patch IS FALSE.
        LOCAL pe_cut IS -1.
        UNTIL patch_i >= 4 {
            IF NOT cur_orb:HASNEXTPATCH {
                SET patch_i TO 4.
            } ELSE {
                SET cur_orb TO cur_orb:NEXTPATCH.
                IF cur_orb:BODY:NAME = AOSO_MANEUVER_CUT_BODY {
                    SET got_patch TO TRUE.
                    SET pe_cut TO cur_orb:PERIAPSIS.
                }
                SET patch_i TO patch_i + 1.
            }
        }
        IF got_patch {
            LOCAL hop_cut IS BODY(AOSO_MANEUVER_CUT_BODY).
            LOCAL pe_ok IS FALSE.
            IF hop_cut:ISTYPE("Body") {
                SET pe_ok TO aoso_rendezvous_pe_ok_value(pe_cut, hop_cut).
            }
            // Only early-cut a transfer when the live patched-conic PE
            // is already inside the accepted capture band. A target-body
            // patch by itself is not enough: the old remaining<3 fallback
            // cut Minmus with a ~2,140 km PE and turned a 14 km planned
            // encounter into a grazing flyby.
            IF pe_ok {
                IF remaining < 40 {
                    aoso_log_info("MANEUVER", "Capture intercept with " + AOSO_MANEUVER_CUT_BODY +
                        " locked PE=" + ROUND(pe_cut, 0) + "m - preserving the valid patch.").
                    aoso_maneuver_finish_node(nd, "intercept").
                    RETURN TRUE.
                }
            }
        }
        IF SHIP:ORBIT:ECCENTRICITY >= 0.995 {
            aoso_log_warn("MANEUVER", "Eccentricity " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + " - cutting before escape.").
            aoso_maneuver_finish_node(nd, "apo cap").
            RETURN TRUE.
        }
    }

    IF AOSO_MANEUVER_APO_CAP > 0 {
        IF SHIP:ORBIT:ECCENTRICITY >= 0.995 {
            aoso_log_warn("MANEUVER", "Eccentricity " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + " - cutting before escape.").
            aoso_maneuver_finish_node(nd, "apo cap").
            RETURN TRUE.
        }
        LOCAL apo_now IS aoso_orbit_apoapsis_alt().
        IF apo_now >= AOSO_MANEUVER_APO_CAP {
            aoso_log_info("MANEUVER", "Apo " + ROUND(apo_now, 0) + "m reached target " + ROUND(AOSO_MANEUVER_APO_CAP, 0) + "m - cutting so we do not escape.").
            aoso_maneuver_finish_node(nd, "apo cap").
            RETURN TRUE.
        }
    }

    LOCAL accel IS aoso_maneuver_current_accel().
    LOCAL t_remain IS 0.
    IF accel > 0.05 { SET t_remain TO remaining / accel. }
    LOCAL follow_s IS AOSO_CONFIG["MANEUVER_FOLLOW_ABOVE_S"].
    LOCAL follow IS FALSE.
    IF t_remain > follow_s { SET follow TO TRUE. }
    IF ABS(nd:NORMAL) > ABS(nd:PROGRADE) + ABS(nd:RADIALOUT) + 5 { SET follow TO FALSE. }
    IF remaining > SHIP:VELOCITY:ORBIT:MAG * 0.35 { SET follow TO FALSE. }
    IF aoso_maneuver_peri_unsafe(0) { SET follow TO TRUE. }

    IF follow {
        LOCAL blended IS remaining_vec.
        IF AOSO_MANEUVER_LOCK:MAG > 0.2 {
            LOCAL mixed IS (AOSO_MANEUVER_LOCK:NORMALIZED * 0.7) + (remaining_vec:NORMALIZED * 0.3).
            IF mixed:MAG > 0.05 { SET blended TO mixed:NORMALIZED. }
        }
        SET AOSO_MANEUVER_LOCK TO blended.
        aoso_steer_to_vector(blended).
    } ELSE {
        IF AOSO_MANEUVER_LOCK:MAG < 0.1 {
            SET AOSO_MANEUVER_LOCK TO SHIP:FACING:FOREVECTOR.
        }
        aoso_steer_to_vector(AOSO_MANEUVER_LOCK).
    }

    LOCAL remaining_along IS VDOT(AOSO_MANEUVER_LOCK:NORMALIZED, remaining_vec).

    IF remaining_along < 0.08 {
        IF aoso_maneuver_peri_unsafe(2000) {
            SET AOSO_MANEUVER_LOCK TO remaining_vec.
            aoso_steer_to_vector(remaining_vec).
            IF remaining < 0.15 {
                aoso_maneuver_finish_node(nd, "incomplete").
                RETURN TRUE.
            }
            LOCAL unsafe_t IS aoso_maneuver_throttle_for_dv(remaining).
            aoso_throttle_set(aoso_maneuver_tick_guard(remaining, unsafe_t)).
            SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
            RETURN FALSE.
        }
        aoso_maneuver_finish_node(nd, "feather cut").
        RETURN TRUE.
    }
    IF remaining > AOSO_MANEUVER_LAST_REMAINING + 0.4 {
        // Small mid-course burns (Acacius 11.3 m/s) had remaining jump as
        // the Minmus patch flickered, "overshoot cut", and PE went negative.
        IF remaining > 25 {
            aoso_maneuver_finish_node(nd, "incomplete").
            RETURN TRUE.
        }
        IF remaining > AOSO_MANEUVER_LAST_REMAINING + 4 {
            aoso_maneuver_finish_node(nd, "overshoot cut").
            RETURN TRUE.
        }
    }

    SET AOSO_MANEUVER_LAST_REMAINING TO remaining.
    LOCAL wanted_t IS aoso_maneuver_throttle_for_dv(remaining_along).
    aoso_throttle_set(aoso_maneuver_tick_guard(remaining_along, wanted_t)).
    RETURN FALSE.
}

FUNCTION aoso_maneuver_clear_all {
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
    aoso_warp_deadline_clear("node").
    aoso_maneuver_reset_exec().
    aoso_maneuver_clear_apo_cap().
}
