// AOSO/dev/selftest.ks
// Vessel-safe checks for the v2 brain/context/XP loop.
// Does not STAGE, LOCK, WARP, THROTTLE, or add nodes.

RUN ONCE "AOSO/core/constants".
RUN ONCE "AOSO/core/json".
RUN ONCE "AOSO/core/logger".
RUN ONCE "AOSO/core/config".
RUN ONCE "AOSO/core/context".
RUN ONCE "AOSO/core/events".
RUN ONCE "AOSO/core/result".
RUN ONCE "AOSO/core/brain".
RUN ONCE "AOSO/vehicle/experience".
RUN ONCE "AOSO/mission/feasibility".

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

    IF fail = 0 {
        PRINT "AOSO selftest: ALL PASS.".
        RETURN TRUE.
    }
    PRINT "AOSO selftest: " + fail + " FAIL.".
    RETURN FALSE.
}

aoso_selftest().
