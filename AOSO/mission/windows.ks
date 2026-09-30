// AOSO/mission/windows.ks
// Cheap transfer-window efficiency for strategic planning and the no-native
// fallback. Native v0.4+ GOTO searches departure-UT x flight-time with
// Lambert and validates finalists through stock patched conics; these Hohmann
// formulas remain a fast heuristic for route scoring and a safe fallback.

GLOBAL AOSO_WINDOW_LAST IS LEXICON().
GLOBAL AOSO_WINDOW_STATIC IS LEXICON().
GLOBAL AOSO_WINDOW_BODIES IS LEXICON().

FUNCTION aoso_window_wrap180 {
    PARAMETER ang.
    LOCAL wrapped IS ang.
    UNTIL wrapped <= 180 {
        SET wrapped TO wrapped - 360.
    }
    UNTIL wrapped > -180 {
        SET wrapped TO wrapped + 360.
    }
    RETURN wrapped.
}

// Body constants that do not change in stock. Filled once per body name.
FUNCTION aoso_window_body_static {
    PARAMETER body_name.
    IF AOSO_WINDOW_BODIES:HASKEY(body_name) {
        RETURN AOSO_WINDOW_BODIES[body_name].
    }
    IF NOT aoso_ctx_heavy_ok() { RETURN LEXICON(). }
    LOCAL body_ref IS BODY(body_name).
    LOCAL atm_h IS 0.
    LOCAL slp IS 0.
    LOCAL has_atm IS FALSE.
    IF body_ref:ATM:EXISTS {
        SET has_atm TO TRUE.
        SET atm_h TO body_ref:ATM:HEIGHT.
        SET slp TO body_ref:ATM:SEALEVELPRESSURE.
    }
    LOCAL mu_b IS body_ref:MU.
    LOCAL rad_b IS body_ref:RADIUS.
    LOCAL gee_b IS 0.
    IF rad_b > 1 { SET gee_b TO mu_b / (rad_b * rad_b). }
    LOCAL per_b IS 0.
    LOCAL sma_b IS 0.
    IF body_name <> SUN:NAME {
        SET per_b TO body_ref:ORBIT:PERIOD.
        SET sma_b TO body_ref:ORBIT:SEMIMAJORAXIS.
    }
    LOCAL rec IS LEXICON(
        "mu", mu_b,
        "radius", rad_b,
        "atm_h", atm_h,
        "has_atm", has_atm,
        "slp", slp,
        "gee", gee_b,
        "period", per_b,
        "sma", sma_b
    ).
    SET AOSO_WINDOW_BODIES[body_name] TO rec.
    aoso_cache_log("window", "miss", body_name).
    RETURN rec.
}

// Hohmann pair constants. Live phase/wait are computed from these plus position at at_ut.
FUNCTION aoso_window_pair {
    PARAMETER from_planet.
    PARAMETER to_planet.
    LOCAL key_s IS from_planet + "|" + to_planet.
    IF AOSO_WINDOW_STATIC:HASKEY(key_s) {
        aoso_cache_log("window", "hit", key_s).
        RETURN AOSO_WINDOW_STATIC[key_s].
    }
    IF NOT aoso_ctx_heavy_ok() { RETURN LEXICON(). }
    LOCAL dep_ref IS BODY(from_planet).
    LOCAL arr_ref IS BODY(to_planet).
    aoso_window_body_static(from_planet).
    aoso_window_body_static(to_planet).
    LOCAL dep_per IS dep_ref:ORBIT:PERIOD.
    LOCAL arr_per IS arr_ref:ORBIT:PERIOD.
    LOCAL rec IS LEXICON(
        "tof", aoso_interplanetary_transfer_time_s(dep_ref, arr_ref),
        "vinf", ABS(aoso_interplanetary_v_infinity_signed(dep_ref, arr_ref)),
        "phase_req", aoso_interplanetary_required_phase_angle_deg(dep_ref, arr_ref),
        "dep_per", dep_per,
        "arr_per", arr_per
    ).
    SET AOSO_WINDOW_STATIC[key_s] TO rec.
    aoso_cache_log("window", "miss", key_s).
    RETURN rec.
}

FUNCTION aoso_window_evaluate {
    PARAMETER from_name.
    PARAMETER to_name.
    RETURN aoso_window_evaluate_at(from_name, to_name, TIME:SECONDS).
}

// Planner-facing window evaluation at projected universal time. Route search
// can now ask "what will the Duna->Eve window look like after we finish
// Minmus and Duna?" instead of pricing every future hop against geometry now.
FUNCTION aoso_window_evaluate_at {
    PARAMETER from_name.
    PARAMETER to_name.
    PARAMETER at_ut.

    LOCAL from_planet IS aoso_feas_planet_of(from_name).
    LOCAL to_planet IS aoso_feas_planet_of(to_name).
    IF from_planet = to_planet {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "transfer_s", 0, "total_s", 0, "efficiency", 1, "best_dv", 80, "now_dv", 80, "phase_err", 0).
    }
    IF from_planet = "Sun" OR to_planet = "Sun" {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "transfer_s", 0, "total_s", 0, "efficiency", 0.5, "best_dv", 4000, "now_dv", 4000, "phase_err", 0).
    }

    LOCAL dep_ref IS BODY(from_planet).
    LOCAL arr_ref IS BODY(to_planet).
    IF NOT aoso_interplanetary_share_parent(dep_ref, arr_ref) {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "transfer_s", 0, "total_s", 0, "efficiency", 0.5, "best_dv", 2500, "now_dv", 2500, "phase_err", 0).
    }

    LOCAL pair IS aoso_window_pair(from_planet, to_planet).
    IF NOT pair:HASKEY("tof") {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "transfer_s", 0, "total_s", 0, "efficiency", 0.5, "best_dv", 2500, "now_dv", 2500, "phase_err", 0).
    }

    LOCAL current_phase IS aoso_interplanetary_phase_angle_deg_at(dep_ref, arr_ref, at_ut).
    LOCAL required_phase IS pair["phase_req"].
    LOCAL phase_err IS ABS(aoso_window_wrap180(current_phase - required_phase)).
    LOCAL efficiency IS 1 - (phase_err / 180) * 0.5.
    IF efficiency < 0.45 { SET efficiency TO 0.45. }

    LOCAL dep_per IS pair["dep_per"].
    LOCAL arr_per IS pair["arr_per"].
    LOCAL wait_s IS 0.
    IF dep_per > 1 {
        IF arr_per > 1 {
            LOCAL dep_rate IS 360 / dep_per.
            LOCAL arr_rate IS 360 / arr_per.
            LOCAL relative_rate IS dep_rate - arr_rate.
            IF relative_rate = 0 {
                SET wait_s TO 0.
            } ELSE {
                SET wait_s TO -(current_phase - required_phase) / relative_rate.
                LOCAL syn_s IS 360 / ABS(relative_rate).
                UNTIL wait_s >= 0 {
                    SET wait_s TO wait_s + syn_s.
                }
                UNTIL wait_s < syn_s {
                    SET wait_s TO wait_s - syn_s.
                }
            }
        }
    }
    IF wait_s < 0 { SET wait_s TO 0. }
    LOCAL transfer_s IS pair["tof"].
    LOCAL vinf IS pair["vinf"].
    LOCAL best_dv IS vinf.
    IF best_dv < 50 { SET best_dv TO 50. }
    LOCAL now_dv IS best_dv / efficiency.

    RETURN LEXICON(
        "from", from_name,
        "to", to_name,
        "wait_s", wait_s,
        "wait_days", ROUND(wait_s / 21600, 1),
        "transfer_s", transfer_s,
        "total_s", wait_s + transfer_s,
        "efficiency", ROUND(efficiency, 2),
        "best_dv", ROUND(best_dv, 0),
        "now_dv", ROUND(now_dv, 0),
        "phase_err", ROUND(phase_err, 1),
        "at_ut", at_ut
    ).
}

FUNCTION aoso_window_decide {
    PARAMETER dep_ref.
    PARAMETER arr_ref.
    LOCAL ev IS aoso_window_evaluate(dep_ref:NAME, arr_ref:NAME).
    LOCAL mode IS aoso_config_get("OPTIMIZATION_MODE", "BALANCED").
    LOCAL max_wait IS aoso_config_get("WINDOW_MAX_WAIT_S", 3888000).
    LOCAL min_eff IS aoso_config_get("WINDOW_MIN_EFFICIENCY", 0.82).
    LOCAL action IS "GO_NOW".
    LOCAL why IS "window open".

    IF ev["wait_s"] > 20 {
        // Hohmann intercepts require the window. Planner uses efficiency
        // to pick a different next target; GOTO still waits.
        SET action TO "WAIT".
        SET why TO "Hohmann intercept in " + ROUND(ev["wait_s"], 0) + "s (eff=" + ev["efficiency"] + ")".
        IF ev["wait_s"] > max_wait {
            SET why TO why + " - long wait, planner should have preferred another cluster".
        }
        IF mode = "TIME" {
            IF ev["efficiency"] >= min_eff {
                IF ev["wait_s"] > 21600 {
                    SET why TO "TIME mode: window is close enough in phase but far in time - still must wait for intercept".
                }
            }
        }
    }
    SET ev["action"] TO action.
    SET ev["why"] TO why.
    SET ev["mode"] TO mode.
    SET AOSO_WINDOW_LAST TO ev.
    RETURN ev.
}
