// AOSO/vehicle/profile.ks
// Vehicle intelligence layer. Discovers what the vessel actually is --
// structure, propulsion, power, mobility, ISRU, navigation, mission
// hardware -- then derives a capability profile with confidence scores.
// Mission code asks "what can this ship do?" instead of hard-coding a
// ship type.
//
// Continuously re-profiles: a scheduler task compares a structured
// snapshot (parts, engines, tanks, mass, stages, docking, drills, solar,
// status, control point, thrust) and only rebuilds the subsystem that
// actually changed -- mass/fuel → dV budget; engine/stage/parts → full
// profile. Staging still calls aoso_profile_refresh() directly.
//
// Every suffix used here is a documented stock kOS Part / Vessel suffix
// or PART:HASMODULE, matching vehicle/vessel.ks's "no invented suffixes"
// stance. The scanned profile is JSON-safe and persisted to PROFILE_FILE.

// kOS identifiers are case-insensitive: a GLOBAL and a FUNCTION must
// never share a name (AOSO_PROFILE_SNAPSHOT vs aoso_profile_snapshot()
// compiles to "Cannot find label ...`0-default"). The last snapshot is
// therefore AOSO_PROFILE_LAST_SNAP, not AOSO_PROFILE_SNAPSHOT.

GLOBAL AOSO_PROFILE IS LEXICON().
GLOBAL AOSO_PROFILE_LAST_MASS IS 0.
GLOBAL AOSO_PROFILE_LAST_SNAP IS LEXICON().

FUNCTION aoso_profile_snapshot {
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL doclist IS LIST().
    LIST DOCKINGPORTS IN doclist.
    LOCAL tank_n IS 0.
    LOCAL drill_n IS 0.
    LOCAL solar_n IS 0.
    FOR p IN plist {
        IF p:HASMODULE("ModuleDeployableSolarPanel") { SET solar_n TO solar_n + 1. }
        IF p:HASMODULE("ModuleResourceHarvester") { SET drill_n TO drill_n + 1. }
        LOCAL has_tank IS FALSE.
        FOR res_item IN p:RESOURCES {
            IF aoso_capabilities_is_propellant(res_item:NAME) {
                IF res_item:CAPACITY > 0 { SET has_tank TO TRUE. }
            }
        }
        IF has_tank { SET tank_n TO tank_n + 1. }
    }
    LOCAL control_id IS "".
    IF SHIP:CONTROLPART:ISTYPE("Part") { SET control_id TO "" + SHIP:CONTROLPART:UID. }
    RETURN LEXICON(
        "parts", plist:LENGTH,
        "engines", elist:LENGTH,
        "tanks", tank_n,
        "mass", SHIP:MASS,
        "stages", STAGE:NUMBER,
        "docking", doclist:LENGTH,
        "drills", drill_n,
        "solar", solar_n,
        "status", SHIP:STATUS,
        "control", control_id,
        "thrust", SHIP:AVAILABLETHRUST
    ).
}

FUNCTION aoso_profile_fingerprint {
    LOCAL snap IS aoso_profile_snapshot().
    RETURN snap["parts"] + "|" + snap["engines"] + "|" + snap["tanks"] + "|" + snap["stages"] + "|" +
        snap["docking"] + "|" + snap["drills"] + "|" + snap["solar"] + "|" + snap["status"] + "|" + snap["control"].
}

FUNCTION aoso_profile_flag {
    PARAMETER capable.
    PARAMETER confidence.
    RETURN LEXICON("capable", capable, "confidence", confidence).
}

FUNCTION aoso_profile_thrust_at_pressure {
    PARAMETER pressure_atm.
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL thrust_sum IS 0.
    FOR e IN elist {
        SET thrust_sum TO thrust_sum + aoso_capabilities_engine_thrust(e, pressure_atm).
    }
    RETURN thrust_sum.
}

FUNCTION aoso_profile_surface_twr {
    PARAMETER body_name.
    LOCAL body_ref IS BODY(body_name).
    LOCAL g_surf IS body_ref:MU / (body_ref:RADIUS * body_ref:RADIUS).
    IF g_surf <= 0 { RETURN 0. }
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL pressure_atm IS 0.
    IF body_ref:ATM:EXISTS { SET pressure_atm TO body_ref:ATM:SEALEVELPRESSURE. }
    LOCAL thrust_sum IS aoso_profile_thrust_at_pressure(pressure_atm).
    RETURN thrust_sum / (SHIP:MASS * g_surf).
}

FUNCTION aoso_profile_refresh {
    PARAMETER reason IS "manual".

    aoso_vessel_scan().
    aoso_parts_scan().
    aoso_capabilities_refresh().

    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL doclist IS LIST().
    LIST DOCKINGPORTS IN doclist.

    LOCAL solar_count IS 0.
    LOCAL generator_count IS 0.
    LOCAL fuelcell_count IS 0.
    LOCAL wheel_count IS 0.
    LOCAL heatshield_count IS 0.
    LOCAL science_count IS 0.
    LOCAL kos_cpu_count IS 0.
    LOCAL lifting_count IS 0.
    LOCAL chute_count IS 0.
    LOCAL leg_count IS 0.
    LOCAL drill_count IS 0.
    LOCAL converter_count IS 0.
    LOCAL radiator_count IS 0.
    LOCAL antenna_count IS 0.
    LOCAL cargo_count IS 0.
    LOCAL fairing_count IS 0.
    LOCAL decoupler_count IS 0.
    LOCAL has_rcs IS FALSE.

    FOR p IN plist {
        IF p:HASMODULE("ModuleDeployableSolarPanel") { SET solar_count TO solar_count + 1. }
        IF p:HASMODULE("ModuleGenerator") { SET generator_count TO generator_count + 1. }
        IF p:HASMODULE("ModuleWheelBase") OR p:HASMODULE("ModuleWheelDeployment") { SET wheel_count TO wheel_count + 1. }
        IF p:HASMODULE("ModuleAblator") { SET heatshield_count TO heatshield_count + 1. }
        IF p:HASMODULE("ModuleScienceExperiment") OR p:HASMODULE("ModuleScienceContainer") { SET science_count TO science_count + 1. }
        IF p:HASMODULE("kOSProcessor") { SET kos_cpu_count TO kos_cpu_count + 1. }
        IF p:HASMODULE("ModuleLiftingSurface") OR p:HASMODULE("ModuleControlSurface") { SET lifting_count TO lifting_count + 1. }
        IF p:HASMODULE("ModuleParachute") { SET chute_count TO chute_count + 1. }
        IF p:HASMODULE("ModuleLandingLeg") { SET leg_count TO leg_count + 1. }
        IF p:HASMODULE("ModuleResourceHarvester") { SET drill_count TO drill_count + 1. }
        IF p:HASMODULE("ModuleResourceConverter") { SET converter_count TO converter_count + 1. }
        IF p:HASMODULE("ModuleDeployableRadiator") { SET radiator_count TO radiator_count + 1. }
        IF p:HASMODULE("ModuleDataTransmitter") { SET antenna_count TO antenna_count + 1. }
        IF p:HASMODULE("ModuleCargoBay") { SET cargo_count TO cargo_count + 1. }
        IF p:HASMODULE("ModuleProceduralFairing") { SET fairing_count TO fairing_count + 1. }
        IF p:HASMODULE("ModuleDecouple") OR p:HASMODULE("ModuleAnchoredDecoupler") OR p:HASMODULE("LaunchClamp") {
            SET decoupler_count TO decoupler_count + 1.
        }
        IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") { SET has_rcs TO TRUE. }
        LOCAL title_lc IS p:TITLE:TOLOWER.
        IF title_lc:CONTAINS("fuel cell") { SET fuelcell_count TO fuelcell_count + 1. }
    }

    IF kos_cpu_count < 1 { SET kos_cpu_count TO 1. }

    LOCAL ec_amount IS aoso_resource_amount("ElectricCharge").
    LOCAL ec_capacity IS aoso_resource_capacity("ElectricCharge").
    LOCAL ore_capacity IS aoso_resource_capacity("Ore").

    LOCAL twr_now IS aoso_caps_get("twr", 0).
    LOCAL dv_total IS aoso_caps_get("dv_total_vac", 0).
    LOCAL dv_stage IS aoso_caps_get("dv_current_stage", 0).
    LOCAL isp_vac IS aoso_caps_get("isp_vac", 0).
    LOCAL fuel_types IS aoso_caps_get("fuel_types", LIST()).
    LOCAL stage_layers IS aoso_caps_get("stages", LIST()).
    LOCAL engine_groups IS stage_layers:LENGTH.

    LOCAL st IS SHIP:STATUS.
    LOCAL on_ground IS FALSE.
    IF st = "PRELAUNCH" OR st = "LANDED" OR st = "SPLASHED" { SET on_ground TO TRUE. }
    LOCAL in_space IS FALSE.
    IF st = "ORBITING" OR st = "ESCAPING" OR st = "DOCKED" { SET in_space TO TRUE. }

    LOCAL can_launch IS FALSE.
    LOCAL launch_conf IS 0.4.
    IF on_ground {
        IF twr_now >= 1.15 {
            SET can_launch TO TRUE.
            SET launch_conf TO MIN(0.98, 0.55 + (twr_now - 1.15) * 0.25).
        } ELSE IF twr_now >= 1.02 {
            SET can_launch TO TRUE.
            SET launch_conf TO 0.6.
        } ELSE {
            SET launch_conf TO 0.9.
        }
    } ELSE {
        SET can_launch TO FALSE.
        SET launch_conf TO 0.85.
    }

    LOCAL can_orbit IS FALSE.
    LOCAL orbit_conf IS 0.5.
    IF in_space {
        SET can_orbit TO TRUE.
        SET orbit_conf TO 0.97.
    } ELSE IF dv_total >= 3200 AND twr_now >= 1.05 {
        SET can_orbit TO TRUE.
        SET orbit_conf TO 0.8.
    } ELSE IF dv_total >= 2500 {
        SET can_orbit TO TRUE.
        SET orbit_conf TO 0.55.
    } ELSE {
        SET orbit_conf TO 0.75.
    }

    LOCAL can_land IS FALSE.
    LOCAL land_conf IS 0.5.
    IF chute_count > 0 OR leg_count > 0 {
        SET can_land TO TRUE.
        SET land_conf TO 0.55.
        IF chute_count > 0 { SET land_conf TO land_conf + 0.2. }
        IF leg_count > 0 { SET land_conf TO land_conf + 0.2. }
        IF land_conf > 0.95 { SET land_conf TO 0.95. }
    } ELSE {
        SET land_conf TO 0.9.
    }

    LOCAL can_takeoff IS FALSE.
    LOCAL takeoff_conf IS 0.5.
    LOCAL home_twr IS aoso_profile_surface_twr(SHIP:BODY:NAME).
    LOCAL min_twr IS aoso_config_get("TOUR_MIN_LAND_TWR", 1.4).
    IF home_twr >= min_twr {
        SET can_takeoff TO TRUE.
        SET takeoff_conf TO MIN(0.97, 0.55 + (home_twr - min_twr) * 0.3).
    } ELSE {
        SET takeoff_conf TO 0.85.
        IF home_twr >= 1.05 {
            SET can_takeoff TO TRUE.
            SET takeoff_conf TO 0.55.
        }
    }

    LOCAL can_atmo IS FALSE.
    LOCAL atmo_conf IS 0.8.
    IF lifting_count >= 2 {
        SET can_atmo TO TRUE.
        SET atmo_conf TO 0.7.
    }

    LOCAL can_dock IS FALSE.
    LOCAL dock_conf IS 0.95.
    IF doclist:LENGTH >= 2 {
        SET can_dock TO TRUE.
        SET dock_conf TO 0.9.
    } ELSE IF doclist:LENGTH = 1 {
        SET can_dock TO TRUE.
        SET dock_conf TO 0.71.
    }

    LOCAL can_isru IS FALSE.
    LOCAL isru_conf IS 0.9.
    IF drill_count > 0 AND converter_count > 0 {
        SET can_isru TO TRUE.
        SET isru_conf TO 0.92.
        IF ore_capacity <= 0 { SET isru_conf TO 0.6. }
    }

    LOCAL can_return IS FALSE.
    LOCAL return_conf IS 0.5.
    IF dv_total >= 800 {
        SET can_return TO TRUE.
        SET return_conf TO MIN(0.9, 0.45 + dv_total / 8000).
    } ELSE {
        SET return_conf TO 0.7.
    }

    LOCAL eve_twr IS aoso_profile_surface_twr("Eve").
    LOCAL can_eve IS FALSE.
    LOCAL eve_conf IS 0.99.
    IF eve_twr >= 1.6 AND dv_total >= 8000 {
        SET can_eve TO TRUE.
        SET eve_conf TO 0.7.
    }

    LOCAL root_title IS "".
    IF SHIP:ROOTPART:ISTYPE("Part") { SET root_title TO SHIP:ROOTPART:TITLE. }

    SET AOSO_PROFILE TO LEXICON(
        "name", SHIP:NAME,
        "body", SHIP:BODY:NAME,
        "status", st,
        "mass", SHIP:MASS,
        "part_count", plist:LENGTH,
        "fingerprint", aoso_profile_fingerprint(),
        "reason", reason,
        "scanned_at", TIME:SECONDS,
        "snapshot", aoso_profile_snapshot(),
        "structure", LEXICON(
            "root", root_title,
            "stages", STAGE:NUMBER + 1,
            "decouplers", decoupler_count,
            "docking", doclist:LENGTH,
            "max_depth", aoso_parts_get("max_depth", 0),
            "fairings", fairing_count
        ),
        "propulsion", LEXICON(
            "engines", elist:LENGTH,
            "engine_groups", engine_groups,
            "fuel_types", fuel_types,
            "twr", twr_now,
            "max_surface_twr", home_twr,
            "isp_vac", isp_vac,
            "dv_total", dv_total,
            "vacuum_dv", dv_total,
            "atmospheric_dv", dv_stage,
            "dv_stage", dv_stage,
            "has_rcs", has_rcs
        ),
        "power", LEXICON(
            "ec_amount", ec_amount,
            "ec_capacity", ec_capacity,
            "solar_count", solar_count,
            "generator_count", generator_count,
            "fuelcell_count", fuelcell_count
        ),
        "mobility", LEXICON(
            "has_gear", leg_count > 0,
            "has_wheels", wheel_count > 0,
            "has_parachutes", chute_count > 0,
            "has_legs", leg_count > 0,
            "parachute_count", chute_count,
            "leg_count", leg_count,
            "wheel_count", wheel_count
        ),
        "isru", LEXICON(
            "has_drills", drill_count > 0,
            "has_converter", converter_count > 0,
            "has_radiators", radiator_count > 0,
            "ore_capacity", ore_capacity,
            "can_mine", drill_count > 0 AND converter_count > 0
        ),
        "navigation", LEXICON(
            "has_antenna", antenna_count > 0,
            "has_sas", TRUE,
            "docking_ports", doclist:LENGTH,
            "kos_cpu", kos_cpu_count
        ),
        "mission_hw", LEXICON(
            "has_heatshield", heatshield_count > 0,
            "has_cargo", cargo_count > 0,
            "science_count", science_count,
            "crew_capacity", SHIP:CREWCAPACITY,
            "crew_count", SHIP:CREW:LENGTH,
            "heatshield_count", heatshield_count
        ),
        "capabilities", LEXICON(
            "can_launch", aoso_profile_flag(can_launch, ROUND(launch_conf, 2)),
            "can_orbit", aoso_profile_flag(can_orbit, ROUND(orbit_conf, 2)),
            "can_land", aoso_profile_flag(can_land, ROUND(land_conf, 2)),
            "can_takeoff", aoso_profile_flag(can_takeoff, ROUND(takeoff_conf, 2)),
            "can_atmospheric_flight", aoso_profile_flag(can_atmo, ROUND(atmo_conf, 2)),
            "can_dock", aoso_profile_flag(can_dock, ROUND(dock_conf, 2)),
            "can_isru", aoso_profile_flag(can_isru, ROUND(isru_conf, 2)),
            "can_return_to_kerbin", aoso_profile_flag(can_return, ROUND(return_conf, 2)),
            "can_takeoff_eve", aoso_profile_flag(can_eve, ROUND(eve_conf, 2))
        )
    ).

    SET AOSO_PROFILE_LAST_MASS TO SHIP:MASS.
    SET AOSO_PROFILE_LAST_SNAP TO AOSO_PROFILE["snapshot"].
    aoso_budget_refresh().
    aoso_capabilities_predict_next().
    aoso_profile_save().

    aoso_log_info("PROFILE", "Re-profiled (" + reason + "): " + plist:LENGTH + " parts, " +
        elist:LENGTH + " engines, dV=" + ROUND(dv_total, 0) + " m/s, TWR=" + ROUND(twr_now, 2) +
        " ISRU=" + can_isru + " land=" + can_land + " dock=" + can_dock + ".").

    aoso_classify_refresh().

    RETURN AOSO_PROFILE.
}

FUNCTION aoso_profile_maybe_refresh {
    IF NOT AOSO_PROFILE:HASKEY("snapshot") {
        aoso_profile_refresh("init").
        RETURN.
    }
    LOCAL snap IS aoso_profile_snapshot().
    LOCAL prev IS AOSO_PROFILE_LAST_SNAP.
    IF NOT prev:HASKEY("parts") {
        aoso_profile_refresh("init").
        RETURN.
    }

    LOCAL structural IS FALSE.
    LOCAL reason IS "".
    IF snap["parts"] <> prev["parts"] { SET structural TO TRUE. SET reason TO "parts " + prev["parts"] + "->" + snap["parts"]. }
    IF snap["engines"] <> prev["engines"] { SET structural TO TRUE. SET reason TO "engines " + prev["engines"] + "->" + snap["engines"]. }
    IF snap["stages"] <> prev["stages"] { SET structural TO TRUE. SET reason TO "stage " + prev["stages"] + "->" + snap["stages"]. }
    IF snap["docking"] <> prev["docking"] { SET structural TO TRUE. SET reason TO "docking". }
    IF snap["drills"] <> prev["drills"] { SET structural TO TRUE. SET reason TO "drills". }
    IF snap["solar"] <> prev["solar"] { SET structural TO TRUE. SET reason TO "solar". }
    IF snap["status"] <> prev["status"] { SET structural TO TRUE. SET reason TO "status " + prev["status"] + "->" + snap["status"]. }
    IF snap["control"] <> prev["control"] { SET structural TO TRUE. SET reason TO "control-point". }

    IF structural {
        aoso_log_info("PROFILE", "Change: " + reason + " - full re-profile.").
        aoso_world_refresh(reason).
        aoso_profile_refresh(reason).
        RETURN.
    }

    LOCAL resource_cfg IS FALSE.
    IF snap["tanks"] <> prev["tanks"] { SET resource_cfg TO TRUE. }

    LOCAL thrust_fail IS FALSE.
    IF prev["thrust"] > 1 {
        IF snap["thrust"] < prev["thrust"] * 0.7 { SET thrust_fail TO TRUE. }
    }

    LOCAL mass_delta IS 0.
    IF prev["mass"] > 0.05 {
        SET mass_delta TO ABS(snap["mass"] - prev["mass"]) / prev["mass"].
    }

    IF resource_cfg OR thrust_fail OR mass_delta > 0.08 {
        LOCAL why IS "mass".
        IF resource_cfg { SET why TO "resource-config". }
        IF thrust_fail { SET why TO "engine-failure". }
        aoso_log_debug("PROFILE", "Change: " + why + " - refresh dV/budget only.").
        aoso_capabilities_refresh().
        aoso_budget_refresh().
        aoso_capabilities_predict_next().
        SET AOSO_PROFILE_LAST_MASS TO snap["mass"].
        SET AOSO_PROFILE_LAST_SNAP TO snap.
        SET AOSO_PROFILE["mass"] TO snap["mass"].
        SET AOSO_PROFILE["snapshot"] TO snap.
        SET AOSO_PROFILE["propulsion"]["dv_total"] TO aoso_caps_get("dv_total_vac", 0).
        SET AOSO_PROFILE["propulsion"]["vacuum_dv"] TO aoso_caps_get("dv_total_vac", 0).
        SET AOSO_PROFILE["propulsion"]["atmospheric_dv"] TO aoso_caps_get("dv_current_stage", 0).
        SET AOSO_PROFILE["propulsion"]["twr"] TO aoso_caps_get("twr", 0).
        RETURN.
    }
}

FUNCTION aoso_profile_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_PROFILE:HASKEY(key) { RETURN AOSO_PROFILE[key]. }
    RETURN default_value.
}

FUNCTION aoso_profile_capable {
    PARAMETER cap_name.
    IF NOT AOSO_PROFILE:HASKEY("capabilities") { RETURN FALSE. }
    LOCAL caps IS AOSO_PROFILE["capabilities"].
    IF NOT caps:HASKEY(cap_name) { RETURN FALSE. }
    RETURN caps[cap_name]["capable"].
}

FUNCTION aoso_profile_confidence {
    PARAMETER cap_name.
    IF NOT AOSO_PROFILE:HASKEY("capabilities") { RETURN 0. }
    LOCAL caps IS AOSO_PROFILE["capabilities"].
    IF NOT caps:HASKEY(cap_name) { RETURN 0. }
    RETURN caps[cap_name]["confidence"].
}

FUNCTION aoso_profile_save {
    aoso_json_write(AOSO_CONST["PROFILE_FILE"], AOSO_PROFILE).
}

FUNCTION aoso_profile_register_task {
    PARAMETER interval_s IS 2.
    aoso_sched_add("vehicle_profile", interval_s, aoso_profile_maybe_refresh@).
}
