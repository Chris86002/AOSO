// AOSO/core/state.ks
// Generic finite-state machine used by every autonomous subsystem (mission
// manager, ascent, descent, refuel, etc). Each state may define:
//   entry(data)    - called once on transition into the state
//   execute(data)  - called every scheduler tick while in the state
//   exit(data)     - called once on transition out of the state
//   timeout_s      - seconds allowed in the state before on_timeout fires
//   on_timeout(data) - called if timeout elapses; return TRUE to allow retry
//   on_abort(data)   - called if aoso_state_abort() is invoked while active
// States are looked up by name in AOSO_STATES. Only one state machine is
// "current" at a time per module instance; callers that need independent
// machines (e.g. ascent vs descent) should keep their own AOSO_STATES-style
// lexicon variables using aoso_state_new_machine().
//
// Nested aoso_state_transition from inside entry/execute does NOT run the
// new state's entry on the same call stack. kOS's argument stack is 3000
// slots; PLAN -> CAPTURE -> PLAN (Acacius LKO, capture node failed) blew
// it with "Tried to push more than the max stack size" at goto.ks:715.

FUNCTION aoso_state_new_machine {
    RETURN LEXICON(
        "states", LEXICON(),
        "current", "",
        "previous", "",
        "entered_at", 0,
        "data", LEXICON(),
        "history", LIST(),
        "aborted", FALSE,
        "busy", FALSE,
        "nest", 0,
        "need_entry", FALSE
    ).
}

FUNCTION aoso_state_ensure_keys {
    PARAMETER machine.
    IF NOT machine:HASKEY("busy") { SET machine["busy"] TO FALSE. }
    IF NOT machine:HASKEY("nest") { SET machine["nest"] TO 0. }
    IF NOT machine:HASKEY("need_entry") { SET machine["need_entry"] TO FALSE. }
}

FUNCTION aoso_state_define {
    PARAMETER machine.
    PARAMETER name.
    PARAMETER entry_fn.
    PARAMETER execute_fn.
    PARAMETER exit_fn.
    PARAMETER timeout_s IS 0.
    PARAMETER on_timeout_fn IS 0.
    PARAMETER on_abort_fn IS 0.

    SET machine["states"][name] TO LEXICON(
        "entry", entry_fn,
        "execute", execute_fn,
        "exit", exit_fn,
        "timeout", timeout_s,
        "on_timeout", on_timeout_fn,
        "on_abort", on_abort_fn
    ).
}

FUNCTION aoso_state_run_entry {
    PARAMETER machine.
    PARAMETER st.
    IF st["entry"]:ISTYPE("Delegate") { st["entry"]:CALL(machine["data"]). }
}

FUNCTION aoso_state_transition {
    PARAMETER machine.
    PARAMETER new_state.
    aoso_state_ensure_keys(machine).

    IF machine["current"] <> "" {
        IF machine["states"]:HASKEY(machine["current"]) {
            LOCAL cur IS machine["states"][machine["current"]].
            IF cur["exit"]:ISTYPE("Delegate") { cur["exit"]:CALL(machine["data"]). }
        }
    }

    IF NOT machine["states"]:HASKEY(new_state) {
        aoso_log_error("STATE", "Unknown state requested: " + new_state).
        RETURN FALSE.
    }

    SET machine["previous"] TO machine["current"].
    SET machine["current"] TO new_state.
    SET machine["entered_at"] TO TIME:SECONDS.
    SET machine["aborted"] TO FALSE.
    machine["history"]:ADD(LEXICON("state", new_state, "t", TIME:SECONDS)).
    IF machine["history"]:LENGTH > 50 { machine["history"]:REMOVE(0). }

    aoso_log_info("STATE", "-> " + new_state).
    aoso_observe_event("STATE", "INFO", new_state, machine["previous"] + "->" + new_state).
    aoso_observe_on_state(new_state).

    // Already inside entry/execute for this machine: do not recurse into
    // the new entry. The next aoso_state_update tick runs it.
    IF machine["nest"] > 0 {
        SET machine["need_entry"] TO TRUE.
        RETURN TRUE.
    }

    SET machine["nest"] TO machine["nest"] + 1.
    LOCAL st IS machine["states"][new_state].
    aoso_state_run_entry(machine, st).
    SET machine["nest"] TO machine["nest"] - 1.
    RETURN TRUE.
}

// Call once per scheduler tick for each active machine.
FUNCTION aoso_state_update {
    PARAMETER machine.
    IF machine["current"] = "" { RETURN. }
    IF NOT machine["states"]:HASKEY(machine["current"]) { RETURN. }
    aoso_state_ensure_keys(machine).
    IF machine["busy"] { RETURN. }
    SET machine["busy"] TO TRUE.
    SET machine["nest"] TO machine["nest"] + 1.

    LOCAL st IS machine["states"][machine["current"]].
    LOCAL before IS machine["current"].

    IF machine["need_entry"] {
        SET machine["need_entry"] TO FALSE.
        aoso_state_run_entry(machine, st).
        IF machine["current"] <> before {
            SET machine["nest"] TO 0.
            SET machine["busy"] TO FALSE.
            RETURN.
        }
        SET st TO machine["states"][machine["current"]].
    }

    IF st["timeout"] > 0 {
        IF (TIME:SECONDS - machine["entered_at"]) > st["timeout"] {
            aoso_log_warn("STATE", "Timeout in " + machine["current"]).
            IF st["on_timeout"]:ISTYPE("Delegate") {
                LOCAL retry IS st["on_timeout"]:CALL(machine["data"]).
                IF retry = TRUE {
                    SET machine["entered_at"] TO TIME:SECONDS.
                    SET machine["nest"] TO 0.
                    SET machine["busy"] TO FALSE.
                    RETURN.
                }
            }
            SET machine["nest"] TO 0.
            SET machine["busy"] TO FALSE.
            RETURN.
        }
    }

    IF st["execute"]:ISTYPE("Delegate") { st["execute"]:CALL(machine["data"]). }
    SET machine["nest"] TO 0.
    SET machine["busy"] TO FALSE.
}

FUNCTION aoso_state_abort {
    PARAMETER machine.
    IF machine["current"] = "" { RETURN. }
    aoso_state_ensure_keys(machine).
    SET machine["aborted"] TO TRUE.
    IF machine["states"]:HASKEY(machine["current"]) {
        LOCAL st IS machine["states"][machine["current"]].
        IF st["on_abort"]:ISTYPE("Delegate") { st["on_abort"]:CALL(machine["data"]). }
    }
    aoso_log_warn("STATE", "Abort requested in " + machine["current"]).
    aoso_observe_event("ABORT", "WARN", machine["current"], "abort").
}
