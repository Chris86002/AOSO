// AOSO/ux/hud_gui.ks
// Movable AOSO computer. Pages are VLAYOUT children toggled with VISIBLE.
// Labels update only when the text actually changed.

GLOBAL AOSO_HUD_GUI IS 0.
GLOBAL AOSO_HUD_STACK IS 0.
GLOBAL AOSO_HUD_BODY IS 0.
GLOBAL AOSO_HUD_PAGES IS LEXICON().
GLOBAL AOSO_HUD_TABS IS LEXICON().
GLOBAL AOSO_HUD_W IS LEXICON().
GLOBAL AOSO_HUD_LAST IS LEXICON().
GLOBAL AOSO_HUD_PAGE IS "".
GLOBAL AOSO_HUD_GUI_ON IS TRUE.
GLOBAL AOSO_HUD_SHOW_LND IS TRUE.
GLOBAL AOSO_HUD_SHOW_PRP IS TRUE.
GLOBAL AOSO_HUD_TAB_LOCK IS FALSE.
GLOBAL AOSO_HUD_TABLABEL IS LEXICON().
GLOBAL AOSO_HUD_HIST IS LIST().
GLOBAL AOSO_HUD_SCALE IS 2.
GLOBAL AOSO_HUD_COMPACT IS FALSE.
GLOBAL AOSO_HUD_BTN_X IS 0.
GLOBAL AOSO_HUD_HDR_TITLE IS 0.
GLOBAL AOSO_HUD_LAST_GUI IS 0.
GLOBAL AOSO_HUD_GUI_PAINTED IS "".
GLOBAL AOSO_HUD_TAC_CHIP IS 0.
GLOBAL AOSO_UI2_AUTO_PAGE IS TRUE.
GLOBAL AOSO_UI2_MANUAL_UNTIL IS 0.
GLOBAL AOSO_UI2_READY IS FALSE.
GLOBAL AOSO_UI2_SELFTEST_REASON IS "not run".
GLOBAL AOSO_UI2_LAST_RENDER_MS IS 0.
GLOBAL AOSO_UI2_MAX_RENDER_MS IS 0.
GLOBAL AOSO_UI2_LAST_RENDER_OP IS 0.
GLOBAL AOSO_UI2_MAX_RENDER_OP IS 0.
GLOBAL AOSO_UI2_LAST_RENDER_PAGE IS "".

FUNCTION aoso_ui2_selftest {
    SET AOSO_UI2_READY TO FALSE.
    SET AOSO_UI2_SELFTEST_REASON TO "".

    IF NOT aoso_config_get("UI2_ENABLED", TRUE) {
        SET AOSO_UI2_SELFTEST_REASON TO "disabled by config".
        RETURN FALSE.
    }

    LOCAL missing_widgets IS LIST().
    IF NOT AOSO_UI2_PFD_MAIN:ISTYPE("BOX") { missing_widgets:ADD("PFD"). }
    IF NOT AOSO_UI2_NAV_MAIN:ISTYPE("BOX") { missing_widgets:ADD("NAV"). }
    IF NOT AOSO_UI2_SURF_MAIN:ISTYPE("BOX") { missing_widgets:ADD("SURF"). }
    IF NOT AOSO_UI2_MSN_MAIN:ISTYPE("BOX") { missing_widgets:ADD("TOUR"). }
    IF NOT AOSO_UI2_SYS_MAIN:ISTYPE("BOX") { missing_widgets:ADD("SYS"). }
    IF NOT AOSO_UI2_VEH_MAIN:ISTYPE("BOX") { missing_widgets:ADD("VEH"). }

    // Widget existence alone reported READY even when archive PNGs were
    // missing. Check the installed art that every primary view can request.
    LOCAL image_files IS LIST(
        "pfd_frame.png", "nav_frame.png", "survey_frame.png",
        "landing_frame.png", "descent_frame.png", "mission_frame.png",
        "systems_frame.png", "twin_frame.png", "window_bg.png",
        "readout_frame.png", "hud_clear.png", "hud_overlay.png", "button_off.png",
        "button_hover.png", "button_on.png", "button_stby.png",
        "button_warn.png", "button_fail.png", "diamond.png",
        "ship_bug.png", "site_bug.png", "target_bug.png",
        "pred_bug.png", "trail_bug.png", "hscale.png", "vscale.png"
    ).
    FOR image_file IN image_files {
        IF NOT EXISTS("0:/" + AOSO_UI2_ASSET_ROOT + image_file) {
            missing_widgets:ADD("art " + image_file).
        }
    }

    IF missing_widgets:LENGTH > 0 {
        LOCAL miss_txt IS "".
        FOR missing_widget IN missing_widgets {
            IF miss_txt <> "" { SET miss_txt TO miss_txt + ",". }
            SET miss_txt TO miss_txt + missing_widget.
        }
        SET AOSO_UI2_SELFTEST_REASON TO "missing " + miss_txt.
        aoso_log_warn("UI2", "Startup self-test FAILED: " + AOSO_UI2_SELFTEST_REASON + ".").
        RETURN FALSE.
    }

    SET AOSO_UI2_READY TO TRUE.
    SET AOSO_UI2_SELFTEST_REASON TO "PFD NAV TOUR VEH SURF SYS ready".
    aoso_log_info("UI2", "Startup self-test READY: " + AOSO_UI2_SELFTEST_REASON + ".").
    RETURN TRUE.
}

FUNCTION aoso_hud_set {
    PARAMETER key.
    PARAMETER txt.
    IF NOT AOSO_HUD_W:HASKEY(key) { RETURN. }
    IF AOSO_HUD_LAST:HASKEY(key) {
        IF AOSO_HUD_LAST[key] = txt { RETURN. }
    }
    SET AOSO_HUD_LAST[key] TO txt.
    SET AOSO_HUD_W[key]:TEXT TO txt.
}

FUNCTION aoso_hud_lab {
    PARAMETER box.
    PARAMETER key.
    PARAMETER txt.
    LOCAL w IS box:ADDLABEL(txt).
    SET w:STYLE:HSTRETCH TO TRUE.
    SET AOSO_HUD_W[key] TO w.
    SET AOSO_HUD_LAST[key] TO txt.
    RETURN w.
}

FUNCTION aoso_hud_title {
    PARAMETER box.
    PARAMETER txt.
    LOCAL w IS box:ADDLABEL("<b>" + txt + "</b>").
    SET w:STYLE:HSTRETCH TO TRUE.
    RETURN w.
}

FUNCTION aoso_hud_hint {
    PARAMETER box.
    PARAMETER txt.
    LOCAL w IS box:ADDLABEL(txt).
    SET w:STYLE:HSTRETCH TO TRUE.
    SET w:STYLE:WORDWRAP TO TRUE.
    RETURN w.
}

// Each display is a real instrument with a permanent, labelled data bank.
// Telemetry must never be hidden behind a global toggle.
FUNCTION aoso_ops_readout {
    PARAMETER row.
    PARAMETER title.
    LOCAL bank IS row:ADDVBOX().
    SET bank:STYLE:WIDTH TO 430.
    SET bank:STYLE:HEIGHT TO 480.
    SET bank:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "readout_frame.png".
    LOCAL heading IS bank:ADDLABEL("<b>" + title + "</b>").
    SET heading:STYLE:HSTRETCH TO TRUE.
    SET heading:STYLE:ALIGN TO "center".
    RETURN bank.
}

FUNCTION aoso_ops_display {
    PARAMETER row.
    LOCAL display IS row:ADDVLAYOUT().
    SET display:STYLE:WIDTH TO 430.
    SET display:STYLE:HEIGHT TO 480.
    RETURN display.
}

FUNCTION aoso_hud_gui_dispose {
    aoso_twin_clear_hl().
    IF AOSO_HUD_GUI:ISTYPE("GUI") {
        AOSO_HUD_GUI:DISPOSE().
    }
    SET AOSO_HUD_GUI TO 0.
    SET AOSO_HUD_STACK TO 0.
    SET AOSO_HUD_BODY TO 0.
    SET AOSO_HUD_BTN_X TO 0.
    SET AOSO_HUD_HDR_TITLE TO 0.
    IF AOSO_HUD_TAC_CHIP:ISTYPE("GUI") {
        AOSO_HUD_TAC_CHIP:DISPOSE().
    }
    SET AOSO_HUD_TAC_CHIP TO 0.
    SET AOSO_HUD_PAGES TO LEXICON().
    SET AOSO_HUD_TABS TO LEXICON().
    SET AOSO_HUD_TABLABEL TO LEXICON().
    SET AOSO_HUD_TAB_LOCK TO FALSE.
    SET AOSO_HUD_PAGE TO "".
    SET AOSO_HUD_W TO LEXICON().
    SET AOSO_HUD_LAST TO LEXICON().
}

FUNCTION aoso_hud_add_page {
    PARAMETER name.
    LOCAL p IS AOSO_HUD_STACK:ADDVLAYOUT().
    SET p:VISIBLE TO FALSE.
    SET AOSO_HUD_PAGES[name] TO p.
    RETURN p.
}

FUNCTION aoso_hud_show_page {
    PARAMETER name.
    PARAMETER record IS TRUE.
    IF AOSO_HUD_TAB_LOCK { RETURN. }
    IF NOT AOSO_HUD_PAGES:HASKEY(name) { RETURN. }
    IF AOSO_HUD_PAGE = name { RETURN. }
    SET AOSO_HUD_TAB_LOCK TO TRUE.
    IF record {
        IF AOSO_HUD_PAGE <> "" {
            AOSO_HUD_HIST:ADD(AOSO_HUD_PAGE).
            IF AOSO_HUD_HIST:LENGTH > 8 { AOSO_HUD_HIST:REMOVE(0). }
        }
    }
    SET AOSO_HUD_PAGE TO name.
    FOR pk IN AOSO_HUD_PAGES:KEYS {
        SET AOSO_HUD_PAGES[pk]:VISIBLE TO (pk = name).
    }
    FOR k IN AOSO_HUD_TABS:KEYS {
        LOCAL lab IS k.
        IF AOSO_HUD_TABLABEL:HASKEY(k) { SET lab TO AOSO_HUD_TABLABEL[k]. }
        IF k = name {
            SET AOSO_HUD_TABS[k]:TEXT TO "[" + lab + "]".
            aoso_ui2_button_bg(AOSO_HUD_TABS[k], "button_on").
        } ELSE {
            SET AOSO_HUD_TABS[k]:TEXT TO lab.
            aoso_ui2_button_bg(AOSO_HUD_TABS[k], "button_off").
        }
    }
    SET AOSO_HUD_TAB_LOCK TO FALSE.
    aoso_hud_event_push("INFO", "page " + name).
}

FUNCTION aoso_hud_tab_click {
    PARAMETER name.
    IF AOSO_HUD_COMPACT { aoso_hud_set_compact(FALSE). }
    SET AOSO_UI2_MANUAL_UNTIL TO TIME:SECONDS +
        aoso_config_get("UI2_MANUAL_PAGE_HOLD_S", 30).
    aoso_hud_show_page(name).
}

FUNCTION aoso_ui2_auto_page_toggle {
    PARAMETER on.
    SET AOSO_UI2_AUTO_PAGE TO on.
    IF on { SET AOSO_UI2_MANUAL_UNTIL TO 0. }
}

FUNCTION aoso_ui2_auto_page_tick {
    IF NOT AOSO_UI2_AUTO_PAGE { RETURN. }
    IF AOSO_HUD_MODE = "ENGINEERING" { RETURN. }
    IF TIME:SECONDS < AOSO_UI2_MANUAL_UNTIL { RETURN. }
    IF AOSO_HUD_PAGE = "HELP" OR AOSO_HUD_PAGE = "DBG" OR AOSO_HUD_PAGE = "LOG" { RETURN. }

    LOCAL want IS "FLT".
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL l IS AOSO_HUD_DATA["landing"].

    IF sys["rollup"] = "FAIL" {
        SET want TO "SYS".
    } ELSE {
        LOCAL tour_st IS "".
        IF DEFINED AOSO_TOUR { SET tour_st TO AOSO_TOUR["current"]. }
        IF l["active"] OR tour_st = "POLAR" OR tour_st = "SCAN" OR tour_st = "DEORBIT" OR tour_st = "DESCEND" {
            SET want TO "LND".
        } ELSE {
            IF o["node"] OR o["burning"] {
                SET want TO "NAV".
            } ELSE {
                LOCAL nav_active IS FALSE.
                IF DEFINED AOSO_GOTO {
                    LOCAL gs IS AOSO_GOTO["current"].
                    IF gs <> "" AND gs <> "DONE" AND gs <> "ABORTED" { SET nav_active TO TRUE. }
                }
                IF nav_active {
                    SET want TO "NAV".
                } ELSE {
                    IF tour_st = "PLAN" OR tour_st = "REFUEL" OR tour_st = "TAKEOFF" {
                        SET want TO "MSN".
                    }
                }
            }
        }
    }

    IF want <> AOSO_HUD_PAGE { aoso_hud_show_page(want, FALSE). }
}

FUNCTION aoso_hud_add_tab {
    PARAMETER row.
    PARAMETER name.
    PARAMETER label.
    LOCAL b IS row:ADDBUTTON(label).
    SET b:ONCLICK TO aoso_hud_tab_click@:BIND(name).
    SET AOSO_HUD_TABS[name] TO b.
    SET AOSO_HUD_TABLABEL[name] TO label.
    RETURN b.
}

FUNCTION aoso_hud_scale_fs {
    RETURN 10 + (2 * AOSO_HUD_SCALE).
}

FUNCTION aoso_hud_scale_width {
    RETURN 830 + (45 * AOSO_HUD_SCALE).
}

FUNCTION aoso_hud_scale_pct {
    RETURN 80 + (20 * AOSO_HUD_SCALE).
}

FUNCTION aoso_hud_skin_apply {
    PARAMETER g.
    LOCAL fs IS aoso_hud_scale_fs().
    SET g:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "window_bg.png".
    SET g:SKIN:LABEL:FONTSIZE TO fs.
    SET g:SKIN:LABEL:TEXTCOLOR TO RGB(0.26, 1.0, 0.38).
    SET g:SKIN:BUTTON:FONTSIZE TO fs.
    SET g:SKIN:BUTTON:BG TO AOSO_UI2_ASSET_ROOT + "button_off.png".
    SET g:SKIN:BUTTON:HOVER:BG TO AOSO_UI2_ASSET_ROOT + "button_hover.png".
    SET g:SKIN:BUTTON:FOCUSED:BG TO AOSO_UI2_ASSET_ROOT + "button_hover.png".
    SET g:SKIN:BUTTON:ACTIVE:BG TO AOSO_UI2_ASSET_ROOT + "button_on.png".
    SET g:SKIN:HORIZONTALSLIDER:BG TO AOSO_UI2_ASSET_ROOT + "hscale.png".
    SET g:SKIN:HORIZONTALSLIDERTHUMB:BG TO AOSO_UI2_ASSET_ROOT + "diamond.png".
    SET g:SKIN:HORIZONTALSLIDERTHUMB:WIDTH TO 16.
    SET g:SKIN:HORIZONTALSLIDERTHUMB:HEIGHT TO 16.
    SET g:SKIN:VERTICALSLIDER:BG TO AOSO_UI2_ASSET_ROOT + "vscale.png".
    SET g:SKIN:VERTICALSLIDERTHUMB:BG TO AOSO_UI2_ASSET_ROOT + "diamond.png".
    SET g:SKIN:VERTICALSLIDERTHUMB:WIDTH TO 16.
    SET g:SKIN:VERTICALSLIDERTHUMB:HEIGHT TO 16.
    SET g:SKIN:TOGGLE:FONTSIZE TO fs.
    SET g:SKIN:WINDOW:FONTSIZE TO fs.
}

FUNCTION aoso_hud_scale_walk {
    PARAMETER box.
    PARAMETER fs.
    LOCAL wq IS LIST(box).
    LOCAL i IS 0.
    UNTIL i >= wq:LENGTH {
        LOCAL w IS wq[i].
        SET i TO i + 1.
        SET w:STYLE:FONTSIZE TO fs.
        IF w:HASSUFFIX("WIDGETS") {
            FOR child IN w:WIDGETS { wq:ADD(child). }
        }
    }
}

FUNCTION aoso_hud_apply_scale {
    IF NOT AOSO_HUD_GUI:ISTYPE("GUI") { RETURN. }
    LOCAL g IS AOSO_HUD_GUI.
    LOCAL fs IS aoso_hud_scale_fs().
    LOCAL wid IS aoso_hud_scale_width().
    aoso_hud_skin_apply(g).
    SET g:STYLE:WIDTH TO wid.
    aoso_hud_scale_walk(g, fs).
    IF AOSO_HUD_HDR_TITLE:ISTYPE("LABEL") {
        SET AOSO_HUD_HDR_TITLE:TEXT TO "<b><size=" + (fs + 4) + "><color=#1AF034>AOSO</color></size>  FLIGHT DECK · OPS DISPLAY r4</b>".
    }
    aoso_hud_set("chrome_pct", "" + aoso_hud_scale_pct() + "%").
}

FUNCTION aoso_hud_scale_down {
    IF AOSO_HUD_SCALE <= 0 { RETURN. }
    SET AOSO_HUD_SCALE TO AOSO_HUD_SCALE - 1.
    aoso_hud_apply_scale().
    aoso_hud_event_push("INFO", "scale " + aoso_hud_scale_pct() + "%").
}

FUNCTION aoso_hud_scale_up {
    IF AOSO_HUD_SCALE >= 4 { RETURN. }
    SET AOSO_HUD_SCALE TO AOSO_HUD_SCALE + 1.
    aoso_hud_apply_scale().
    aoso_hud_event_push("INFO", "scale " + aoso_hud_scale_pct() + "%").
}

FUNCTION aoso_hud_back {
    IF AOSO_HUD_COMPACT { aoso_hud_set_compact(FALSE). }
    IF AOSO_HUD_HIST:LENGTH = 0 {
        aoso_hud_show_page("FLT", FALSE).
        RETURN.
    }
    LOCAL i IS AOSO_HUD_HIST:LENGTH - 1.
    LOCAL prev IS AOSO_HUD_HIST[i].
    AOSO_HUD_HIST:REMOVE(i).
    aoso_hud_show_page(prev, FALSE).
}

FUNCTION aoso_hud_home {
    IF AOSO_HUD_COMPACT { aoso_hud_set_compact(FALSE). }
    SET AOSO_HUD_HIST TO LIST().
    aoso_hud_show_page("FLT", FALSE).
}

FUNCTION aoso_hud_help_click {
    IF AOSO_HUD_COMPACT { aoso_hud_set_compact(FALSE). }
    aoso_hud_show_page("HELP").
}

FUNCTION aoso_hud_set_compact {
    PARAMETER on.
    SET AOSO_HUD_COMPACT TO on.
    IF AOSO_HUD_BODY:ISTYPE("BOX") {
        SET AOSO_HUD_BODY:VISIBLE TO NOT on.
    }
    IF AOSO_HUD_BTN_X:ISTYPE("BUTTON") {
        IF on { SET AOSO_HUD_BTN_X:TEXT TO "OPEN". }
        ELSE { SET AOSO_HUD_BTN_X:TEXT TO "X". }
    }
}

FUNCTION aoso_hud_toggle_compact {
    aoso_hud_set_compact(NOT AOSO_HUD_COMPACT).
    IF AOSO_HUD_COMPACT {
        aoso_hud_event_push("INFO", "HUD collapsed").
    } ELSE {
        aoso_hud_event_push("INFO", "HUD expanded").
    }
}

FUNCTION aoso_hud_gui_build_flight {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    aoso_ui2_build_pfd(aoso_ops_display(row)).
    LOCAL data IS aoso_ops_readout(row, "FLIGHT / LIVE TELEMETRY").
    aoso_hud_lab(data, "flt_body", "BODY  -").
    aoso_hud_lab(data, "flt_alt", "ALT  -").
    aoso_hud_lab(data, "flt_spd", "SPEED  -").
    aoso_hud_lab(data, "flt_att", "ATT  -").
    aoso_hud_lab(data, "flt_orb", "ORBIT  -").
    aoso_hud_lab(data, "flt_twr", "TWR  -").
    aoso_hud_lab(data, "flt_guid", "GUIDANCE  -").
    aoso_hud_lab(data, "flt_steer", "STEERING  -").
    aoso_hud_lab(data, "flt_thr", "THROTTLE  -").
    aoso_hud_lab(data, "flt_nav", "").
    aoso_hud_lab(data, "flt_pri", "").
}

FUNCTION aoso_hud_gui_build_nav {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    aoso_ui2_build_nav_display(aoso_ops_display(row)).
    LOCAL data IS aoso_ops_readout(row, "NAVIGATION / ORBIT DATA").
    aoso_hud_lab(data, "nav_soi", "SPHERE OF INFLUENCE  -").
    aoso_hud_lab(data, "nav_orb", "ORBIT  -").
    aoso_hud_lab(data, "nav_tgt", "TARGET  NO TARGET").
    aoso_hud_lab(data, "nav_rel", "REL VEL  -").
    aoso_hud_lab(data, "nav_patch", "PATCH  -").
    aoso_hud_lab(data, "nav_node", "NODE  -").
    aoso_hud_lab(data, "nav_burn", "BURN  -").
    aoso_hud_lab(data, "nav_goto", "GOTO  -").
}

FUNCTION aoso_hud_gui_build_mission {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    aoso_ui2_mission_build(aoso_ops_display(row)).
    LOCAL data IS aoso_ops_readout(row, "TOUR / MISSION DATA").
    aoso_hud_lab(data, "msn_name", "MISSION  -").
    aoso_hud_lab(data, "msn_prog", "PROGRESS  -").
    aoso_hud_lab(data, "msn_cur", "CURRENT  -").
    aoso_hud_lab(data, "msn_phase", "PHASE  -").
    aoso_hud_lab(data, "msn_next", "NEXT  -").
    aoso_hud_lab(data, "msn_obj", "OBJECTIVE  -").
    aoso_hud_lab(data, "msn_ret", "RETURN  KERBIN -> KSC").
    aoso_hud_lab(data, "msn_stat", "STATUS  -").
    aoso_hud_lab(data, "msn_feas", "FEASIBLE  -").
    aoso_hud_lab(data, "msn_class", "CLASS  -").
    aoso_hud_lab(data, "msn_time", "ROUTE  -").
    aoso_hud_lab(data, "msn_legend", "Green = current  blue = next  check = completed in this route window.").
    aoso_hud_lab(data, "msn_skip", "").
}

FUNCTION aoso_hud_gui_build_vehicle {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    aoso_ui2_vehicle_build(aoso_ops_display(row)).
    LOCAL data IS aoso_ops_readout(row, "VESSEL / CAPABILITIES").
    aoso_hud_hint(data, "Selecting a Digital Twin node highlights its vessel part.").
    aoso_hud_lab(data, "veh_id", "SHIP  -").
    aoso_hud_lab(data, "veh_cls", "CLASS  -").
    aoso_hud_lab(data, "veh_crew", "CREW  -").
    aoso_hud_lab(data, "veh_hw", "HARDWARE  -").
    aoso_hud_lab(data, "veh_mob", "MOBILITY  -").
    aoso_hud_lab(data, "veh_cap", "CAPABILITIES  -").
    aoso_hud_lab(data, "veh_pwr", "POWER  -").
    aoso_hud_lab(data, "veh_twin", "TWIN  -").
}

FUNCTION aoso_hud_gui_build_prop {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    LOCAL engine IS aoso_ops_readout(row, "PROPULSION / ENGINES").
    aoso_hud_hint(engine, "Read only. AOSO flight control owns throttle and staging.").
    aoso_hud_lab(engine, "prp_thr", "THRUST  -").
    aoso_hud_lab(engine, "prp_twr", "TWR / STAGE  -").
    aoso_hud_lab(engine, "prp_dv", "DELTA-V  -").
    aoso_hud_lab(engine, "prp_eng", "ENGINES  -").
    aoso_hud_lab(engine, "prp_next", "NEXT STAGE  -").
    LOCAL stores IS aoso_ops_readout(row, "PROPULSION / STORES").
    aoso_hud_hint(stores, "LF liquid fuel   OX oxidizer   MP monopropellant   EC electric charge").
    aoso_hud_lab(stores, "prp_lf", "LIQUID FUEL  -").
    aoso_hud_lab(stores, "prp_ox", "OXIDIZER  -").
    aoso_hud_lab(stores, "prp_mp", "MONOPROP  -").
    aoso_hud_lab(stores, "prp_ec", "ELECTRIC  -").
}

FUNCTION aoso_hud_gui_build_land {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    aoso_ui2_build_surface_display(aoso_ops_display(row)).
    LOCAL data IS aoso_ops_readout(row, "SURFACE / LANDING DATA").
    aoso_hud_lab(data, "lnd_st", "LANDING SYSTEM  STANDBY").
    aoso_hud_lab(data, "lnd_site", "SITE  -").
    aoso_hud_lab(data, "lnd_alt", "RADAR  -").
    aoso_hud_lab(data, "lnd_spd", "VSPD / HSPD  -").
    aoso_hud_lab(data, "lnd_twr", "TWR / THROTTLE  -").
    aoso_hud_lab(data, "lnd_trig", "SUICIDE  -").
    aoso_hud_lab(data, "lnd_dv", "LANDING dV  -").
    aoso_hud_lab(data, "lnd_gear", "GEAR  -").
    aoso_hud_lab(data, "lnd_ret0", "").
    aoso_hud_lab(data, "lnd_ret1", "").
    aoso_hud_lab(data, "lnd_ret2", "").
    aoso_hud_lab(data, "lnd_ret3", "").
}

FUNCTION aoso_hud_gui_build_stg {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    LOCAL state IS aoso_ops_readout(row, "STAGING / CURRENT STAGE").
    aoso_hud_lab(state, "stg_cur", "CURRENT  -").
    aoso_hud_lab(state, "stg_fuel", "STAGE FUEL  -").
    aoso_hud_lab(state, "stg_thr", "THRUST  -").
    aoso_hud_lab(state, "stg_eng", "ENGINES  -").
    aoso_hud_lab(state, "stg_conf", "READY  -").
    LOCAL notes IS aoso_ops_readout(row, "STAGING / CONTROL NOTES").
    aoso_hud_hint(notes, "The current-stage fields update from the vessel model.").
    aoso_hud_hint(notes, "AOSO stages automatically when the flight controller determines it is safe.").
    aoso_hud_hint(notes, "This page never presses SPACE or changes staging.").
}

FUNCTION aoso_hud_gui_build_sys {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    aoso_ui2_systems_build(aoso_ops_display(row)).
    LOCAL data IS aoso_ops_readout(row, "SYSTEMS / HEALTH DATA").
    aoso_hud_lab(data, "sys_roll", "AOSO  -").
    aoso_hud_lab(data, "sys_why", "").
    aoso_hud_lab(data, "sys_cpu_note", "").
    aoso_hud_lab(data, "sys_guid", "GUIDANCE     -").
    aoso_hud_lab(data, "sys_nav", "NAVIGATION   -").
    aoso_hud_lab(data, "sys_steer", "STEERING     -").
    aoso_hud_lab(data, "sys_thr", "THROTTLE     -").
    aoso_hud_lab(data, "sys_stg", "STAGING      -").
    aoso_hud_lab(data, "sys_msn", "MISSION      -").
    aoso_hud_lab(data, "sys_lnd", "LANDING      -").
    aoso_hud_lab(data, "sys_pwr", "POWER        -").
    aoso_hud_lab(data, "sys_com", "COMMS        -").
    aoso_hud_lab(data, "sys_wd", "WATCHDOG     -").
    aoso_hud_lab(data, "sys_cpu", "CPU          -").
}

FUNCTION aoso_hud_gui_build_log {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    LOCAL older IS aoso_ops_readout(row, "EVENT LOG / EARLIER").
    aoso_hud_lab(older, "log_0", "-").
    aoso_hud_lab(older, "log_1", "-").
    aoso_hud_lab(older, "log_2", "-").
    aoso_hud_lab(older, "log_3", "-").
    aoso_hud_lab(older, "log_4", "-").
    LOCAL recent IS aoso_ops_readout(row, "EVENT LOG / RECENT").
    aoso_hud_hint(recent, "Latest AOSO decisions and events; newest at the bottom.").
    aoso_hud_lab(recent, "log_5", "-").
    aoso_hud_lab(recent, "log_6", "-").
    aoso_hud_lab(recent, "log_7", "-").
    aoso_hud_lab(recent, "log_8", "-").
    aoso_hud_lab(recent, "log_9", "-").
}

FUNCTION aoso_hud_gui_build_dbg {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    LOCAL flight IS aoso_ops_readout(row, "DEBUG / FLIGHT STATE").
    LOCAL dump_btn IS flight:ADDBUTTON("DUMP HUD JSON").
    SET dump_btn:ONCLICK TO aoso_hud_debug_dump@.
    aoso_hud_lab(flight, "dbg_page", "PAGE  -").
    aoso_hud_lab(flight, "dbg_ctx", "CTX  -").
    aoso_hud_lab(flight, "dbg_gui", "GUI  -").
    aoso_hud_lab(flight, "dbg_sys", "SYS  -").
    aoso_hud_lab(flight, "dbg_fd", "FD  -").
    aoso_hud_lab(flight, "dbg_st", "STATE  -").
    aoso_hud_lab(flight, "dbg_do", "DOING  -").
    aoso_hud_lab(flight, "dbg_flt", "FLT  -").
    LOCAL health IS aoso_ops_readout(row, "DEBUG / HEALTH + CAPTURE").
    aoso_hud_lab(health, "dbg_cpu", "CPU  -").
    aoso_hud_lab(health, "dbg_ipu", "IPU  -").
    aoso_hud_lab(health, "dbg_warn", "WARN  -").
    aoso_hud_lab(health, "dbg_err", "ERR  -").
    aoso_hud_lab(health, "dbg_last", "LAST  -").
    aoso_hud_lab(health, "dbg_twin", "TWIN  -").
    aoso_hud_lab(health, "dbg_file", "FILE  0:/aoso_hud.json").
    aoso_hud_hint(health, "DUMP saves HUD geometry, telemetry age and last error.").
}

FUNCTION aoso_hud_gui_build_help {
    PARAMETER p.
    LOCAL row IS p:ADDHLAYOUT().
    LOCAL displays IS aoso_ops_readout(row, "QUICK GUIDE / DISPLAYS").
    aoso_hud_hint(displays, "Six primary displays keep live telemetry beside the instrument. Reload AOSO after an update.").
    aoso_hud_hint(displays, "PFD  Flight director, speed/altitude, TWR, propellant and warnings.").
    aoso_hud_hint(displays, "NAV  Current orbit, recent trail, vessel, maneuver and next-SOI markers.").
    aoso_hud_hint(displays, "TOUR  Route, current objective, completion, dV and feasibility.").
    aoso_hud_hint(displays, "VEH  Vessel and Digital Twin. Select a part to highlight it.").
    aoso_hud_hint(displays, "SURF  Survey map or landing director, depending on mission phase.").
    aoso_hud_hint(displays, "SYS  Caution/warning board. NOM healthy, DEG degraded, FAIL fault.").
    LOCAL controls IS aoso_ops_readout(row, "QUICK GUIDE / CONTROLS").
    aoso_hud_hint(controls, "DISPLAY ONLY. Flight controllers own steering, throttle, staging and warp.").
    aoso_hud_hint(controls, "HUD  Separate flight director; DCL declutters, REC recenters, TEST checks geometry, DUMP saves diagnostics.").
    aoso_hud_hint(controls, "AUTO  Optional phase-based screen choice. Starts off so manual tabs stay selected.").
    aoso_hud_hint(controls, "FD  PRO/RET/NML/TGT/REL/BURN/LAND draw 3D reference arrows only.").
    aoso_hud_hint(controls, "ENG/TWIN  Full topology and filter view. REBUILD rescans the vessel.").
    aoso_hud_hint(controls, "CPU protection defers UI prediction and twin work when flight safety needs time.").
}

FUNCTION aoso_hud_fd_cb_master { PARAMETER on. aoso_hud_fd_enable(on). aoso_hud_trace("FD master=" + on). }
FUNCTION aoso_hud_fd_cb_pro { PARAMETER on. aoso_hud_fd_set("PRO", on). aoso_hud_trace("FD PRO=" + on). }
FUNCTION aoso_hud_fd_cb_ret { PARAMETER on. aoso_hud_fd_set("RET", on). aoso_hud_trace("FD RET=" + on). }
FUNCTION aoso_hud_fd_cb_nml { PARAMETER on. aoso_hud_fd_set("NML", on). aoso_hud_trace("FD NML=" + on). }
FUNCTION aoso_hud_fd_cb_tgt { PARAMETER on. aoso_hud_fd_set("TGT", on). aoso_hud_trace("FD TGT=" + on). }
FUNCTION aoso_hud_fd_cb_rel { PARAMETER on. aoso_hud_fd_set("REL", on). aoso_hud_trace("FD REL=" + on). }
FUNCTION aoso_hud_fd_cb_burn { PARAMETER on. aoso_hud_fd_set("BURN", on). aoso_hud_trace("FD BURN=" + on). }
FUNCTION aoso_hud_fd_cb_land { PARAMETER on. aoso_hud_fd_set("LAND", on). aoso_hud_trace("FD LAND vec=" + on + " (display only, does not land)"). }

FUNCTION aoso_hud_gui_init {
    aoso_hud_gui_dispose().
    LOCAL g IS GUI(aoso_hud_scale_width()).
    SET g:X TO 20.
    SET g:Y TO 60.
    SET g:DRAGGABLE TO TRUE.
    aoso_hud_skin_apply(g).
    SET AOSO_HUD_GUI TO g.

    LOCAL hdr IS g:ADDLABEL("<b><size=16><color=#1AF034>AOSO</color></size>  FLIGHT DECK · OPS DISPLAY r4</b>").
    SET hdr:STYLE:HSTRETCH TO TRUE.
    SET AOSO_HUD_HDR_TITLE TO hdr.
    aoso_hud_lab(g, "hdr_sys", "SYS  NOMINAL").
    LOCAL status_row IS g:ADDHLAYOUT().
    aoso_hud_lab(status_row, "hdr_ui2", "OPS DISPLAY r4  STARTING").
    aoso_hud_lab(status_row, "hdr_twin", "TWIN  -").
    aoso_hud_lab(g, "hdr_do", "DOING  -").
    aoso_hud_lab(g, "hdr_dt", "").

    LOCAL chrome IS g:ADDHLAYOUT().
    LOCAL b_back IS chrome:ADDBUTTON("BACK").
    SET b_back:ONCLICK TO aoso_hud_back@.
    LOCAL b_home IS chrome:ADDBUTTON("HOME").
    SET b_home:ONCLICK TO aoso_hud_home@.
    LOCAL b_help IS chrome:ADDBUTTON("HELP").
    SET b_help:ONCLICK TO aoso_hud_help_click@.
    LOCAL b_minus IS chrome:ADDBUTTON("A-").
    SET b_minus:ONCLICK TO aoso_hud_scale_down@.
    aoso_hud_lab(chrome, "chrome_pct", "100%").
    SET AOSO_HUD_W["chrome_pct"]:STYLE:HSTRETCH TO FALSE.
    LOCAL b_plus IS chrome:ADDBUTTON("A+").
    SET b_plus:ONCLICK TO aoso_hud_scale_up@.
    LOCAL b_x IS chrome:ADDBUTTON("X").
    SET b_x:ONCLICK TO aoso_hud_toggle_compact@.
    SET AOSO_HUD_BTN_X TO b_x.

    LOCAL vbox IS g:ADDVLAYOUT().
    SET AOSO_HUD_BODY TO vbox.

    LOCAL modes IS vbox:ADDHLAYOUT().
    LOCAL b_tac IS modes:ADDBUTTON("HUD").
    SET b_tac:STYLE:WIDTH TO 67.
    SET b_tac:ONCLICK TO aoso_hud_mode_tactical@.
    LOCAL b_gui IS modes:ADDBUTTON("MFD").
    SET b_gui:STYLE:WIDTH TO 67.
    SET b_gui:ONCLICK TO aoso_hud_mode_computer@.
    LOCAL b_eng IS modes:ADDBUTTON("ENG").
    SET b_eng:STYLE:WIDTH TO 67.
    SET b_eng:ONCLICK TO aoso_hud_mode_eng@.
    LOCAL b_fd IS modes:ADDCHECKBOX("FD", TRUE).
    SET b_fd:ONTOGGLE TO aoso_hud_fd_cb_master@.
    LOCAL b_auto IS modes:ADDCHECKBOX("AUTO", FALSE).
    SET b_auto:ONTOGGLE TO aoso_ui2_auto_page_toggle@.

    LOCAL fdrow IS vbox:ADDHLAYOUT().
    LOCAL c1 IS fdrow:ADDCHECKBOX("PRO", TRUE).
    SET c1:ONTOGGLE TO aoso_hud_fd_cb_pro@.
    LOCAL c1b IS fdrow:ADDCHECKBOX("RET", FALSE).
    SET c1b:ONTOGGLE TO aoso_hud_fd_cb_ret@.
    LOCAL c1c IS fdrow:ADDCHECKBOX("NML", FALSE).
    SET c1c:ONTOGGLE TO aoso_hud_fd_cb_nml@.
    LOCAL c2 IS fdrow:ADDCHECKBOX("TGT", TRUE).
    SET c2:ONTOGGLE TO aoso_hud_fd_cb_tgt@.
    LOCAL c2b IS fdrow:ADDCHECKBOX("REL", FALSE).
    SET c2b:ONTOGGLE TO aoso_hud_fd_cb_rel@.
    LOCAL c3 IS fdrow:ADDCHECKBOX("BURN", TRUE).
    SET c3:ONTOGGLE TO aoso_hud_fd_cb_burn@.
    LOCAL c4 IS fdrow:ADDCHECKBOX("LAND", FALSE).
    SET c4:ONTOGGLE TO aoso_hud_fd_cb_land@.
    // The legend lives on HELP; the front panel stays focused on the display.

    // Flight-deck row: phase-aware primary displays.
    LOCAL row1 IS vbox:ADDHLAYOUT().
    aoso_hud_add_tab(row1, "FLT", "PFD").
    aoso_hud_add_tab(row1, "NAV", "NAV").
    aoso_hud_add_tab(row1, "MSN", "TOUR").
    aoso_hud_add_tab(row1, "VEH", "VEH").
    aoso_hud_add_tab(row1, "LND", "SURF").
    aoso_hud_add_tab(row1, "SYS", "SYS").

    // Engineering row: detailed subsystems and diagnostics.
    LOCAL row2 IS vbox:ADDHLAYOUT().
    aoso_hud_add_tab(row2, "PRP", "PROP").
    aoso_hud_add_tab(row2, "STG", "STAGE").
    aoso_hud_add_tab(row2, "TWIN", "TWIN").
    aoso_hud_add_tab(row2, "LOG", "LOG").
    aoso_hud_add_tab(row2, "DBG", "DBG").
    aoso_hud_add_tab(row2, "HELP", "HELP").

    SET AOSO_HUD_STACK TO vbox:ADDVLAYOUT().
    aoso_hud_gui_build_flight(aoso_hud_add_page("FLT")).
    aoso_hud_gui_build_nav(aoso_hud_add_page("NAV")).
    aoso_hud_gui_build_mission(aoso_hud_add_page("MSN")).
    aoso_hud_gui_build_vehicle(aoso_hud_add_page("VEH")).
    aoso_hud_gui_build_prop(aoso_hud_add_page("PRP")).
    aoso_hud_gui_build_land(aoso_hud_add_page("LND")).
    aoso_hud_gui_build_stg(aoso_hud_add_page("STG")).
    aoso_hud_gui_build_sys(aoso_hud_add_page("SYS")).
    aoso_twin_view_build(aoso_hud_add_page("TWIN")).
    aoso_hud_gui_build_log(aoso_hud_add_page("LOG")).
    aoso_hud_gui_build_dbg(aoso_hud_add_page("DBG")).
    aoso_hud_gui_build_help(aoso_hud_add_page("HELP")).

    SET AOSO_UI2_AUTO_PAGE TO FALSE.
    aoso_hud_apply_scale().
    aoso_hud_set_compact(AOSO_HUD_COMPACT).
    aoso_hud_show_page("FLT", FALSE).
    SET AOSO_HUD_GUI_ON TO TRUE.
    g:SHOW().

    IF aoso_ui2_selftest() {
        aoso_hud_set("hdr_ui2", "OPS DISPLAY r4  <color=#1AF034>READY</color>").
    } ELSE {
        aoso_hud_set("hdr_ui2", "UI2  <color=#FF5A46>FAULT</color>  " + AOSO_UI2_SELFTEST_REASON).
    }
    aoso_hud_trace_log("GUI online UI2=" + AOSO_UI2_READY + " " + AOSO_UI2_SELFTEST_REASON).
}

FUNCTION aoso_hud_tac_chip_show {
    IF AOSO_HUD_TAC_CHIP:ISTYPE("GUI") {
        AOSO_HUD_TAC_CHIP:SHOW().
        RETURN.
    }
    LOCAL c IS GUI(140).
    SET c:X TO 20.
    SET c:Y TO 80.
    LOCAL b IS c:ADDBUTTON("GUI").
    SET b:ONCLICK TO aoso_hud_mode_computer@.
    SET AOSO_HUD_TAC_CHIP TO c.
    c:SHOW().
}

FUNCTION aoso_hud_tac_chip_hide {
    IF AOSO_HUD_TAC_CHIP:ISTYPE("GUI") { AOSO_HUD_TAC_CHIP:HIDE(). }
}

FUNCTION aoso_hud_gui_hide {
    IF AOSO_HUD_GUI:ISTYPE("GUI") { AOSO_HUD_GUI:HIDE(). }
    SET AOSO_HUD_GUI_ON TO FALSE.
    IF aoso_config_get("UI2_ENABLED", TRUE) {
        aoso_hud_tac_chip_hide().
        aoso_ui2_hud_show().
    } ELSE {
        aoso_hud_tac_chip_show().
    }
}

FUNCTION aoso_hud_gui_show {
    aoso_hud_tac_chip_hide().
    aoso_ui2_hud_hide().
    IF AOSO_HUD_GUI:ISTYPE("GUI") { AOSO_HUD_GUI:SHOW(). }
    SET AOSO_HUD_GUI_ON TO TRUE.
}

FUNCTION aoso_hud_doing_fast {
    LOCAL doing IS AOSO_UI["doing"].
    IF doing <> "" { RETURN doing. }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" {
                IF AOSO_ASCENT["current"] <> "ABORTED" {
                    RETURN "Ascent  " + AOSO_ASCENT["current"].
                }
            }
        }
    }
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] <> "" {
            IF AOSO_GOTO["current"] <> "DONE" {
                IF AOSO_GOTO["current"] <> "ABORTED" {
                    RETURN "GOTO  " + AOSO_GOTO["current"].
                }
            }
        }
    }
    IF DEFINED AOSO_MANEUVER_BURNING {
        IF AOSO_MANEUVER_BURNING { RETURN "BURNING". }
    }
    RETURN SHIP:STATUS.
}

FUNCTION aoso_hud_gui_fast {
    IF AOSO_UI2_HUD_VISIBLE { aoso_ui2_hud_fast(). }
    IF NOT AOSO_HUD_GUI_ON { RETURN. }
    IF NOT AOSO_HUD_GUI:ISTYPE("GUI") { RETURN. }
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL doing IS aoso_hud_doing_fast().
    aoso_hud_set("hdr_do", "DOING  " + doing).
    aoso_hud_set("hdr_dt", f["detail"]).
    LOCAL roll IS "".
    IF AOSO_HUD_DATA["systems"]:HASKEY("rollup") { SET roll TO AOSO_HUD_DATA["systems"]["rollup"] + "  ". }
    aoso_hud_set("hdr_sys", "SYS  " + roll + f["body"] + "  " + f["status"] + "  STG " + f["stage"]).
    LOCAL live IS "ALT " + aoso_hud_km(f["alt"]) + "  VS " + ROUND(f["vs"], 1) + "  AP " + aoso_hud_km(o["ap"]) + "  PE " + aoso_hud_km(o["pe"]).
    IF o["node"] {
        SET live TO live + "  NODE " + ROUND(o["node_dv"], 1) + " m/s T-" + aoso_hud_eta(o["node_eta"]).
    }
    LOCAL pg IS AOSO_HUD_PAGE.
    IF pg = "FLT" {
        aoso_hud_set("flt_alt", "ALT  " + aoso_hud_km(f["alt"]) + "   VS " + ROUND(f["vs"], 1) + " m/s").
        IF f["in_atm"] {
            aoso_hud_set("flt_spd", "SRF " + ROUND(f["srf"], 0) + "  GS " + ROUND(f["gs"], 0) + " m/s").
        } ELSE {
            aoso_hud_set("flt_spd", "ORB " + ROUND(f["orb"], 0) + "  SRF " + ROUND(f["srf"], 0) + " m/s").
        }
        aoso_hud_set("flt_orb", "AP " + aoso_hud_km(o["ap"]) + "  PE " + aoso_hud_km(o["pe"])).
        aoso_hud_set("flt_twr", "TWR " + ROUND(f["twr"], 2) + "  THR " + ROUND(f["throttle"] * 100, 0) + "%  MASS " + ROUND(f["mass"], 2) + " t  STG " + f["stage"]).
        aoso_hud_set("flt_guid", doing).
        IF o["node"] {
            LOCAL ntxt IS "NODE  " + ROUND(o["node_dv"], 1) + " m/s  T-" + aoso_hud_eta(o["node_eta"]).
            IF o["burning"] { SET ntxt TO "BURN  " + ROUND(o["node_dv"], 1) + " m/s". }
            aoso_hud_set("flt_pri", ntxt).
        }
    }
    IF pg = "DBG" {
        aoso_hud_set("dbg_do", "DOING  " + doing + "  " + f["detail"]).
        aoso_hud_set("dbg_cpu", live).
    }
    IF pg = "NAV" {
        IF o["node"] {
            aoso_hud_set("nav_node", "NODE  " + ROUND(o["node_dv"], 1) + " m/s  T-" + aoso_hud_eta(o["node_eta"])).
        } ELSE {
            aoso_hud_set("nav_node", "NODE  none").
        }
        aoso_hud_set("nav_orb", "ORBIT  AP " + aoso_hud_km(o["ap"]) + "  PE " + aoso_hud_km(o["pe"])).
    }
}

FUNCTION aoso_hud_gui_upd_header {
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL roll IS "NOMINAL".
    IF sys:HASKEY("rollup") { SET roll TO sys["rollup"]. }
    LOCAL col_roll IS aoso_hud_ok(roll).
    IF roll = "DEGRADED" { SET col_roll TO aoso_hud_warn(roll). }
    IF roll = "FAIL" { SET col_roll TO aoso_hud_bad(roll). }
    LOCAL why IS "".
    IF sys:HASKEY("why") { SET why TO sys["why"]. }
    IF why = "" {
        aoso_hud_set("hdr_sys", "SYS  " + col_roll + "   " + f["body"] + "  " + f["status"]).
    } ELSE {
        aoso_hud_set("hdr_sys", "SYS  " + col_roll + "   " + why).
    }
    LOCAL twin_txt IS "TWIN  -".
    IF DEFINED AOSO_TWIN {
        IF AOSO_TWIN:HASKEY("status") { SET twin_txt TO aoso_twin_status_txt(). }
    }
    aoso_hud_set("hdr_twin", twin_txt).
    LOCAL doing IS f["doing"].
    IF doing = "" { SET doing TO aoso_hud_doing_text(). }
    aoso_hud_set("hdr_do", "DOING  " + doing).
    aoso_hud_set("hdr_dt", f["detail"]).
    aoso_hud_tabs_adapt().
    aoso_ui2_auto_page_tick().
}

FUNCTION aoso_hud_tabs_adapt {
    // Keep every display selectable, even when a vessel lacks the associated
    // hardware. The page itself can then explain a standby or absent state.
    IF AOSO_HUD_TABS:HASKEY("LND") { SET AOSO_HUD_TABS["LND"]:VISIBLE TO TRUE. }
    IF AOSO_HUD_TABS:HASKEY("PRP") { SET AOSO_HUD_TABS["PRP"]:VISIBLE TO TRUE. }
}

FUNCTION aoso_hud_gui_upd_flight {
    aoso_ui2_pfd_update().
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL ctx IS AOSO_HUD_CTX.
    LOCAL mode_txt IS ctx.
    IF mode_txt = "IDLE" { SET mode_txt TO f["status"]. }
    aoso_hud_set("flt_body", "BODY  " + f["body"] + "   " + mode_txt).

    IF ctx = "LANDING" {
        aoso_hud_set("flt_alt", "RAD  " + aoso_hud_km(AOSO_HUD_DATA["landing"]["radar"]) + "   VS " + ROUND(f["vs"], 1) + " m/s").
        aoso_hud_set("flt_spd", "HSPD " + ROUND(f["gs"], 1) + "  SRF " + ROUND(f["srf"], 1) + " m/s").
        aoso_hud_set("flt_att", "PITCH " + ROUND(f["pitch"], 1) + "  ROLL " + ROUND(f["roll"], 1)).
        aoso_hud_set("flt_orb", "").
    } ELSE {
        LOCAL radar_txt IS "".
        IF f["show_radar"] { SET radar_txt TO "  RAD " + aoso_hud_km(f["radar"]). }
        aoso_hud_set("flt_alt", "ALT  " + aoso_hud_km(f["alt"]) + radar_txt + "   VS " + ROUND(f["vs"], 1) + " m/s").
        IF f["in_atm"] {
            aoso_hud_set("flt_spd", "SRF " + ROUND(f["srf"], 0) + "  GS " + ROUND(f["gs"], 0) + " m/s").
        } ELSE {
            aoso_hud_set("flt_spd", "ORB " + ROUND(f["orb"], 0) + "  SRF " + ROUND(f["srf"], 0) + " m/s").
        }
        aoso_hud_set("flt_att", "HDG " + ROUND(f["hdg"], 0) + "  PITCH " + ROUND(f["pitch"], 1) + "  ROLL " + ROUND(f["roll"], 1)).
        LOCAL orb_line IS "AP " + aoso_hud_km(o["ap"]).
        IF o["pe"] > 0 {
            SET orb_line TO orb_line + "  PE " + aoso_hud_km(o["pe"]).
        }
        IF NOT f["in_atm"] {
            SET orb_line TO orb_line + "  INC " + ROUND(o["inc"], 1) + "  e " + ROUND(o["ecc"], 3).
        }
        IF o["hyper"] { SET orb_line TO "AP  hyperbolic". }
        aoso_hud_set("flt_orb", orb_line).
    }

    LOCAL twr_line IS "TWR " + ROUND(f["twr"], 2) + "  THR " + ROUND(f["throttle"] * 100, 0) + "%  MASS " + ROUND(f["mass"], 2) + " t  STG " + f["stage"].
    IF f["in_atm"] { SET twr_line TO twr_line + "  Q " + ROUND(f["q"], 3) + "  AoA " + ROUND(f["aoa"], 1). }
    aoso_hud_set("flt_twr", twr_line).

    LOCAL doing IS f["doing"].
    IF doing = "" { SET doing TO aoso_hud_doing_text(). }
    IF doing = "idle" { SET doing TO "". }
    IF doing <> "" { aoso_hud_set("flt_guid", doing). }
    ELSE { aoso_hud_set("flt_guid", ""). }

    aoso_hud_set("flt_steer", "STEER  " + sys["steer_mode"] + "   THR  " + sys["thr_mode"]).
    LOCAL flags IS "".
    IF f["sas"] { SET flags TO flags + "SAS  ". }
    IF f["rcs"] { SET flags TO flags + "RCS  ". }
    IF f["gear"] { SET flags TO flags + "GEAR  ". }
    SET flags TO flags + f["warp"].
    aoso_hud_set("flt_thr", flags).
    aoso_hud_set("flt_nav", "").
    aoso_hud_set("flt_pri", aoso_hud_flight_priority_txt()).
}

FUNCTION aoso_hud_flight_priority_txt {
    LOCAL ctx IS AOSO_HUD_CTX.
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL rsrc IS AOSO_HUD_DATA["res"].
    LOCAL lnd IS AOSO_HUD_DATA["landing"].
    LOCAL tgt IS AOSO_HUD_DATA["target"].
    IF ctx = "LAUNCH" {
        RETURN "".
    }
    IF ctx = "BURN" {
        LOCAL left IS o["node_dv"].
        IF o["burning"] { SET left TO o["burn_left"]. }
        RETURN "BURN  " + ROUND(left, 1) + " m/s  T-" + aoso_hud_eta(o["node_eta"]).
    }
    IF ctx = "TRANSFER" {
        LOCAL ttxt IS "".
        IF tgt["has"] { SET ttxt TO tgt["name"] + "  " + aoso_hud_km(tgt["dist"]) + "  rel " + ROUND(tgt["rel"], 0) + " m/s". }
        IF ttxt = "" { RETURN "". }
        RETURN ttxt.
    }
    IF ctx = "LANDING" {
        RETURN "SUICIDE  trig " + ROUND(lnd["trig"], 0) + " m".
    }
    IF ctx = "DOCK" {
        IF tgt["has"] { RETURN tgt["name"] + "  " + aoso_hud_km(tgt["dist"]) + "  rel " + ROUND(tgt["rel"], 1) + " m/s". }
        RETURN "".
    }
    IF ctx = "REFUEL" {
        LOCAL ore IS 0.
        IF rsrc:HASKEY("ore") { SET ore TO rsrc["ore"]. }
        RETURN "ORE " + ROUND(ore, 0) + "%  LF " + ROUND(rsrc["lf"], 0) + "%  OX " + ROUND(rsrc["ox"], 0) + "%".
    }
    IF ctx = "RETURN" {
        RETURN "HOME  dV " + ROUND(rsrc["mission_dv"], 0) + " m/s".
    }
    RETURN "".
}

FUNCTION aoso_hud_gui_upd_nav {
    aoso_ui2_nav_update().
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL t IS AOSO_HUD_DATA["target"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    aoso_hud_set("nav_soi", "SPHERE OF INFLUENCE  " + o["body"]).
    LOCAL ap_txt IS aoso_hud_km(o["ap"]).
    IF o["hyper"] { SET ap_txt TO "hyper". }
    aoso_hud_set("nav_orb", "AP " + ap_txt + " T-" + aoso_hud_eta(o["ap_eta"]) + "   PE " + aoso_hud_km(o["pe"]) + " T-" + aoso_hud_eta(o["pe_eta"])).
    IF t["has"] {
        aoso_hud_set("nav_tgt", "TARGET  " + t["name"] + "  " + aoso_hud_km(t["dist"]) + "  brg " + ROUND(t["bearing"], 0)).
        aoso_hud_set("nav_rel", "REL VEL  " + ROUND(t["rel"], 1) + " m/s").
    } ELSE {
        aoso_hud_set("nav_tgt", "TARGET  NO TARGET").
        aoso_hud_set("nav_rel", "REL VEL  " + aoso_hud_na()).
    }
    IF o["patch"] <> "" {
        aoso_hud_set("nav_patch", "PATCH  " + o["patch"] + "  PE " + aoso_hud_km(o["patch_pe"]) + "  in " + aoso_hud_eta(o["patch_eta"])).
    } ELSE {
        aoso_hud_set("nav_patch", "PATCH  none").
    }
    IF o["node"] {
        LOCAL st IS "ALIGNING".
        IF o["burning"] { SET st TO "BURN ACTIVE". }
        ELSE {
            IF o["node_eta"] < 8 { SET st TO "IGNITION". }
        }
        aoso_hud_set("nav_node", "NODE  " + ROUND(o["node_dv"], 1) + " m/s  T-" + aoso_hud_eta(o["node_eta"]) + "  " + st).
        LOCAL left IS o["node_dv"].
        IF o["burning"] { SET left TO o["burn_left"]. }
        aoso_hud_set("nav_burn", "BURN  " + ROUND(left, 1) + " m/s left  " + ROUND(o["burn_s"], 1) + "s  pro " + ROUND(o["node_pro"], 0) + " nml " + ROUND(o["node_nml"], 0) + " rad " + ROUND(o["node_rad"], 0)).
    } ELSE {
        aoso_hud_set("nav_node", "NODE  none").
        aoso_hud_set("nav_burn", "BURN  idle").
    }
    LOCAL gtxt IS m["goto"].
    IF m["goal"] <> "" { SET gtxt TO gtxt + " -> " + m["goal"]. }
    IF m["hop"] <> "" { SET gtxt TO gtxt + "  hop " + m["hop"]. }
    aoso_hud_set("nav_goto", "GOTO  " + gtxt).
}

FUNCTION aoso_hud_gui_upd_mission {
    aoso_ui2_mission_update().
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    aoso_hud_set("msn_name", "MISSION  " + m["mission"] + " / " + m["step"]).
    LOCAL prog IS "-".
    IF m["n"] > 0 { SET prog TO (m["idx"] + 1) + " / " + m["n"] + " DESTINATIONS". }
    aoso_hud_set("msn_prog", "PROGRESS  " + prog).
    LOCAL cur IS m["goal"].
    IF cur = "" { SET cur TO m["next"]. }
    IF cur = "" { SET cur TO SHIP:BODY:NAME. }
    aoso_hud_set("msn_cur", "CURRENT  " + cur).
    LOCAL phase IS m["tour"].
    IF phase = "" { SET phase TO m["goto"]. }
    IF phase = "" { SET phase TO m["mission"]. }
    aoso_hud_set("msn_phase", "PHASE  " + phase).
    aoso_hud_set("msn_next", "NEXT  " + m["next"]).
    LOCAL obj IS AOSO_HUD_DATA["flight"]["doing"].
    IF obj = "" { SET obj TO m["step"]. }
    aoso_hud_set("msn_obj", "OBJECTIVE  " + obj).
    aoso_hud_set("msn_ret", "RETURN  KERBIN -> KSC").
    aoso_hud_set("msn_stat", "STATUS  " + aoso_hud_st_glyph(sys["msn"]) + "  " + AOSO_HUD_DATA["systems"]["rollup"]).
    aoso_hud_set("msn_feas", "FEASIBLE  " + m["feas"]).
    LOCAL cls IS m["class"].
    IF cls = "hopper" { SET cls TO "hopper (land, mine, hop to the next body)". }
    aoso_hud_set("msn_class", "CLASS  " + cls).
    LOCAL tl IS "".
    IF m:HASKEY("timeline") { SET tl TO m["timeline"]. }
    IF tl = "" { SET tl TO aoso_hud_na(). }
    aoso_hud_set("msn_time", "ROUTE  " + tl).
    LOCAL skip IS "".
    IF m:HASKEY("skip") { SET skip TO m["skip"]. }
    IF skip = "" { aoso_hud_set("msn_skip", ""). }
    ELSE { aoso_hud_set("msn_skip", "SKIP  " + skip). }
}

FUNCTION aoso_hud_gui_upd_vehicle {
    aoso_ui2_vehicle_update().
    LOCAL veh IS AOSO_HUD_DATA["vehicle"].
    aoso_hud_set("veh_id", "SHIP  " + veh["name"] + "   TYPE " + veh["type"] + "   PARTS " + veh["parts"]).
    aoso_hud_set("veh_cls", "CLASS  " + veh["class"]).
    aoso_hud_set("veh_crew", "CREW  " + veh["crew"] + " / " + veh["crew_cap"]).
    LOCAL hw IS "ENG " + veh["engines"].
    IF veh["antenna"] { SET hw TO hw + "  ANT Y". } ELSE { SET hw TO hw + "  ANT n". }
    IF veh["rcs"] { SET hw TO hw + "  RCS Y". } ELSE { SET hw TO hw + "  RCS n". }
    aoso_hud_set("veh_hw", "HARDWARE  " + hw).
    LOCAL mob IS "".
    IF veh["gear"] { SET mob TO mob + "GEAR  ". } ELSE { SET mob TO mob + "GEAR n  ". }
    IF veh["chutes"] { SET mob TO mob + "CHUTES  ". } ELSE { SET mob TO mob + "CHUTES n  ". }
    aoso_hud_set("veh_mob", "MOBILITY  " + mob).
    LOCAL cap IS "".
    IF veh["launch"] { SET cap TO cap + "LAUNCH Y  ". } ELSE { SET cap TO cap + "LAUNCH n  ". }
    IF veh["orbit"] { SET cap TO cap + "ORBIT Y  ". } ELSE { SET cap TO cap + "ORBIT n  ". }
    IF veh["land"] { SET cap TO cap + "LAND Y  ". } ELSE { SET cap TO cap + "LAND n  ". }
    IF veh["isru"] { SET cap TO cap + "ISRU Y  ". } ELSE { SET cap TO cap + "ISRU n  ". }
    IF veh["dock"] { SET cap TO cap + "DOCK Y  ". } ELSE { SET cap TO cap + "DOCK n  ". }
    IF veh["home"] { SET cap TO cap + "HOME Y". } ELSE { SET cap TO cap + "HOME n". }
    aoso_hud_set("veh_cap", "CAPABILITIES  " + cap).
    aoso_hud_set("veh_pwr", "POWER  SOLAR " + veh["solar"] + "  EC " + ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%").
    LOCAL tw IS "TWIN  -".
    IF DEFINED AOSO_TWIN {
        IF AOSO_TWIN:HASKEY("status") {
            SET tw TO aoso_twin_status_txt() + "  eng " + AOSO_TWIN["engines_on"] + "/" + AOSO_TWIN["engines_total"].
        }
    }
    aoso_hud_set("veh_twin", tw).
}

FUNCTION aoso_hud_gui_upd_prop {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL rsrc IS AOSO_HUD_DATA["res"].
    LOCAL veh IS AOSO_HUD_DATA["vehicle"].
    aoso_hud_set("prp_thr", "THRUST  " + ROUND(f["thrust"], 1) + " kN   THROTTLE " + ROUND(f["throttle"] * 100, 0) + "%").
    aoso_hud_set("prp_twr", "TWR " + ROUND(f["twr"], 2) + "   STAGE " + f["stage"]).
    aoso_hud_set("prp_dv", "DELTA-V  " + ROUND(rsrc["mission_dv"], 0) + " / " + ROUND(rsrc["total_dv"], 0) + " m/s").
    aoso_hud_set("prp_eng", "ENGINES  " + veh["engines"]).
    IF rsrc["lf_has"] { aoso_hud_set("prp_lf", "LIQUID FUEL  " + aoso_hud_bar(rsrc["lf"])). }
    ELSE { aoso_hud_set("prp_lf", "LIQUID FUEL  " + aoso_hud_na()). }
    IF rsrc["ox_has"] { aoso_hud_set("prp_ox", "OXIDIZER  " + aoso_hud_bar(rsrc["ox"])). }
    ELSE { aoso_hud_set("prp_ox", "OXIDIZER  " + aoso_hud_na()). }
    IF rsrc["mp_has"] { aoso_hud_set("prp_mp", "MONOPROP  " + aoso_hud_bar(rsrc["mp"])). }
    ELSE { aoso_hud_set("prp_mp", "MONOPROP  " + aoso_hud_na()). }
    aoso_hud_set("prp_ec", "ELECTRIC  " + aoso_hud_bar(rsrc["ec"])).
    LOCAL nxt IS "NEXT STAGE  -".
    IF rsrc:HASKEY("twr_next") {
        SET nxt TO "NEXT STAGE  TWR " + ROUND(rsrc["twr_next"], 2) + "  now " + ROUND(rsrc["twr_now"], 2).
        IF rsrc["role_next"] <> "" { SET nxt TO nxt + "  " + rsrc["role_next"]. }
    }
    aoso_hud_set("prp_next", nxt).
}

FUNCTION aoso_hud_gui_upd_land {
    aoso_ui2_surface_update().
    LOCAL l IS AOSO_HUD_DATA["landing"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL rsrc IS AOSO_HUD_DATA["res"].
    IF NOT l:HASKEY("active") { RETURN. }
    IF NOT l["active"] {
        aoso_hud_set("lnd_st", "LANDING SYSTEM  STANDBY").
    } ELSE {
        aoso_hud_set("lnd_st", "LANDING SYSTEM  " + aoso_hud_info(l["state"])).
    }
    LOCAL site IS l["site"].
    IF site = "" { SET site TO aoso_hud_na(). }
    aoso_hud_set("lnd_site", "SITE  " + site).
    aoso_hud_set("lnd_alt", "RADAR  " + aoso_hud_km(l["radar"]) + "   ALT " + aoso_hud_km(f["alt"])).
    aoso_hud_set("lnd_spd", "VSPD " + ROUND(f["vs"], 1) + "   HSPD " + ROUND(f["gs"], 1) + " m/s").
    aoso_hud_set("lnd_twr", "TWR " + ROUND(f["twr"], 2) + "   THROTTLE " + ROUND(f["throttle"] * 100, 0) + "%").
    IF l["active"] {
        aoso_hud_set("lnd_trig", "SUICIDE  trig " + ROUND(l["trig"], 0) + " m   radar " + ROUND(l["radar"], 0) + " m").
    } ELSE {
        aoso_hud_set("lnd_trig", "SUICIDE  " + aoso_hud_na()).
    }
    aoso_hud_set("lnd_dv", "LANDING dV  need " + ROUND(rsrc["land_dv"], 0) + "   have " + ROUND(rsrc["mission_dv"], 0) + " m/s").
    LOCAL gtxt IS "UP".
    IF f["gear"] { SET gtxt TO "DOWN". }
    IF NOT AOSO_HUD_DATA["vehicle"]["gear"] { SET gtxt TO "NOT INSTALLED". }
    aoso_hud_set("lnd_gear", "GEAR  " + gtxt).
    IF l["active"] {
        LOCAL cell_e IS 1.
        LOCAL cell_n IS 1.
        IF l["drift_e"] > 2 { SET cell_e TO 2. }
        IF l["drift_e"] < -2 { SET cell_e TO 0. }
        IF l["drift_n"] > 2 { SET cell_n TO 0. }
        IF l["drift_n"] < -2 { SET cell_n TO 2. }
        aoso_hud_set("lnd_ret0", "DRIFT  E " + ROUND(l["drift_e"], 1) + "  N " + ROUND(l["drift_n"], 1) + " m/s  (surface, not a GPS reticle)").
        aoso_hud_set("lnd_ret1", aoso_hud_reticle_row(0, cell_n, cell_e)).
        aoso_hud_set("lnd_ret2", aoso_hud_reticle_row(1, cell_n, cell_e)).
        aoso_hud_set("lnd_ret3", aoso_hud_reticle_row(2, cell_n, cell_e)).
    } ELSE {
        aoso_hud_set("lnd_ret0", "").
        aoso_hud_set("lnd_ret1", "").
        aoso_hud_set("lnd_ret2", "").
        aoso_hud_set("lnd_ret3", "").
    }
}

FUNCTION aoso_hud_reticle_row {
    PARAMETER row.
    PARAMETER mark_row.
    PARAMETER mark_col.
    LOCAL out IS "    ".
    LOCAL col IS 0.
    UNTIL col >= 3 {
        IF row = mark_row {
            IF col = mark_col { SET out TO out + "[*]". }
            ELSE { SET out TO out + "[ ]". }
        } ELSE {
            SET out TO out + "[ ]".
        }
        SET col TO col + 1.
    }
    RETURN out.
}

FUNCTION aoso_hud_gui_upd_stg {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL rsrc IS AOSO_HUD_DATA["res"].
    LOCAL veh IS AOSO_HUD_DATA["vehicle"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    aoso_hud_set("stg_cur", "CURRENT  STAGE " + f["stage"]).
    aoso_hud_set("stg_fuel", "STAGE FUEL  " + aoso_hud_bar(rsrc["stage_pct"])).
    aoso_hud_set("stg_thr", "THRUST  " + ROUND(f["thrust"], 1) + " kN").
    aoso_hud_set("stg_eng", "ENGINES  " + veh["engines"]).
    LOCAL ready IS aoso_hud_ok("READY").
    IF sys["stg"] = "DEG" { SET ready TO aoso_hud_warn("NO THRUST"). }
    IF sys["stg"] = "FAIL" { SET ready TO aoso_hud_bad("FAIL"). }
    aoso_hud_set("stg_conf", "STATUS  " + ready).
}

FUNCTION aoso_hud_gui_upd_sys {
    aoso_ui2_systems_update().
    LOCAL s IS AOSO_HUD_DATA["systems"].
    aoso_hud_set("sys_roll", "AOSO  " + s["rollup"]).
    LOCAL why IS "".
    IF s:HASKEY("why") { SET why TO s["why"]. }
    IF why = "" { aoso_hud_set("sys_why", "All systems nominal."). }
    ELSE { aoso_hud_set("sys_why", "WHY  " + why). }
    aoso_hud_set("sys_guid", "GUIDANCE     " + aoso_hud_st_glyph(s["guid"])).
    aoso_hud_set("sys_nav", "NAVIGATION   " + aoso_hud_st_glyph(s["nav"])).
    aoso_hud_set("sys_steer", "STEERING     " + aoso_hud_st_glyph(s["steer"]) + "  " + s["steer_mode"]).
    aoso_hud_set("sys_thr", "THROTTLE     " + aoso_hud_st_glyph(s["thr"]) + "  " + s["thr_mode"]).
    aoso_hud_set("sys_stg", "STAGING      " + aoso_hud_st_glyph(s["stg"]) + aoso_hud_sys_suffix("stg", s)).
    aoso_hud_set("sys_msn", "MISSION      " + aoso_hud_st_glyph(s["msn"])).
    aoso_hud_set("sys_lnd", "LANDING      " + aoso_hud_st_glyph(s["lnd"])).
    aoso_hud_set("sys_pwr", "POWER        " + aoso_hud_st_glyph(s["pwr"]) + "  " + ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%" + aoso_hud_sys_suffix("pwr", s)).
    aoso_hud_set("sys_com", "COMMS        " + aoso_hud_st_glyph(s["com"]) + aoso_hud_sys_suffix("com", s)).
    aoso_hud_set("sys_wd", "WATCHDOG     " + aoso_hud_st_glyph(s["wd"])).
    LOCAL cpu_line IS AOSO_HUD_DATA["debug"]["cpu"].
    IF AOSO_HUD_DATA["debug"]:HASKEY("band") { SET cpu_line TO cpu_line + " / " + AOSO_HUD_DATA["debug"]["band"]. }
    aoso_hud_set("sys_cpu", "CPU          " + aoso_hud_st_glyph(s["cpu"]) + "  " + cpu_line + aoso_hud_sys_suffix("cpu", s)).
    LOCAL cpu_note IS "CPU has spare instructions. HUD running at full rate.".
    IF DEFINED AOSO_CPU_NAME {
        IF AOSO_CPU_NAME = "ELEVATED" { SET cpu_note TO "kOS is working. HUD still updating.". }
        IF AOSO_CPU_NAME = "HIGH" { SET cpu_note TO "kOS is busy (often a burn). HUD still updating. Twin/profile paused. Not a ship failure.". }
        IF AOSO_CPU_NAME = "CRITICAL" { SET cpu_note TO "kOS is very busy. HUD still updating, flight first. Not a ship failure.". }
    }
    IF DEFINED AOSO_HUD_DATA {
        IF AOSO_HUD_DATA["debug"]:HASKEY("band") {
            IF AOSO_HUD_DATA["debug"]["band"] = "YELLOW" { SET cpu_note TO "CPU YELLOW - background work slowed.". }
            IF AOSO_HUD_DATA["debug"]["band"] = "RED" { SET cpu_note TO "CPU RED - strategic work deferred. Flight first.". }
            IF AOSO_HUD_DATA["debug"]["band"] = "CRITICAL" { SET cpu_note TO "CPU CRITICAL - only flight/safety tasks. Not a ship failure.". }
        }
    }
    aoso_hud_set("sys_cpu_note", cpu_note).
}

FUNCTION aoso_hud_sys_suffix {
    PARAMETER key.
    PARAMETER s.
    IF NOT s:HASKEY(key) { RETURN "". }
    LOCAL st IS s[key].
    IF st = "DEG" OR st = "FAIL" {
        RETURN "  " + aoso_hud_sys_reason(key, s).
    }
    RETURN "".
}

FUNCTION aoso_hud_gui_upd_log {
    LOCAL n IS AOSO_HUD_EVENTS:LENGTH.
    LOCAL i IS 0.
    UNTIL i >= 10 {
        LOCAL src IS n - 10 + i.
        LOCAL txt IS "".
        IF src >= 0 { SET txt TO AOSO_HUD_EVENTS[src]. }
        aoso_hud_set("log_" + i, txt).
        SET i TO i + 1.
    }
}

FUNCTION aoso_hud_gui_upd_dbg {
    LOCAL snap IS aoso_hud_debug_snap().
    LOCAL d IS AOSO_HUD_DATA["debug"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    aoso_hud_set("dbg_cpu", "CPU  " + snap["cpu"] + "  used " + ROUND(snap["used"], 0) + "  spills " + snap["spills"] + "  hud_dt " + ROUND(snap["hud_dt"], 3) + "s").
    LOCAL band_txt IS "".
    LOCAL def_txt IS "".
    IF d:HASKEY("band") { SET band_txt TO "  band " + d["band"]. }
    IF d:HASKEY("deferred") { SET def_txt TO "  def " + d["deferred"] + "  shed " + d["shed"]. }
    aoso_hud_set("dbg_ipu", "IPU  " + snap["ipu"] + "   left " + snap["left"] + band_txt + def_txt).
    aoso_hud_set("dbg_page", "PAGE  " + snap["page"] + "   MODE " + snap["mode"] +
        "   OPS UI " + snap["ops_ui_ready"] + " / " + snap["ops_ui_reason"]).
    aoso_hud_set("dbg_ctx", "CTX  " + snap["ctx"] + "   PHASE " + d["phase"] + "   body " + snap["body"] + " " + snap["status"]).
    aoso_hud_set("dbg_gui", "GUI  on=" + snap["gui_on"] + " HUD " + snap["hud_visible"] +
        " test " + snap["hud_test"] + " bug " + ROUND(snap["hud_bug_x"], 0) + "," +
        ROUND(snap["hud_bug_y"], 0) + "  collect hi/md/lo age " +
        ROUND(snap["hi_age"], 1) + "/" + ROUND(snap["md_age"], 1) + "/" + ROUND(snap["lo_age"], 1) + "s").
    LOCAL why IS snap["why"].
    IF why = "" { SET why TO "nominal". }
    aoso_hud_set("dbg_sys", "SYS  " + snap["sys"] + "  " + why).
    aoso_hud_set("dbg_fd", "FD  " + snap["fd"]).
    LOCAL cert_txt IS "".
    LOCAL health_txt IS "".
    LOCAL weak_txt IS "".
    IF m:HASKEY("cert") { SET cert_txt TO m["cert"]. }
    IF m:HASKEY("health") { SET health_txt TO m["health"]. }
    IF m:HASKEY("weak") { SET weak_txt TO m["weak"]. }
    aoso_hud_set("dbg_st", "MSN " + m["mission"] + " / " + m["step"] + "  TOUR " + m["tour"] + "  GOTO " + m["goto"] + "  ASC " + m["ascent"] + "  CERT " + cert_txt + "  " + health_txt + "  weak " + weak_txt).
    aoso_hud_set("dbg_do", "DOING  " + snap["doing"] + "  " + snap["detail"]).
    aoso_hud_set("dbg_flt", "FLT  alt " + ROUND(snap["alt"], 0) + "  vs " + ROUND(snap["vs"], 1) + "  twr " + ROUND(snap["twr"], 2) + "  thr " + ROUND(100 * snap["throttle"], 0) + "%  stg " + snap["stage"]).
    aoso_hud_set("dbg_warn", "WARN  " + snap["warn_n"] + "  " + snap["last_warn"]).
    aoso_hud_set("dbg_err", "ERR   " + snap["err_n"] + "  " + snap["last_err"]).
    aoso_hud_set("dbg_last", "LAST  " + snap["last_evt"]).
    aoso_hud_set("dbg_twin", "TWIN  " + snap["twin"] + "  n=" + snap["twin_n"] + "  " + snap["twin_reason"]).
    LOCAL age IS TIME:SECONDS - AOSO_HUD_LAST_DUMP.
    aoso_hud_set("dbg_file", "FILE  0:/aoso_hud.json  last dump " + ROUND(age, 0) + "s ago  (DUMP HUD writes now)").
}

FUNCTION aoso_hud_gui_paint_page {
    PARAMETER page_key.
    IF page_key = "FLT" { aoso_hud_gui_upd_flight(). RETURN. }
    IF page_key = "NAV" { aoso_hud_gui_upd_nav(). RETURN. }
    IF page_key = "MSN" { aoso_hud_gui_upd_mission(). RETURN. }
    IF page_key = "VEH" { aoso_hud_gui_upd_vehicle(). RETURN. }
    IF page_key = "PRP" { aoso_hud_gui_upd_prop(). RETURN. }
    IF page_key = "LND" { aoso_hud_gui_upd_land(). RETURN. }
    IF page_key = "STG" { aoso_hud_gui_upd_stg(). RETURN. }
    IF page_key = "SYS" { aoso_hud_gui_upd_sys(). RETURN. }
    IF page_key = "TWIN" { aoso_twin_view_tick(). RETURN. }
    IF page_key = "LOG" { aoso_hud_gui_upd_log(). RETURN. }
    IF page_key = "DBG" { aoso_hud_gui_upd_dbg(). RETURN. }
}

FUNCTION aoso_hud_gui_tick {
    PARAMETER allow.
    IF NOT AOSO_HUD_GUI:ISTYPE("GUI") { RETURN. }
    IF NOT allow {
        IF AOSO_HUD_GUI_ON { aoso_hud_gui_hide(). }
        RETURN.
    }
    IF AOSO_HUD_MODE = "TACTICAL" {
        IF AOSO_HUD_GUI_ON { aoso_hud_gui_hide(). }
        aoso_ui2_hud_update().
        RETURN.
    }
    IF NOT AOSO_HUD_GUI_ON { aoso_hud_gui_show(). }

    // Rendering cadence is wall-clock based. Rails warp may advance UT by
    // minutes per rendered frame and must not turn the MFD into a hot loop.
    LOCAL paint_now_rt IS KUNIVERSE:REALTIME.
    LOCAL page_key IS AOSO_HUD_PAGE.
    LOCAL force_paint IS FALSE.
    IF page_key <> AOSO_HUD_GUI_PAINTED { SET force_paint TO TRUE. }

    LOCAL paint_min_s IS 0.10.
    IF WARP > 0 { SET paint_min_s TO MAX(paint_min_s, 0.20). }
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 { SET paint_min_s TO MAX(paint_min_s, 0.20). }
        IF AOSO_CPU_LEVEL >= 3 { SET paint_min_s TO MAX(paint_min_s, 0.35). }
    }
    IF paint_now_rt - AOSO_HUD_LAST_GUI < paint_min_s {
        IF NOT force_paint { RETURN. }
    }

    SET AOSO_HUD_LAST_GUI TO paint_now_rt.
    SET AOSO_HUD_GUI_PAINTED TO page_key.

    LOCAL paint_rt0 IS KUNIVERSE:REALTIME.
    LOCAL paint_op0 IS OPCODESLEFT.
    aoso_hud_gui_upd_header().
    IF page_key <> "HELP" { aoso_hud_gui_paint_page(page_key). }

    LOCAL paint_ms IS (KUNIVERSE:REALTIME - paint_rt0) * 1000.
    LOCAL paint_ops IS paint_op0 - OPCODESLEFT.
    IF paint_ops < 0 { SET paint_ops TO 0. }
    SET AOSO_UI2_LAST_RENDER_MS TO paint_ms.
    SET AOSO_UI2_LAST_RENDER_OP TO paint_ops.
    SET AOSO_UI2_LAST_RENDER_PAGE TO page_key.
    IF paint_ms > AOSO_UI2_MAX_RENDER_MS { SET AOSO_UI2_MAX_RENDER_MS TO paint_ms. }
    IF paint_ops > AOSO_UI2_MAX_RENDER_OP { SET AOSO_UI2_MAX_RENDER_OP TO paint_ops. }
}
