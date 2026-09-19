// AOSO/core/scheduler.ks
// Cooperative, multi-rate task scheduler. Tasks are plain kOS user functions
// (delegates) registered with a name + interval (seconds). aoso_sched_run()
// is called once per main-loop tick and dispatches every task whose
// interval has elapsed, passing no arguments. Long-running work must be
// implemented as non-blocking (return quickly); use the state machine
// (core/state.ks) for multi-tick sequences.
//
// next_run (init 0) makes the first dispatch immediate. Nested IF so a
// disabled task never pays the time compare (kOS AND always evaluates both
// sides). The hot loop inlines CALL.
// CPU HIGH/CRITICAL sheds profile/checkpoints/telemetry first; HUD,
// staging, watchdog, mission, and power always run.

GLOBAL AOSO_TASKS IS LIST().

FUNCTION aoso_sched_add {
    PARAMETER task_name.
    PARAMETER interval_s.
    PARAMETER task_delegate.
    PARAMETER enabled IS TRUE.

    // Replace if already registered.
    aoso_sched_remove(task_name).
    AOSO_TASKS:ADD(LEXICON(
        "name", task_name,
        "interval", interval_s,
        "next_run", 0,
        "fn", task_delegate,
        "enabled", enabled,
        "run_count", 0,
        "last_error", "",
        "last_dt", 0,
        "sum_dt", 0,
        "max_dt", 0
    )).
}

FUNCTION aoso_sched_remove {
    PARAMETER task_name.
    LOCAL idx IS -1.
    FOR i IN RANGE(0, AOSO_TASKS:LENGTH) {
        IF AOSO_TASKS[i]["name"] = task_name { SET idx TO i. }
    }
    IF idx >= 0 { AOSO_TASKS:REMOVE(idx). }
}

FUNCTION aoso_sched_keep {
    PARAMETER name.
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl <= 1 { RETURN TRUE. }

    // Never shed flight / staging / landing / watchdog / hop / suicide.
    IF name = "auto_staging" { RETURN TRUE. }
    IF name = "watchdog" { RETURN TRUE. }
    IF name = "mission" { RETURN TRUE. }
    IF name = "auto_power" { RETURN TRUE. }
    IF name = "goto" { RETURN TRUE. }
    IF name = "descent" { RETURN TRUE. }

    IF name = "telemetry" {
        IF DEFINED AOSO_POST_LEFT {
            IF AOSO_POST_LEFT > 0 { RETURN TRUE. }
        }
        IF lvl >= 3 { RETURN FALSE. }
        RETURN TRUE.
    }
    IF name = "hud" { RETURN TRUE. }
    IF name = "vehicle_profile" { RETURN FALSE. }
    IF name = "checkpoint_autosave" { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_sched_run {
    LOCAL now IS TIME:SECONDS.
    // COPY: tasks may aoso_sched_add/remove during CALL (GOTO PLAN, descent).
    // kOS throws "Collection was modified" if we enumerate AOSO_TASKS live.
    LOCAL snap IS AOSO_TASKS:COPY.
    FOR t IN snap {
        IF t["enabled"] {
            IF now >= t["next_run"] {
                IF aoso_sched_keep(t["name"]) {
                    SET t["next_run"] TO now + t["interval"].
                    SET t["run_count"] TO t["run_count"] + 1.
                    LOCAL t0 IS KUNIVERSE:REALTIME.
                    t["fn"]:CALL().
                    LOCAL dt IS KUNIVERSE:REALTIME - t0.
                    SET t["last_dt"] TO dt.
                    SET t["sum_dt"] TO t["sum_dt"] + dt.
                    IF dt > t["max_dt"] { SET t["max_dt"] TO dt. }
                } ELSE {
                    SET t["next_run"] TO now + t["interval"].
                }
            }
        }
    }
}
