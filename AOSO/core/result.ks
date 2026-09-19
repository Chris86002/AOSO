// AOSO/core/result.ks
// Standard action result, decision, heartbeat, prediction lexicons.

GLOBAL AOSO_DECIDE_SEQ IS 0.
GLOBAL AOSO_OPEN_DECISIONS IS LEXICON().
GLOBAL AOSO_HB IS LEXICON().
GLOBAL AOSO_LAST_RESULT IS LEXICON().
GLOBAL AOSO_ACTION_CUR IS 0.

FUNCTION aoso_result_make {
    PARAMETER action_type.
    PARAMETER result_status.
    PARAMETER reason IS "".
    LOCAL aid IS AOSO_DECIDE_SEQ.
    LOCAL pred_dv IS 0.
    LOCAL started IS 0.
    LOCAL start_b IS SHIP:BODY:NAME.
    LOCAL start_fuel_amt IS 0.
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        IF AOSO_ACTION_CUR:HASKEY("action_id") { SET aid TO AOSO_ACTION_CUR["action_id"]. }
        IF AOSO_ACTION_CUR:HASKEY("predicted_dv") { SET pred_dv TO AOSO_ACTION_CUR["predicted_dv"]. }
        IF AOSO_ACTION_CUR:HASKEY("started_at") { SET started TO AOSO_ACTION_CUR["started_at"]. }
        IF AOSO_ACTION_CUR:HASKEY("start_body") { SET start_b TO AOSO_ACTION_CUR["start_body"]. }
        IF AOSO_ACTION_CUR:HASKEY("start_fuel") { SET start_fuel_amt TO AOSO_ACTION_CUR["start_fuel"]. }
        IF AOSO_ACTION_CUR:HASKEY("type") {
            IF action_type = "" { SET action_type TO AOSO_ACTION_CUR["type"]. }
        }
    }
    LOCAL dur IS 0.
    IF started > 0 { SET dur TO TIME:SECONDS - started. }
    RETURN LEXICON(
        "action_id", aid,
        "decision_id", aid,
        "action_type", action_type,
        "status", result_status,
        "reason", reason,
        "started_at", started,
        "completed_at", TIME:SECONDS,
        "duration", dur,
        "start_body", start_b,
        "end_body", SHIP:BODY:NAME,
        "predicted_dv", pred_dv,
        "actual_dv", 0,
        "dv_error", 0,
        "predicted_fuel", 0,
        "actual_fuel", start_fuel_amt,
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
    SET AOSO_ACTION_CUR TO 0.
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

FUNCTION aoso_action_create {
    PARAMETER decision_id.
    PARAMETER action_type.
    PARAMETER target_name IS "".
    PARAMETER predicted_dv IS 0.
    LOCAL aid IS decision_id.
    IF aid <= 0 {
        SET AOSO_DECIDE_SEQ TO AOSO_DECIDE_SEQ + 1.
        SET aid TO AOSO_DECIDE_SEQ.
    }
    LOCAL topo_r IS 0.
    LOCAL veh_r IS 0.
    LOCAL plan_r IS 0.
    IF DEFINED AOSO_CTX {
        SET topo_r TO aoso_ctx_get("rev_topo", 0).
        SET veh_r TO aoso_ctx_get("rev_vehicle", 0).
        SET plan_r TO aoso_ctx_get("rev_plan", 0).
    }
    LOCAL fuel_now IS 0.
    FOR res_row IN SHIP:RESOURCES {
        IF res_row:NAME = "LiquidFuel" { SET fuel_now TO res_row:AMOUNT. }
    }
    LOCAL act IS LEXICON(
        "action_id", aid,
        "decision_id", aid,
        "type", action_type,
        "target", target_name,
        "controller", action_type,
        "predicted_dv", predicted_dv,
        "predicted_fuel", 0,
        "predicted_duration", 0,
        "confidence", 0.5,
        "start_body", SHIP:BODY:NAME,
        "start_mass", SHIP:MASS,
        "start_fuel", fuel_now,
        "started_at", TIME:SECONDS,
        "topology_revision", topo_r,
        "vehicle_revision", veh_r,
        "plan_revision", plan_r
    ).
    RETURN act.
}

FUNCTION aoso_action_begin {
    PARAMETER act.
    SET AOSO_ACTION_CUR TO act.
    aoso_log_info("ACTION", "START id=" + act["action_id"] + " " + act["type"] + " " + act["target"] +
        " pred=" + ROUND(act["predicted_dv"], 1) + ".").
    RETURN act["action_id"].
}

FUNCTION aoso_result_from_action {
    PARAMETER act.
    PARAMETER result_status.
    PARAMETER reason IS "".
    SET AOSO_ACTION_CUR TO act.
    LOCAL res IS aoso_result_make(act["type"], result_status, reason).
    SET res["action_id"] TO act["action_id"].
    SET res["decision_id"] TO act["decision_id"].
    SET res["predicted_dv"] TO act["predicted_dv"].
    IF act:HASKEY("predicted_fuel") { SET res["predicted_fuel"] TO act["predicted_fuel"]. }
    SET res["started_at"] TO act["started_at"].
    SET res["start_body"] TO act["start_body"].
    IF act["started_at"] > 0 {
        SET res["duration"] TO TIME:SECONDS - act["started_at"].
    }
    RETURN res.
}

FUNCTION aoso_action_finish {
    PARAMETER result_status.
    PARAMETER reason IS "".
    IF NOT AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        RETURN aoso_result_make("", result_status, reason).
    }
    LOCAL act IS AOSO_ACTION_CUR.
    LOCAL res IS aoso_result_from_action(act, result_status, reason).
    aoso_log_info("ACTION", "COMPLETE id=" + act["action_id"] + " " + act["type"] +
        " " + result_status + " " + reason + ".").
    RETURN res.
}

FUNCTION aoso_action_clear {
    SET AOSO_ACTION_CUR TO 0.
}
