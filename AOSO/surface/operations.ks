// AOSO/surface/operations.ks
// Landed executive: do not drill while sliding, do not launch without
// departure certification, do not always fill to 100%.
//
// Tour calls aoso_surface_begin / aoso_surface_update. Helpers below
// stay public. Do not name FUNCTION aoso_surface (GLOBAL AOSO_SURFACE_LAST).

GLOBAL AOSO_SURFACE_LAST IS LEXICON().

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
    LOCAL nxt IS "".
    LOCAL next_is_isru IS FALSE.
    LOCAL next_is_hard IS FALSE.
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("targets") {
            FOR dest_name IN AOSO_PLAN_LAST["targets"] {
                IF dest_name <> SHIP:BODY:NAME {
                    IF nxt = "" { SET nxt TO dest_name. }
                }
            }
        }
    }
    IF nxt <> "" {
        LOCAL costs IS aoso_project_costs(SHIP:BODY:NAME, nxt).
        SET next_dv TO costs["xfer_only"] + costs["capture"].
        SET next_is_isru TO costs["can_refuel"].
        IF nxt = "Eve" { SET next_is_hard TO TRUE. }
        IF nxt = "Tylo" { SET next_is_hard TO TRUE. }
        IF nxt = "Moho" { SET next_is_hard TO TRUE. }
    }
    LOCAL reserve IS aoso_budget_get("reserve_dv", 200).
    LOCAL corr IS aoso_config_get("CORRECT_LOCAL_DV", 25).
    LOCAL need_dv IS takeoff_dv + next_dv + reserve + corr.
    LOCAL have_dv IS aoso_feas_full_tank_dv().
    LOCAL pct IS fill_full.
    IF have_dv > 50 {
        SET pct TO 100 * need_dv / have_dv.
    }
    IF pct < 40 { SET pct TO 40. }
    IF pct > fill_full { SET pct TO fill_full. }
    IF next_is_isru {
        IF NOT next_is_hard {
            IF pct > 70 { SET pct TO 70. }
        }
    }
    IF next_is_hard {
        IF pct < 85 { SET pct TO 85. }
        IF pct > fill_full { SET pct TO fill_full. }
    }
    IF mode = "TIME" {
        IF pct > 70 { SET pct TO 70. }
        IF pct < 55 { SET pct TO 55. }
    }
    IF mode = "MINIMUM_DV" { SET pct TO fill_full. }
    IF mode = "FUEL" { SET pct TO fill_full. }
    RETURN ROUND(pct, 0).
}

FUNCTION aoso_surface_begin {
    IF SHIP:STATUS <> "LANDED" {
        IF SHIP:STATUS <> "SPLASHED" {
            SET AOSO_SURFACE_LAST TO LEXICON("phase", "NONE", "reason", "not landed").
            RETURN AOSO_SURFACE_LAST.
        }
    }
    IF NOT aoso_surface_stable() {
        SET AOSO_SURFACE_LAST TO LEXICON("phase", "HOLD", "reason", "surface not stable").
        RETURN AOSO_SURFACE_LAST.
    }
    IF NOT aoso_surface_power_ok() {
        SET AOSO_SURFACE_LAST TO LEXICON("phase", "HOLD", "reason", "power low").
        RETURN AOSO_SURFACE_LAST.
    }
    IF aoso_refuel_available() {
        IF aoso_world_has_ore(SHIP:BODY:NAME) {
            LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
            LOCAL need_pct IS aoso_refuel_needed_pct().
            IF fuel_pct < need_pct {
                LOCAL started IS aoso_refuel_start().
                IF started {
                    SET AOSO_SURFACE_LAST TO LEXICON("phase", "REFUEL", "reason", "filling to " + need_pct + "%").
                    RETURN AOSO_SURFACE_LAST.
                }
            }
        }
    }
    SET AOSO_SURFACE_LAST TO LEXICON("phase", "LAUNCH", "reason", "ready to depart").
    RETURN AOSO_SURFACE_LAST.
}

FUNCTION aoso_surface_update {
    IF DEFINED AOSO_REFUEL {
        IF AOSO_REFUEL["current"] <> "" {
            IF AOSO_REFUEL["current"] <> "DONE" {
                IF AOSO_REFUEL["current"] <> "ABORTED" {
                    aoso_refuel_tick().
                    IF aoso_refuel_is_aborted() {
                        SET AOSO_SURFACE_LAST TO LEXICON("phase", "LAUNCH", "reason", "refuel aborted").
                        RETURN AOSO_SURFACE_LAST.
                    }
                    IF aoso_refuel_is_done() {
                        SET AOSO_SURFACE_LAST TO LEXICON("phase", "LAUNCH", "reason", "refuel done").
                        RETURN AOSO_SURFACE_LAST.
                    }
                    SET AOSO_SURFACE_LAST TO LEXICON("phase", "REFUEL", "reason", "harvesting").
                    RETURN AOSO_SURFACE_LAST.
                }
            }
        }
    }
    IF NOT aoso_surface_stable() {
        SET AOSO_SURFACE_LAST TO LEXICON("phase", "HOLD", "reason", "surface not stable").
        RETURN AOSO_SURFACE_LAST.
    }
    SET AOSO_SURFACE_LAST TO LEXICON("phase", "LAUNCH", "reason", "ready to depart").
    RETURN AOSO_SURFACE_LAST.
}

FUNCTION aoso_surface_tick {
    IF DEFINED AOSO_REFUEL {
        IF AOSO_REFUEL["current"] <> "" {
            IF AOSO_REFUEL["current"] <> "DONE" {
                IF AOSO_REFUEL["current"] <> "ABORTED" {
                    RETURN aoso_surface_update().
                }
            }
        }
    }
    RETURN aoso_surface_begin().
}
