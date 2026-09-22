// AOSO/dev/selftest.ks
// Vessel-safe checks for the v2 brain/context/XP loop.
// Does not STAGE, LOCK, WARP, THROTTLE, or add nodes.

RUN ONCE "AOSO/core/constants".
RUN ONCE "AOSO/core/json".
RUN ONCE "AOSO/core/logger".
RUN ONCE "AOSO/core/addons".
RUN ONCE "AOSO/core/config".
RUN ONCE "AOSO/core/observe".
RUN ONCE "AOSO/core/context".
RUN ONCE "AOSO/core/events".
RUN ONCE "AOSO/core/result".
RUN ONCE "AOSO/core/authority".
RUN ONCE "AOSO/core/verify".
RUN ONCE "AOSO/core/warp".
RUN ONCE "AOSO/core/brain".
RUN ONCE "AOSO/core/state".
RUN ONCE "AOSO/flight/steering".
RUN ONCE "AOSO/vehicle/experience".
RUN ONCE "AOSO/mission/feasibility".
RUN ONCE "AOSO/mission/project".
RUN ONCE "AOSO/refuel/isru".
RUN ONCE "AOSO/surface/operations".
RUN ONCE "AOSO/hardening/watchdog".
RUN ONCE "AOSO/interplanetary/bodydb".
RUN ONCE "AOSO/interplanetary/assist".
RUN ONCE "AOSO/nav/lambert".
RUN ONCE "AOSO/nav/cw".

FUNCTION aoso_selftest_check {
    PARAMETER name.
    PARAMETER ok.
    PARAMETER failures.
    IF ok {
        PRINT "  PASS  " + name.
        RETURN failures.
    }
    PRINT "  FAIL  " + name.
    RETURN failures + 1.
}

FUNCTION aoso_selftest {
    PRINT "AOSO selftest (no vessel control).".
    LOCAL fail IS 0.

    aoso_event_init().

    SET fail TO aoso_selftest_check("native addon detect boolean",
        aoso_addon_native_available() = TRUE OR aoso_addon_native_available() = FALSE, fail).
    IF aoso_addon_native_available() {
        LOCAL native_ver IS aoso_addon_native_version().
        SET fail TO aoso_selftest_check("native addon version", native_ver:ISTYPE("String") AND native_ver:LENGTH > 0, fail).
    }

    LOCAL i IS 0.
    UNTIL i >= 40 {
        aoso_event_publish("TEST", "selftest", "" + i).
        SET i TO i + 1.
    }
    SET fail TO aoso_selftest_check("event cap 32", aoso_event_count() = 32, fail).
    LOCAL n_drain IS aoso_event_process(4).
    SET fail TO aoso_selftest_check("event drain 4", n_drain = 4, fail).
    SET fail TO aoso_selftest_check("event leftover 28", aoso_event_count() = 28, fail).

    LOCAL res IS aoso_result_make("ASCENT", "SUCCESS", "orbit").
    SET fail TO aoso_selftest_check("result action_type", res["action_type"] = "ASCENT", fail).
    SET fail TO aoso_selftest_check("result status", res["status"] = "SUCCESS", fail).

    aoso_hb_set("selftest", "A", 0.1).
    LOCAL t1 IS AOSO_HB["selftest"]["progress_at"].
    aoso_hb_set("selftest", "A", 0.1).
    LOCAL t2 IS AOSO_HB["selftest"]["progress_at"].
    SET fail TO aoso_selftest_check("hb sticky progress_at", t1 = t2, fail).
    aoso_hb_set("selftest", "A", 0.2).
    LOCAL t3 IS AOSO_HB["selftest"]["progress_at"].
    SET fail TO aoso_selftest_check("hb moves on delta", t3 >= t1, fail).

    // 8.1 Lambert circular 90 deg.
    LOCAL lam_mu IS SHIP:BODY:MU.
    LOCAL radius_c IS SHIP:BODY:RADIUS + 80000.
    LOCAL pos_a IS V(radius_c, 0, 0).
    LOCAL pos_b IS V(0, radius_c, 0).
    LOCAL lam_tof IS CONSTANT:PI * SQRT((radius_c)^3 / lam_mu) / 2.
    LOCAL sol_90 IS aoso_lambert_solve(pos_a, pos_b, lam_tof, lam_mu, FALSE).
    LOCAL circular_speed IS SQRT(lam_mu / radius_c).
    LOCAL lam_90_ok IS sol_90["ok"].
    IF lam_90_ok {
        SET lam_90_ok TO ABS(sol_90["vel1"]:MAG - circular_speed) / circular_speed < 0.02.
    }
    IF lam_90_ok {
        IF ABS(VDOT(sol_90["vel1"], pos_a)) > 0.02 * circular_speed * radius_c { SET lam_90_ok TO FALSE. }
    }
    IF lam_90_ok {
        IF sol_90:HASKEY("tof_err") {
            IF sol_90["tof_err"] > 2 { SET lam_90_ok TO FALSE. }
        }
    }
    SET fail TO aoso_selftest_check("lambert circular 90", lam_90_ok, fail).

    LOCAL sol_90_ks IS aoso_lambert_solve_ks(pos_a, pos_b, lam_tof, lam_mu, FALSE).
    LOCAL lam_90_ks_ok IS sol_90_ks["ok"].
    IF lam_90_ks_ok {
        SET lam_90_ks_ok TO ABS(sol_90_ks["vel1"]:MAG - circular_speed) / circular_speed < 0.02.
    }
    IF lam_90_ks_ok {
        IF ABS(VDOT(sol_90_ks["vel1"], pos_a)) > 0.02 * circular_speed * radius_c { SET lam_90_ks_ok TO FALSE. }
    }
    IF lam_90_ks_ok {
        IF sol_90_ks:HASKEY("tof_err") {
            IF sol_90_ks["tof_err"] > 2 { SET lam_90_ks_ok TO FALSE. }
        }
    }
    SET fail TO aoso_selftest_check("lambert ks circular 90", lam_90_ks_ok, fail).

    // 8.2 Lambert 180 deg vis-viva special case.
    LOCAL pos_180 IS V(0 - radius_c, 0, 0).
    LOCAL half_period IS CONSTANT:PI * SQRT((radius_c)^3 / lam_mu).
    LOCAL sol_180 IS aoso_lambert_solve(pos_a, pos_180, half_period, lam_mu, FALSE).
    LOCAL lam_180_ok IS sol_180["ok"].
    IF lam_180_ok {
        SET lam_180_ok TO ABS(sol_180["vel1"]:MAG - circular_speed) / circular_speed < 0.02.
    }
    SET fail TO aoso_selftest_check("lambert 180 special", lam_180_ok, fail).

    // 8.2b Near-180 must use universal variable (not the Hohmann shortcut)
    // so a 0.85x TOF seed is not given a half-period vis-viva speed.
    LOCAL pos_179 IS V(0 - radius_c * COS(1), radius_c * SIN(1), 0).
    LOCAL sol_179 IS aoso_lambert_solve(pos_a, pos_179, half_period * 0.85, lam_mu, FALSE).
    LOCAL lam_179_ok IS sol_179["ok"].
    IF lam_179_ok {
        IF sol_179:HASKEY("tof_err") {
            IF sol_179["tof_err"] > 4 { SET lam_179_ok TO FALSE. }
        }
        IF ABS(sol_179["vel1"]:MAG - circular_speed) / circular_speed > 0.25 { SET lam_179_ok TO FALSE. }
    }
    SET fail TO aoso_selftest_check("lambert near-180 tof", lam_179_ok, fail).

    // 8.3 CW intercept algebra.
    LOCAL cw_st IS LEXICON("x", 0, "y", 2000, "z", 0,
        "ux", 0, "uy", 0, "uz", 0, "omega", 0.001, "ok", TRUE).
    LOCAL cw_imp IS aoso_cw_impulse_to_intercept(cw_st, 200).
    LOCAL cw_imp_ok IS cw_imp["ok"].
    IF cw_imp_ok {
        SET cw_imp_ok TO cw_imp["dv_mag"] > 0 AND ABS(cw_imp["dvz"]) < 1e-6.
    }
    SET fail TO aoso_selftest_check("cw intercept impulse", cw_imp_ok, fail).
    LOCAL cw_st2 IS LEXICON(
        "x", cw_st["x"], "y", cw_st["y"], "z", cw_st["z"],
        "ux", cw_st["ux"] + cw_imp["dvx"],
        "uy", cw_st["uy"] + cw_imp["dvy"],
        "uz", cw_st["uz"] + cw_imp["dvz"],
        "omega", cw_st["omega"], "ok", TRUE
    ).
    LOCAL cw_end IS aoso_cw_propagate(cw_st2, 200).
    LOCAL cw_pos_mag IS SQRT(cw_end["x"] ^ 2 + cw_end["y"] ^ 2 + cw_end["z"] ^ 2).
    SET fail TO aoso_selftest_check("cw intercept closes position", cw_end["ok"] AND cw_pos_mag < 50, fail).

    // 8.4 Astrogator compatibility stub: must never create a node.
    LOCAL ag_stub IS aoso_addon_astrogator_add_transfer(SHIP:BODY).
    SET fail TO aoso_selftest_check("astrogator intercept stub", ag_stub = 0, fail).

    LOCAL blank IS aoso_xp_blank().
    SET fail TO aoso_selftest_check("xp blank corr 1", blank["corr"] = 1, fail).
    LOCAL applied IS aoso_xp_apply("TRANSFER", "Minmus", 860).
    SET fail TO aoso_selftest_check("xp apply identity", ABS(applied - 860) < 0.01, fail).

    SET fail TO aoso_selftest_check("cont SAFE landable", aoso_feas_continuation_of(TRUE, TRUE, 2000, 800) = "SAFE", fail).
    SET fail TO aoso_selftest_check("cont DEAD_END no takeoff", aoso_feas_continuation_of(TRUE, FALSE, 2000, 800) = "DEAD_END", fail).
    SET fail TO aoso_selftest_check("cont DEAD_END leftover", aoso_feas_continuation_of(TRUE, TRUE, 20, 800) = "DEAD_END", fail).
    SET fail TO aoso_selftest_check("cont LOW", aoso_feas_continuation_of(TRUE, TRUE, 400, 1200) = "LOW", fail).
    SET fail TO aoso_selftest_check("cont SAFE no land", aoso_feas_continuation_of(FALSE, FALSE, 0, 800) = "SAFE", fail).

    LOCAL seq_a IS aoso_project_seq(5000, 3000, 1500, 1000, 800, FALSE, 5000).
    SET fail TO aoso_selftest_check("proj reach 5000-3000", seq_a["can_reach"] = TRUE, fail).
    SET fail TO aoso_selftest_check("proj capture 2000-1500", seq_a["can_orbit"] = TRUE, fail).
    SET fail TO aoso_selftest_check("proj land 500-1000 no", seq_a["can_land"] = FALSE, fail).
    SET fail TO aoso_selftest_check("proj takeoff skipped", seq_a["can_takeoff"] = FALSE, fail).
    SET fail TO aoso_selftest_check("xfer_only 3000-1500", aoso_project_xfer_only(3000, 1500) = 1500, fail).

    LOCAL seq_b IS aoso_project_seq(5000, 1000, 400, 800, 800, TRUE, 5000).
    SET fail TO aoso_selftest_check("proj ISRU takeoff", seq_b["can_takeoff"] = TRUE, fail).

    LOCAL id1 IS aoso_decide_open("TEST", "one", "Duna", "first", 1080).
    LOCAL id2 IS aoso_decide_open("TEST", "two", "Eve", "second", 2000).
    LOCAL act1 IS aoso_action_create(id1, "TRANSFER", "Duna", 1080).
    LOCAL act2 IS aoso_action_create(id2, "TRANSFER", "Eve", 2000).
    aoso_action_begin(act1).
    SET act1["predicted_duration"] TO 12.
    LOCAL detached_res IS aoso_result_from_action(act2, "SUCCESS", "detached").
    SET fail TO aoso_selftest_check("detached result keeps parent action", AOSO_ACTION_CUR["action_id"] = id1, fail).
    LOCAL res_act IS aoso_result_from_action(act1, "SUCCESS", "ok").
    SET fail TO aoso_selftest_check("action id not latest seq", res_act["action_id"] = id1, fail).
    SET fail TO aoso_selftest_check("action id not id2", res_act["action_id"] <> id2, fail).
    SET fail TO aoso_selftest_check("action predicted", res_act["predicted_dv"] = 1080, fail).
    SET fail TO aoso_selftest_check("action predicted duration", res_act["predicted_duration"] = 12, fail).
    aoso_action_clear().
    aoso_decide_close(id1, res_act).
    aoso_decide_close(id2, res_act).

    SET fail TO aoso_selftest_check("isru classify partial", aoso_refuel_classify(20, 55, 70) = "PARTIAL", fail).
    SET fail TO aoso_selftest_check("isru classify success", aoso_refuel_classify(20, 70, 70) = "SUCCESS", fail).
    SET fail TO aoso_selftest_check("isru classify failed", aoso_refuel_classify(20, 20, 70) = "FAILED", fail).

    LOCAL kind_hold IS aoso_watchdog_recovery_kind(TRUE, FALSE, FALSE).
    SET fail TO aoso_selftest_check("watchdog stall replan", kind_hold = "REPLAN", fail).
    LOCAL kind_abort IS aoso_watchdog_recovery_kind(TRUE, TRUE, FALSE).
    SET fail TO aoso_selftest_check("watchdog critical abort", kind_abort = "ABORT", fail).
    LOCAL kind_fly IS aoso_watchdog_recovery_kind(TRUE, FALSE, TRUE).
    SET fail TO aoso_selftest_check("watchdog ascent no generic recover", kind_fly = "NONE", fail).

    SET fail TO aoso_selftest_check("schema version 2", aoso_const_get("SCHEMA_VERSION") = 2, fail).
    LOCAL stamped IS LEXICON("n", 1).
    SET fail TO aoso_selftest_check("schema migrate v1", aoso_json_schema_of(aoso_json_migrate(stamped)) = 1, fail).

    LOCAL xp_save_at IS AOSO_XP["save_at"].
    LOCAL xp_loaded IS AOSO_XP["loaded"].
    LOCAL xp_store IS AOSO_XP["store"].
    SET AOSO_XP["store"] TO LEXICON("models", LEXICON(), "samples", LIST()).
    SET AOSO_XP["loaded"] TO TRUE.
    SET AOSO_XP["save_at"] TO TIME:SECONDS + 99999.
    LOCAL m1 IS aoso_xp_record("TRANSFER", "SelftestBody", 1000, 1100, FALSE).
    LOCAL m2 IS aoso_xp_record("TRANSFER", "SelftestBody", 1000, 1100, FALSE).
    LOCAL m3 IS aoso_xp_record("TRANSFER", "SelftestBody", 1000, 1100, FALSE).
    LOCAL tm1 IS aoso_xp_record_metric("MANEUVER", "SelftestBody", "BURN_TIME", 10, 12, FALSE).
    LOCAL tm2 IS aoso_xp_record_metric("MANEUVER", "SelftestBody", "BURN_TIME", 10, 12, FALSE).
    LOCAL tm3 IS aoso_xp_record_metric("MANEUVER", "SelftestBody", "BURN_TIME", 10, 12, FALSE).
    SET fail TO aoso_selftest_check("xp corr rises", m3["corr"] > 1, fail).
    SET fail TO aoso_selftest_check("xp time corr rises", tm3["corr"] > 1, fail).
    SET fail TO aoso_selftest_check("xp time apply changes estimate", aoso_xp_metric_apply("MANEUVER", "SelftestBody", "BURN_TIME", 10) > 10, fail).
    SET fail TO aoso_selftest_check("xp corr bounded", m3["corr"] <= 1.35, fail).
    SET AOSO_XP["store"] TO xp_store.
    SET AOSO_XP["loaded"] TO xp_loaded.
    SET AOSO_XP["save_at"] TO xp_save_at.

    LOCAL seq_tylo IS aoso_project_seq(2000, 800, 400, 2270, 2270, FALSE, 2000).
    SET fail TO aoso_selftest_check("tylo land not sequential", seq_tylo["can_land"] = FALSE, fail).

    LOCAL quiet IS aoso_brain_is_quiet().
    SET fail TO aoso_selftest_check("brain_is_quiet boolean", quiet = TRUE OR quiet = FALSE, fail).

    LOCAL cid IS aoso_cfg_id_make().
    SET fail TO aoso_selftest_check("cfg_id has mass bucket", cid:FIND("|M") >= 0, fail).
    SET fail TO aoso_selftest_check("cfg_id has engines", cid:FIND("|E") >= 0, fail).

    LOCAL max_c IS aoso_config_get("XP_MAX_CORRECTION", 0.35).
    SET fail TO aoso_selftest_check("xp max correction", max_c > 0.1, fail).
    SET fail TO aoso_selftest_check("xp model rev", aoso_config_get("XP_MODEL_REV", 0) >= 2, fail).
    SET fail TO aoso_selftest_check("route beam width", aoso_config_get("ROUTE_BEAM_WIDTH", 0) >= 1, fail).
    SET fail TO aoso_selftest_check("tick guard configured", aoso_config_get("MANEUVER_TICK_GUARD", 0) > 0, fail).
    SET fail TO aoso_selftest_check("think lead", aoso_config_get("BRAIN_THINK_LEAD_S", 0) >= 60, fail).
    SET fail TO aoso_selftest_check("ipu target 2000", aoso_config_get("IPU_TARGET", 0) = 2000, fail).
    SET fail TO aoso_selftest_check("cpu reserve abs", aoso_config_get("CPU_RESERVE_ABS", 0) >= 200, fail).
    SET fail TO aoso_selftest_check("cpu headroom positive", aoso_cpu_headroom() >= 80, fail).
    LOCAL band IS aoso_cpu_band().
    LOCAL band_ok IS FALSE.
    IF band = "GREEN" { SET band_ok TO TRUE. }
    IF band = "YELLOW" { SET band_ok TO TRUE. }
    IF band = "RED" { SET band_ok TO TRUE. }
    IF band = "CRITICAL" { SET band_ok TO TRUE. }
    SET fail TO aoso_selftest_check("cpu band named", band_ok, fail).

    LOCAL v_mn IS aoso_verify_maneuver("missed").
    SET fail TO aoso_selftest_check("verify maneuver missed", v_mn["ok"] = FALSE, fail).
    LOCAL v_okm IS aoso_verify_maneuver("complete").
    SET fail TO aoso_selftest_check("verify maneuver complete", v_okm["ok"] = TRUE, fail).
    LOCAL v_land IS aoso_verify_landing().
    IF SHIP:STATUS <> "LANDED" {
        IF SHIP:STATUS <> "SPLASHED" {
            SET fail TO aoso_selftest_check("verify landing not success in flight", v_land["ok"] = FALSE, fail).
        }
    }
    LOCAL res0 IS aoso_result_make("MANEUVER", "SUCCESS", "x").
    LOCAL v_bad IS LEXICON("ok", FALSE, "reason", "missed node", "status", "FAILED").
    LOCAL res1 IS aoso_verify_apply_result(res0, v_bad).
    SET fail TO aoso_selftest_check("verify apply failed", res1["status"] = "FAILED", fail).
    LOCAL vok IS aoso_verify_ok(FALSE, "nope").
    SET fail TO aoso_selftest_check("verify_ok false is not SUCCESS", vok["status"] <> "SUCCESS", fail).

    aoso_ctx_init().
    SET fail TO aoso_selftest_check("ctx rev_topo key", AOSO_CTX:HASKEY("rev_topo"), fail).
    SET fail TO aoso_selftest_check("ctx dirty_topo key", AOSO_CTX:HASKEY("dirty_topo"), fail).
    aoso_ctx_bump("rev_topo").
    SET fail TO aoso_selftest_check("ctx rev_topo bumps", AOSO_CTX["rev_topo"] = 1, fail).

    aoso_warp_deadline_set("selftest", TIME:SECONDS + 90).
    LOCAL nxt IS aoso_warp_next_deadline().
    SET fail TO aoso_selftest_check("warp deadline set", nxt > TIME:SECONDS, fail).
    LOCAL safe_eta IS aoso_warp_safe_eta(3600).
    SET fail TO aoso_selftest_check("warp safe eta clamps", safe_eta <= 90.5, fail).
    aoso_warp_deadline_clear("selftest").

    SET fail TO aoso_selftest_check("warp rails far uses 5+", aoso_warp_rails_want(50000, 70) >= 5, fail).
    SET fail TO aoso_selftest_check("warp rails align window is 0", aoso_warp_rails_want(20, 50) = 0, fail).
    SET fail TO aoso_selftest_check("warp rails respects max factor", aoso_warp_rails_want(400000, 50) <= aoso_config_get("MAX_WARP_FACTOR", 6), fail).
    SET fail TO aoso_selftest_check("warp rails mid not 7 at 11h", aoso_warp_rails_want(40000, 70) <= 6, fail).

    LOCAL up_look IS aoso_steer_heading_pitch_vector(90, 90).
    SET fail TO aoso_selftest_check("steer pitch 90 near up", VANG(up_look, SHIP:UP:VECTOR) < 8, fail).
    LOCAL east_look IS aoso_steer_heading_pitch_vector(90, 0).
    SET fail TO aoso_selftest_check("steer pitch 0 not up", VANG(east_look, SHIP:UP:VECTOR) > 50, fail).
    LOCAL face_dir IS aoso_steer_facing_for_vector(SHIP:UP:VECTOR).
    SET fail TO aoso_selftest_check("steer facing has vector", face_dir:VECTOR:MAG > 0.5, fail).

    aoso_auth_acquire("selftestA", "STEERING", 1).
    SET fail TO aoso_selftest_check("auth acquire steering", aoso_auth_owner("STEERING") = "selftestA", fail).
    LOCAL denied IS aoso_auth_acquire("selftestB", "STEERING", 1).
    SET fail TO aoso_selftest_check("auth deny lower prio", denied = FALSE, fail).
    LOCAL pre IS aoso_auth_acquire("selftestB", "STEERING", 5).
    SET fail TO aoso_selftest_check("auth preempt higher", pre, fail).
    aoso_auth_release("selftestB", "STEERING").
    SET fail TO aoso_selftest_check("auth released empty", aoso_auth_owner("STEERING") = "", fail).

    aoso_auth_acquire("ascent", "STEERING", 3).
    aoso_auth_acquire("ascent", "THROTTLE", 3).
    LOCAL same_prio IS aoso_auth_acquire("maneuver", "STEERING", 3).
    SET fail TO aoso_selftest_check("auth equal prio denied", same_prio = FALSE, fail).
    aoso_auth_release("ascent", "STEERING").
    aoso_auth_release("ascent", "THROTTLE").
    LOCAL handoff IS aoso_auth_acquire("maneuver", "STEERING", 3).
    SET fail TO aoso_selftest_check("circ handoff after yield", handoff, fail).
    SET fail TO aoso_selftest_check("circ handoff owner", aoso_auth_owner("STEERING") = "maneuver", fail).
    aoso_auth_release("maneuver", "STEERING").

    LOCAL fake_db IS LEXICON(
        "Mun", LEXICON("PARENT", "Kerbin", "SMA", 12000000),
        "Minmus", LEXICON("PARENT", "Kerbin", "SMA", 47000000),
        "Duna", LEXICON("PARENT", "Sun", "SMA", 20726155264),
        "broken", 42
    ).
    LOCAL sibs IS aoso_assist_parent_siblings(fake_db, "Kerbin", "Minmus", 47000000, "Kerbin").
    SET fail TO aoso_selftest_check("assist skips scalar db entries", sibs:LENGTH = 1, fail).
    IF sibs:LENGTH > 0 {
        SET fail TO aoso_selftest_check("assist picks inner moon", sibs[0] = "Mun", fail).
    }
    LOCAL empty_sibs IS aoso_assist_parent_siblings(42, "Kerbin", "Minmus", 47000000, "Kerbin").
    SET fail TO aoso_selftest_check("assist scalar db is empty", empty_sibs:LENGTH = 0, fail).

    LOCAL stab IS aoso_surface_stable().
    SET fail TO aoso_selftest_check("surface_stable boolean", stab = TRUE OR stab = FALSE, fail).

    IF DEFINED AOSO_TOPO {
        LOCAL fp_now IS aoso_topo_fp().
        SET fail TO aoso_selftest_check("topo fp string", fp_now:ISTYPE("String"), fail).
        IF AOSO_TOPO:HASKEY("rev") {
            LOCAL rev0 IS AOSO_TOPO["rev"].
            LOCAL dyn0 IS AOSO_TOPO["dyn_rev"].
            aoso_topo_refresh_dynamic().
            SET fail TO aoso_selftest_check("topo dyn fuel no struct rebuild", AOSO_TOPO["rev"] = rev0, fail).
            SET fail TO aoso_selftest_check("topo dyn_rev increments", AOSO_TOPO["dyn_rev"] > dyn0, fail).
        }
    }
    IF DEFINED AOSO_CERT_LAST {
        LOCAL cert IS aoso_cert_eval("grand_tour").
        SET fail TO aoso_selftest_check("cert has status", cert:HASKEY("status"), fail).
    }

    IF fail = 0 {
        PRINT "AOSO selftest: ALL PASS.".
        RETURN TRUE.
    }
    PRINT "AOSO selftest: " + fail + " FAIL.".
    RETURN FALSE.
}

aoso_selftest().
