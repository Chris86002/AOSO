// AOSO/vehicle/experience.ks
// Bounded prediction corrections. Physics stays the baseline.
// corrected = analytical * clamp(mean(actual/pred), 1±max).
// Keys: configuration_id | body | operation. Survives Archive reverts.

GLOBAL AOSO_XP IS LEXICON("loaded", FALSE, "store", LEXICON(), "save_at", 0).

FUNCTION aoso_xp_ops {
    RETURN LIST("ASCENT", "CIRCULARIZATION", "MANEUVER", "TRANSFER", "CAPTURE", "LANDING", "TAKEOFF", "STAGING", "REFUEL", "RETURN").
}

FUNCTION aoso_xp_key {
    PARAMETER op_name.
    PARAMETER body_name.
    RETURN aoso_cfg_id() + "|" + body_name + "|" + op_name.
}

FUNCTION aoso_xp_load {
    IF AOSO_XP["loaded"] { RETURN AOSO_XP["store"]. }
    LOCAL loaded IS aoso_json_read_persistent(
        AOSO_CONST["XP_FILE"],
        AOSO_CONST["XP_ARCHIVE_FILE"],
        LEXICON("models", LEXICON(), "samples", LIST())
    ).
    IF NOT loaded:ISTYPE("Lexicon") { SET loaded TO LEXICON("models", LEXICON(), "samples", LIST()). }
    IF NOT loaded:HASKEY("models") { SET loaded["models"] TO LEXICON(). }
    IF NOT loaded:HASKEY("samples") { SET loaded["samples"] TO LIST(). }
    SET AOSO_XP["store"] TO loaded.
    SET AOSO_XP["loaded"] TO TRUE.
    aoso_xp_migrate_learn().
    RETURN loaded.
}

FUNCTION aoso_xp_save {
    aoso_json_write_persistent(
        AOSO_CONST["XP_FILE"],
        AOSO_CONST["XP_ARCHIVE_FILE"],
        AOSO_XP["store"]
    ).
    SET AOSO_XP["save_at"] TO TIME:SECONDS.
}

FUNCTION aoso_xp_migrate_learn {
    IF NOT DEFINED AOSO_LEARN { RETURN. }
    LOCAL learn_store IS aoso_learn_load().
    IF NOT learn_store:HASKEY("stats") { RETURN. }
    LOCAL stats IS learn_store["stats"].
    FOR skey IN stats:KEYS {
        LOCAL row IS stats[skey].
        IF row:ISTYPE("Lexicon") {
            IF row:HASKEY("count") {
                IF row["count"] >= 1 {
                    IF row:HASKEY("sum_circ_dv") {
                        LOCAL parts IS skey:SPLIT("|").
                        LOCAL body_n IS SHIP:BODY:NAME.
                        IF parts:LENGTH >= 2 { SET body_n TO parts[1]. }
                        LOCAL mk IS aoso_xp_key("CIRCULARIZATION", body_n).
                        LOCAL models IS AOSO_XP["store"]["models"].
                        IF NOT models:HASKEY(mk) {
                            LOCAL n IS row["count"].
                            LOCAL avg IS row["sum_circ_dv"] / n.
                            LOCAL ratio IS 1.
                            IF avg > 40 { SET ratio TO MIN(1.4, MAX(0.7, avg / 58)). }
                            SET models[mk] TO aoso_xp_blank(n, ratio).
                        }
                    }
                }
            }
        }
    }
}

FUNCTION aoso_xp_blank {
    PARAMETER n IS 0.
    PARAMETER ratio IS 1.
    RETURN LEXICON(
        "n", n,
        "sum_ratio", ratio * n,
        "mean_ratio", ratio,
        "best", ratio,
        "worst", ratio,
        "corr", 1,
        "conf", 0
    ).
}

FUNCTION aoso_xp_model {
    PARAMETER op_name.
    PARAMETER body_name.
    LOCAL store IS aoso_xp_load().
    LOCAL mk IS aoso_xp_key(op_name, body_name).
    IF store["models"]:HASKEY(mk) { RETURN store["models"][mk]. }
    RETURN aoso_xp_blank().
}

FUNCTION aoso_xp_record {
    PARAMETER op_name.
    PARAMETER body_name.
    PARAMETER predicted.
    PARAMETER actual.
    PARAMETER failed IS FALSE.

    IF predicted <= 0.01 { RETURN aoso_xp_model(op_name, body_name). }
    IF actual < 0 { RETURN aoso_xp_model(op_name, body_name). }
    LOCAL ratio IS actual / predicted.
    LOCAL max_c IS aoso_config_get("XP_MAX_CORRECTION", 0.35).
    IF ratio < 1 - max_c { SET ratio TO 1 - max_c. }
    IF ratio > 1 + max_c { SET ratio TO 1 + max_c. }
    IF failed {
        IF ratio > 1.15 { SET ratio TO 1.15. }
    }

    LOCAL store IS aoso_xp_load().
    LOCAL mk IS aoso_xp_key(op_name, body_name).
    IF NOT store["models"]:HASKEY(mk) {
        SET store["models"][mk] TO aoso_xp_blank().
    }
    LOCAL m IS store["models"][mk].
    SET m["n"] TO m["n"] + 1.
    SET m["sum_ratio"] TO m["sum_ratio"] + ratio.
    SET m["mean_ratio"] TO m["sum_ratio"] / m["n"].
    IF ratio < m["best"] { SET m["best"] TO ratio. }
    IF ratio > m["worst"] { SET m["worst"] TO ratio. }

    LOCAL min_n IS aoso_config_get("XP_MIN_SAMPLES", 3).
    LOCAL blend IS m["n"] / (m["n"] + min_n).
    LOCAL corr IS 1 + (m["mean_ratio"] - 1) * blend.
    IF corr < 1 - max_c { SET corr TO 1 - max_c. }
    IF corr > 1 + max_c { SET corr TO 1 + max_c. }
    SET m["corr"] TO corr.
    LOCAL conf IS 0.3.
    IF m["n"] >= min_n { SET conf TO 0.6. }
    IF m["n"] >= min_n * 2 { SET conf TO 0.82. }
    SET m["conf"] TO conf.
    SET store["models"][mk] TO m.

    store["samples"]:ADD(LEXICON(
        "op", op_name,
        "body", body_name,
        "pred", predicted,
        "act", actual,
        "ratio", ratio,
        "fail", failed,
        "ut", TIME:SECONDS
    )).
    UNTIL store["samples"]:LENGTH <= 40 {
        store["samples"]:REMOVE(0).
    }

    IF TIME:SECONDS - AOSO_XP["save_at"] > 8 { aoso_xp_save(). }
    aoso_ctx_bump("rev_xp").
    aoso_log_info("XP", op_name + " " + body_name + " n=" + m["n"] + " corr=" + ROUND(corr, 3) +
        " pred=" + ROUND(predicted, 1) + " act=" + ROUND(actual, 1) + " conf=" + ROUND(conf, 2) + ".").
    RETURN m.
}

FUNCTION aoso_xp_corr {
    PARAMETER op_name.
    PARAMETER body_name.
    LOCAL m IS aoso_xp_model(op_name, body_name).
    IF m["n"] < 1 { RETURN 1. }
    RETURN m["corr"].
}

FUNCTION aoso_xp_apply {
    PARAMETER op_name.
    PARAMETER body_name.
    PARAMETER analytical.
    LOCAL corr IS aoso_xp_corr(op_name, body_name).
    RETURN analytical * corr.
}

FUNCTION aoso_xp_predict {
    PARAMETER op_name.
    PARAMETER body_name.
    PARAMETER analytical.
    LOCAL m IS aoso_xp_model(op_name, body_name).
    LOCAL corr IS 1.
    IF m["n"] >= 1 { SET corr TO m["corr"]. }
    RETURN aoso_prediction_make(analytical * corr, m["n"], corr).
}

FUNCTION aoso_xp_ingest_result {
    PARAMETER res.
    IF NOT res:ISTYPE("Lexicon") { RETURN. }
    LOCAL op_name IS "".
    IF res:HASKEY("action_type") { SET op_name TO res["action_type"]. }
    IF op_name = "" { RETURN. }
    LOCAL pred IS 0.
    LOCAL act IS 0.
    IF res:HASKEY("predicted_dv") { SET pred TO res["predicted_dv"]. }
    IF res:HASKEY("actual_dv") { SET act TO res["actual_dv"]. }
    IF pred <= 0 {
        IF res:HASKEY("predicted_fuel") { SET pred TO res["predicted_fuel"]. }
        IF res:HASKEY("fuel_used") { SET act TO res["fuel_used"]. }
    }
    IF pred <= 0 { RETURN. }
    LOCAL failed IS FALSE.
    IF res["status"] = "FAILED" { SET failed TO TRUE. }
    IF res["status"] = "ABORTED" { SET failed TO TRUE. }
    LOCAL body_n IS SHIP:BODY:NAME.
    IF res:HASKEY("end_body") { SET body_n TO res["end_body"]. }
    aoso_xp_record(op_name, body_n, pred, act, failed).
}
