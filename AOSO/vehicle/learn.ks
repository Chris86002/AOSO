// AOSO/vehicle/learn.ks
// Flight-performance database. Every completed ascent (and later, other
// events) is stored against a vessel fingerprint + body, so the next
// flight of the same stack can say "I've flown this 7 times, best LF
// remaining was 4382, this one is 2.7% worse -- possible early gravity
// turn." Persists to LEARN_FILE across reboots; the per-attempt log still
// starts clean.

GLOBAL AOSO_LEARN IS LEXICON("loaded", FALSE, "store", LEXICON()).
GLOBAL AOSO_LEARN_LAST IS LEXICON().

FUNCTION aoso_learn_vessel_key {
    // Name only: part/engine counts change after staging and after a VAB
    // revert, so a 110-part pad stack would never match the 59-part orbit
    // record from the last flight.
    RETURN SHIP:NAME.
}

FUNCTION aoso_learn_stat_key {
    PARAMETER event_name.
    PARAMETER body_name.
    RETURN aoso_learn_vessel_key() + "|" + body_name + "|" + event_name.
}

FUNCTION aoso_learn_load {
    IF AOSO_LEARN["loaded"] { RETURN AOSO_LEARN["store"]. }
    LOCAL loaded IS aoso_json_read_persistent(
        AOSO_CONST["LEARN_FILE"],
        AOSO_CONST["LEARN_ARCHIVE_FILE"],
        LEXICON("flights", LIST(), "stats", LEXICON())
    ).
    IF NOT loaded:ISTYPE("Lexicon") { SET loaded TO LEXICON("flights", LIST(), "stats", LEXICON()). }
    IF NOT loaded:HASKEY("flights") { SET loaded["flights"] TO LIST(). }
    IF NOT loaded:HASKEY("stats") { SET loaded["stats"] TO LEXICON(). }
    SET AOSO_LEARN["store"] TO loaded.
    SET AOSO_LEARN["loaded"] TO TRUE.
    RETURN loaded.
}

FUNCTION aoso_learn_save {
    aoso_json_write_persistent(
        AOSO_CONST["LEARN_FILE"],
        AOSO_CONST["LEARN_ARCHIVE_FILE"],
        AOSO_LEARN["store"]
    ).
}

FUNCTION aoso_learn_record_ascent {
    PARAMETER rec.

    LOCAL store IS aoso_learn_load().
    LOCAL event_name IS "ascent".
    LOCAL body_name IS rec["body"].
    LOCAL skey IS aoso_learn_stat_key(event_name, body_name).
    LOCAL orbit_lf IS rec["orbit_lf"].
    LOCAL used_lf IS rec["used_lf"].
    LOCAL circ_dv IS rec["circ_dv"].

    LOCAL flight IS LEXICON(
        "fp", aoso_learn_vessel_key(),
        "event", event_name,
        "body", body_name,
        "profile", rec["profile"],
        "orbit_lf", orbit_lf,
        "used_lf", used_lf,
        "circ_dv", circ_dv,
        "apo", rec["apo"],
        "peri", rec["peri"],
        "mass", rec["mass"],
        "ut", rec["ut"]
    ).
    store["flights"]:ADD(flight).
    UNTIL store["flights"]:LENGTH <= 30 {
        store["flights"]:REMOVE(0).
    }

    LOCAL stats IS store["stats"].
    IF NOT stats:HASKEY(skey) {
        SET stats[skey] TO LEXICON("count", 0, "sum_orbit_lf", 0, "sum_used_lf", 0, "sum_circ_dv", 0, "best_orbit_lf", orbit_lf).
    }
    LOCAL row IS stats[skey].
    SET row["count"] TO row["count"] + 1.
    SET row["sum_orbit_lf"] TO row["sum_orbit_lf"] + orbit_lf.
    SET row["sum_used_lf"] TO row["sum_used_lf"] + used_lf.
    SET row["sum_circ_dv"] TO row["sum_circ_dv"] + circ_dv.
    IF orbit_lf > row["best_orbit_lf"] { SET row["best_orbit_lf"] TO orbit_lf. }
    SET stats[skey] TO row.

    LOCAL n IS row["count"].
    LOCAL avg_lf IS row["sum_orbit_lf"] / n.
    LOCAL avg_used IS row["sum_used_lf"] / n.
    LOCAL avg_circ IS row["sum_circ_dv"] / n.
    LOCAL best_lf IS row["best_orbit_lf"].
    LOCAL deviation_pct IS 0.
    IF avg_lf > 1 { SET deviation_pct TO ((orbit_lf - avg_lf) / avg_lf) * 100. }

    LOCAL issue IS "".
    IF circ_dv > 200 { SET issue TO "high circularization dV". }
    IF n >= 2 {
        IF used_lf > avg_used * 1.1 {
            IF issue = "" { SET issue TO "inefficient ascent (fuel)". }
        }
    }

    SET AOSO_LEARN_LAST TO LEXICON(
        "event", event_name,
        "body", body_name,
        "count", n,
        "best_orbit_lf", best_lf,
        "avg_orbit_lf", avg_lf,
        "current_orbit_lf", orbit_lf,
        "deviation_pct", deviation_pct,
        "issue", issue
    ).

    LOCAL issue_txt IS "none".
    IF issue <> "" { SET issue_txt TO issue. }
    aoso_log_info("LEARN", "This vessel config flown " + n + " time(s) from " + body_name +
        ". Best LF remaining " + ROUND(best_lf, 1) +
        "  avg " + ROUND(avg_lf, 1) +
        "  current " + ROUND(orbit_lf, 1) +
        "  deviation " + ROUND(deviation_pct, 2) + "%" +
        "  issue=" + issue_txt + ".").

    aoso_learn_save().
    RETURN AOSO_LEARN_LAST.
}
