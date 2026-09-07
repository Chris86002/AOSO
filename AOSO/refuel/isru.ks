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
    FOR name IN target_names {
        IF aoso_resource_pct(name) < target_pct { RETURN FALSE. }
    }
    RETURN TRUE.
}

// TRUE once Ore has run out, i.e. there is nothing left worth mining.
FUNCTION aoso_refuel_ore_depleted {
    RETURN aoso_resource_amount("Ore") <= aoso_config_get("REFUEL_ORE_MIN_AMOUNT", 0.01).
}

FUNCTION aoso_refuel_on_abort {
    PARAMETER data.
    SET DRILLS TO FALSE.
    SET ISRU TO FALSE.
    IF aoso_vessel_get("has_radiators", FALSE) { SET RADIATORS TO FALSE. }
    SET DEPLOYDRILLS TO FALSE.
    aoso_state_transition(AOSO_REFUEL, "ABORTED").
}

FUNCTION aoso_refuel_deploy_entry {
    PARAMETER data.
    SET DEPLOYDRILLS TO TRUE.
    IF aoso_vessel_get("has_radiators", FALSE) { SET RADIATORS TO TRUE. }
    IF DEFINED aoso_log_info { aoso_log_info("REFUEL", "Deploying drills/radiators."). }
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
    IF DEFINED aoso_log_warn { aoso_log_warn("REFUEL", "Drill deploy timed out; starting harvest anyway."). }
    aoso_state_transition(AOSO_REFUEL, "HARVEST").
}

FUNCTION aoso_refuel_harvest_entry {
    PARAMETER data.
    SET DRILLS TO TRUE.
    SET ISRU TO TRUE.
    IF DEFINED aoso_log_info { aoso_log_info("REFUEL", "Harvesting/converting started."). }
}

FUNCTION aoso_refuel_harvest_execute {
    PARAMETER data.
    IF aoso_refuel_ore_depleted() {
        IF DEFINED aoso_log_warn { aoso_log_warn("REFUEL", "Ore depleted before targets were full."). }
        aoso_state_transition(AOSO_REFUEL, "STOW").
        RETURN.
    }
    IF aoso_refuel_targets_full(data["targets"]) {
        aoso_state_transition(AOSO_REFUEL, "STOW").
    }
}

FUNCTION aoso_refuel_stow_entry {
    PARAMETER data.
    SET DRILLS TO FALSE.
    SET ISRU TO FALSE.
    IF aoso_vessel_get("has_radiators", FALSE) { SET RADIATORS TO FALSE. }
    SET DEPLOYDRILLS TO FALSE.
    IF DEFINED aoso_log_info { aoso_log_info("REFUEL", "Harvest complete; drills/converters stowed."). }
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
        IF DEFINED aoso_log_warn { aoso_log_warn("REFUEL", "No harvester/converter aboard; refuel not started."). }
        RETURN FALSE.
    }

    aoso_state_define(AOSO_REFUEL, "DEPLOY", aoso_refuel_deploy_entry@, aoso_refuel_deploy_execute@, 0, 15, aoso_refuel_deploy_on_timeout@, aoso_refuel_on_abort@).
    aoso_state_define(AOSO_REFUEL, "HARVEST", aoso_refuel_harvest_entry@, aoso_refuel_harvest_execute@, 0, 0, 0, aoso_refuel_on_abort@).
    aoso_state_define(AOSO_REFUEL, "STOW", aoso_refuel_stow_entry@, 0, 0).
    aoso_state_define(AOSO_REFUEL, "DONE", 0, 0, 0).
    aoso_state_define(AOSO_REFUEL, "ABORTED", 0, 0, 0).

    SET AOSO_REFUEL["data"] TO LEXICON("targets", target_names).
    aoso_state_transition(AOSO_REFUEL, "DEPLOY").
    IF DEFINED aoso_log_info { aoso_log_info("REFUEL", "Refuel sequence started."). }
    RETURN TRUE.
}

FUNCTION aoso_refuel_tick {
    aoso_state_update(AOSO_REFUEL).
}

// Wires the refuel tick into core/scheduler.ks, mirroring
// landing/descent.ks's aoso_descent_register_task().
FUNCTION aoso_refuel_register_task {
    PARAMETER interval_s IS 1.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("refuel_isru", interval_s, aoso_refuel_tick@).
    }
}
