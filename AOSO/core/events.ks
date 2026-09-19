// AOSO/core/events.ks
// Queued events. Publish never calls a subscriber. The brain/scheduler
// drains later so we do not nest state transitions (kOS stack depth).

GLOBAL AOSO_EVENTS IS LIST().
GLOBAL AOSO_EVENT_SEQ IS 0.

FUNCTION aoso_event_init {
    SET AOSO_EVENTS TO LIST().
    SET AOSO_EVENT_SEQ TO 0.
}

FUNCTION aoso_event_publish {
    PARAMETER etype.
    PARAMETER source.
    PARAMETER data_str IS "".
    SET AOSO_EVENT_SEQ TO AOSO_EVENT_SEQ + 1.
    IF AOSO_EVENTS:LENGTH >= 32 {
        AOSO_EVENTS:REMOVE(0).
    }
    AOSO_EVENTS:ADD(LEXICON(
        "id", AOSO_EVENT_SEQ,
        "type", etype,
        "source", source,
        "data", data_str,
        "ut", TIME:SECONDS
    )).
}

FUNCTION aoso_event_count {
    RETURN AOSO_EVENTS:LENGTH.
}

FUNCTION aoso_event_next {
    IF AOSO_EVENTS:LENGTH = 0 { RETURN 0. }
    LOCAL ev IS AOSO_EVENTS[0].
    AOSO_EVENTS:REMOVE(0).
    RETURN ev.
}

FUNCTION aoso_event_process {
    PARAMETER max_n IS 4.
    LOCAL n IS 0.
    UNTIL n >= max_n {
        IF AOSO_EVENTS:LENGTH = 0 { RETURN n. }
        LOCAL ev IS aoso_event_next().
        IF ev:ISTYPE("Lexicon") {
            aoso_brain_on_event(ev).
        }
        SET n TO n + 1.
    }
    RETURN n.
}
