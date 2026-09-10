// AOSO/mission/windows.ks
// Transfer-window efficiency for the planner. GOTO still burns a Hohmann
// intercept, so it must wait for the actual window -- going off-window
// would miss. "WAIT vs GO NOW" therefore means "pick a destination whose
// window is open" (planner), not "eject toward Duna 90 degrees off".

GLOBAL AOSO_WINDOW_LAST IS LEXICON().

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

FUNCTION aoso_window_evaluate {
    PARAMETER from_name.
    PARAMETER to_name.

    LOCAL from_planet IS aoso_feas_planet_of(from_name).
    LOCAL to_planet IS aoso_feas_planet_of(to_name).
    IF from_planet = to_planet {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "efficiency", 1, "best_dv", 80, "now_dv", 80, "phase_err", 0).
    }
    IF from_planet = "Sun" OR to_planet = "Sun" {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "efficiency", 0.5, "best_dv", 4000, "now_dv", 4000, "phase_err", 0).
    }

    LOCAL dep_ref IS BODY(from_planet).
    LOCAL arr_ref IS BODY(to_planet).
    IF NOT aoso_interplanetary_share_parent(dep_ref, arr_ref) {
        RETURN LEXICON("from", from_name, "to", to_name, "wait_s", 0, "wait_days", 0,
            "efficiency", 0.5, "best_dv", 2500, "now_dv", 2500, "phase_err", 0).
    }

    LOCAL wait_s IS aoso_interplanetary_wait_time_to_window_s(dep_ref, arr_ref).
    IF wait_s < 0 { SET wait_s TO 0. }
    LOCAL current_phase IS aoso_interplanetary_phase_angle_deg(dep_ref, arr_ref).
    LOCAL required_phase IS aoso_interplanetary_required_phase_angle_deg(dep_ref, arr_ref).
    LOCAL phase_err IS ABS(aoso_window_wrap180(current_phase - required_phase)).
    LOCAL efficiency IS 1 - (phase_err / 180) * 0.5.
    IF efficiency < 0.45 { SET efficiency TO 0.45. }

    LOCAL vinf IS ABS(aoso_interplanetary_v_infinity_signed(dep_ref, arr_ref)).
    LOCAL best_dv IS vinf.
    IF best_dv < 50 { SET best_dv TO 50. }
    LOCAL now_dv IS best_dv / efficiency.

    RETURN LEXICON(
        "from", from_name,
        "to", to_name,
        "wait_s", wait_s,
        "wait_days", ROUND(wait_s / 21600, 1),
        "efficiency", ROUND(efficiency, 2),
        "best_dv", ROUND(best_dv, 0),
        "now_dv", ROUND(now_dv, 0),
        "phase_err", ROUND(phase_err, 1)
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
