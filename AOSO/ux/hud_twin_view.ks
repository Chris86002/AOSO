// AOSO/ux/hud_twin_view.ks
// GUI schematic for AOSO_TWIN. Widgets for the node set are rebuilt
// only when the displayed UID set / view / filter changes. Tank bars
// update in place. APPROXIMATE flow tags are labelled as such.

GLOBAL AOSO_TWIN_BOX IS 0.
GLOBAL AOSO_TWIN_W IS LEXICON().
GLOBAL AOSO_TWIN_LAST IS LEXICON().

FUNCTION aoso_twin_wset {
    PARAMETER key.
    PARAMETER txt.
    IF NOT AOSO_TWIN_W:HASKEY(key) { RETURN. }
    IF AOSO_TWIN_LAST:HASKEY(key) {
        IF AOSO_TWIN_LAST[key] = txt { RETURN. }
    }
    SET AOSO_TWIN_LAST[key] TO txt.
    SET AOSO_TWIN_W[key]:TEXT TO txt.
}

FUNCTION aoso_twin_primary_pct {
    PARAMETER node.
    LOCAL focus IS AOSO_TWIN["resource_focus"].
    LOCAL best_amt IS -1.
    LOCAL best_cap IS 0.
    FOR res_item IN node["resources"] {
        LOCAL use IS FALSE.
        IF focus = "ALL" {
            IF aoso_capabilities_is_propellant(res_item["name"]) { SET use TO TRUE. }
            IF node["kind"] = "battery" {
                IF res_item["name"] = "ElectricCharge" { SET use TO TRUE. }
            }
            IF node["kind"] = "isru" {
                IF res_item["name"] = "Ore" { SET use TO TRUE. }
            }
        } ELSE {
            IF res_item["name"] = focus { SET use TO TRUE. }
        }
        IF use {
            IF res_item["capacity"] > best_cap {
                SET best_cap TO res_item["capacity"].
                SET best_amt TO res_item["amount"].
            }
        }
    }
    IF best_cap <= 0 { RETURN -1. }
    RETURN 100 * best_amt / best_cap.
}

FUNCTION aoso_twin_node_txt {
    PARAMETER node.
    LOCAL tag IS node["kind"].
    IF tag:LENGTH >= 3 { SET tag TO tag:SUBSTRING(0, 3):TOUPPER. }
    ELSE { SET tag TO tag:TOUPPER. }
    LOCAL line IS tag + "  " + node["short"].
    LOCAL pct IS aoso_twin_primary_pct(node).
    IF pct >= 0 { SET line TO line + "  " + ROUND(pct, 0) + "%". }
    LOCAL flow IS aoso_twin_flow_tag(node).
    IF flow <> "" { SET line TO line + "  " + flow. }
    RETURN line.
}

FUNCTION aoso_twin_bar_txt {
    PARAMETER node.
    LOCAL focus IS AOSO_TWIN["resource_focus"].
    LOCAL lines IS "".
    FOR res_item IN node["resources"] {
        LOCAL show IS FALSE.
        IF focus = "ALL" { SET show TO TRUE. }
        IF res_item["name"] = focus { SET show TO TRUE. }
        IF show {
            LOCAL pct IS 0.
            IF res_item["capacity"] > 0 { SET pct TO 100 * res_item["amount"] / res_item["capacity"]. }
            LOCAL nm IS res_item["name"].
            IF nm = "LiquidFuel" { SET nm TO "LF". }
            IF nm = "Oxidizer" { SET nm TO "OX". }
            IF nm = "ElectricCharge" { SET nm TO "EC". }
            IF nm = "MonoPropellant" { SET nm TO "MP". }
            IF lines <> "" { SET lines TO lines + "  ". }
            SET lines TO lines + nm + " " + aoso_hud_bar(pct, 8).
        }
    }
    RETURN lines.
}

FUNCTION aoso_twin_view_filter { PARAMETER filt. aoso_twin_set_filter(filt). SET AOSO_TWIN_VIEW_DIRTY TO TRUE. }
FUNCTION aoso_twin_view_mode {
    PARAMETER view.
    aoso_twin_set_view(view).
    IF view = "FUEL" { aoso_twin_set_filter("FUEL"). }
    IF view = "POWER" { aoso_twin_set_filter("POWER"). }
    IF view = "PROPULSION" { aoso_twin_set_filter("PROPULSION"). }
    IF view = "CONTROL" { aoso_twin_set_filter("CONTROL"). }
    IF view = "NORMAL" { aoso_twin_set_filter("ALL"). }
    IF view = "STAGING" { aoso_twin_set_filter("ALL"). }
    SET AOSO_TWIN_VIEW_DIRTY TO TRUE.
}
FUNCTION aoso_twin_view_focus { PARAMETER focus. aoso_twin_set_focus(focus). SET AOSO_TWIN_VIEW_DIRTY TO TRUE. }

FUNCTION aoso_twin_view_rebuild_user {
    aoso_twin_rebuild("user").
    SET AOSO_TWIN_VIEW_DIRTY TO TRUE.
}

FUNCTION aoso_twin_view_build {
    PARAMETER page.
    aoso_hud_title(page, "DIGITAL TWIN").
    aoso_hud_lab(page, "tw_st", "TWIN  UPDATING").
    aoso_hud_lab(page, "tw_tot", "TOTALS  -").
    aoso_hud_lab(page, "tw_eng", "ENGINES  -").
    aoso_hud_lab(page, "tw_note", "Flow tags are APPROXIMATE (no crossfeed solver).").

    LOCAL vrow IS page:ADDHLAYOUT().
    LOCAL b1 IS vrow:ADDBUTTON("NORM").
    SET b1:ONCLICK TO aoso_twin_view_mode@:BIND("NORMAL").
    LOCAL b2 IS vrow:ADDBUTTON("STG").
    SET b2:ONCLICK TO aoso_twin_view_mode@:BIND("STAGING").
    LOCAL b3 IS vrow:ADDBUTTON("FUEL").
    SET b3:ONCLICK TO aoso_twin_view_mode@:BIND("FUEL").
    LOCAL b4 IS vrow:ADDBUTTON("PWR").
    SET b4:ONCLICK TO aoso_twin_view_mode@:BIND("POWER").
    LOCAL b5 IS vrow:ADDBUTTON("ENG").
    SET b5:ONCLICK TO aoso_twin_view_mode@:BIND("PROPULSION").
    LOCAL b6 IS vrow:ADDBUTTON("CTL").
    SET b6:ONCLICK TO aoso_twin_view_mode@:BIND("CONTROL").

    LOCAL frow IS page:ADDHLAYOUT().
    LOCAL f1 IS frow:ADDBUTTON("ALL").
    SET f1:ONCLICK TO aoso_twin_view_filter@:BIND("ALL").
    LOCAL f2 IS frow:ADDBUTTON("TANK").
    SET f2:ONCLICK TO aoso_twin_view_filter@:BIND("FUEL").
    LOCAL f3 IS frow:ADDBUTTON("ENG").
    SET f3:ONCLICK TO aoso_twin_view_filter@:BIND("ENGINES").
    LOCAL f4 IS frow:ADDBUTTON("PWR").
    SET f4:ONCLICK TO aoso_twin_view_filter@:BIND("POWER").
    LOCAL f5 IS frow:ADDBUTTON("CMD").
    SET f5:ONCLICK TO aoso_twin_view_filter@:BIND("COMMAND").
    LOCAL rb IS frow:ADDBUTTON("REBUILD").
    SET rb:ONCLICK TO aoso_twin_view_rebuild_user@.

    LOCAL rrow IS page:ADDHLAYOUT().
    LOCAL r0 IS rrow:ADDBUTTON("RES ALL").
    SET r0:ONCLICK TO aoso_twin_view_focus@:BIND("ALL").
    LOCAL r1 IS rrow:ADDBUTTON("LF").
    SET r1:ONCLICK TO aoso_twin_view_focus@:BIND("LiquidFuel").
    LOCAL r2 IS rrow:ADDBUTTON("OX").
    SET r2:ONCLICK TO aoso_twin_view_focus@:BIND("Oxidizer").
    LOCAL r3 IS rrow:ADDBUTTON("EC").
    SET r3:ONCLICK TO aoso_twin_view_focus@:BIND("ElectricCharge").
    LOCAL r4 IS rrow:ADDBUTTON("MP").
    SET r4:ONCLICK TO aoso_twin_view_focus@:BIND("MonoPropellant").
    LOCAL r5 IS rrow:ADDBUTTON("ORE").
    SET r5:ONCLICK TO aoso_twin_view_focus@:BIND("Ore").

    SET AOSO_TWIN_BOX TO page:ADDVLAYOUT().
    aoso_hud_lab(page, "tw_sel", "SELECT a node").
    aoso_hud_lab(page, "tw_det", "").
    aoso_hud_lab(page, "tw_mod", "").
    SET AOSO_TWIN_VIEW_DIRTY TO TRUE.
}

FUNCTION aoso_twin_view_clear_box {
    IF NOT AOSO_TWIN_BOX:ISTYPE("Box") { RETURN. }
    LOCAL kids IS AOSO_TWIN_BOX:WIDGETS.
    FOR w IN kids {
        w:DISPOSE().
    }
    SET AOSO_TWIN_W TO LEXICON().
    SET AOSO_TWIN_LAST TO LEXICON().
}

FUNCTION aoso_twin_view_rebuild_schematic {
    aoso_twin_view_clear_box().
    IF NOT AOSO_TWIN_BOX:ISTYPE("Box") { RETURN. }
    LOCAL bands IS AOSO_TWIN["bands"].
    IF bands:LENGTH = 0 {
        LOCAL empty IS AOSO_TWIN_BOX:ADDLABEL("no matching parts").
        SET empty:STYLE:HSTRETCH TO TRUE.
        RETURN.
    }
    LOCAL bi IS 0.
    UNTIL bi >= bands:LENGTH {
        IF bi > 0 {
            LOCAL conn IS AOSO_TWIN_BOX:ADDLABEL("          |").
            SET conn:STYLE:HSTRETCH TO TRUE.
        }
        LOCAL row IS AOSO_TWIN_BOX:ADDHLAYOUT().
        FOR node IN bands[bi] {
            LOCAL uid IS node["uid"].
            LOCAL btn IS row:ADDBUTTON(aoso_twin_node_txt(node)).
            SET btn:ONCLICK TO aoso_twin_select@:BIND(uid).
            SET AOSO_TWIN_W[uid] TO btn.
            SET AOSO_TWIN_LAST[uid] TO btn:TEXT.
        }
        SET bi TO bi + 1.
    }
    SET AOSO_TWIN_UID_SIG TO aoso_twin_disp_sig().
    SET AOSO_TWIN_VIEW_DIRTY TO FALSE.
}

FUNCTION aoso_twin_view_upd_fills {
    FOR node IN AOSO_TWIN["disp"] {
        LOCAL uid IS node["uid"].
        IF AOSO_TWIN_W:HASKEY(uid) {
            LOCAL txt IS aoso_twin_node_txt(node).
            IF NOT AOSO_TWIN_LAST:HASKEY(uid) {
                SET AOSO_TWIN_W[uid]:TEXT TO txt.
                SET AOSO_TWIN_LAST[uid] TO txt.
            } ELSE {
                IF AOSO_TWIN_LAST[uid] <> txt {
                    SET AOSO_TWIN_W[uid]:TEXT TO txt.
                    SET AOSO_TWIN_LAST[uid] TO txt.
                }
            }
        }
    }
}

FUNCTION aoso_twin_totals_txt {
    LOCAL tot IS AOSO_TWIN["totals"].
    LOCAL out IS "TOTALS".
    LOCAL names IS LIST("LiquidFuel", "Oxidizer", "ElectricCharge", "MonoPropellant", "Ore").
    LOCAL labels IS LIST("LF", "OX", "EC", "MP", "ORE").
    LOCAL i IS 0.
    UNTIL i >= names:LENGTH {
        LOCAL rn IS names[i].
        IF tot:HASKEY(rn) {
            IF tot[rn]["capacity"] > 0.001 {
                LOCAL pct IS 100 * tot[rn]["amount"] / tot[rn]["capacity"].
                SET out TO out + "  " + labels[i] + " " + ROUND(pct, 0) + "%".
            }
        }
        SET i TO i + 1.
    }
    RETURN out.
}

FUNCTION aoso_twin_detail_txt {
    LOCAL uid IS AOSO_TWIN["selected_uid"].
    IF uid = "" { RETURN "SELECT a node". }
    LOCAL node IS 0.
    FOR dnode IN AOSO_TWIN["disp"] {
        IF dnode["uid"] = uid { SET node TO dnode. }
    }
    IF NOT node:ISTYPE("Lexicon") { RETURN "SELECT a node". }
    LOCAL line IS node["title"] + "  " + node["kind"]:TOUPPER.
    IF node["n"] > 1 { SET line TO line + "  x" + node["n"]. }
    SET line TO line + "  STG " + node["stage"].
    LOCAL bars IS aoso_twin_bar_txt(node).
    IF bars <> "" { SET line TO line + "  " + bars. }
    RETURN line.
}

FUNCTION aoso_twin_view_tick {
    LOCAL st IS aoso_twin_status_txt().
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl >= 2 { SET st TO st + "  CPU HOLD". }
    aoso_hud_set("tw_st", st + "  view " + AOSO_TWIN["view"] + "  " + AOSO_TWIN["part_n"] + " parts").
    aoso_hud_set("tw_tot", aoso_twin_totals_txt()).
    aoso_hud_set("tw_eng", "ENGINES  " + AOSO_TWIN["engines_on"] + " / " + AOSO_TWIN["engines_total"] + " active   flow APPROXIMATE").
    aoso_hud_set("tw_sel", aoso_twin_detail_txt()).

    IF lvl >= 2 { RETURN. }

    LOCAL sig IS aoso_twin_disp_sig().
    IF AOSO_TWIN_VIEW_DIRTY {
        aoso_twin_view_rebuild_schematic().
        RETURN.
    }
    IF sig <> AOSO_TWIN_UID_SIG {
        aoso_twin_view_rebuild_schematic().
        RETURN.
    }
    aoso_twin_view_upd_fills().
}
