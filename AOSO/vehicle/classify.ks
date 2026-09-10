// AOSO/vehicle/classify.ks
// What kind of vehicle is this? Classification never forbids a destination
// -- it only changes planner priorities (a hopper prefers Minmus first; a
// nuclear stack prefers the outer planets; a tug skips landings as SHOULD
// even when it CAN).

GLOBAL AOSO_CLASS_LAST IS LEXICON().

FUNCTION aoso_classify_engine_flags {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL has_nuke IS FALSE.
    LOCAL has_ion IS FALSE.
    LOCAL lifting_n IS 0.
    LOCAL intake_n IS 0.
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    FOR p IN plist {
        IF p:HASMODULE("ModuleLiftingSurface") OR p:HASMODULE("ModuleControlSurface") {
            SET lifting_n TO lifting_n + 1.
        }
        IF p:HASMODULE("ModuleResourceIntake") { SET intake_n TO intake_n + 1. }
    }
    FOR e IN elist {
        IF e:VACUUMISP >= 2000 { SET has_ion TO TRUE. }
        IF e:VACUUMISP >= 700 {
            IF e:VACUUMISP < 2000 { SET has_nuke TO TRUE. }
        }
        LOCAL title_lc IS e:TITLE:TOLOWER.
        IF title_lc:CONTAINS("nerv") { SET has_nuke TO TRUE. }
        IF title_lc:CONTAINS("lv-n") { SET has_nuke TO TRUE. }
        IF title_lc:CONTAINS("nuclear") { SET has_nuke TO TRUE. }
        IF title_lc:CONTAINS("ion") { SET has_ion TO TRUE. }
        IF title_lc:CONTAINS("dawn") { SET has_ion TO TRUE. }
    }
    RETURN LEXICON("nuke", has_nuke, "ion", has_ion, "lifting", lifting_n, "intakes", intake_n).
}

FUNCTION aoso_classify_refresh {
    LOCAL flags IS aoso_classify_engine_flags().
    LOCAL dv_total IS aoso_caps_get("dv_total_vac", 0).
    LOCAL twr_now IS aoso_caps_get("twr", 0).
    LOCAL decouplers IS 0.
    LOCAL stages_n IS STAGE:NUMBER + 1.
    LOCAL docks IS 0.
    LOCAL has_legs IS FALSE.
    LOCAL has_wheels IS FALSE.
    LOCAL has_chutes IS FALSE.
    LOCAL has_isru IS FALSE.
    LOCAL has_cargo IS FALSE.
    IF DEFINED AOSO_PROFILE {
        IF AOSO_PROFILE:HASKEY("structure") {
            SET decouplers TO AOSO_PROFILE["structure"]["decouplers"].
            SET docks TO AOSO_PROFILE["structure"]["docking"].
        }
        IF AOSO_PROFILE:HASKEY("mobility") {
            SET has_legs TO AOSO_PROFILE["mobility"]["has_legs"].
            SET has_wheels TO AOSO_PROFILE["mobility"]["has_wheels"].
            SET has_chutes TO AOSO_PROFILE["mobility"]["has_parachutes"].
        }
        IF AOSO_PROFILE:HASKEY("isru") {
            SET has_isru TO AOSO_PROFILE["isru"]["can_mine"].
        }
        IF AOSO_PROFILE:HASKEY("mission_hw") {
            SET has_cargo TO AOSO_PROFILE["mission_hw"]["has_cargo"].
        }
    }

    LOCAL tags IS LIST().
    LOCAL class_name IS "hybrid".

    IF flags["ion"] { tags:ADD("ion"). }
    IF flags["nuke"] { tags:ADD("nuclear"). }
    IF has_isru { tags:ADD("isru"). }
    IF has_legs { tags:ADD("lander"). }
    IF docks >= 1 { tags:ADD("docking"). }
    IF flags["lifting"] >= 2 { tags:ADD("winged"). }
    IF decouplers >= 3 { tags:ADD("multistage"). }

    IF docks >= 1 {
        IF has_isru OR has_cargo {
            IF dv_total >= 4000 {
                SET class_name TO "mothership".
            }
        }
    }
    IF class_name = "hybrid" {
        IF flags["nuke"] {
            IF dv_total >= 4000 { SET class_name TO "nuclear_interplanetary". }
        }
    }
    IF class_name = "hybrid" {
        IF has_wheels {
            IF flags["lifting"] >= 2 { SET class_name TO "spaceplane". }
        }
    }
    IF class_name = "hybrid" {
        IF flags["lifting"] >= 2 {
            IF decouplers <= 2 {
                IF flags["intakes"] > 0 OR has_chutes { SET class_name TO "ssto". }
            }
        }
    }
    IF class_name = "hybrid" {
        IF has_legs {
            IF has_isru {
                IF dv_total < 4500 { SET class_name TO "hopper". }
            }
        }
    }
    IF class_name = "hybrid" {
        IF docks >= 1 {
            IF NOT has_legs {
                IF dv_total >= 2000 { SET class_name TO "tug". }
            }
        }
    }
    IF class_name = "hybrid" {
        IF has_legs {
            IF decouplers <= 3 { SET class_name TO "lander". }
        }
    }
    IF class_name = "hybrid" {
        IF has_chutes {
            IF has_legs {
                IF decouplers <= 2 { SET class_name TO "reusable". }
            }
        }
    }
    IF class_name = "hybrid" {
        IF decouplers >= 3 { SET class_name TO "multistage". }
    }
    IF class_name = "hybrid" {
        IF SHIP:STATUS = "ORBITING" OR SHIP:STATUS = "ESCAPING" {
            IF NOT has_legs { SET class_name TO "orbital". }
        }
    }

    LOCAL prefer_refuel_first IS FALSE.
    LOCAL prefer_outer IS FALSE.
    LOCAL prefer_atmo IS FALSE.
    LOCAL prefer_nearby IS FALSE.
    LOCAL prefer_orbit_only IS FALSE.
    IF class_name = "hopper" { SET prefer_refuel_first TO TRUE. SET prefer_nearby TO TRUE. }
    IF class_name = "lander" { SET prefer_nearby TO TRUE. }
    IF class_name = "nuclear_interplanetary" { SET prefer_outer TO TRUE. }
    IF flags["ion"] { SET prefer_outer TO TRUE. }
    IF class_name = "spaceplane" { SET prefer_atmo TO TRUE. }
    IF class_name = "ssto" { SET prefer_atmo TO TRUE. }
    IF class_name = "tug" { SET prefer_orbit_only TO TRUE. }
    IF class_name = "mothership" { SET prefer_refuel_first TO TRUE. }

    SET AOSO_CLASS_LAST TO LEXICON(
        "class", class_name,
        "tags", tags,
        "dv", dv_total,
        "twr", twr_now,
        "nuke", flags["nuke"],
        "ion", flags["ion"],
        "lifting", flags["lifting"],
        "prefer_refuel_first", prefer_refuel_first,
        "prefer_outer", prefer_outer,
        "prefer_atmo", prefer_atmo,
        "prefer_nearby", prefer_nearby,
        "prefer_orbit_only", prefer_orbit_only,
        "at", TIME:SECONDS
    ).
    IF DEFINED AOSO_PROFILE {
        SET AOSO_PROFILE["class"] TO class_name.
    }
    aoso_log_info("CLASS", SHIP:NAME + " is a " + class_name + " (dV=" + ROUND(dv_total, 0) +
        " TWR=" + ROUND(twr_now, 2) + " stages=" + stages_n + " docks=" + docks + ").").
    RETURN AOSO_CLASS_LAST.
}

FUNCTION aoso_classify_get {
    PARAMETER key_name.
    PARAMETER default_value IS 0.
    IF AOSO_CLASS_LAST:HASKEY(key_name) { RETURN AOSO_CLASS_LAST[key_name]. }
    RETURN default_value.
}

FUNCTION aoso_classify_name {
    IF AOSO_CLASS_LAST:HASKEY("class") { RETURN AOSO_CLASS_LAST["class"]. }
    RETURN "hybrid".
}
