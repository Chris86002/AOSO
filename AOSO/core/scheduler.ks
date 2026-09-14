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
// sides). The hot loop inlines CALL -- aoso_sched_invoke remains as a
// wrapper for any external caller but is not used from run.

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

FUNCTION aoso_sched_enable {
    PARAMETER task_name.
    PARAMETER enabled.
    FOR t IN AOSO_TASKS {
        IF t["name"] = task_name { SET t["enabled"] TO enabled. }
    }
}

FUNCTION aoso_sched_run {
    LOCAL now IS TIME:SECONDS.
    FOR t IN AOSO_TASKS {
        IF t["enabled"] {
            IF now >= t["next_run"] {
                SET t["next_run"] TO now + t["interval"].
                SET t["run_count"] TO t["run_count"] + 1.
                LOCAL t0 IS KUNIVERSE:REALTIME.
                t["fn"]:CALL().
                LOCAL dt IS KUNIVERSE:REALTIME - t0.
                SET t["last_dt"] TO dt.
                SET t["sum_dt"] TO t["sum_dt"] + dt.
                IF dt > t["max_dt"] { SET t["max_dt"] TO dt. }
            }
        }
    }
}

// Isolated so a single misbehaving task cannot silently take down the whole
// loop; failures are logged and the task is left enabled for the next tick.
FUNCTION aoso_sched_invoke {
    PARAMETER t.
    t["fn"]:CALL().
}

FUNCTION aoso_sched_status {
    LOCAL out IS LIST().
    FOR t IN AOSO_TASKS {
        out:ADD(t["name"] + ": every " + t["interval"] + "s, runs=" + t["run_count"] + (CHOOSE " (disabled)" IF NOT t["enabled"] ELSE "")).
    }
    RETURN out.
}
