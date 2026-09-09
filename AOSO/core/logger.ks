// AOSO/core/logger.ks
// Severity-leveled logger with a buffered file writer so we don't hit the
// archive/volume with a WRITELN every tick. Depends on constants.ks for the
// level ordinals and file path, and config.ks (optional) for the configured
// minimum level.

GLOBAL AOSO_LOG_BUFFER IS LIST().
GLOBAL AOSO_LOG_MIN_LEVEL IS 1.          // DEBUG by default
GLOBAL AOSO_LOG_LAST_FLUSH IS 0.

FUNCTION aoso_log_set_level {
    PARAMETER level_name.
    IF AOSO_LOG_LEVELS:HASKEY(level_name) {
        SET AOSO_LOG_MIN_LEVEL TO AOSO_LOG_LEVELS[level_name].
    }
}

// Starts a brand-new on-disk log for this boot instead of letting
// core/logger.ks's own aoso_log_flush() append to whatever core/boot.ks's
// previous run (or a previous game session) already left on disk --
// otherwise AOSO_CONST["LOG_FILE"] grows forever and a fresh attempt's
// messages get buried after every earlier try's. Unlike
// mission/checkpoints.ks's AOSO_CHECKPOINT (deliberately kept so a run can
// resume) or core/config.ks's AOSO_CONFIG (deliberately kept as operator
// settings), the log is purely a per-attempt debugging aid, so it is safe
// -- and clearer for the operator -- to discard on every boot.
FUNCTION aoso_log_reset {
    SET AOSO_LOG_BUFFER TO LIST().
    SET AOSO_LOG_LAST_FLUSH TO 0.
    IF EXISTS(AOSO_CONST["LOG_FILE"]) {
        DELETEPATH(AOSO_CONST["LOG_FILE"]).
    }
}

FUNCTION aoso_log {
    PARAMETER level_name.
    PARAMETER tag.
    PARAMETER message.

    LOCAL lvl IS 2.
    IF AOSO_LOG_LEVELS:HASKEY(level_name) { SET lvl TO AOSO_LOG_LEVELS[level_name]. }
    IF lvl < AOSO_LOG_MIN_LEVEL { RETURN. }

    LOCAL t IS 0.
    IF DEFINED TIME { SET t TO TIME:SECONDS. }
    LOCAL line IS "[" + ROUND(t, 2) + "][" + level_name + "][" + tag + "] " + message.

    PRINT line.
    AOSO_LOG_BUFFER:ADD(line).

    IF lvl >= AOSO_LOG_LEVELS["ERROR"] {
        // Errors/fatals flush immediately so we never lose them on a crash.
        aoso_log_flush().
    } ELSE IF (t - AOSO_LOG_LAST_FLUSH) >= AOSO_CONST["LOG_FLUSH_INTERVAL"] {
        aoso_log_flush().
    }
}

FUNCTION aoso_log_flush {
    IF AOSO_LOG_BUFFER:LENGTH = 0 {
        SET AOSO_LOG_LAST_FLUSH TO TIME:SECONDS.
        RETURN.
    }
    // OPEN() returns a plain BooleanValue(false) instead of a file handle
    // when the path doesn't exist yet, so CREATE it the first time and
    // OPEN it (for append) on every call after that.
    LOCAL log_path IS AOSO_CONST["LOG_FILE"].
    LOCAL f IS 0.
    IF EXISTS(log_path) {
        SET f TO OPEN(log_path).
    } ELSE {
        SET f TO CREATE(log_path).
    }
    UNTIL AOSO_LOG_BUFFER:LENGTH = 0 {
        LOCAL line IS AOSO_LOG_BUFFER[0].
        AOSO_LOG_BUFFER:REMOVE(0).
        f:WRITELN(line).
    }
    SET AOSO_LOG_LAST_FLUSH TO TIME:SECONDS.
}

FUNCTION aoso_log_trace { PARAMETER tag. PARAMETER msg. aoso_log("TRACE", tag, msg). }
FUNCTION aoso_log_debug { PARAMETER tag. PARAMETER msg. aoso_log("DEBUG", tag, msg). }
FUNCTION aoso_log_info  { PARAMETER tag. PARAMETER msg. aoso_log("INFO", tag, msg). }
FUNCTION aoso_log_warn  { PARAMETER tag. PARAMETER msg. aoso_log("WARN", tag, msg). }
FUNCTION aoso_log_error { PARAMETER tag. PARAMETER msg. aoso_log("ERROR", tag, msg). }
FUNCTION aoso_log_fatal { PARAMETER tag. PARAMETER msg. aoso_log("FATAL", tag, msg). }
