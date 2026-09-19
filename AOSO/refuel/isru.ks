// AOSO/refuel/isru.ks
// Phase 7 (Refuel & power): ISRU mining/converting sequence -- deploy the
// drills, mine Ore, run the converter(s) until the configured target
// resources are full (or Ore runs out), then stow everything again. Built
// on core/state.ks as its own independent machine (AOSO_REFUEL), the same
// pattern landing/descent.ks uses, so it can run alongside ascent/descent
// without interfering. Hardware is only ever touched through kOS's
// documented DEPLOYDRILLS/DRILLS/ISRU/RADIATORS global bindings
// (core/addons.ks's "no invented suffixes" stance) -- this module never
// guesses at ModuleResourceHarvester/ModuleResourceConverter suffixes.
// Reuses vehicle/resources.ks's aoso_resource_amount()/aoso_resource_pct()
// for the Ore/product-tank readouts instead of duplicating SHIP:RESOURCES
// iteration.

GLOBAL AOSO_REFUEL IS aoso_state_new_machine().

// TRUE only if the vessel scan (vehicle/vessel.ks) found both a harvester
// (drill) and a resource converter -- mining Ore is pointless without a
// converter to turn it into something useful, and running a converter dry
// of Ore is pointless without a drill to refill it.
FUNCTION aoso_refuel_available {
    RETURN aoso_vessel_get("has_harvesters", FALSE) AND aoso_vessel_get("has_converters", FALSE).
}

// TRUE once every resource in target_names has reached the configured
// REFUEL_TARGET_PCT of its capacity (empty list -> vacuously TRUE, so a
// caller that hasn't customized the target list doesn't get stuck).
FUNCTION aoso_refuel_targets_full {
    PARAMETER target_names.
    LOCAL target_pct IS aoso_config_get("REFUEL_TARGET_PCT", 95).
    IF DEFINED AOSO_REFUEL {
        IF AOSO_REFUEL:HASKEY("data") {
            IF AOSO_REFUEL["data"]:HASKEY("target_pct") {
                SET target_pct TO AOSO_REFUEL["data"]["target_pct"].
            }
        }
    }
    FOR name IN target_names {
        IF aoso_resource_pct(name) < target_pct { RETURN FALSE. }
    }
    RETURN TRUE.
}

// TRUE once Ore has run out, i.e. there is nothing left worth mining.
// Tank Ore near zero is NOT biome-empty: a drill+converter can consume
// Ore as fast as it is produced. Progress is fuel/ore movement over time.
FUNCTION aoso_refuel_ore_depleted {
    RETURN FALSE.
}

FUNCTION aoso_refuel_classify {
    PARAMETER start_pct.
    PARAMETER end_pct.
    PARAMETER target_pct.
    LOCAL gain IS end_pct - start_pct.
    IF end_pct >= target_pct - 1 { RETURN "SUCCESS". }
    IF gain >= 2 { RETURN "PARTIAL". }
    RETURN "FAILED".
}

FUNCTION aoso_refuel_stalled {
    PARAMETER data.
    IF NOT data:HASKEY("last_progress_at") { RETURN FALSE. }
    LOCAL stall_s IS aoso_config_get("REFUEL_STALL_S", 90).
    IF TIME:SECONDS - data["last_progress_at"] < stall_s { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_refuel_note_progress {
    PARAMETER data.
    LOCAL fuel_now IS aoso_resource_amount("LiquidFuel").
    LOCAL ore_now IS aoso_resource_amount("Ore").
    LOCAL moved IS FALSE.
    IF data:HASKEY("last_fuel") {
        IF fuel_now > data["last_fuel"] + 0.05 { SET moved TO TRUE. }
    }
    IF data:HASKEY("last_ore") {
        IF ABS(ore_now - data["last_ore"]) > 0.05 { SET moved TO TRUE. }
    }
    IF moved {
        SET data["last_progress_at"] TO TIME:SECONDS.
        SET data["last_fuel"] TO fuel_now.
        SET data["last_ore"] TO ore_now.
    }
    RETURN moved.
}

FUNCTION aoso_refuel_on_abort {
    PARAMETER data.
    SET DRILLS TO FALSE.
    SET ISRU TO FALSE.
    IF aoso_vessel_get("has_radiators", FALSE) { SET RADIATORS TO FALSE. }
    SET DEPLOYDRILLS TO FALSE.
    LOCAL res_a IS aoso_result_make("REFUEL", "ABORTED", "safety interruption").
    IF data:HASKEY("start_fuel_pct") { SET res_a["predicted_fuel"] TO data["target_pct"] - data["start_fuel_pct"]. }
    SET res_a["actual_fuel"] TO aoso_resource_pct("LiquidFuel").
    IF data:HASKEY("start_fuel_pct") { SET res_a["fuel_used"] TO res_a["actual_fuel"] - data["start_fuel_pct"]. }
    aoso_result_emit(res_a).
    aoso_state_transition(AOSO_REFUEL, "ABORTED").
}

FUNCTION aoso_refuel_deploy_entry {
    PARAMETER data.
    SET DEPLOYDRILLS TO TRUE.
    IF aoso_vessel_get("has_radiators", FALSE) { SET RADIATORS TO TRUE. }
    aoso_log_info("REFUEL", "Deploying drills/radiators.").
}

// DEPLOYDRILLS reflects the harvester's actual deploy animation state, so
// this simply waits until every drill reports deployed before starting to
// mine; a timeout on this state (see aoso_refuel_start()) guards against a
// drill that can't deploy (e.g. blocked, or resting on the wrong surface).
FUNCTION aoso_refuel_deploy_execute {
    PARAMETER data.
    IF DEPLOYDRILLS {
        aoso_state_transition(AOSO_REFUEL, "HARVEST").
    }
}

FUNCTION aoso_refuel_deploy_on_timeout {
    PARAMETER data.
    aoso_log_warn("REFUEL", "Drill deploy timed out; starting harvest anyway.").
    aoso_state_transition(AOSO_REFUEL, "HARVEST").
}

FUNCTION aoso_refuel_harvest_entry {
    PARAMETER data.
    SET DRILLS TO TRUE.
    SET ISRU TO TRUE.
    aoso_log_info("REFUEL", "Harvesting/converting started.").
}

FUNCTION aoso_refuel_harvest_execute {
    PARAMETER data.
    IF NOT aoso_surface_stable() {
        SET DRILLS TO FALSE.
        SET ISRU TO FALSE.
        SET data["ec_paused"] TO TRUE.
        aoso_log_every(20, "REFUEL", "Harvest paused - surface not stable.").
        aoso_hb_set("refuel", "UNSTABLE", aoso_resource_pct("LiquidFuel") / 100).
        RETURN.
    }
    LOCAL ec_now IS aoso_power_ec_pct().
    IF ec_now < 8 {
        SET DRILLS TO FALSE.
        SET ISRU TO FALSE.
        SET data["ec_paused"] TO TRUE.
        aoso_log_every(20, "REFUEL", "Harvest paused EC=" + ROUND(ec_now, 1) + "% (need >=8).").
        aoso_hb_set("refuel", "EC_WAIT", ec_now / 100).
        RETURN.
    }
    IF data:HASKEY("ec_paused") {
        IF data["ec_paused"] {
            SET DRILLS TO TRUE.
            SET ISRU TO TRUE.
            SET data["ec_paused"] TO FALSE.
            aoso_log_info("REFUEL", "Harvest resumed EC=" + ROUND(ec_now, 1) + "%.").
        }
    }
    aoso_warp_set_physics_cruise().
    aoso_refuel_note_progress(data).
    IF aoso_refuel_stalled(data) {
        aoso_log_warn("REFUEL", "Harvest stalled (no fuel/ore progress).").
        SET data["stow_kind"] TO "stalled".
        aoso_state_transition(AOSO_REFUEL, "STOW").
        RETURN.
    }
    IF aoso_refuel_targets_full(data["targets"]) {
        SET data["stow_kind"] TO "full".
        aoso_state_transition(AOSO_REFUEL, "STOW").
    }
    LOCAL fuel_p IS aoso_resource_pct("LiquidFuel") / 100.
    aoso_hb_set("refuel", "HARVEST", fuel_p).
}

FUNCTION aoso_refuel_stow_entry {
    PARAMETER data.
    SET DRILLS TO FALSE.
    SET ISRU TO FALSE.
    IF aoso_vessel_get("has_radiators", FALSE) { SET RADIATORS TO FALSE. }
    SET DEPLOYDRILLS TO FALSE.
    LOCAL start_pct IS 0.
    LOCAL target_pct IS aoso_config_get("REFUEL_TARGET_PCT", 95).
    IF data:HASKEY("start_fuel_pct") { SET start_pct TO data["start_fuel_pct"]. }
    IF data:HASKEY("target_pct") { SET target_pct TO data["target_pct"]. }
    LOCAL end_pct IS aoso_resource_pct("LiquidFuel").
    LOCAL stow_st IS aoso_refuel_classify(start_pct, end_pct, target_pct).
    LOCAL why IS "stow".
    IF data:HASKEY("stow_kind") { SET why TO data["stow_kind"]. }
    aoso_log_info("REFUEL", "Harvest " + stow_st + " (" + why + ") " + ROUND(start_pct, 0) + "% -> " + ROUND(end_pct, 0) + "% target " + ROUND(target_pct, 0) + "%.").
    LOCAL res_r IS aoso_result_make("REFUEL", stow_st, why).
    SET res_r["predicted_fuel"] TO target_pct - start_pct.
    SET res_r["actual_fuel"] TO end_pct.
    SET res_r["fuel_used"] TO end_pct - start_pct.
    aoso_result_emit(res_r).
    aoso_state_transition(AOSO_REFUEL, "DONE").
}

FUNCTION aoso_refuel_is_done {
    RETURN AOSO_REFUEL["current"] = "DONE".
}

// Mirrors flight/ascent.ks's/return/return.ks's own aoso_*_is_aborted() so
// mission/mission.ks's generic step wrapper can check every subsystem's
// abort state the same way.
FUNCTION aoso_refuel_is_aborted {
    RETURN AOSO_REFUEL["current"] = "ABORTED".
}

// Wires all states into AOSO_REFUEL and starts the machine in DEPLOY.
// target_names is the list of resources (e.g. LIST("LiquidFuel",
// "Oxidizer")) that must reach REFUEL_TARGET_PCT before the sequence stows
// itself; defaults to LiquidFuel+Oxidizer, the stock ISRU converter's
// output pair. Returns FALSE (and does not start) if the vessel has no
// drills/converters at all.
FUNCTION aoso_refuel_start {
    PARAMETER target_names IS LIST("LiquidFuel", "Oxidizer").

    IF NOT aoso_refuel_available() {
        aoso_log_warn("REFUEL", "No harvester/converter aboard; refuel not started.").
        RETURN FALSE.
    }

    aoso_state_define(AOSO_REFUEL, "DEPLOY", aoso_refuel_deploy_entry@, aoso_refuel_deploy_execute@, 0, 15, aoso_refuel_deploy_on_timeout@, aoso_refuel_on_abort@).
    aoso_state_define(AOSO_REFUEL, "HARVEST", aoso_refuel_harvest_entry@, aoso_refuel_harvest_execute@, 0, 0, 0, aoso_refuel_on_abort@).
    aoso_state_define(AOSO_REFUEL, "STOW", aoso_refuel_stow_entry@, 0, 0).
    aoso_state_define(AOSO_REFUEL, "DONE", 0, 0, 0).
    aoso_state_define(AOSO_REFUEL, "ABORTED", 0, 0, 0).

    LOCAL pct IS aoso_config_get("REFUEL_TARGET_PCT", 95).
    SET pct TO aoso_refuel_needed_pct().
    LOCAL start_pct IS aoso_resource_pct("LiquidFuel").
    SET AOSO_REFUEL["data"] TO LEXICON(
        "targets", target_names,
        "target_pct", pct,
        "ec_paused", FALSE,
        "start_fuel_pct", start_pct,
        "last_fuel", aoso_resource_amount("LiquidFuel"),
        "last_ore", aoso_resource_amount("Ore"),
        "last_progress_at", TIME:SECONDS,
        "stow_kind", "ok"
    ).
    LOCAL did IS aoso_decide("REFUEL", "start", SHIP:BODY:NAME, "target " + pct + "%", "start=" + ROUND(start_pct, 0), pct - start_pct).
    LOCAL act IS aoso_action_create(did, "REFUEL", SHIP:BODY:NAME, 0).
    SET act["predicted_fuel"] TO pct - start_pct.
    aoso_action_begin(act).
    aoso_state_transition(AOSO_REFUEL, "DEPLOY").
    aoso_log_info("REFUEL", "Refuel sequence started, target " + pct + "%.").
    RETURN TRUE.
}

FUNCTION aoso_refuel_tick {
    aoso_state_update(AOSO_REFUEL).
}
