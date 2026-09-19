// AOSO/core/result.ks
// Standard action result, decision, heartbeat, prediction lexicons.

GLOBAL AOSO_DECIDE_SEQ IS 0.
GLOBAL AOSO_OPEN_DECISIONS IS LEXICON().
GLOBAL AOSO_HB IS LEXICON().
GLOBAL AOSO_LAST_RESULT IS LEXICON().

FUNCTION aoso_result_make {
    PARAMETER action_type.
    PARAMETER result_status.
    PARAMETER reason IS "".
    RETURN LEXICON(
        "action_id", AOSO_DECIDE_SEQ,
        "action_type", action_type,
        "status", result_status,
        "reason", reason,
        "started_at", 0,
        "completed_at", TIME:SECONDS,
        "duration", 0,
        "start_body", SHIP:BODY:NAME,
        "end_body", SHIP:BODY:NAME,
        "predicted_dv", 0,
        "actual_dv", 0,
        "dv_error", 0,
        "predicted_fuel", 0,
        "actual_fuel", 0,
        "fuel_used", 0,
        "confidence", 0.5,
        "anomalies", ""
    ).
}

FUNCTION aoso_result_emit {
    PARAMETER res.
    SET AOSO_LAST_RESULT TO res.
    IF res:HASKEY("predicted_dv") {
        IF res:HASKEY("actual_dv") {
            SET res["dv_error"] TO res["actual_dv"] - res["predicted_dv"].
            IF res["predicted_dv"] > 0 {
                LOCAL mag IS ABS(res["dv_error"]).
                LOCAL replan_n IS aoso_config_get("REPLAN_DV_ERROR", 250).
                LOCAL local_n IS aoso_config_get("CORRECT_LOCAL_DV", 25).
                IF mag >= replan_n {
                    aoso_event_publish("REPLAN_REQUESTED", "result", res["action_type"] + " dv_error=" + ROUND(res["dv_error"], 0)).
                } ELSE {
                    IF mag >= local_n {
                        aoso_event_publish("CORRECT_REQUESTED", "result", res["action_type"] + " dv_error=" + ROUND(res["dv_error"], 0)).
                    }
                }
            }
        }
    }
    IF DEFINED AOSO_XP {
        aoso_xp_ingest_result(res).
    }
    IF res:HASKEY("action_id") {
        aoso_decide_close(res["action_id"], res).
    }
    aoso_event_publish(res["action_type"] + "_" + res["status"], "result", res["reason"]).
}

FUNCTION aoso_prediction_make {
    PARAMETER value.
    PARAMETER samples IS 0.
    PARAMETER corr IS 1.
    LOCAL conf IS 0.35.
    IF samples >= 3 { SET conf TO 0.6. }
    IF samples >= 6 { SET conf TO 0.82. }
    IF samples >= 12 { SET conf TO 0.9. }
    RETURN LEXICON(
        "value", value,
        "confidence", conf,
        "samples", samples,
        "correction", corr,
        "source", "analytical+experience"
    ).
}

FUNCTION aoso_hb_set {
    PARAMETER controller.
    PARAMETER state_name.
    PARAMETER progress.
    LOCAL at IS TIME:SECONDS.
    IF AOSO_HB:HASKEY(controller) {
        LOCAL prev IS AOSO_HB[controller].
        IF prev:ISTYPE("Lexicon") {
            LOCAL moved IS FALSE.
            IF prev["state"] <> state_name { SET moved TO TRUE. }
            IF ABS(prev["progress"] - progress) > 0.015 { SET moved TO TRUE. }
            IF NOT moved { SET at TO prev["progress_at"]. }
        }
    }
    SET AOSO_HB[controller] TO LEXICON(
        "controller", controller,
        "state", state_name,
        "progress", progress,
        "progress_at", at
    ).
    IF DEFINED AOSO_CTX {
        SET AOSO_CTX["controller"] TO controller.
        SET AOSO_CTX["progress"] TO progress.
        SET AOSO_CTX["action"] TO state_name.
        SET AOSO_CTX["progress_at"] TO at.
    }
}

FUNCTION aoso_hb_get {
    PARAMETER controller.
    IF AOSO_HB:HASKEY(controller) { RETURN AOSO_HB[controller]. }
    RETURN 0.
}

FUNCTION aoso_hb_any_progress_at {
    LOCAL latest IS 0.
    FOR k IN AOSO_HB:KEYS {
        LOCAL row IS AOSO_HB[k].
        IF row:ISTYPE("Lexicon") {
            IF row["progress_at"] > latest { SET latest TO row["progress_at"]. }
        }
    }
    RETURN latest.
}

FUNCTION aoso_decide_open {
    PARAMETER tag.
    PARAMETER decision.
    PARAMETER selected.
    PARAMETER reason.
    PARAMETER predicted IS 0.
    SET AOSO_DECIDE_SEQ TO AOSO_DECIDE_SEQ + 1.
    LOCAL id IS AOSO_DECIDE_SEQ.
    SET AOSO_OPEN_DECISIONS[id] TO LEXICON(
        "id", id,
        "type", tag,
        "decision", decision,
        "selected", selected,
        "reason", reason,
        "predicted", predicted,
        "created_at", TIME:SECONDS
    ).
    RETURN id.
}

FUNCTION aoso_decide_close {
    PARAMETER id.
    PARAMETER res.
    IF NOT AOSO_OPEN_DECISIONS:HASKEY(id) { RETURN. }
    LOCAL dec IS AOSO_OPEN_DECISIONS[id].
    LOCAL pred IS 0.
    IF dec:HASKEY("predicted") { SET pred TO dec["predicted"]. }
    LOCAL act IS 0.
    IF res:HASKEY("actual_dv") { SET act TO res["actual_dv"]. }
    LOCAL err IS act - pred.
    aoso_log_info("DECIDE", "closed id=" + id + " " + dec["type"] + " sel=" + dec["selected"] +
        " pred=" + ROUND(pred, 1) + " act=" + ROUND(act, 1) + " err=" + ROUND(err, 1) + ".").
    AOSO_OPEN_DECISIONS:REMOVE(id).
}
