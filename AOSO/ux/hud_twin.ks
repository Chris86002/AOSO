// AOSO/ux/hud_twin.ks
// Vessel Digital Twin model cache. Geometry is rebuilt on structural
// events only (stage / part count / dock / control point). Resource
// fills refresh on the HUD medium tick. Nodes store UIDs, not Part
// objects (those live in the RAM map AOSO_TWIN_PARTS).
//
// Do not LIST PARTS here — aoso_parts_list() is already cached by
// vehicle/parts.ks. Do not touch PART:BOUNDS (expensive).

GLOBAL AOSO_TWIN IS LEXICON().
GLOBAL AOSO_TWIN_PARTS IS LEXICON().
GLOBAL AOSO_TWIN_HLS IS LIST().
GLOBAL AOSO_TWIN_CAP IS 40.
GLOBAL AOSO_TWIN_LAST_STAGE IS -999.
GLOBAL AOSO_TWIN_UID_SIG IS "".
GLOBAL AOSO_TWIN_LAST_FILL IS 0.
GLOBAL AOSO_TWIN_VIEW_DIRTY IS TRUE.

FUNCTION aoso_twin_init {
    aoso_twin_clear_hl().
    SET AOSO_TWIN_PARTS TO LEXICON().
    SET AOSO_TWIN TO LEXICON(
        "status", "UPDATING",
        "reason", "init",
        "scanned_at", 0,
        "fingerprint", "",
        "root_uid", "",
        "view", "NORMAL",
        "filter", "ALL",
        "resource_focus", "ALL",
        "selected_uid", "",
        "nodes", LIST(),
        "disp", LIST(),
        "bands", LIST(),
        "totals", LEXICON(),
        "engines_on", 0,
        "engines_total", 0,
        "limited", FALSE,
        "part_n", 0
    ).
    SET AOSO_TWIN_LAST_STAGE TO STAGE:NUMBER.
    SET AOSO_TWIN_UID_SIG TO "".
    SET AOSO_TWIN_LAST_FILL TO 0.
    aoso_twin_rebuild("init").
}

FUNCTION aoso_twin_clear_hl {
    FOR hl IN AOSO_TWIN_HLS {
        SET hl:ENABLED TO FALSE.
    }
    SET AOSO_TWIN_HLS TO LIST().
}

FUNCTION aoso_twin_fingerprint {
    LOCAL dock_n IS 0.
    LOCAL dplist IS aoso_parts_dockports().
    SET dock_n TO dplist:LENGTH.
    LOCAL root_uid IS "".
    IF SHIP:ROOTPART:ISTYPE("Part") { SET root_uid TO "" + SHIP:ROOTPART:UID. }
    LOCAL ctrl IS "".
    IF SHIP:CONTROLPART:ISTYPE("Part") { SET ctrl TO "" + SHIP:CONTROLPART:UID. }
    LOCAL n IS 0.
    LOCAL plist IS aoso_parts_list().
    SET n TO plist:LENGTH.
    RETURN n + "|" + STAGE:NUMBER + "|" + root_uid + "|" + dock_n + "|" + ctrl.
}

FUNCTION aoso_twin_kind {
    PARAMETER prt.
    IF prt:ISTYPE("Engine") { RETURN "engine". }
    IF prt:HASMODULE("ModuleEngines") { RETURN "engine". }
    IF prt:HASMODULE("ModuleEnginesFX") { RETURN "engine". }
    IF prt:HASMODULE("ModuleCommand") { RETURN "command". }
    IF prt:HASMODULE("ModuleRCS") { RETURN "rcs". }
    IF prt:HASMODULE("ModuleRCSFX") { RETURN "rcs". }
    IF prt:HASMODULE("ModuleDockingNode") { RETURN "dock". }
    IF prt:HASMODULE("ModuleParachute") { RETURN "chute". }
    IF prt:HASMODULE("ModuleWheelBase") { RETURN "gear". }
    IF prt:HASMODULE("ModuleLandingLeg") { RETURN "gear". }
    IF prt:HASMODULE("ModuleResourceHarvester") { RETURN "isru". }
    IF prt:HASMODULE("ModuleResourceConverter") { RETURN "isru". }
    IF prt:HASMODULE("ModuleDeployableSolarPanel") { RETURN "solar". }
    IF prt:HASMODULE("ModuleDataTransmitter") { RETURN "antenna". }
    IF prt:HASMODULE("ModuleActiveRadiator") { RETURN "radiator". }
    IF prt:HASMODULE("ModuleScienceExperiment") { RETURN "science". }

    LOCAL has_prop IS FALSE.
    LOCAL has_ec IS FALSE.
    LOCAL has_ore IS FALSE.
    FOR res_item IN prt:RESOURCES {
        IF res_item:CAPACITY > 0.001 {
            IF res_item:NAME = "Ore" { SET has_ore TO TRUE. }
            IF res_item:NAME = "ElectricCharge" { SET has_ec TO TRUE. }
            IF aoso_capabilities_is_propellant(res_item:NAME) { SET has_prop TO TRUE. }
        }
    }
    IF has_ore { RETURN "isru". }
    IF has_prop { RETURN "tank". }
    IF has_ec { RETURN "battery". }
    RETURN "structural".
}

FUNCTION aoso_twin_short {
    PARAMETER title.
    IF title:LENGTH <= 16 { RETURN title. }
    RETURN title:SUBSTRING(0, 16).
}

FUNCTION aoso_twin_mod_short {
    PARAMETER prt.
    LOCAL out IS "".
    LOCAL n IS 0.
    FOR mname IN prt:MODULES {
        IF n >= 4 { BREAK. }
        IF out <> "" { SET out TO out + ",". }
        SET out TO out + mname.
        SET n TO n + 1.
    }
    RETURN out.
}

FUNCTION aoso_twin_read_resources {
    PARAMETER prt.
    LOCAL bag IS LIST().
    FOR res_item IN prt:RESOURCES {
        IF res_item:CAPACITY > 0.001 {
            bag:ADD(LEXICON(
                "name", res_item:NAME,
                "amount", res_item:AMOUNT,
                "capacity", res_item:CAPACITY,
                "enabled", res_item:ENABLED
            )).
        }
    }
    RETURN bag.
}

FUNCTION aoso_twin_rebuild {
    PARAMETER reason IS "manual".
    SET AOSO_TWIN["status"] TO "UPDATING".
    SET AOSO_TWIN["reason"] TO reason.
    aoso_twin_clear_hl().
    SET AOSO_TWIN["selected_uid"] TO "".

    LOCAL plist IS aoso_parts_list().
    LOCAL root_pos IS V(0, 0, 0).
    LOCAL root_uid IS "".
    IF SHIP:ROOTPART:ISTYPE("Part") {
        SET root_pos TO SHIP:ROOTPART:POSITION.
        SET root_uid TO "" + SHIP:ROOTPART:UID.
    }

    LOCAL nodes IS LIST().
    LOCAL parts_map IS LEXICON().
    LOCAL totals IS LEXICON().
    LOCAL eng_n IS 0.
    LOCAL eng_on IS 0.

    FOR prt IN plist {
        LOCAL uid IS "" + prt:UID.
        SET parts_map[uid] TO prt.
        LOCAL rel IS prt:POSITION - root_pos.
        LOCAL kind IS aoso_twin_kind(prt).
        LOCAL parent_uid IS "".
        LOCAL depth IS 0.
        IF prt:HASPARENT {
            SET parent_uid TO "" + prt:PARENT:UID.
            LOCAL walk IS prt.
            UNTIL NOT walk:HASPARENT {
                SET walk TO walk:PARENT.
                SET depth TO depth + 1.
                IF depth > 40 { BREAK. }
            }
        }
        LOCAL bag IS aoso_twin_read_resources(prt).
        FOR res_item IN bag {
            LOCAL rn IS res_item["name"].
            IF NOT totals:HASKEY(rn) {
                SET totals[rn] TO LEXICON("amount", 0, "capacity", 0).
            }
            SET totals[rn]["amount"] TO totals[rn]["amount"] + res_item["amount"].
            SET totals[rn]["capacity"] TO totals[rn]["capacity"] + res_item["capacity"].
        }

        LOCAL ignition IS FALSE.
        LOCAL flameout IS FALSE.
        LOCAL thrust_now IS 0.
        LOCAL thrust_max IS 0.
        IF kind = "engine" {
            SET eng_n TO eng_n + 1.
            IF prt:ISTYPE("Engine") {
                SET ignition TO prt:IGNITION.
                SET flameout TO prt:FLAMEOUT.
                SET thrust_now TO prt:THRUST.
                SET thrust_max TO prt:AVAILABLETHRUST.
                IF ignition {
                    IF NOT flameout { SET eng_on TO eng_on + 1. }
                }
            }
        }

        LOCAL dec_in IS -1.
        SET dec_in TO prt:DECOUPLEDIN.

        nodes:ADD(LEXICON(
            "uid", uid,
            "title", prt:TITLE,
            "short", aoso_twin_short(prt:TITLE),
            "kind", kind,
            "parent_uid", parent_uid,
            "depth", depth,
            "stage", prt:STAGE,
            "decoupled_in", dec_in,
            "rx", rel:X,
            "ry", rel:Y,
            "rz", rel:Z,
            "resources", bag,
            "ignition", ignition,
            "flameout", flameout,
            "thrust", thrust_now,
            "maxthrust", thrust_max,
            "mass", prt:MASS,
            "modules", aoso_twin_mod_short(prt),
            "n", 1,
            "members", LIST(uid)
        )).
    }

    SET AOSO_TWIN_PARTS TO parts_map.
    SET AOSO_TWIN["nodes"] TO nodes.
    SET AOSO_TWIN["totals"] TO totals.
    SET AOSO_TWIN["engines_on"] TO eng_on.
    SET AOSO_TWIN["engines_total"] TO eng_n.
    SET AOSO_TWIN["root_uid"] TO root_uid.
    SET AOSO_TWIN["part_n"] TO plist:LENGTH.
    SET AOSO_TWIN["fingerprint"] TO aoso_twin_fingerprint().
    SET AOSO_TWIN["scanned_at"] TO TIME:SECONDS.
    SET AOSO_TWIN_LAST_STAGE TO STAGE:NUMBER.

    aoso_twin_rebuild_display().
    LOCAL limited IS AOSO_TWIN["limited"].
    IF limited { SET AOSO_TWIN["status"] TO "LIMITED". }
    ELSE { SET AOSO_TWIN["status"] TO "SYNCHRONIZED". }
    SET AOSO_TWIN_UID_SIG TO aoso_twin_disp_sig().
    SET AOSO_TWIN_VIEW_DIRTY TO TRUE.
    SET AOSO_TWIN_LAST_FILL TO TIME:SECONDS.
}

FUNCTION aoso_twin_node_keep {
    PARAMETER kind.
    PARAMETER filt.
    IF filt = "ALL" {
        IF kind = "structural" { RETURN FALSE. }
        RETURN TRUE.
    }
    IF filt = "COMMAND" { RETURN kind = "command". }
    IF filt = "FUEL" { RETURN kind = "tank". }
    IF filt = "ENGINES" { RETURN kind = "engine". }
    IF filt = "RCS" { RETURN kind = "rcs". }
    IF filt = "POWER" {
        IF kind = "battery" { RETURN TRUE. }
        IF kind = "solar" { RETURN TRUE. }
        RETURN FALSE.
    }
    IF filt = "DOCKING" { RETURN kind = "dock". }
    IF filt = "SCIENCE" { RETURN kind = "science". }
    IF filt = "STRUCTURAL" { RETURN kind = "structural". }
    IF filt = "PROPULSION" {
        IF kind = "engine" { RETURN TRUE. }
        IF kind = "tank" { RETURN TRUE. }
        IF kind = "rcs" { RETURN TRUE. }
        RETURN FALSE.
    }
    IF filt = "CONTROL" {
        IF kind = "command" { RETURN TRUE. }
        IF kind = "antenna" { RETURN TRUE. }
        IF kind = "rcs" { RETURN TRUE. }
        RETURN FALSE.
    }
    IF filt = "SYSTEM" {
        IF kind = "command" { RETURN TRUE. }
        IF kind = "antenna" { RETURN TRUE. }
        IF kind = "battery" { RETURN TRUE. }
        IF kind = "solar" { RETURN TRUE. }
        IF kind = "rcs" { RETURN TRUE. }
        IF kind = "dock" { RETURN TRUE. }
        IF kind = "isru" { RETURN TRUE. }
        IF kind = "chute" { RETURN TRUE. }
        IF kind = "gear" { RETURN TRUE. }
        IF kind = "radiator" { RETURN TRUE. }
        RETURN FALSE.
    }
    IF filt = "STATUS" { RETURN TRUE. }
    IF kind = "structural" { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_twin_focus_hit {
    PARAMETER bag.
    PARAMETER focus.
    IF focus = "ALL" { RETURN TRUE. }
    FOR res_item IN bag {
        IF res_item["name"] = focus { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_twin_cluster_key {
    PARAMETER tnode.
    RETURN tnode["kind"] + "|" + tnode["stage"] + "|" + tnode["title"].
}

FUNCTION aoso_twin_merge_res {
    PARAMETER into_bag.
    PARAMETER add_bag.
    FOR res_item IN add_bag {
        LOCAL found IS FALSE.
        FOR existing IN into_bag {
            IF existing["name"] = res_item["name"] {
                SET existing["amount"] TO existing["amount"] + res_item["amount"].
                SET existing["capacity"] TO existing["capacity"] + res_item["capacity"].
                SET found TO TRUE.
            }
        }
        IF NOT found {
            into_bag:ADD(LEXICON(
                "name", res_item["name"],
                "amount", res_item["amount"],
                "capacity", res_item["capacity"],
                "enabled", res_item["enabled"]
            )).
        }
    }
}

FUNCTION aoso_twin_rebuild_display {
    LOCAL filt IS AOSO_TWIN["filter"].
    LOCAL focus IS AOSO_TWIN["resource_focus"].
    LOCAL view IS AOSO_TWIN["view"].
    LOCAL kept IS LIST().
    FOR tnode IN AOSO_TWIN["nodes"] {
        IF aoso_twin_node_keep(tnode["kind"], filt) {
            IF aoso_twin_focus_hit(tnode["resources"], focus) {
                IF view = "STATUS" {
                    LOCAL tag IS aoso_twin_flow_tag(tnode).
                    IF tag <> "" { kept:ADD(tnode). }
                    ELSE {
                        IF tnode["kind"] = "engine" { kept:ADD(tnode). }
                    }
                } ELSE {
                    IF filt = "STATUS" {
                        LOCAL tag2 IS aoso_twin_flow_tag(tnode).
                        IF tag2 <> "" { kept:ADD(tnode). }
                        ELSE {
                            IF tnode["kind"] = "engine" { kept:ADD(tnode). }
                        }
                    } ELSE {
                        kept:ADD(tnode).
                    }
                }
            }
        }
    }

    LOCAL limited IS FALSE.
    LOCAL disp IS LIST().
    IF kept:LENGTH <= AOSO_TWIN_CAP {
        SET disp TO kept.
    } ELSE {
        SET limited TO TRUE.
        LOCAL groups IS LEXICON().
        LOCAL order IS LIST().
        FOR tnode IN kept {
            LOCAL key IS aoso_twin_cluster_key(tnode).
            IF NOT groups:HASKEY(key) {
                LOCAL copy IS LEXICON(
                    "uid", tnode["uid"],
                    "title", tnode["title"],
                    "short", tnode["short"],
                    "kind", tnode["kind"],
                    "parent_uid", tnode["parent_uid"],
                    "depth", tnode["depth"],
                    "stage", tnode["stage"],
                    "decoupled_in", tnode["decoupled_in"],
                    "rx", tnode["rx"],
                    "ry", tnode["ry"],
                    "rz", tnode["rz"],
                    "resources", LIST(),
                    "ignition", tnode["ignition"],
                    "flameout", tnode["flameout"],
                    "thrust", tnode["thrust"],
                    "maxthrust", tnode["maxthrust"],
                    "mass", tnode["mass"],
                    "modules", tnode["modules"],
                    "n", 0,
                    "members", LIST()
                ).
                aoso_twin_merge_res(copy["resources"], tnode["resources"]).
                SET groups[key] TO copy.
                order:ADD(key).
            } ELSE {
                aoso_twin_merge_res(groups[key]["resources"], tnode["resources"]).
                SET groups[key]["thrust"] TO groups[key]["thrust"] + tnode["thrust"].
                SET groups[key]["maxthrust"] TO groups[key]["maxthrust"] + tnode["maxthrust"].
                IF tnode["ignition"] { SET groups[key]["ignition"] TO TRUE. }
                IF tnode["flameout"] { SET groups[key]["flameout"] TO TRUE. }
            }
            SET groups[key]["n"] TO groups[key]["n"] + 1.
            groups[key]["members"]:ADD(tnode["uid"]).
        }
        FOR key IN order {
            LOCAL gnode IS groups[key].
            IF gnode["n"] > 1 {
                SET gnode["short"] TO aoso_twin_short(gnode["title"]) + " x" + gnode["n"].
            }
            disp:ADD(gnode).
        }
        UNTIL disp:LENGTH <= AOSO_TWIN_CAP {
            disp:REMOVE(disp:LENGTH - 1).
        }
    }

    SET AOSO_TWIN["disp"] TO disp.
    SET AOSO_TWIN["limited"] TO limited.
    IF view = "STAGING" {
        SET AOSO_TWIN["bands"] TO aoso_twin_bands_stage(disp).
    } ELSE {
        IF view = "SYSTEM" {
            SET AOSO_TWIN["bands"] TO aoso_twin_bands_kind(disp).
        } ELSE {
            IF view = "STATUS" {
                SET AOSO_TWIN["bands"] TO aoso_twin_bands_kind(disp).
            } ELSE {
                SET AOSO_TWIN["bands"] TO aoso_twin_bands_spatial(disp).
            }
        }
    }
}

FUNCTION aoso_twin_bands_stage {
    PARAMETER disp.
    LOCAL by_st IS LEXICON().
    LOCAL st_keys IS LIST().
    FOR tnode IN disp {
        LOCAL key IS "" + tnode["decoupled_in"].
        IF NOT by_st:HASKEY(key) {
            SET by_st[key] TO LIST().
            st_keys:ADD(key).
        }
        by_st[key]:ADD(tnode).
    }
    LOCAL sorted IS LIST().
    UNTIL st_keys:LENGTH = 0 {
        LOCAL best IS 0.
        LOCAL i IS 1.
        UNTIL i >= st_keys:LENGTH {
            IF by_st[st_keys[i]][0]["decoupled_in"] > by_st[st_keys[best]][0]["decoupled_in"] { SET best TO i. }
            SET i TO i + 1.
        }
        sorted:ADD(by_st[st_keys[best]]).
        st_keys:REMOVE(best).
    }
    RETURN sorted.
}

FUNCTION aoso_twin_bands_kind {
    PARAMETER disp.
    LOCAL order IS LIST("command", "antenna", "battery", "solar", "tank", "engine", "rcs", "dock", "isru", "chute", "gear", "science", "radiator", "structural").
    LOCAL byk IS LEXICON().
    FOR tnode IN disp {
        LOCAL k IS tnode["kind"].
        IF NOT byk:HASKEY(k) { SET byk[k] TO LIST(). }
        byk[k]:ADD(tnode).
    }
    LOCAL bands IS LIST().
    FOR k IN order {
        IF byk:HASKEY(k) { bands:ADD(byk[k]). }
    }
    RETURN bands.
}

FUNCTION aoso_twin_axis_of {
    PARAMETER tnode.
    LOCAL ax IS "Y".
    LOCAL avx IS ABS(tnode["rx"]).
    LOCAL avy IS ABS(tnode["ry"]).
    LOCAL avz IS ABS(tnode["rz"]).
    IF avx >= avy {
        IF avx >= avz { SET ax TO "X". }
        ELSE { SET ax TO "Z". }
    } ELSE {
        IF avy >= avz { SET ax TO "Y". }
        ELSE { SET ax TO "Z". }
    }
    RETURN ax.
}

FUNCTION aoso_twin_coord {
    PARAMETER tnode.
    PARAMETER ax.
    IF ax = "X" { RETURN tnode["rx"]. }
    IF ax = "Z" { RETURN tnode["rz"]. }
    RETURN tnode["ry"].
}

FUNCTION aoso_twin_bands_spatial {
    PARAMETER disp.
    IF disp:LENGTH = 0 { RETURN LIST(). }

    LOCAL sx IS 0. LOCAL sy IS 0. LOCAL sz IS 0.
    FOR tnode IN disp {
        SET sx TO sx + tnode["rx"].
        SET sy TO sy + tnode["ry"].
        SET sz TO sz + tnode["rz"].
    }
    LOCAL inv IS 1 / disp:LENGTH.
    LOCAL mx IS sx * inv.
    LOCAL my IS sy * inv.
    LOCAL mz IS sz * inv.
    LOCAL vx IS 0. LOCAL vy IS 0. LOCAL vz IS 0.
    FOR tnode IN disp {
        SET vx TO vx + (tnode["rx"] - mx) * (tnode["rx"] - mx).
        SET vy TO vy + (tnode["ry"] - my) * (tnode["ry"] - my).
        SET vz TO vz + (tnode["rz"] - mz) * (tnode["rz"] - mz).
    }
    LOCAL ax IS "Y".
    IF vx >= vy {
        IF vx >= vz { SET ax TO "X". }
        ELSE { SET ax TO "Z". }
    } ELSE {
        IF vy >= vz { SET ax TO "Y". }
        ELSE { SET ax TO "Z". }
    }
    LOCAL ax2 IS "X".
    IF ax = "X" {
        IF vy >= vz { SET ax2 TO "Y". }
        ELSE { SET ax2 TO "Z". }
    }
    IF ax = "Y" {
        IF vx >= vz { SET ax2 TO "X". }
        ELSE { SET ax2 TO "Z". }
    }
    IF ax = "Z" {
        IF vx >= vy { SET ax2 TO "X". }
        ELSE { SET ax2 TO "Y". }
    }

    LOCAL min_a IS aoso_twin_coord(disp[0], ax).
    LOCAL max_a IS min_a.
    LOCAL eng_sum IS 0.
    LOCAL eng_n IS 0.
    FOR tnode IN disp {
        LOCAL c IS aoso_twin_coord(tnode, ax).
        IF c < min_a { SET min_a TO c. }
        IF c > max_a { SET max_a TO c. }
        IF tnode["kind"] = "engine" {
            SET eng_sum TO eng_sum + c.
            SET eng_n TO eng_n + 1.
        }
    }
    LOCAL span IS max_a - min_a.
    IF span < 0.05 { SET span TO 0.05. }
    LOCAL nb IS MIN(10, MAX(3, disp:LENGTH)).
    LOCAL buckets IS LIST().
    LOCAL bi IS 0.
    UNTIL bi >= nb {
        buckets:ADD(LIST()).
        SET bi TO bi + 1.
    }
    FOR tnode IN disp {
        LOCAL c IS aoso_twin_coord(tnode, ax).
        LOCAL idx IS FLOOR(((c - min_a) / span) * nb).
        IF idx < 0 { SET idx TO 0. }
        IF idx >= nb { SET idx TO nb - 1. }
        buckets[idx]:ADD(tnode).
    }

    LOCAL eng_mean IS min_a.
    IF eng_n > 0 { SET eng_mean TO eng_sum / eng_n. }
    LOCAL engines_high IS FALSE.
    IF ABS(eng_mean - max_a) < ABS(eng_mean - min_a) { SET engines_high TO TRUE. }

    LOCAL bands IS LIST().
    IF engines_high {
        SET bi TO 0.
        UNTIL bi >= nb {
            IF buckets[bi]:LENGTH > 0 { bands:ADD(aoso_twin_sort_band(buckets[bi], ax2)). }
            SET bi TO bi + 1.
        }
    } ELSE {
        SET bi TO nb - 1.
        UNTIL bi < 0 {
            IF buckets[bi]:LENGTH > 0 { bands:ADD(aoso_twin_sort_band(buckets[bi], ax2)). }
            SET bi TO bi - 1.
        }
    }
    RETURN bands.
}

FUNCTION aoso_twin_sort_band {
    PARAMETER band.
    PARAMETER ax2.
    LOCAL out IS LIST().
    LOCAL rest IS LIST().
    FOR tnode IN band { rest:ADD(tnode). }
    UNTIL rest:LENGTH = 0 {
        LOCAL best IS 0.
        LOCAL i IS 1.
        UNTIL i >= rest:LENGTH {
            IF aoso_twin_coord(rest[i], ax2) < aoso_twin_coord(rest[best], ax2) { SET best TO i. }
            SET i TO i + 1.
        }
        out:ADD(rest[best]).
        rest:REMOVE(best).
    }
    RETURN out.
}

FUNCTION aoso_twin_disp_sig {
    LOCAL sig IS AOSO_TWIN["view"] + "|" + AOSO_TWIN["filter"] + "|" + AOSO_TWIN["resource_focus"] + "|".
    FOR tnode IN AOSO_TWIN["disp"] {
        SET sig TO sig + tnode["uid"] + ",".
    }
    RETURN sig.
}

FUNCTION aoso_twin_refresh_fills {
    LOCAL totals IS LEXICON().
    LOCAL eng_on IS 0.
    LOCAL eng_n IS 0.
    FOR tnode IN AOSO_TWIN["nodes"] {
        LOCAL uid IS tnode["uid"].
        IF AOSO_TWIN_PARTS:HASKEY(uid) {
            LOCAL prt IS AOSO_TWIN_PARTS[uid].
            SET tnode["resources"] TO aoso_twin_read_resources(prt).
            SET tnode["mass"] TO prt:MASS.
            IF tnode["kind"] = "engine" {
                SET eng_n TO eng_n + 1.
                IF prt:ISTYPE("Engine") {
                    SET tnode["ignition"] TO prt:IGNITION.
                    SET tnode["flameout"] TO prt:FLAMEOUT.
                    SET tnode["thrust"] TO prt:THRUST.
                    SET tnode["maxthrust"] TO prt:AVAILABLETHRUST.
                    IF prt:IGNITION {
                        IF NOT prt:FLAMEOUT { SET eng_on TO eng_on + 1. }
                    }
                }
            }
        }
        FOR res_item IN tnode["resources"] {
            LOCAL rn IS res_item["name"].
            IF NOT totals:HASKEY(rn) {
                SET totals[rn] TO LEXICON("amount", 0, "capacity", 0).
            }
            SET totals[rn]["amount"] TO totals[rn]["amount"] + res_item["amount"].
            SET totals[rn]["capacity"] TO totals[rn]["capacity"] + res_item["capacity"].
        }
    }
    SET AOSO_TWIN["totals"] TO totals.
    SET AOSO_TWIN["engines_on"] TO eng_on.
    SET AOSO_TWIN["engines_total"] TO eng_n.

    IF AOSO_TWIN["limited"] {
        aoso_twin_rebuild_display().
    } ELSE {
        FOR dnode IN AOSO_TWIN["disp"] {
            IF dnode["n"] <= 1 {
                IF AOSO_TWIN_PARTS:HASKEY(dnode["uid"]) {
                    SET dnode["resources"] TO aoso_twin_read_resources(AOSO_TWIN_PARTS[dnode["uid"]]).
                    SET dnode["mass"] TO AOSO_TWIN_PARTS[dnode["uid"]]:MASS.
                    LOCAL prt IS AOSO_TWIN_PARTS[dnode["uid"]].
                    IF dnode["kind"] = "engine" {
                        IF prt:ISTYPE("Engine") {
                            SET dnode["ignition"] TO prt:IGNITION.
                            SET dnode["flameout"] TO prt:FLAMEOUT.
                            SET dnode["thrust"] TO prt:THRUST.
                        }
                    }
                }
            }
        }
    }
}

FUNCTION aoso_twin_engine_state {
    PARAMETER tnode.
    IF tnode["kind"] <> "engine" { RETURN "". }
    IF tnode["flameout"] {
        IF THROTTLE > 0.05 { RETURN "STARVED". }
        RETURN "FLAMEOUT".
    }
    IF tnode["ignition"] { RETURN "ACTIVE". }
    RETURN "IDLE".
}

FUNCTION aoso_twin_flow_tag {
    PARAMETER tnode.
    IF tnode["kind"] = "engine" { RETURN aoso_twin_engine_state(tnode). }
    IF tnode["kind"] <> "tank" { RETURN "". }
    LOCAL enabled IS TRUE.
    LOCAL empty IS TRUE.
    FOR res_item IN tnode["resources"] {
        IF aoso_capabilities_is_propellant(res_item["name"]) {
            IF res_item["amount"] > 0.05 { SET empty TO FALSE. }
            IF NOT res_item["enabled"] { SET enabled TO FALSE. }
        }
    }
    IF NOT enabled { RETURN "DISABLED". }
    IF empty { RETURN "EMPTY". }
    IF AOSO_TWIN["engines_on"] > 0 {
        IF tnode["stage"] = STAGE:NUMBER { RETURN "FEED". }
    }
    RETURN "".
}

FUNCTION aoso_twin_select {
    PARAMETER uid.
    aoso_twin_clear_hl().
    SET AOSO_TWIN["selected_uid"] TO uid.
    LOCAL members IS LIST(uid).
    FOR dnode IN AOSO_TWIN["disp"] {
        IF dnode["uid"] = uid { SET members TO dnode["members"]. }
    }
    LOCAL n_hl IS 0.
    FOR mu IN members {
        IF n_hl >= 4 { BREAK. }
        IF AOSO_TWIN_PARTS:HASKEY(mu) {
            LOCAL hl IS HIGHLIGHT(AOSO_TWIN_PARTS[mu], RGB(0.25, 0.85, 1.0)).
            AOSO_TWIN_HLS:ADD(hl).
            SET n_hl TO n_hl + 1.
        }
    }
}

FUNCTION aoso_twin_set_view {
    PARAMETER view.
    SET AOSO_TWIN["view"] TO view.
    aoso_twin_rebuild_display().
}

FUNCTION aoso_twin_set_filter {
    PARAMETER filt.
    SET AOSO_TWIN["filter"] TO filt.
    aoso_twin_rebuild_display().
}

FUNCTION aoso_twin_set_focus {
    PARAMETER focus.
    SET AOSO_TWIN["resource_focus"] TO focus.
    aoso_twin_rebuild_display().
}

FUNCTION aoso_twin_status_txt {
    LOCAL st IS AOSO_TWIN["status"].
    IF st = "SYNCHRONIZED" { RETURN "TWIN  SYNCHRONIZED". }
    IF st = "UPDATING" { RETURN "TWIN  UPDATING". }
    IF st = "LIMITED" { RETURN "TWIN  LIMITED (aggregated)". }
    IF st = "GEOMETRY_INVALID" { RETURN "TWIN  GEOMETRY INVALID". }
    RETURN "TWIN  " + st.
}

FUNCTION aoso_twin_tick {
    PARAMETER allow_geom.
    PARAMETER allow_fills.
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl >= 3 { RETURN. }

    IF allow_geom {
        IF STAGE:NUMBER <> AOSO_TWIN_LAST_STAGE {
            aoso_twin_rebuild("stage").
            RETURN.
        }
        IF lvl < 2 {
            IF TIME:SECONDS - AOSO_TWIN["scanned_at"] >= 1 {
                LOCAL fp IS aoso_twin_fingerprint().
                IF fp <> AOSO_TWIN["fingerprint"] {
                    aoso_twin_rebuild("fingerprint").
                    RETURN.
                }
            }
        }
    }
    IF allow_fills {
        IF lvl >= 2 { RETURN. }
        IF TIME:SECONDS - AOSO_TWIN_LAST_FILL >= 0.5 {
            aoso_twin_refresh_fills().
            SET AOSO_TWIN_LAST_FILL TO TIME:SECONDS.
        }
    }
}
