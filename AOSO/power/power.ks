// AOSO/power/power.ks
// Phase 7 (Refuel & power): ElectricCharge monitoring plus automatic solar
// panel and fuel cell management. Reuses vehicle/resources.ks's generic
// aoso_resource_pct() for the EC percentage (ElectricCharge is just another
// SHIP:RESOURCES entry).
//
// Aero-sensitive hardware (the airstream-shell fairing and the solar panels)
// is only ever deployed once the vessel is clear of the atmosphere -- see
// aoso_power_out_of_atmosphere() -- so nothing is jettisoned or extended into
// the airstream during the climb. Cargo/service bays are deliberately left
// alone (never commanded open) per operator preference.
//
// Solar panels are extended through each ModuleDeployableSolarPanel's own
// "extend" KSPAction (the documented PartModule DOACTION path -- the same
// action a manually-assigned action group would fire), not kOS's PANELS global
// binding, which proved unreliable at actually deploying the panels on the
// as-flown vehicle. Fuel cells still use the FUELCELLS binding, per
// core/addons.ks's "no invented suffixes" stance.

// Current ElectricCharge fill percentage (0-100).
FUNCTION aoso_power_ec_pct {
    RETURN aoso_resource_pct("ElectricCharge").
}

// TRUE if EC has dropped to/below the configured low-power threshold.
FUNCTION aoso_power_ec_low {
    RETURN aoso_power_ec_pct() <= aoso_config_get("LOW_EC_PCT", 20).
}

// Tracks whether we've already commanded the panels out this deploy cycle so
// the per-panel extend action isn't re-fired every tick. Reset on retract.
GLOBAL AOSO_POWER_PANELS_DEPLOYED IS FALSE.

// TRUE once the vessel is clear of the atmosphere (or on an airless body,
// where there's no airstream to protect against). Aero-sensitive hardware --
// the airstream-shell fairing, service/cargo bays and the solar panels they
// enclose -- is only deployed once this is TRUE, so nothing is jettisoned or
// extended into the airstream during the climb.
FUNCTION aoso_power_out_of_atmosphere {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN TRUE. }
    RETURN ALTITUDE > SHIP:BODY:ATM:HEIGHT.
}

// Solar panels are unsafe to have extended at high airspeed inside an
// atmosphere (aero stress risks ripping them off); in vacuum/space or below
// the configured airspeed they're safe to leave deployed, mirroring
// landing/parachute.ks's altitude-vs-ATM:HEIGHT convention for atmosphere
// membership. While still above the atmosphere, this also retracts early
// (predictively) once the current orbit's periapsis already dips inside
// it -- i.e. a deorbit/aerobraking burn has already been made -- so panels
// are stowed well before atmosphere is actually reached instead of only
// reacting once airspeed has already climbed past the threshold.
FUNCTION aoso_power_panels_should_retract {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    IF ALTITUDE > SHIP:BODY:ATM:HEIGHT {
        RETURN PERIAPSIS <= SHIP:BODY:ATM:HEIGHT.
    }
    RETURN SHIP:AIRSPEED > aoso_config_get("PANEL_MAX_AIRSPEED", 50).
}

// TRUE while it's not yet safe to even attempt extending panels, regardless
// of aero considerations: still clamped to the pad pre-launch (SHIP:STATUS
// "PRELAUNCH"), so kOS's PANELS binding either fails outright or the panels
// would be torn off on liftoff anyway. Checked separately from
// aoso_power_panels_should_retract() so a genuine on-pad deploy attempt
// never gets retried (and re-logged) every single scheduler tick.
FUNCTION aoso_power_panels_prelaunch {
    RETURN SHIP:STATUS = "PRELAUNCH".
}

// TRUE while a procedural fairing/canopy (e.g. an AE-FF1/2/3 "Airstream
// Protective Shell") enclosing other hardware still hasn't been jettisoned.
// kOS has no documented global for fairings the way BAYS covers service
// bays, so this checks each ModuleProceduralFairing PartModule's own
// one-shot "Deploy" KSPEvent directly: HASEVENT("Deploy") is only TRUE
// while the fairing hasn't been deployed/jettisoned yet, so this
// automatically stops matching (and this function starts returning FALSE)
// the moment aoso_power_deploy_fairings() below has done its job -- no
// separate "already deployed" bookkeeping flag needed.
FUNCTION aoso_power_fairings_pending {
    IF NOT aoso_vessel_get("has_fairings", FALSE) { RETURN FALSE. }
    FOR fairing_module IN SHIP:MODULESNAMED("ModuleProceduralFairing") {
        IF fairing_module:HASEVENT("Deploy") { RETURN TRUE. }
    }
    RETURN FALSE.
}

// Jettisons every not-yet-deployed procedural fairing/canopy so whatever it
// was enclosing (e.g. solar panels) can subsequently deploy. Safe to call
// repeatedly -- HASEVENT("Deploy") guards each module so an already-fired
// fairing is simply skipped.
FUNCTION aoso_power_deploy_fairings {
    FOR fairing_module IN SHIP:MODULESNAMED("ModuleProceduralFairing") {
        IF fairing_module:HASEVENT("Deploy") {
            fairing_module:DOEVENT("Deploy").
            aoso_log_info("POWER", "Deploying fairing/canopy: " + fairing_module:PART:TITLE + ".").
        }
    }
}

// Fires the first KSPAction on a part module whose (case-insensitive) display
// name contains the given keyword (e.g. "extend"/"retract"), returning TRUE if
// one was found and triggered. Iterating ALLACTIONNAMES and matching a
// substring tolerates the stock name differences across KSP versions/parts
// ("Extend Solar Panel" vs "Extend Panel" etc.) instead of hard-coding one
// exact string HASACTION() would need. DOACTION is the documented, action-
// group-equivalent way to drive a part -- the same thing pressing an action
// key would do.
FUNCTION aoso_power_module_do_action {
    PARAMETER part_module.
    PARAMETER keyword.
    LOCAL kw IS keyword:TOLOWER.
    FOR action_name IN part_module:ALLACTIONNAMES {
        IF action_name:TOLOWER:CONTAINS(kw) {
            part_module:DOACTION(action_name, TRUE).
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

// Extends every solar panel via its own ModuleDeployableSolarPanel "extend"
// action (falling back to a "toggle" action for panels that only expose a
// single toggle), which reliably deploys them where the PANELS global binding
// did not. The PANELS binding is still set as a harmless belt-and-suspenders
// fallback for any panel whose action names don't match. Safe to call once per
// deploy; AOSO_POWER_PANELS_DEPLOYED guards against re-firing every tick.
FUNCTION aoso_power_deploy_panels {
    FOR panel_module IN SHIP:MODULESNAMED("ModuleDeployableSolarPanel") {
        IF NOT aoso_power_module_do_action(panel_module, "extend") {
            aoso_power_module_do_action(panel_module, "toggle").
        }
    }
    SET PANELS TO TRUE.
    SET AOSO_POWER_PANELS_DEPLOYED TO TRUE.
    aoso_log_info("POWER", "Deploying solar panels.").
}

// Retracts every solar panel the same per-module way (with the PANELS binding
// as a fallback), and clears this deploy cycle's bookkeeping so a later
// re-deploy re-extends from scratch.
FUNCTION aoso_power_retract_panels {
    FOR panel_module IN SHIP:MODULESNAMED("ModuleDeployableSolarPanel") {
        IF NOT aoso_power_module_do_action(panel_module, "retract") {
            aoso_power_module_do_action(panel_module, "toggle").
        }
    }
    SET PANELS TO FALSE.
    SET AOSO_POWER_PANELS_DEPLOYED TO FALSE.
    aoso_log_info("POWER", "Retracting solar panels: airspeed=" + ROUND(SHIP:AIRSPEED, 1) + " m/s.").
}

// Idempotent per-tick driver. Retracts aero-exposed panels, and otherwise
// only deploys the fairing/panels once the vessel is clear of the atmosphere
// (aoso_power_out_of_atmosphere), so the airstream shell isn't jettisoned and
// the panels aren't extended into the airstream on the way up. Cargo/service
// bays are deliberately never commanded open (operator preference): the panels
// are extended directly via their own actions. Each step -- jettison fairing,
// extend panels -- runs at most once and yields a tick before the next, so it
// never spams DOACTION calls or log lines.
FUNCTION aoso_power_panels_auto_check {
    IF NOT aoso_vessel_get("has_solar_panels", FALSE) { RETURN. }

    IF aoso_power_panels_should_retract() {
        IF PANELS OR AOSO_POWER_PANELS_DEPLOYED {
            aoso_power_retract_panels().
        }
        RETURN.
    }

    // Not retracting: only ever deploy once we're clear of the atmosphere.
    IF NOT aoso_power_out_of_atmosphere() { RETURN. } // still climbing -- wait for space
    IF aoso_power_panels_prelaunch() { RETURN. }      // still clamped to the pad
    IF PANELS OR AOSO_POWER_PANELS_DEPLOYED { RETURN. } // already deployed

    // Jettison any enclosing airstream-shell fairing first, giving it a tick
    // to separate before extending the panels.
    IF aoso_power_fairings_pending() {
        aoso_power_deploy_fairings().
        RETURN.
    }

    aoso_power_deploy_panels().
}

// Fuel cells (stock ModuleResourceConverter configured as a "Fuel Cell") are
// switched on when EC is low and off again once it recovers past a higher
// threshold, so this doesn't chatter on/off right at the trigger point.
FUNCTION aoso_power_fuelcells_auto_check {
    IF NOT aoso_vessel_get("has_converters", FALSE) { RETURN. }

    LOCAL pct IS aoso_power_ec_pct().
    IF pct <= aoso_config_get("LOW_EC_PCT", 20) AND NOT FUELCELLS {
        SET FUELCELLS TO TRUE.
        aoso_log_info("POWER", "Fuel cells ON: EC=" + ROUND(pct, 1) + "%.").
    } ELSE IF pct >= aoso_config_get("FUEL_CELL_DISABLE_PCT", 90) AND FUELCELLS {
        SET FUELCELLS TO FALSE.
        aoso_log_info("POWER", "Fuel cells OFF: EC=" + ROUND(pct, 1) + "%.").
    }
}

// Single entry point combining both checks; call once per scheduler tick
// (or register via aoso_power_register_task()).
FUNCTION aoso_power_auto_manage {
    aoso_power_panels_auto_check().
    aoso_power_fuelcells_auto_check().
}

// Wires power management into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_power_register_task {
    PARAMETER interval_s IS 1.
    aoso_sched_add("auto_power", interval_s, aoso_power_auto_manage@).
}
