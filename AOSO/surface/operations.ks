// AOSO/surface/operations.ks
// Landed executive: do not drill while sliding, do not launch without
// departure certification, do not always fill to 100%.

FUNCTION aoso_surface_stable {
    IF SHIP:STATUS <> "LANDED" {
        IF SHIP:STATUS <> "SPLASHED" { RETURN FALSE. }
    }
    IF SHIP:VELOCITY:SURFACE:MAG > 0.35 { RETURN FALSE. }
    IF ABS(VERTICALSPEED) > 0.25 { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_surface_power_ok {
    LOCAL ec IS aoso_power_ec_pct().
    IF ec >= 12 { RETURN TRUE. }
    LOCAL solar IS aoso_topo_hw_get("solar", 0).
    IF solar > 0 {
        IF ec >= 5 { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_refuel_needed_pct {
    LOCAL fill_full IS aoso_config_get("REFUEL_TARGET_PCT", 95).
    LOCAL mode IS aoso_config_get("OPTIMIZATION_MODE", "BALANCED").
    LOCAL takeoff_dv IS aoso_feas_takeoff_cost(SHIP:BODY:NAME).
    LOCAL next_dv IS 0.
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("targets") {
            IF AOSO_PLAN_LAST["targets"]:LENGTH > 0 {
                LOCAL nxt IS AOSO_PLAN_LAST["targets"][0].
                SET next_dv TO aoso_feas_transfer_cost(SHIP:BODY:NAME, nxt).
            }
        }
    }
    LOCAL reserve IS aoso_budget_get("reserve_dv", 200).
    LOCAL need_dv IS takeoff_dv + next_dv + reserve.
    LOCAL have_dv IS aoso_feas_full_tank_dv().
    LOCAL pct IS fill_full.
    IF have_dv > 50 {
        SET pct TO 100 * need_dv / have_dv.
    }
    IF pct < 40 { SET pct TO 40. }
    IF pct > fill_full { SET pct TO fill_full. }
    IF mode = "TIME" {
        IF pct > 70 { SET pct TO 70. }
        IF pct < 55 { SET pct TO 55. }
    }
    IF mode = "MINIMUM_DV" { SET pct TO fill_full. }
    IF mode = "FUEL" { SET pct TO fill_full. }
    RETURN ROUND(pct, 0).
}
