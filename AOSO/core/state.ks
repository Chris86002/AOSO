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

FUNCTION aoso_state_new_machine {
    RETURN LEXICON(
        "states", LEXICON(),
        "current", "",
        "previous", "",
        "entered_at", 0,
        "data", LEXICON(),
        "history", LIST(),
        "aborted", FALSE
    ).
}

GLOBAL AOSO_STATE IS aoso_state_new_machine().

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

FUNCTION aoso_state_transition {
    PARAMETER machine.
    PARAMETER new_state.

    IF machine["current"] <> "" AND machine["states"]:HASKEY(machine["current"]) {
        LOCAL cur IS machine["states"][machine["current"]].
        IF cur["exit"]:ISTYPE("KOSDelegate") { cur["exit"]:CALL(machine["data"]). }
    }

    IF NOT machine["states"]:HASKEY(new_state) {
        IF DEFINED aoso_log_error { aoso_log_error("STATE", "Unknown state requested: " + new_state). }
        RETURN FALSE.
    }

    SET machine["previous"] TO machine["current"].
    SET machine["current"] TO new_state.
    SET machine["entered_at"] TO TIME:SECONDS.
    SET machine["aborted"] TO FALSE.
    machine["history"]:ADD(LEXICON("state", new_state, "t", TIME:SECONDS)).
    IF machine["history"]:LENGTH > 50 { machine["history"]:REMOVE(0). }

    LOCAL st IS machine["states"][new_state].
    IF st["entry"]:ISTYPE("KOSDelegate") { st["entry"]:CALL(machine["data"]). }
    IF DEFINED aoso_log_info { aoso_log_info("STATE", "-> " + new_state). }
    RETURN TRUE.
}

// Call once per scheduler tick for each active machine.
FUNCTION aoso_state_update {
    PARAMETER machine.
    IF machine["current"] = "" { RETURN. }
    IF NOT machine["states"]:HASKEY(machine["current"]) { RETURN. }
    LOCAL st IS machine["states"][machine["current"]].

    IF st["timeout"] > 0 AND (TIME:SECONDS - machine["entered_at"]) > st["timeout"] {
        IF DEFINED aoso_log_warn { aoso_log_warn("STATE", "Timeout in " + machine["current"]). }
        IF st["on_timeout"]:ISTYPE("KOSDelegate") {
            LOCAL retry IS st["on_timeout"]:CALL(machine["data"]).
            IF retry = TRUE {
                SET machine["entered_at"] TO TIME:SECONDS. // grant another window
                RETURN.
            }
        }
        RETURN. // caller's on_timeout is responsible for transitioning away
    }

    IF st["execute"]:ISTYPE("KOSDelegate") { st["execute"]:CALL(machine["data"]). }
}

FUNCTION aoso_state_abort {
    PARAMETER machine.
    IF machine["current"] = "" { RETURN. }
    SET machine["aborted"] TO TRUE.
    IF machine["states"]:HASKEY(machine["current"]) {
        LOCAL st IS machine["states"][machine["current"]].
        IF st["on_abort"]:ISTYPE("KOSDelegate") { st["on_abort"]:CALL(machine["data"]). }
    }
    IF DEFINED aoso_log_warn { aoso_log_warn("STATE", "Abort requested in " + machine["current"]). }
}

// --- Persistence: survive a reload/scene-change/resume ------------------

FUNCTION aoso_state_save {
    PARAMETER machine.
    PARAMETER path IS "".
    IF path = "" { SET path TO AOSO_CONST["STATE_FILE"]. }
    LOCAL snapshot IS LEXICON(
        "current", machine["current"],
        "previous", machine["previous"],
        "data", machine["data"]
    ).
    aoso_json_write(path, snapshot).
}

FUNCTION aoso_state_load {
    PARAMETER machine.
    PARAMETER path IS "".
    IF path = "" { SET path TO AOSO_CONST["STATE_FILE"]. }
    LOCAL snapshot IS aoso_json_read(path, LEXICON()).
    IF snapshot:ISTYPE("Lexicon") AND snapshot:HASKEY("current") {
        IF machine["states"]:HASKEY(snapshot["current"]) {
            IF snapshot:HASKEY("data") { SET machine["data"] TO snapshot["data"]. }
            aoso_state_transition(machine, snapshot["current"]).
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}
