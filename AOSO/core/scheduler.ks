// AOSO/core/scheduler.ks
// Cooperative, multi-rate task scheduler. Tasks are plain kOS user functions
// (delegates) registered with a name + interval (seconds). aoso_sched_run()
// is called once per main-loop tick and dispatches every task whose
// interval has elapsed, passing no arguments. Long-running work must be
// implemented as non-blocking (return quickly); use the state machine
// (core/state.ks) for multi-tick sequences.
//
// Opcode budget: kOS gives CONFIG:IPU instructions per physics update.
// Running staging + mission + HUD in the same slice spills into the next
// frame and the CPU classifier sticks on CRITICAL. Flight tasks (prio 0)
// always run; HUD/power (prio 1) need leftover headroom; telemetry and
// profile yield first. Skipped work stays due so it runs next physics tick.
//
// Snapshot COPY only when the task list mutates (GOTO PLAN, descent).

GLOBAL AOSO_TASKS IS LIST().
GLOBAL AOSO_TASKS_SNAP IS LIST().
GLOBAL AOSO_TASKS_DIRTY IS TRUE.

FUNCTION aoso_sched_prio_of {
    PARAMETER name.
    IF name = "auto_staging" { RETURN 0. }
    IF name = "watchdog" { RETURN 0. }
    IF name = "mission" { RETURN 0. }
    IF name = "goto" { RETURN 0. }
    IF name = "descent" { RETURN 0. }
    IF name = "hud" { RETURN 1. }
    IF name = "auto_power" { RETURN 1. }
    IF name = "telemetry" { RETURN 2. }
    IF name = "vehicle_profile" { RETURN 3. }
    IF name = "checkpoint_autosave" { RETURN 3. }
    RETURN 1.
}

FUNCTION aoso_sched_floor_of {
    PARAMETER name.
    IF name = "auto_staging" { RETURN 40. }
    IF name = "watchdog" { RETURN 40. }
    IF name = "mission" { RETURN 80. }
    IF name = "goto" { RETURN 80. }
    IF name = "descent" { RETURN 80. }
    IF name = "hud" { RETURN 220. }
    IF name = "auto_power" { RETURN 80. }
    IF name = "telemetry" { RETURN 160. }
    IF name = "vehicle_profile" { RETURN 280. }
    IF name = "checkpoint_autosave" { RETURN 200. }
    RETURN 120.
}

FUNCTION aoso_sched_rebuild_snap {
    LOCAL b0 IS LIST().
    LOCAL b1 IS LIST().
    LOCAL b2 IS LIST().
    LOCAL b3 IS LIST().
    FOR t IN AOSO_TASKS {
        LOCAL p IS t["prio"].
        IF p <= 0 { b0:ADD(t). }
        ELSE {
            IF p = 1 { b1:ADD(t). }
            ELSE {
                IF p = 2 { b2:ADD(t). }
                ELSE { b3:ADD(t). }
            }
        }
    }
    LOCAL snap IS LIST().
    FOR t IN b0 { snap:ADD(t). }
    FOR t IN b1 { snap:ADD(t). }
    FOR t IN b2 { snap:ADD(t). }
    FOR t IN b3 { snap:ADD(t). }
    SET AOSO_TASKS_SNAP TO snap.
    SET AOSO_TASKS_DIRTY TO FALSE.
}

FUNCTION aoso_sched_add {
    PARAMETER task_name.
    PARAMETER interval_s.
    PARAMETER task_delegate.
    PARAMETER enabled IS TRUE.

    aoso_sched_remove(task_name).
    AOSO_TASKS:ADD(LEXICON(
        "name", task_name,
        "interval", interval_s,
        "next_run", 0,
        "fn", task_delegate,
        "enabled", enabled,
        "prio", aoso_sched_prio_of(task_name),
        "floor", aoso_sched_floor_of(task_name),
        "skip_n", 0,
        "run_count", 0,
        "last_error", "",
        "last_dt", 0,
        "sum_dt", 0,
        "max_dt", 0
    )).
    SET AOSO_TASKS_DIRTY TO TRUE.
}

FUNCTION aoso_sched_remove {
    PARAMETER task_name.
    LOCAL idx IS -1.
    FOR i IN RANGE(0, AOSO_TASKS:LENGTH) {
        IF AOSO_TASKS[i]["name"] = task_name { SET idx TO i. }
    }
    IF idx >= 0 {
        AOSO_TASKS:REMOVE(idx).
        SET AOSO_TASKS_DIRTY TO TRUE.
    }
}

FUNCTION aoso_sched_keep {
    PARAMETER name.
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl <= 1 { RETURN TRUE. }

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
    IF AOSO_TASKS_DIRTY { aoso_sched_rebuild_snap(). }
    LOCAL snap IS AOSO_TASKS_SNAP.
    FOR t IN snap {
        IF t["enabled"] {
            IF now >= t["next_run"] {
                LOCAL keep_it IS aoso_sched_keep(t["name"]).
                LOCAL run_it IS keep_it.
                IF run_it {
                    LOCAL left IS OPCODESLEFT.
                    LOCAL floor_n IS t["floor"].
                    IF left < floor_n {
                        SET t["skip_n"] TO t["skip_n"] + 1.
                        IF t["prio"] > 0 {
                            IF t["skip_n"] < 6 { SET run_it TO FALSE. }
                        }
                    }
                }
                IF run_it {
                    SET t["skip_n"] TO 0.
                    SET t["next_run"] TO now + t["interval"].
                    SET t["run_count"] TO t["run_count"] + 1.
                    LOCAL t0 IS KUNIVERSE:REALTIME.
                    t["fn"]:CALL().
                    LOCAL dt IS KUNIVERSE:REALTIME - t0.
                    SET t["last_dt"] TO dt.
                    SET t["sum_dt"] TO t["sum_dt"] + dt.
                    IF dt > t["max_dt"] { SET t["max_dt"] TO dt. }
                } ELSE {
                    IF NOT keep_it {
                        SET t["next_run"] TO now + t["interval"].
                    }
                }
            }
        }
    }
}
