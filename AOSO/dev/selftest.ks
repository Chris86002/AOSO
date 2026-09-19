// AOSO/dev/selftest.ks
// Vessel-safe checks for the v2 brain/context/XP loop.
// Does not STAGE, LOCK, WARP, THROTTLE, or add nodes.

RUN ONCE "AOSO/core/constants".
RUN ONCE "AOSO/core/json".
RUN ONCE "AOSO/core/logger".
RUN ONCE "AOSO/core/config".
RUN ONCE "AOSO/core/observe".
RUN ONCE "AOSO/core/context".
RUN ONCE "AOSO/core/events".
RUN ONCE "AOSO/core/result".
RUN ONCE "AOSO/core/authority".
RUN ONCE "AOSO/core/verify".
RUN ONCE "AOSO/core/warp".
RUN ONCE "AOSO/core/brain".
RUN ONCE "AOSO/vehicle/experience".
RUN ONCE "AOSO/mission/feasibility".
RUN ONCE "AOSO/surface/operations".

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

    LOCAL blank IS aoso_xp_blank().
    SET fail TO aoso_selftest_check("xp blank corr 1", blank["corr"] = 1, fail).
    LOCAL applied IS aoso_xp_apply("TRANSFER", "Minmus", 860).
    SET fail TO aoso_selftest_check("xp apply identity", ABS(applied - 860) < 0.01, fail).

    SET fail TO aoso_selftest_check("cont SAFE landable", aoso_feas_continuation_of(TRUE, TRUE, 2000, 800) = "SAFE", fail).
    SET fail TO aoso_selftest_check("cont DEAD_END no takeoff", aoso_feas_continuation_of(TRUE, FALSE, 2000, 800) = "DEAD_END", fail).
    SET fail TO aoso_selftest_check("cont DEAD_END leftover", aoso_feas_continuation_of(TRUE, TRUE, 20, 800) = "DEAD_END", fail).
    SET fail TO aoso_selftest_check("cont LOW", aoso_feas_continuation_of(TRUE, TRUE, 400, 1200) = "LOW", fail).
    SET fail TO aoso_selftest_check("cont SAFE no land", aoso_feas_continuation_of(FALSE, FALSE, 0, 800) = "SAFE", fail).

    LOCAL quiet IS aoso_brain_is_quiet().
    SET fail TO aoso_selftest_check("brain_is_quiet boolean", quiet = TRUE OR quiet = FALSE, fail).

    LOCAL cid IS aoso_cfg_id_make().
    SET fail TO aoso_selftest_check("cfg_id has mass bucket", cid:FIND("|M") >= 0, fail).
    SET fail TO aoso_selftest_check("cfg_id has engines", cid:FIND("|E") >= 0, fail).

    LOCAL max_c IS aoso_config_get("XP_MAX_CORRECTION", 0.35).
    SET fail TO aoso_selftest_check("xp max correction", max_c > 0.1, fail).
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

    aoso_auth_acquire("selftestA", "STEERING", 1).
    SET fail TO aoso_selftest_check("auth acquire steering", aoso_auth_owner("STEERING") = "selftestA", fail).
    LOCAL denied IS aoso_auth_acquire("selftestB", "STEERING", 1).
    SET fail TO aoso_selftest_check("auth deny lower prio", denied = FALSE, fail).
    LOCAL pre IS aoso_auth_acquire("selftestB", "STEERING", 5).
    SET fail TO aoso_selftest_check("auth preempt higher", pre, fail).
    aoso_auth_release("selftestB", "STEERING").
    SET fail TO aoso_selftest_check("auth released empty", aoso_auth_owner("STEERING") = "", fail).

    LOCAL stab IS aoso_surface_stable().
    SET fail TO aoso_selftest_check("surface_stable boolean", stab = TRUE OR stab = FALSE, fail).

    IF DEFINED AOSO_TOPO {
        LOCAL fp_now IS aoso_topo_fp().
        SET fail TO aoso_selftest_check("topo fp string", fp_now:ISTYPE("String"), fail).
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
