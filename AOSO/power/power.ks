// AOSO/power/power.ks
// Phase 7 (Refuel & power): ElectricCharge monitoring plus automatic solar
// panel and fuel cell management. Reuses vehicle/resources.ks's generic
// aoso_resource_pct() for the EC percentage (ElectricCharge is just another
// SHIP:RESOURCES entry) and controls hardware only through kOS's documented
// PANELS/FUELCELLS global bindings (core/addons.ks's "no invented suffixes"
// stance) -- never by guessing at ModuleDeployableSolarPanel/
// ModuleResourceConverter suffixes directly.

// Current ElectricCharge fill percentage (0-100).
FUNCTION aoso_power_ec_pct {
    RETURN aoso_resource_pct("ElectricCharge").
}

// TRUE if EC has dropped to/below the configured low-power threshold.
FUNCTION aoso_power_ec_low {
    RETURN aoso_power_ec_pct() <= aoso_config_get("LOW_EC_PCT", 20).
}

// Solar panels are only unsafe to have extended at high airspeed inside an
// atmosphere (aero stress risks ripping them off); in vacuum/space or below
// the configured airspeed they're always safe to leave deployed, mirroring
// landing/parachute.ks's altitude-vs-ATM:HEIGHT convention for atmosphere
// membership.
FUNCTION aoso_power_panels_should_retract {
    IF NOT SHIP:BODY:ATM:EXISTS { RETURN FALSE. }
    IF ALTITUDE > SHIP:BODY:ATM:HEIGHT { RETURN FALSE. }
    RETURN SHIP:AIRSPEED > aoso_config_get("PANEL_MAX_AIRSPEED", 50).
}

// Idempotent: only touches the PANELS binding when its current state
// disagrees with what's wanted, so this can run every scheduler tick
// without spamming SetGroup calls or log lines.
FUNCTION aoso_power_panels_auto_check {
    IF NOT aoso_vessel_get("has_solar_panels", FALSE) { RETURN. }

    LOCAL should_retract IS aoso_power_panels_should_retract().
    IF should_retract AND PANELS {
        SET PANELS TO FALSE.
        IF DEFINED aoso_log_info { aoso_log_info("POWER", "Retracting solar panels: airspeed=" + ROUND(SHIP:AIRSPEED, 1) + " m/s."). }
    } ELSE IF NOT should_retract AND NOT PANELS {
        SET PANELS TO TRUE.
        IF DEFINED aoso_log_info { aoso_log_info("POWER", "Deploying solar panels."). }
    }
}

// Fuel cells (stock ModuleResourceConverter configured as a "Fuel Cell") are
// switched on when EC is low and off again once it recovers past a higher
// threshold, so this doesn't chatter on/off right at the trigger point.
FUNCTION aoso_power_fuelcells_auto_check {
    IF NOT aoso_vessel_get("has_converters", FALSE) { RETURN. }

    LOCAL pct IS aoso_power_ec_pct().
    IF pct <= aoso_config_get("LOW_EC_PCT", 20) AND NOT FUELCELLS {
        SET FUELCELLS TO TRUE.
        IF DEFINED aoso_log_info { aoso_log_info("POWER", "Fuel cells ON: EC=" + ROUND(pct, 1) + "%."). }
    } ELSE IF pct >= aoso_config_get("FUEL_CELL_DISABLE_PCT", 90) AND FUELCELLS {
        SET FUELCELLS TO FALSE.
        IF DEFINED aoso_log_info { aoso_log_info("POWER", "Fuel cells OFF: EC=" + ROUND(pct, 1) + "%."). }
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
    IF DEFINED aoso_sched_add {
        aoso_sched_add("auto_power", interval_s, aoso_power_auto_manage@).
    }
}
