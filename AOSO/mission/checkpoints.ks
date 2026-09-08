// AOSO/mission/checkpoints.ks
// Phase 10 (Mission layer): persists just enough of mission/mission.ks's
// progress to resume after a reload/scene-change/KSP restart -- the current
// plan step index/name, plus an arbitrary caller-supplied data lexicon
// (e.g. which body a transfer step targets). A KOSDelegate (a mission
// step's start/update/is_done/is_aborted callbacks) can't itself survive a
// JSON round trip (core/json.ks only supports scalar/LIST/LEXICON values),
// so this deliberately never tries to persist the plan itself -- only the
// index into whatever plan the caller rebuilds identically on resume, the
// same "caller rebuilds, we just remember where" contract core/state.ks's
// own aoso_state_save/aoso_state_load documents for its "data" lexicon.
//
// core/boot.ks already conditionally calls aoso_checkpoints_load() on every
// boot (`IF DEFINED aoso_checkpoints_load`); it only loads the last
// snapshot into AOSO_CHECKPOINT for whatever mission script chooses to
// consult (e.g. mission/mission.ks's aoso_mission_start
// resume_from_checkpoint parameter) -- boot.ks has no plan of its own to
// resume automatically.

GLOBAL AOSO_CHECKPOINT IS LEXICON(
    "step_index", -1,
    "step_name", "",
    "data", LEXICON(),
    "saved_at", 0
).

FUNCTION aoso_checkpoints_save {
    PARAMETER step_index.
    PARAMETER step_name IS "".
    PARAMETER data IS LEXICON().

    SET AOSO_CHECKPOINT TO LEXICON(
        "step_index", step_index,
        "step_name", step_name,
        "data", data,
        "saved_at", TIME:SECONDS
    ).
    aoso_json_write(AOSO_CONST["CHECKPOINT_FILE"], AOSO_CHECKPOINT).
    IF DEFINED aoso_log_info {
        aoso_log_info("CHECKPOINT", "Saved at step " + (step_index + 1) + ": " + step_name).
    }
}

FUNCTION aoso_checkpoints_load {
    LOCAL loaded IS aoso_json_read(AOSO_CONST["CHECKPOINT_FILE"], 0).
    IF loaded:ISTYPE("Lexicon") AND loaded:HASKEY("step_index") {
        SET AOSO_CHECKPOINT TO loaded.
        IF DEFINED aoso_log_info {
            aoso_log_info("CHECKPOINT", "Loaded checkpoint: step " + (AOSO_CHECKPOINT["step_index"] + 1) +
                " (" + AOSO_CHECKPOINT["step_name"] + ").").
        }
        RETURN TRUE.
    }
    RETURN FALSE.
}

FUNCTION aoso_checkpoints_available {
    RETURN AOSO_CHECKPOINT["step_index"] >= 0.
}

FUNCTION aoso_checkpoints_step_index {
    RETURN AOSO_CHECKPOINT["step_index"].
}

FUNCTION aoso_checkpoints_step_name {
    RETURN AOSO_CHECKPOINT["step_name"].
}

FUNCTION aoso_checkpoints_data {
    RETURN AOSO_CHECKPOINT["data"].
}

FUNCTION aoso_checkpoints_clear {
    SET AOSO_CHECKPOINT TO LEXICON("step_index", -1, "step_name", "", "data", LEXICON(), "saved_at", 0).
    IF EXISTS(AOSO_CONST["CHECKPOINT_FILE"]) {
        DELETEPATH(AOSO_CONST["CHECKPOINT_FILE"]).
    }
}

// Periodic safety-net save on top of mission.ks's own per-step-transition
// save, using the existing AUTO_CHECKPOINT_INTERVAL config -- covers long
// single steps (e.g. a multi-minute interplanetary coast) where nothing
// would otherwise trigger a fresh save between step transitions. A no-op
// unless mission/mission.ks's AOSO_MISSION is actually running, so this can
// be registered unconditionally without assuming a mission is active.
FUNCTION aoso_checkpoints_autosave_tick {
    // kOS's grammar only allows a single unary prefix (NOT *or* DEFINED, not
    // both), so "IF NOT DEFINED x" is a parse error -- nest the DEFINED
    // check instead.
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "RUNNING" { RETURN. }

        LOCAL idx IS AOSO_MISSION["data"]["index"].
        LOCAL name IS "".
        IF idx >= 0 AND idx < AOSO_MISSION_PLAN:LENGTH { SET name TO AOSO_MISSION_PLAN[idx]["name"]. }
        aoso_checkpoints_save(idx, name).
    }
}

FUNCTION aoso_checkpoints_register_task {
    IF DEFINED aoso_sched_add {
        aoso_sched_add("checkpoint_autosave", aoso_config_get("AUTO_CHECKPOINT_INTERVAL", 30), aoso_checkpoints_autosave_tick@).
    }
}
