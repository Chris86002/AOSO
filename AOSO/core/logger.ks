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
    LOCAL f IS OPEN(AOSO_CONST["LOG_FILE"]).
    UNTIL AOSO_LOG_BUFFER:LENGTH = 0 {
        f:WRITELN(AOSO_LOG_BUFFER:REMOVE(0)).
    }
    SET AOSO_LOG_LAST_FLUSH TO TIME:SECONDS.
}

FUNCTION aoso_log_trace { PARAMETER tag. PARAMETER msg. aoso_log("TRACE", tag, msg). }
FUNCTION aoso_log_debug { PARAMETER tag. PARAMETER msg. aoso_log("DEBUG", tag, msg). }
FUNCTION aoso_log_info  { PARAMETER tag. PARAMETER msg. aoso_log("INFO", tag, msg). }
FUNCTION aoso_log_warn  { PARAMETER tag. PARAMETER msg. aoso_log("WARN", tag, msg). }
FUNCTION aoso_log_error { PARAMETER tag. PARAMETER msg. aoso_log("ERROR", tag, msg). }
FUNCTION aoso_log_fatal { PARAMETER tag. PARAMETER msg. aoso_log("FATAL", tag, msg). }
