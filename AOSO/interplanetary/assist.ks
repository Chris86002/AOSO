// AOSO/interplanetary/assist.ks
// Patched-conic gravity-assist pick. MechJeb / RSVP / the stock dV map all
// treat a Mun flyby as a cheap AP pump toward Minmus, and Eve as the inner
// pump toward Moho. We do not drive ADDONS:MJ or Astrogator suffixes.
//
// Always log the comparison. Use the flyby when it saves ~12% or when
// mission dV is too tight for a direct Hohmann.

FUNCTION aoso_assist_safe_pe {
    PARAMETER b.
    IF b:ATM:EXISTS {
        LOCAL pe_a IS b:ATM:HEIGHT + 15000.
        IF pe_a < 80000 { SET pe_a TO 80000. }
        RETURN pe_a.
    }
    LOCAL pe_b IS b:RADIUS * 0.08.
    IF pe_b < 15000 { SET pe_b TO 15000. }
    RETURN pe_b.
}

FUNCTION aoso_assist_hohmann_dv {
    PARAMETER dest.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r1 IS SHIP:ORBIT:SEMIMAJORAXIS.
    IF r1 < SHIP:BODY:RADIUS + 1000 { SET r1 TO SHIP:BODY:RADIUS + 80000. }
    LOCAL r2 IS dest:ORBIT:SEMIMAJORAXIS.
    LOCAL sma IS (r1 + r2) / 2.
    LOCAL v1 IS SQRT(MAX(1, mu / r1)).
    LOCAL vt IS SQRT(MAX(0, mu * (2 / r1 - 1 / sma))).
    RETURN ABS(vt - v1).
}

FUNCTION aoso_assist_v_inf {
    PARAMETER via.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r1 IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL r2 IS via:ORBIT:SEMIMAJORAXIS.
    LOCAL sma IS (r1 + r2) / 2.
    LOCAL v_circ IS SQRT(MAX(1, mu / r2)).
    LOCAL v_arr IS SQRT(MAX(0, mu * (2 / r2 - 1 / sma))).
    RETURN ABS(v_arr - v_circ).
}

FUNCTION aoso_assist_max_turn_deg {
    PARAMETER via.
    PARAMETER v_inf.
    LOCAL mu_b IS via:MU.
    LOCAL r_pe IS via:RADIUS + aoso_assist_safe_pe(via).
    LOCAL e IS 1 + (r_pe * v_inf * v_inf) / mu_b.
    IF e < 1.02 { SET e TO 1.02. }
    LOCAL inv_e IS 1 / e.
    IF inv_e > 0.999 { SET inv_e TO 0.999. }
    RETURN 2 * ARCSIN(inv_e).
}

// Upper bound on parent-frame dV you can steal from a flyby: 2 v_inf * sin(turn/2).
FUNCTION aoso_assist_pump_dv {
    PARAMETER via.
    LOCAL v_inf IS aoso_assist_v_inf(via).
    LOCAL turn IS aoso_assist_max_turn_deg(via, v_inf).
    RETURN 2 * v_inf * SIN(turn / 2).
}

FUNCTION aoso_assist_eval {
    PARAMETER via.
    PARAMETER dest.
    LOCAL direct IS aoso_assist_hohmann_dv(dest).
    LOCAL via_dv IS aoso_assist_hohmann_dv(via).
    LOCAL pump IS aoso_assist_pump_dv(via).
    LOCAL remain IS direct - pump.
    IF remain < 80 { SET remain TO 80. }
    LOCAL total_via IS via_dv + remain * 0.35.
    LOCAL save_dv IS direct - total_via.
    LOCAL save_pct IS 0.
    IF direct > 1 { SET save_pct TO 100 * save_dv / direct. }
    LOCAL useful IS FALSE.
    IF save_pct > 15 { SET useful TO TRUE. }
    LOCAL have IS aoso_budget_get("mission_dv", 0).
    IF have > 0 {
        IF have < direct * 1.25 {
            IF save_pct > 0 { SET useful TO TRUE. }
        }
    }
    RETURN LEXICON(
        "via", via:NAME,
        "dest", dest:NAME,
        "direct_dv", ROUND(direct, 0),
        "via_dv", ROUND(via_dv, 0),
        "pump_dv", ROUND(pump, 0),
        "est_total", ROUND(total_via, 0),
        "save_dv", ROUND(save_dv, 0),
        "save_pct", ROUND(save_pct, 1),
        "useful", useful
    ).
}

// Walk a body-db lexicon for siblings of dest under parent_name whose
// SMA is inside dest. Skip non-lexicon values: a JSON/simpleJson load can
// leave scalars in the map, and e["PARENT"] on a number is
// "Can't iterate on Scalar IntValue" (Acacius tour replan after LKO).
FUNCTION aoso_assist_parent_siblings {
    PARAMETER db.
    PARAMETER parent_name.
    PARAMETER dest_name.
    PARAMETER dest_sma.
    PARAMETER skip_name.
    LOCAL found IS LIST().
    IF NOT db:ISTYPE("Lexicon") { RETURN found. }
    LOCAL ks IS db:KEYS.
    IF NOT ks:ISTYPE("List") { RETURN found. }
    FOR k IN ks {
        LOCAL e IS db[k].
        IF e:ISTYPE("Lexicon") {
            IF e:HASKEY("PARENT") {
                IF e:HASKEY("SMA") {
                    IF e["PARENT"] = parent_name {
                        IF k <> dest_name {
                            IF k <> skip_name {
                                IF e["SMA"] > 0 {
                                    IF e["SMA"] < dest_sma * 0.85 {
                                        found:ADD(k).
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    RETURN found.
}

FUNCTION aoso_assist_candidates {
    PARAMETER dest.
    LOCAL found IS LIST().
    IF NOT dest:ISTYPE("Body") { RETURN found. }
    IF AOSO_BODY_DB:LENGTH = 0 { RETURN found. }
    LOCAL parent_name IS dest:BODY:NAME.
    LOCAL dest_sma IS dest:ORBIT:SEMIMAJORAXIS.
    RETURN aoso_assist_parent_siblings(AOSO_BODY_DB, parent_name, dest:NAME, dest_sma, SHIP:BODY:NAME).
}

// Returns the via BODY if a flyby should be used, otherwise 0.
FUNCTION aoso_assist_should_flyby {
    PARAMETER dest.
    IF NOT dest:ISTYPE("Body") { RETURN 0. }
    LOCAL names IS aoso_assist_candidates(dest).
    IF names:LENGTH = 0 { RETURN 0. }
    LOCAL best_name IS "".
    LOCAL best_save IS 0.
    FOR n IN names {
        LOCAL via IS BODY(n).
        LOCAL ev IS aoso_assist_eval(via, dest).
        aoso_log_info("ASSIST", "Direct " + dest:NAME + " " + ev["direct_dv"] + " m/s vs via " + n + " est " + ev["est_total"] + " m/s save=" + ev["save_pct"] + "% useful=" + ev["useful"] + ".").
        IF ev["useful"] {
            IF ev["save_dv"] > best_save {
                SET best_save TO ev["save_dv"].
                SET best_name TO n.
            }
        }
    }
    IF best_name <> "" {
        aoso_log_info("ASSIST", "Using " + best_name + " flyby toward " + dest:NAME + " (save ~" + ROUND(best_save, 0) + " m/s).").
        aoso_decide("ASSIST", "flyby", best_name, dest:NAME, "save=" + ROUND(best_save, 0)).
        RETURN BODY(best_name).
    }
    RETURN 0.
}
