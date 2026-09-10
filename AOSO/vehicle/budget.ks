// AOSO/vehicle/budget.ks
// Usable mission delta-v, not "the ship has X m/s". A 5,200 m/s stack is
// not 5,200 m/s of useful dV: reserve, landing, return, abort, and
// unusable stages (TWR too low to burn) all come off the top.
//
//   MISSION_DV = TOTAL - UNUSABLE - RESERVE - LANDING - RETURN - ABORT
//
// Recalculated whenever the vehicle profile refreshes and whenever mass
// jumps without a part-count change (fuel burn). Totals come from
// vehicle/capabilities.ks's multi-stage vacuum estimate. Landing/return
// costs come from mission/feasibility.ks's body table when that module
// has been loaded; otherwise conservative stock-Kerbin defaults.

GLOBAL AOSO_BUDGET IS LEXICON().

FUNCTION aoso_budget_refresh {
    LOCAL total_dv IS aoso_caps_get("dv_total_vac", 0).
    LOCAL unusable_dv IS aoso_caps_get("dv_unusable", 0).
    LOCAL usable_raw IS total_dv - unusable_dv.
    IF usable_raw < 0 { SET usable_raw TO 0. }

    LOCAL reserve_pct IS aoso_config_get("FUEL_RESERVE_PCT", 10).
    LOCAL reserve_min IS aoso_config_get("DV_RESERVE_MIN", 200).
    LOCAL reserve_dv IS usable_raw * (reserve_pct / 100).
    IF reserve_dv < reserve_min {
        IF usable_raw < reserve_min {
            SET reserve_dv TO usable_raw * 0.1.
        } ELSE {
            SET reserve_dv TO reserve_min.
        }
    }

    LOCAL abort_min IS aoso_config_get("DV_ABORT_MIN", 100).
    LOCAL abort_dv IS abort_min.
    IF abort_dv > usable_raw * 0.15 { SET abort_dv TO usable_raw * 0.15. }

    LOCAL landing_dv IS 0.
    LOCAL return_dv IS 0.
    LOCAL home_name IS aoso_config_get("HOME_BODY", "Kerbin").
    LOCAL here_name IS SHIP:BODY:NAME.

    // Feasibility is loaded after this file; the functions exist by the
    // time boot/staging/scheduler actually call us.
    SET landing_dv TO aoso_feas_land_cost(here_name).
    SET return_dv TO aoso_feas_return_cost(here_name).

    IF here_name = home_name {
        // Already at home: return reserve is the KSC deorbit, not an
        // interplanetary injection.
        IF SHIP:STATUS = "ORBITING" {
            SET return_dv TO 100.
            SET landing_dv TO aoso_feas_land_cost(home_name).
        } ELSE {
            SET return_dv TO 0.
            SET landing_dv TO 0.
        }
    }

    IF SHIP:STATUS = "PRELAUNCH" {
        SET landing_dv TO 0.
        SET abort_dv TO MAX(abort_dv, 200).
    }

    LOCAL mission_dv IS usable_raw - reserve_dv - landing_dv - return_dv - abort_dv.
    IF mission_dv < 0 { SET mission_dv TO 0. }

    SET AOSO_BUDGET TO LEXICON(
        "total_dv", total_dv,
        "unusable_dv", unusable_dv,
        "reserve_dv", reserve_dv,
        "landing_dv", landing_dv,
        "return_dv", return_dv,
        "abort_dv", abort_dv,
        "mission_dv", mission_dv,
        "body", here_name,
        "refreshed_at", TIME:SECONDS
    ).

    aoso_log_debug("BUDGET", "total=" + ROUND(total_dv, 0) +
        " unusable=" + ROUND(unusable_dv, 0) +
        " reserve=" + ROUND(reserve_dv, 0) +
        " land=" + ROUND(landing_dv, 0) +
        " return=" + ROUND(return_dv, 0) +
        " abort=" + ROUND(abort_dv, 0) +
        " mission=" + ROUND(mission_dv, 0)).

    RETURN AOSO_BUDGET.
}

FUNCTION aoso_budget_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_BUDGET:HASKEY(key) { RETURN AOSO_BUDGET[key]. }
    RETURN default_value.
}
