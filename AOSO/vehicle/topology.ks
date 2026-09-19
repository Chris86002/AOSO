// AOSO/vehicle/topology.ks
// Authoritative structural model. One LIST PARTS / ENGINES / DOCKINGPORTS
// (via parts.ks cache) and one HASMODULE census. Profile, vessel, classify
// and certification read this. Fuel amounts are dynamic; parent/stage
// grouping is not rebuilt just because a tank drained.

GLOBAL AOSO_TOPO IS LEXICON().
GLOBAL AOSO_TOPO_PARENT IS LEXICON().
GLOBAL AOSO_TOPO_GROUPS IS LEXICON().

FUNCTION aoso_topo_blank_hw {
    RETURN LEXICON(
        "solar", 0, "generator", 0, "fuelcell", 0, "wheels", 0, "heatshield", 0,
        "science", 0, "kos", 0, "lifting", 0, "chute", 0, "legs", 0,
        "drill", 0, "converter", 0, "radiator", 0, "antenna", 0, "cargo", 0,
        "fairing", 0, "decoupler", 0, "rcs", 0, "rwheel", 0, "tanks", 0,
        "intakes", 0, "nuke", 0, "ion", 0
    ).
}

FUNCTION aoso_topo_fp_now {
    LOCAL plist IS aoso_parts_list().
    LOCAL elist IS aoso_parts_engines().
    LOCAL dlist IS aoso_parts_dockports().
    LOCAL root_id IS "".
    IF SHIP:ROOTPART:ISTYPE("Part") { SET root_id TO "" + SHIP:ROOTPART:UID. }
    LOCAL control_id IS "".
    IF SHIP:CONTROLPART:ISTYPE("Part") { SET control_id TO "" + SHIP:CONTROLPART:UID. }
    RETURN plist:LENGTH + "|" + elist:LENGTH + "|" + STAGE:NUMBER + "|" + root_id + "|" + dlist:LENGTH + "|" + control_id.
}

FUNCTION aoso_topo_fp {
    IF AOSO_TOPO:HASKEY("fp") { RETURN AOSO_TOPO["fp"]. }
    RETURN "".
}

FUNCTION aoso_topo_hw {
    IF AOSO_TOPO:HASKEY("hw") { RETURN AOSO_TOPO["hw"]. }
    RETURN aoso_topo_blank_hw().
}

FUNCTION aoso_topo_hw_get {
    PARAMETER key_name.
    PARAMETER default_value IS 0.
    LOCAL hw IS aoso_topo_hw().
    IF hw:HASKEY(key_name) { RETURN hw[key_name]. }
    RETURN default_value.
}

FUNCTION aoso_topo_group_key {
    PARAMETER decoupled_in.
    RETURN "" + decoupled_in.
}

FUNCTION aoso_topo_ensure_group {
    PARAMETER d.
    LOCAL dkey IS aoso_topo_group_key(d).
    IF NOT AOSO_TOPO_GROUPS:HASKEY(dkey) {
        SET AOSO_TOPO_GROUPS[dkey] TO LEXICON(
            "decoupled_in", d,
            "parts", 0,
            "engines", 0,
            "tanks", 0,
            "legs", 0,
            "drill", 0,
            "converter", 0,
            "rwheel", 0,
            "rcs", 0,
            "wet_mass", 0,
            "dry_mass", 0,
            "lf", 0, "ox", 0, "sf", 0, "xe", 0, "mp", 0,
            "lf_cap", 0, "ox_cap", 0
        ).
    }
    RETURN AOSO_TOPO_GROUPS[dkey].
}

FUNCTION aoso_topo_rebuild {
    aoso_parts_cache_ensure().
    LOCAL plist IS aoso_parts_list().
    LOCAL elist IS aoso_parts_engines().
    LOCAL dlist IS aoso_parts_dockports().

    SET AOSO_TOPO_PARENT TO LEXICON().
    SET AOSO_TOPO_GROUPS TO LEXICON().
    LOCAL hw IS aoso_topo_blank_hw().
    LOCAL max_depth IS 0.

    FOR p IN plist {
        LOCAL uid IS "" + p:UID.
        IF p:HASPARENT {
            SET AOSO_TOPO_PARENT[uid] TO "" + p:PARENT:UID.
        }
        LOCAL depth IS 0.
        LOCAL cur IS p.
        UNTIL NOT cur:HASPARENT {
            SET cur TO cur:PARENT.
            SET depth TO depth + 1.
        }
        IF depth > max_depth { SET max_depth TO depth. }

        LOCAL g IS aoso_topo_ensure_group(p:DECOUPLEDIN).
        SET g["parts"] TO g["parts"] + 1.
        SET g["wet_mass"] TO g["wet_mass"] + p:MASS.
        SET g["dry_mass"] TO g["dry_mass"] + p:DRYMASS.

        LOCAL has_tank IS FALSE.
        FOR res_item IN p:RESOURCES {
            LOCAL rn IS res_item:NAME.
            LOCAL amt IS res_item:AMOUNT.
            LOCAL cap IS res_item:CAPACITY.
            IF rn = "LiquidFuel" {
                SET g["lf"] TO g["lf"] + amt.
                SET g["lf_cap"] TO g["lf_cap"] + cap.
                IF cap > 0 { SET has_tank TO TRUE. }
            }
            IF rn = "Oxidizer" {
                SET g["ox"] TO g["ox"] + amt.
                SET g["ox_cap"] TO g["ox_cap"] + cap.
                IF cap > 0 { SET has_tank TO TRUE. }
            }
            IF rn = "SolidFuel" {
                SET g["sf"] TO g["sf"] + amt.
                IF cap > 0 { SET has_tank TO TRUE. }
            }
            IF rn = "XenonGas" {
                SET g["xe"] TO g["xe"] + amt.
                IF cap > 0 { SET has_tank TO TRUE. }
            }
            IF rn = "MonoPropellant" {
                SET g["mp"] TO g["mp"] + amt.
            }
        }
        IF has_tank {
            SET g["tanks"] TO g["tanks"] + 1.
            SET hw["tanks"] TO hw["tanks"] + 1.
        }

        IF p:HASMODULE("ModuleDeployableSolarPanel") { SET hw["solar"] TO hw["solar"] + 1. }
        IF p:HASMODULE("ModuleGenerator") { SET hw["generator"] TO hw["generator"] + 1. }
        IF p:HASMODULE("ModuleWheelBase") { SET hw["wheels"] TO hw["wheels"] + 1. }
        IF p:HASMODULE("ModuleAblator") { SET hw["heatshield"] TO hw["heatshield"] + 1. }
        IF p:HASMODULE("ModuleScienceExperiment") { SET hw["science"] TO hw["science"] + 1. }
        IF p:HASMODULE("kOSProcessor") { SET hw["kos"] TO hw["kos"] + 1. }
        IF p:HASMODULE("ModuleLiftingSurface") { SET hw["lifting"] TO hw["lifting"] + 1. }
        IF p:HASMODULE("ModuleControlSurface") { SET hw["lifting"] TO hw["lifting"] + 1. }
        IF p:HASMODULE("ModuleParachute") { SET hw["chute"] TO hw["chute"] + 1. }
        IF p:HASMODULE("ModuleLandingLeg") {
            SET hw["legs"] TO hw["legs"] + 1.
            SET g["legs"] TO g["legs"] + 1.
        }
        IF p:HASMODULE("ModuleResourceHarvester") {
            SET hw["drill"] TO hw["drill"] + 1.
            SET g["drill"] TO g["drill"] + 1.
        }
        IF p:HASMODULE("ModuleResourceConverter") {
            SET hw["converter"] TO hw["converter"] + 1.
            SET g["converter"] TO g["converter"] + 1.
        }
        IF p:HASMODULE("ModuleDeployableRadiator") { SET hw["radiator"] TO hw["radiator"] + 1. }
        IF p:HASMODULE("ModuleDataTransmitter") { SET hw["antenna"] TO hw["antenna"] + 1. }
        IF p:HASMODULE("ModuleCargoBay") { SET hw["cargo"] TO hw["cargo"] + 1. }
        IF p:HASMODULE("ModuleProceduralFairing") { SET hw["fairing"] TO hw["fairing"] + 1. }
        IF p:HASMODULE("ModuleDecouple") { SET hw["decoupler"] TO hw["decoupler"] + 1. }
        IF p:HASMODULE("ModuleAnchoredDecoupler") { SET hw["decoupler"] TO hw["decoupler"] + 1. }
        IF p:HASMODULE("LaunchClamp") { SET hw["decoupler"] TO hw["decoupler"] + 1. }
        IF p:HASMODULE("ModuleRCS") {
            SET hw["rcs"] TO hw["rcs"] + 1.
            SET g["rcs"] TO g["rcs"] + 1.
        }
        IF p:HASMODULE("ModuleRCSFX") {
            SET hw["rcs"] TO hw["rcs"] + 1.
            SET g["rcs"] TO g["rcs"] + 1.
        }
        IF p:HASMODULE("ModuleReactionWheel") {
            SET hw["rwheel"] TO hw["rwheel"] + 1.
            SET g["rwheel"] TO g["rwheel"] + 1.
        }
        IF p:HASMODULE("ModuleResourceIntake") { SET hw["intakes"] TO hw["intakes"] + 1. }
        LOCAL title_lc IS p:TITLE:TOLOWER.
        IF title_lc:CONTAINS("fuel cell") { SET hw["fuelcell"] TO hw["fuelcell"] + 1. }
    }

    FOR e IN elist {
        LOCAL g IS aoso_topo_ensure_group(e:DECOUPLEDIN).
        SET g["engines"] TO g["engines"] + 1.
        IF e:VACUUMISP >= 2000 {
            SET hw["ion"] TO hw["ion"] + 1.
        } ELSE {
            IF e:VACUUMISP >= 700 { SET hw["nuke"] TO hw["nuke"] + 1. }
        }
        LOCAL et IS e:TITLE:TOLOWER.
        IF et:CONTAINS("nerv") { SET hw["nuke"] TO hw["nuke"] + 1. }
        IF et:CONTAINS("lv-n") { SET hw["nuke"] TO hw["nuke"] + 1. }
        IF et:CONTAINS("dawn") { SET hw["ion"] TO hw["ion"] + 1. }
    }
    IF hw["kos"] < 1 { SET hw["kos"] TO 1. }

    LOCAL unsorted IS LIST().
    FOR k IN AOSO_TOPO_GROUPS:KEYS { unsorted:ADD(AOSO_TOPO_GROUPS[k]). }
    LOCAL layers IS LIST().
    UNTIL unsorted:LENGTH = 0 {
        LOCAL best_idx IS 0.
        FOR i IN RANGE(0, unsorted:LENGTH) {
            IF unsorted[i]["decoupled_in"] > unsorted[best_idx]["decoupled_in"] { SET best_idx TO i. }
        }
        layers:ADD(unsorted[best_idx]).
        unsorted:REMOVE(best_idx).
    }
    FOR i IN RANGE(0, layers:LENGTH) {
        LOCAL d IS layers[i]["decoupled_in"].
        LOCAL role IS "STAGE".
        IF d < 0 { SET role TO "CORE". }
        ELSE {
            IF i = 0 { SET role TO "BOOSTER". }
        }
        SET layers[i]["role"] TO role.
    }

    LOCAL nxt IS aoso_topo_predict_drop(layers).
    LOCAL prev_rev IS 0.
    IF AOSO_TOPO:HASKEY("rev") { SET prev_rev TO AOSO_TOPO["rev"]. }
    LOCAL fp IS aoso_topo_fp_now().
    SET AOSO_TOPO TO LEXICON(
        "fp", fp,
        "rev", prev_rev + 1,
        "dyn_rev", 0,
        "part_n", plist:LENGTH,
        "engine_n", elist:LENGTH,
        "dock_n", dlist:LENGTH,
        "stage", STAGE:NUMBER,
        "max_depth", max_depth,
        "hw", hw,
        "layers", layers,
        "landing", LEXICON(
            "legs", hw["legs"],
            "chutes", hw["chute"],
            "wheels", hw["wheels"],
            "engines", elist:LENGTH
        ),
        "isru", LEXICON(
            "drills", hw["drill"],
            "converters", hw["converter"],
            "radiators", hw["radiator"],
            "can_mine", FALSE
        ),
        "control", LEXICON(
            "rwheel", hw["rwheel"],
            "rcs", hw["rcs"],
            "lifting", hw["lifting"],
            "turn_lead_s", 50
        ),
        "next_stage", nxt,
        "mass", SHIP:MASS,
        "thrust", SHIP:AVAILABLETHRUST,
        "scanned_at", TIME:SECONDS
    ).
    IF hw["drill"] > 0 {
        IF hw["converter"] > 0 { SET AOSO_TOPO["isru"]["can_mine"] TO TRUE. }
    }
    LOCAL lead IS 50.
    IF SHIP:MASS > 25 {
        IF hw["rcs"] < 1 { SET lead TO 70. }
    }
    IF hw["rwheel"] < 1 {
        IF hw["rcs"] < 1 { SET lead TO 80. }
    }
    SET AOSO_TOPO["control"]["turn_lead_s"] TO lead.
    aoso_log_info("TOPO", "Structure rev=" + AOSO_TOPO["rev"] + " parts=" + plist:LENGTH +
        " engines=" + elist:LENGTH + " layers=" + layers:LENGTH + " fp=" + fp + ".").
    IF DEFINED AOSO_CTX {
        SET AOSO_CTX["rev_topo"] TO AOSO_TOPO["rev"].
    }
    RETURN AOSO_TOPO.
}

FUNCTION aoso_topo_predict_drop {
    PARAMETER layers.
    LOCAL drop_stage IS STAGE:NUMBER.
    LOCAL lost_parts IS 0.
    LOCAL lost_eng IS 0.
    LOCAL lost_tank IS 0.
    LOCAL lost_leg IS 0.
    LOCAL lost_isru IS 0.
    LOCAL lost_dry IS 0.
    LOCAL lost_wet IS 0.
    LOCAL dkey IS aoso_topo_group_key(drop_stage).
    IF AOSO_TOPO_GROUPS:HASKEY(dkey) {
        LOCAL g IS AOSO_TOPO_GROUPS[dkey].
        SET lost_parts TO g["parts"].
        SET lost_eng TO g["engines"].
        SET lost_tank TO g["tanks"].
        SET lost_leg TO g["legs"].
        SET lost_isru TO g["drill"] + g["converter"].
        SET lost_dry TO g["dry_mass"].
        SET lost_wet TO g["wet_mass"].
    }
    LOCAL role_this IS "".
    LOCAL role_next IS "".
    IF layers:LENGTH > 0 { SET role_this TO layers[0]["role"]. }
    IF layers:LENGTH > 1 { SET role_next TO layers[1]["role"]. }
    RETURN LEXICON(
        "drop_stage", drop_stage,
        "parts_lost", lost_parts,
        "engines_lost", lost_eng,
        "tanks_lost", lost_tank,
        "legs_lost", lost_leg,
        "isru_lost", lost_isru,
        "dry_mass_lost", lost_dry,
        "wet_mass_lost", lost_wet,
        "mass_next", MAX(0.1, SHIP:MASS - lost_wet),
        "role_this", role_this,
        "role_next", role_next
    ).
}

FUNCTION aoso_topo_touch_dynamic {
    IF NOT AOSO_TOPO:HASKEY("rev") { RETURN. }
    SET AOSO_TOPO["mass"] TO SHIP:MASS.
    SET AOSO_TOPO["thrust"] TO SHIP:AVAILABLETHRUST.
    SET AOSO_TOPO["dyn_rev"] TO AOSO_TOPO["dyn_rev"] + 1.
}

FUNCTION aoso_topo_refresh {
    PARAMETER force IS FALSE.
    aoso_parts_cache_ensure().
    LOCAL fp IS aoso_topo_fp_now().
    IF NOT force {
        IF AOSO_TOPO:HASKEY("fp") {
            IF AOSO_TOPO["fp"] = fp {
                aoso_topo_touch_dynamic().
                RETURN AOSO_TOPO.
            }
        }
    }
    RETURN aoso_topo_rebuild().
}

FUNCTION aoso_topo_fuel_of {
    PARAMETER decoupled_in.
    LOCAL dkey IS aoso_topo_group_key(decoupled_in).
    IF AOSO_TOPO_GROUPS:HASKEY(dkey) { RETURN AOSO_TOPO_GROUPS[dkey]. }
    RETURN LEXICON("lf", 0, "ox", 0, "lf_cap", 0, "ox_cap", 0, "engines", 0).
}

FUNCTION aoso_topo_turn_lead_s {
    IF AOSO_TOPO:HASKEY("control") { RETURN AOSO_TOPO["control"]["turn_lead_s"]. }
    RETURN aoso_config_get("MANEUVER_ALIGN_S", 50).
}

FUNCTION aoso_topo_get {
    PARAMETER key_name.
    PARAMETER default_value IS 0.
    IF AOSO_TOPO:HASKEY(key_name) { RETURN AOSO_TOPO[key_name]. }
    RETURN default_value.
}
