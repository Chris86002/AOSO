// AOSO/core/scheduler.ks
// Cooperative, multi-rate task scheduler. Tasks are plain kOS user functions
// (delegates) registered with a name + interval (seconds). aoso_sched_run()
// is called once per main-loop tick and dispatches due work.
//
// Opcode budget: kOS gives CONFIG:IPU instructions per physics update.
// If this function keeps calling tasks after TIME:SECONDS steps, leftover
// resets to a full IPU and the next task spills again -- that is why the
// HUD sat on CRITICAL with 2000+ spills. Stop the slice when the physics
// clock moves or leftover is too low; due work runs on the next WAIT 0.
// Flight tasks (goto/descent/staging/mission) go first. HUD/power need
// leftover headroom. The main loop also paints HUD after the scheduler
// so a slow glass cockpit cannot skip a burn. Telemetry and profile yield
// first.
//
// Snapshot rebuilt only when the task list mutates (GOTO PLAN, descent).

GLOBAL AOSO_TASKS IS LIST().
GLOBAL AOSO_TASKS_SNAP IS LIST().
GLOBAL AOSO_TASKS_DIRTY IS TRUE.

FUNCTION aoso_sched_prio_of {
    PARAMETER name.
    IF name = "goto" { RETURN 0. }
    IF name = "descent" { RETURN 0. }
    IF name = "auto_staging" { RETURN 0. }
    IF name = "mission" { RETURN 0. }
    IF name = "launch_hold" { RETURN 0. }
    IF name = "watchdog" { RETURN 0. }
    IF name = "hud" { RETURN 2. }
    IF name = "auto_power" { RETURN 1. }
    IF name = "brain" { RETURN 2. }
    IF name = "telemetry" { RETURN 2. }
    IF name = "vehicle_profile" { RETURN 3. }
    IF name = "checkpoint_autosave" { RETURN 3. }
    RETURN 1.
}

FUNCTION aoso_sched_floor_of {
    PARAMETER name.
    IF name = "goto" { RETURN 40. }
    IF name = "descent" { RETURN 40. }
    IF name = "auto_staging" { RETURN 40. }
    IF name = "watchdog" { RETURN 40. }
    IF name = "mission" { RETURN 80. }
    IF name = "launch_hold" { RETURN 80. }
    IF name = "hud" { RETURN 80. }
    IF name = "brain" { RETURN 200. }
    IF name = "auto_power" {
        IF DEFINED AOSO_POWER_SPACE_DONE {
            IF NOT AOSO_POWER_SPACE_DONE { RETURN 40. }
        }
        RETURN 80.
    }
    IF name = "telemetry" { RETURN 160. }
    IF name = "vehicle_profile" { RETURN 280. }
    IF name = "checkpoint_autosave" { RETURN 200. }
    RETURN 120.
}

FUNCTION aoso_sched_phase_of {
    PARAMETER name.
    IF name = "auto_staging" { RETURN 0. }
    IF name = "mission" { RETURN 0.04. }
    IF name = "launch_hold" { RETURN 0.16. }
    IF name = "hud" { RETURN 0.07. }
    IF name = "brain" { RETURN 0.22. }
    IF name = "telemetry" { RETURN 0.12. }
    IF name = "auto_power" { RETURN 0.35. }
    IF name = "watchdog" { RETURN 0.55. }
    IF name = "vehicle_profile" { RETURN 0.8. }
    IF name = "checkpoint_autosave" { RETURN 1.1. }
    RETURN 0.
}

FUNCTION aoso_sched_rebuild_snap {
    LOCAL prefer IS LIST(
        "goto",
        "descent",
        "auto_staging",
        "mission",
        "watchdog",
        "hud",
        "launch_hold",
        "auto_power",
        "brain",
        "telemetry",
        "vehicle_profile",
        "checkpoint_autosave"
    ).
    LOCAL snap IS LIST().
    LOCAL seen IS LEXICON().
    FOR nm IN prefer {
        FOR t IN AOSO_TASKS {
            IF t["name"] = nm {
                snap:ADD(t).
                SET seen[nm] TO TRUE.
            }
        }
    }
    FOR t IN AOSO_TASKS {
        IF NOT seen:HASKEY(t["name"]) { snap:ADD(t). }
    }
    SET AOSO_TASKS_SNAP TO snap.
    SET AOSO_TASKS_DIRTY TO FALSE.
}

FUNCTION aoso_sched_add {
    PARAMETER task_name.
    PARAMETER interval_s.
    PARAMETER task_delegate.
    PARAMETER enabled IS TRUE.

    aoso_sched_remove(task_name).
    LOCAL phase IS 0.
    IF interval_s > 0 { SET phase TO aoso_sched_phase_of(task_name). }
    AOSO_TASKS:ADD(LEXICON(
        "name", task_name,
        "interval", interval_s,
        "next_run", TIME:SECONDS + phase,
        "fn", task_delegate,
        "enabled", enabled,
        "prio", aoso_sched_prio_of(task_name),
        "floor", aoso_sched_floor_of(task_name),
        "skip_n", 0,
        "run_count", 0,
        "last_error", "",
        "last_dt", 0,
        "sum_dt", 0,
        "max_dt", 0,
        "last_op", 0,
        "sum_op", 0,
        "max_op", 0,
        "deferred_n", 0,
        "shed_n", 0
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
    IF name = "auto_staging" { RETURN TRUE. }
    IF name = "watchdog" { RETURN TRUE. }
    IF name = "mission" { RETURN TRUE. }
    IF name = "launch_hold" { RETURN TRUE. }
    IF name = "goto" { RETURN TRUE. }
    IF name = "descent" { RETURN TRUE. }
    IF name = "auto_power" {
        IF DEFINED AOSO_POWER_SPACE_DONE {
            IF NOT AOSO_POWER_SPACE_DONE { RETURN TRUE. }
        }
        RETURN aoso_cpu_allow(1).
    }
    // Heavy HUD refresh yields when the frame is already critical. The
    // cheap instrument path in main still runs on leftover opcodes.
    IF name = "hud" { RETURN aoso_cpu_allow(2). }
    IF name = "brain" { RETURN aoso_cpu_allow(2). }
    IF name = "telemetry" {
        IF DEFINED AOSO_POST_LEFT {
            IF AOSO_POST_LEFT > 0 { RETURN TRUE. }
        }
        RETURN aoso_cpu_allow(2).
    }
    IF name = "vehicle_profile" { RETURN aoso_cpu_allow(3). }
    IF name = "checkpoint_autosave" { RETURN aoso_cpu_allow(3). }
    RETURN aoso_cpu_allow(1).
}

FUNCTION aoso_sched_run {
    LOCAL start_ut IS TIME:SECONDS.
    IF AOSO_TASKS_DIRTY { aoso_sched_rebuild_snap(). }
    LOCAL snap IS AOSO_TASKS_SNAP.
    LOCAL room IS aoso_cpu_headroom().
    LOCAL ran IS 0.
    LOCAL prof IS FALSE.
    IF DEFINED AOSO_CONFIG {
        IF AOSO_CONFIG:HASKEY("PROF_ENABLED") {
            IF AOSO_CONFIG["PROF_ENABLED"] { SET prof TO TRUE. }
        }
        IF AOSO_CONFIG:HASKEY("CPU_PROFILE") {
            IF AOSO_CONFIG["CPU_PROFILE"] { SET prof TO TRUE. }
        }
    }
    FOR t IN snap {
        IF TIME:SECONDS <> start_ut { RETURN. }
        LOCAL left0 IS OPCODESLEFT.
        IF ran > 0 {
            IF left0 < room { RETURN. }
        } ELSE {
            IF left0 < 50 { RETURN. }
        }
        IF t["enabled"] {
            LOCAL now IS TIME:SECONDS.
            IF now >= t["next_run"] {
                LOCAL keep_it IS aoso_sched_keep(t["name"]).
                LOCAL run_it IS keep_it.
                IF run_it {
                    LOCAL floor_n IS t["floor"].
                    IF t["prio"] > 0 {
                        IF left0 < room { SET floor_n TO left0 + 1. }
                    }
                    IF left0 < floor_n {
                        SET t["skip_n"] TO t["skip_n"] + 1.
                        IF t:HASKEY("deferred_n") { SET t["deferred_n"] TO t["deferred_n"] + 1. }
                        IF t["prio"] > 0 {
                            SET run_it TO FALSE.
                            IF t["skip_n"] >= 10 {
                                IF left0 >= 80 { SET run_it TO TRUE. }
                            }
                        }
                    }
                }
                IF run_it {
                    SET t["skip_n"] TO 0.
                    LOCAL iv IS t["interval"].
                    IF iv <= 0 {
                        SET t["next_run"] TO now.
                    } ELSE {
                        SET t["next_run"] TO now + iv.
                    }
                    SET t["run_count"] TO t["run_count"] + 1.
                    SET ran TO ran + 1.
                    LOCAL op0 IS OPCODESLEFT.
                    IF prof {
                        LOCAL t0 IS KUNIVERSE:REALTIME.
                        t["fn"]:CALL().
                        LOCAL dt IS KUNIVERSE:REALTIME - t0.
                        SET t["last_dt"] TO dt.
                        SET t["sum_dt"] TO t["sum_dt"] + dt.
                        IF dt > t["max_dt"] { SET t["max_dt"] TO dt. }
                    } ELSE {
                        t["fn"]:CALL().
                    }
                    LOCAL used_op IS op0 - OPCODESLEFT.
                    IF used_op < 0 { SET used_op TO op0. }
                    SET t["last_op"] TO used_op.
                    IF t:HASKEY("sum_op") {
                        SET t["sum_op"] TO t["sum_op"] + used_op.
                        IF used_op > t["max_op"] { SET t["max_op"] TO used_op. }
                    }
                    IF TIME:SECONDS <> start_ut { RETURN. }
                    IF OPCODESLEFT < room { RETURN. }
                } ELSE {
                    IF NOT keep_it {
                        SET t["next_run"] TO now + t["interval"].
                        IF t:HASKEY("shed_n") { SET t["shed_n"] TO t["shed_n"] + 1. }
                    }
                }
            }
        }
    }
}

FUNCTION aoso_sched_stat_sum {
    PARAMETER key_name.
    LOCAL n IS 0.
    FOR t IN AOSO_TASKS {
        IF t:HASKEY(key_name) { SET n TO n + t[key_name]. }
    }
    RETURN n.
}