// AOSO/mission/project.ks
// Projected vehicle state. Simulates sequential operations against a
// dV ledger. Does not fly the ship. Feasibility, certification,
// assurance and 1-hop lookahead consume this; they must not each keep
// a second copy of remaining dV.
//
// Do not name FUNCTION aoso_project — GLOBAL AOSO_PROJECT_LAST would
// collide (kOS identifiers are case-insensitive).

GLOBAL AOSO_PROJECT_LAST IS LEXICON().

FUNCTION aoso_project_state_blank {
    RETURN LEXICON(
        "body", "",
        "situation", "ORBITING",
        "mass", 0,
        "fuel_mass", 0,
        "fuel_pct", 0,
        "dv_remaining", 0,
        "reserve_remaining", 0,
        "topology_revision", 0,
        "configuration_id", "",
        "refueled", FALSE,
        "landed", FALSE,
        "orbiting", TRUE,
        "ok", TRUE,
        "fail_step", "",
        "last_step", "",
        "last_cost", 0,
        "confidence", 0.5
    ).
}

FUNCTION aoso_project_clone {
    PARAMETER state.
    RETURN LEXICON(
        "body", state["body"],
        "situation", state["situation"],
        "mass", state["mass"],
        "fuel_mass", state["fuel_mass"],
        "fuel_pct", state["fuel_pct"],
        "dv_remaining", state["dv_remaining"],
        "reserve_remaining", state["reserve_remaining"],
        "topology_revision", state["topology_revision"],
        "configuration_id", state["configuration_id"],
        "refueled", state["refueled"],
        "landed", state["landed"],
        "orbiting", state["orbiting"],
        "ok", state["ok"],
        "fail_step", state["fail_step"],
        "last_step", state["last_step"],
        "last_cost", state["last_cost"],
        "confidence", state["confidence"]
    ).
}

FUNCTION aoso_project_state_current {
    LOCAL st IS aoso_project_state_blank().
    SET st["body"] TO SHIP:BODY:NAME.
    SET st["situation"] TO SHIP:STATUS.
    SET st["mass"] TO SHIP:MASS.
    SET st["fuel_pct"] TO aoso_resource_pct("LiquidFuel").
    SET st["dv_remaining"] TO aoso_budget_get("mission_dv", 0).
    SET st["reserve_remaining"] TO aoso_budget_get("reserve_dv", 0).
    IF DEFINED AOSO_CTX {
        SET st["topology_revision"] TO aoso_ctx_get("rev_topo", 0).
        SET st["configuration_id"] TO aoso_ctx_get("cfg_id", "").
    }
    LOCAL landed_now IS FALSE.
    IF SHIP:STATUS = "LANDED" { SET landed_now TO TRUE. }
    IF SHIP:STATUS = "SPLASHED" { SET landed_now TO TRUE. }
    IF SHIP:STATUS = "PRELAUNCH" { SET landed_now TO TRUE. }
    SET st["landed"] TO landed_now.
    SET st["orbiting"] TO NOT landed_now.
    RETURN st.
}

FUNCTION aoso_project_apply_cost {
    PARAMETER state.
    PARAMETER step_name.
    PARAMETER dv_cost.
    LOCAL nxt IS aoso_project_clone(state).
    SET nxt["last_step"] TO step_name.
    SET nxt["last_cost"] TO dv_cost.
    IF NOT nxt["ok"] { RETURN nxt. }
    SET nxt["dv_remaining"] TO nxt["dv_remaining"] - dv_cost.
    IF nxt["dv_remaining"] < 0 {
        SET nxt["ok"] TO FALSE.
        SET nxt["fail_step"] TO step_name.
    }
    RETURN nxt.
}

// Split transfer_cost (which already includes dest capture) so capture
// is not deducted twice. Public so feasibility and tests share one rule.
FUNCTION aoso_project_xfer_only {
    PARAMETER transfer_dv.
    PARAMETER capture_dv.
    IF capture_dv <= 0 { RETURN transfer_dv. }
    IF transfer_dv >= capture_dv { RETURN transfer_dv - capture_dv. }
    RETURN transfer_dv.
}

// Deterministic sequential ledger. No SHIP reads. Used by feasibility
// and selftest. land_dv is only paid if orbit succeeded; takeoff only
// if land succeeded (or do_refuel after a successful land).
FUNCTION aoso_project_seq {
    PARAMETER start_dv.
    PARAMETER transfer_dv.
    PARAMETER capture_dv.
    PARAMETER land_dv.
    PARAMETER takeoff_dv.
    PARAMETER do_refuel IS FALSE.
    PARAMETER full_tank IS 0.

    LOCAL remain IS start_dv.
    LOCAL leftover IS start_dv.
    LOCAL reach IS FALSE.
    LOCAL orbit_ok IS FALSE.
    LOCAL land_ok IS FALSE.
    LOCAL takeoff_ok IS FALSE.
    LOCAL fail_step IS "".

    SET remain TO remain - transfer_dv.
    IF remain >= 0 {
        SET reach TO TRUE.
        SET leftover TO remain.
    } ELSE {
        SET fail_step TO "TRANSFER".
    }

    IF reach {
        SET remain TO remain - capture_dv.
        IF remain >= 0 {
            SET orbit_ok TO TRUE.
            SET leftover TO remain.
        } ELSE {
            SET fail_step TO "CAPTURE".
        }
    }

    IF orbit_ok {
        SET remain TO remain - land_dv.
        IF remain >= 0 {
            SET land_ok TO TRUE.
            SET leftover TO remain.
        } ELSE {
            SET fail_step TO "LAND".
        }
    }

    IF land_ok {
        IF do_refuel {
            IF full_tank > 0 {
                SET remain TO full_tank.
            } ELSE {
                SET remain TO start_dv.
            }
            SET leftover TO remain.
        }
        SET remain TO remain - takeoff_dv.
        IF remain >= 0 {
            SET takeoff_ok TO TRUE.
            SET leftover TO remain.
        } ELSE {
            SET fail_step TO "TAKEOFF".
        }
    }

    RETURN LEXICON(
        "can_reach", reach,
        "can_orbit", orbit_ok,
        "can_land", land_ok,
        "can_takeoff", takeoff_ok,
        "leftover", leftover,
        "fail_step", fail_step,
        "dv_after_transfer", start_dv - transfer_dv,
        "dv_after_capture", start_dv - transfer_dv - capture_dv
    ).
}

FUNCTION aoso_project_costs {
    PARAMETER from_name.
    PARAMETER dest_name.
    LOCAL margin IS aoso_config_get("FEAS_DV_MARGIN", 1.15).
    LOCAL transfer_raw IS aoso_feas_transfer_cost(from_name, dest_name).
    LOCAL capture_raw IS 0.
    IF from_name <> dest_name {
        SET capture_raw TO aoso_feas_body_stat(dest_name, "capture", 0).
    }
    LOCAL land_raw IS aoso_feas_land_cost(dest_name).
    LOCAL takeoff_raw IS aoso_feas_takeoff_cost(dest_name).
    IF DEFINED AOSO_XP {
        SET transfer_raw TO aoso_xp_apply("TRANSFER", dest_name, transfer_raw).
        SET capture_raw TO aoso_xp_apply("CAPTURE", dest_name, capture_raw).
        SET land_raw TO aoso_xp_apply("LANDING", dest_name, land_raw).
        SET takeoff_raw TO aoso_xp_apply("TAKEOFF", dest_name, takeoff_raw).
    }
    LOCAL transfer_dv IS transfer_raw * margin.
    LOCAL capture_dv IS capture_raw * margin.
    LOCAL xfer_only IS aoso_project_xfer_only(transfer_dv, capture_dv).
    LOCAL can_refuel IS FALSE.
    IF aoso_profile_capable("can_isru") {
        IF aoso_world_has_ore(dest_name) { SET can_refuel TO TRUE. }
    }
    RETURN LEXICON(
        "xfer_only", xfer_only,
        "capture", capture_dv,
        "land", land_raw * margin,
        "takeoff", takeoff_raw * margin,
        "transfer", transfer_dv,
        "can_refuel", can_refuel
    ).
}

FUNCTION aoso_project_transfer {
    PARAMETER state.
    PARAMETER dest_name.
    LOCAL costs IS aoso_project_costs(state["body"], dest_name).
    LOCAL nxt IS aoso_project_apply_cost(state, "TRANSFER", costs["xfer_only"]).
    RETURN nxt.
}

FUNCTION aoso_project_capture {
    PARAMETER state.
    PARAMETER dest_name.
    LOCAL costs IS aoso_project_costs(state["body"], dest_name).
    LOCAL nxt IS aoso_project_apply_cost(state, "CAPTURE", costs["capture"]).
    SET nxt["body"] TO dest_name.
    SET nxt["orbiting"] TO TRUE.
    SET nxt["landed"] TO FALSE.
    SET nxt["situation"] TO "ORBITING".
    RETURN nxt.
}

FUNCTION aoso_project_land {
    PARAMETER state.
    PARAMETER dest_name.
    LOCAL costs IS aoso_project_costs(state["body"], dest_name).
    LOCAL nxt IS aoso_project_apply_cost(state, "LAND", costs["land"]).
    SET nxt["body"] TO dest_name.
    SET nxt["landed"] TO TRUE.
    SET nxt["orbiting"] TO FALSE.
    SET nxt["situation"] TO "LANDED".
    RETURN nxt.
}

FUNCTION aoso_project_refuel {
    PARAMETER state.
    PARAMETER dest_name.
    LOCAL nxt IS aoso_project_clone(state).
    LOCAL full_tank IS aoso_feas_full_tank_dv().
    LOCAL reserve_dv IS aoso_budget_get("reserve_dv", 0).
    LOCAL tank_mission IS full_tank - reserve_dv.
    IF tank_mission < 0 { SET tank_mission TO 0. }
    SET nxt["dv_remaining"] TO tank_mission.
    SET nxt["refueled"] TO TRUE.
    SET nxt["fuel_pct"] TO aoso_config_get("REFUEL_TARGET_PCT", 95).
    SET nxt["last_step"] TO "REFUEL".
    SET nxt["last_cost"] TO 0.
    SET nxt["ok"] TO TRUE.
    SET nxt["fail_step"] TO "".
    SET nxt["body"] TO dest_name.
    SET nxt["landed"] TO TRUE.
    RETURN nxt.
}

FUNCTION aoso_project_takeoff {
    PARAMETER state.
    PARAMETER dest_name.
    LOCAL costs IS aoso_project_costs(state["body"], dest_name).
    LOCAL nxt IS aoso_project_apply_cost(state, "TAKEOFF", costs["takeoff"]).
    SET nxt["landed"] TO FALSE.
    SET nxt["orbiting"] TO TRUE.
    SET nxt["situation"] TO "ORBITING".
    SET nxt["body"] TO dest_name.
    RETURN nxt.
}

FUNCTION aoso_project_return {
    PARAMETER state.
    LOCAL home_name IS aoso_config_get("HOME_BODY", "Kerbin").
    LOCAL costs IS aoso_project_costs(state["body"], home_name).
    LOCAL nxt IS aoso_project_apply_cost(state, "RETURN", costs["transfer"]).
    IF nxt["ok"] {
        SET nxt["body"] TO home_name.
        SET nxt["orbiting"] TO TRUE.
        SET nxt["landed"] TO FALSE.
        SET nxt["situation"] TO "ORBITING".
    }
    RETURN nxt.
}

// One destination from a rolling state. Consumes previous leftover.
FUNCTION aoso_project_leg {
    PARAMETER state.
    PARAMETER dest_name.
    LOCAL costs IS aoso_project_costs(state["body"], dest_name).
    LOCAL nxt IS aoso_project_apply_cost(state, "TRANSFER", costs["xfer_only"]).
    IF nxt["ok"] {
        SET nxt TO aoso_project_apply_cost(nxt, "CAPTURE", costs["capture"]).
    }
    IF nxt["ok"] {
        SET nxt["body"] TO dest_name.
        SET nxt["orbiting"] TO TRUE.
        SET nxt["landed"] TO FALSE.
        SET nxt["situation"] TO "ORBITING".
        SET nxt TO aoso_project_apply_cost(nxt, "LAND", costs["land"]).
    }
    IF nxt["ok"] {
        SET nxt["landed"] TO TRUE.
        SET nxt["orbiting"] TO FALSE.
        SET nxt["situation"] TO "LANDED".
        IF costs["can_refuel"] {
            SET nxt TO aoso_project_refuel(nxt, dest_name).
        }
        SET nxt TO aoso_project_takeoff(nxt, dest_name).
    }
    RETURN nxt.
}

// Walk remaining plan targets from the live ship. Cheap arithmetic;
// call from planner / assurance, never from a critical flight tick.
FUNCTION aoso_project_route {
    LOCAL order IS LIST().
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("targets") { SET order TO AOSO_PLAN_LAST["targets"]. }
    }
    IF order:LENGTH = 0 {
        IF DEFINED AOSO_ROUTE_LAST {
            IF AOSO_ROUTE_LAST:HASKEY("order") { SET order TO AOSO_ROUTE_LAST["order"]. }
        }
    }
    LOCAL st IS aoso_project_state_current().
    LOCAL hop IS aoso_budget_get("mission_dv", 0).
    LOCAL full_tank IS aoso_feas_full_tank_dv().
    LOCAL reserve_dv IS aoso_budget_get("reserve_dv", 0).
    LOCAL tank_mission IS full_tank - reserve_dv.
    IF tank_mission < 0 { SET tank_mission TO 0. }
    IF tank_mission > hop { SET hop TO tank_mission. }
    SET st["dv_remaining"] TO hop.

    LOCAL legs IS LEXICON().
    LOCAL weakest IS "".
    LOCAL worst IS 99999.
    LOCAL min_twr IS 99.
    LOCAL next_refuel IS "".
    LOCAL ok_all IS TRUE.
    FOR dest_name IN order {
        LOCAL before IS st["dv_remaining"].
        SET st TO aoso_project_leg(st, dest_name).
        LOCAL margin IS st["dv_remaining"].
        IF NOT st["ok"] {
            SET margin TO st["dv_remaining"].
            SET ok_all TO FALSE.
        }
        SET legs[dest_name] TO LEXICON(
            "have_in", before,
            "leftover_out", st["dv_remaining"],
            "margin", margin,
            "ok", st["ok"],
            "fail_step", st["fail_step"],
            "refueled", st["refueled"]
        ).
        IF margin < worst {
            SET worst TO margin.
            SET weakest TO dest_name.
        }
        LOCAL costs IS aoso_project_costs(st["body"], dest_name).
        IF costs["can_refuel"] {
            IF next_refuel = "" { SET next_refuel TO dest_name. }
        }
    }
    LOCAL twr_home IS 0.
    IF DEFINED AOSO_CAPS {
        SET twr_home TO aoso_caps_get("twr", 0).
    }
    SET AOSO_PROJECT_LAST TO LEXICON(
        "order", order,
        "legs", legs,
        "weakest", weakest,
        "min_margin", worst,
        "min_twr", twr_home,
        "next_refuel", next_refuel,
        "ok", ok_all,
        "end_dv", st["dv_remaining"],
        "end_body", st["body"],
        "at", TIME:SECONDS
    ).
    RETURN AOSO_PROJECT_LAST.
}

FUNCTION aoso_project_lookahead_bonus {
    PARAMETER dest_name.
    LOCAL bonus IS 0.
    IF NOT AOSO_PROJECT_LAST:HASKEY("legs") { RETURN 0. }
    IF NOT AOSO_PROJECT_LAST["legs"]:HASKEY(dest_name) { RETURN 0. }
    LOCAL leg IS AOSO_PROJECT_LAST["legs"][dest_name].
    LOCAL leftover IS leg["leftover_out"].
    IF leftover >= 1500 { SET bonus TO bonus + 8. }
    ELSE {
        IF leftover >= 600 { SET bonus TO bonus + 3. }
        ELSE {
            IF leftover < 0 { SET bonus TO bonus - 12. }
        }
    }
    IF NOT leg["ok"] { SET bonus TO bonus - 10. }
    RETURN bonus.
}
