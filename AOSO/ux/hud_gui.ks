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
        } ELSE {
            SET AOSO_HUD_TABS[k]:TEXT TO lab.
        }
    }
    SET AOSO_HUD_TAB_LOCK TO FALSE.
    aoso_hud_event_push("INFO", "page " + name).
}

FUNCTION aoso_hud_tab_click {
    PARAMETER name.
    IF AOSO_HUD_COMPACT { aoso_hud_set_compact(FALSE). }
    aoso_hud_show_page(name).
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
    RETURN 380 + (50 * AOSO_HUD_SCALE).
}

FUNCTION aoso_hud_scale_pct {
    RETURN 80 + (20 * AOSO_HUD_SCALE).
}

FUNCTION aoso_hud_skin_apply {
    PARAMETER g.
    LOCAL fs IS aoso_hud_scale_fs().
    SET g:SKIN:LABEL:FONTSIZE TO fs.
    SET g:SKIN:BUTTON:FONTSIZE TO fs.
    SET g:SKIN:TOGGLE:FONTSIZE TO fs.
    SET g:SKIN:WINDOW:FONTSIZE TO fs.
}

FUNCTION aoso_hud_scale_walk {
    PARAMETER box.
    PARAMETER fs.
    LOCAL q IS LIST(box).
    LOCAL i IS 0.
    UNTIL i >= q:LENGTH {
        LOCAL w IS q[i].
        SET i TO i + 1.
        SET w:STYLE:FONTSIZE TO fs.
        IF w:HASSUFFIX("WIDGETS") {
            FOR child IN w:WIDGETS { q:ADD(child). }
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
        SET AOSO_HUD_HDR_TITLE:TEXT TO "<b><size=" + (fs + 4) + "><color=#7EC8FF>AOSO</color></size>  MISSION COMPUTER</b>".
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
    aoso_hud_title(p, "FLIGHT").
    aoso_hud_hint(p, "Live ship state. Display only — AOSO is already flying.").
    aoso_hud_lab(p, "flt_body", "BODY  -").
    aoso_hud_lab(p, "flt_alt", "ALT  -").
    aoso_hud_lab(p, "flt_spd", "SPEED  -").
    aoso_hud_lab(p, "flt_att", "ATT  -").
    aoso_hud_lab(p, "flt_orb", "ORBIT  -").
    aoso_hud_lab(p, "flt_twr", "TWR  -").
    aoso_hud_lab(p, "flt_guid", "GUIDANCE  -").
    aoso_hud_lab(p, "flt_steer", "STEERING  -").
    aoso_hud_lab(p, "flt_thr", "THROTTLE  -").
    aoso_hud_lab(p, "flt_nav", "NAVIGATION  -").
    aoso_hud_lab(p, "flt_pri", "").
}

FUNCTION aoso_hud_gui_build_nav {
    PARAMETER p.
    aoso_hud_title(p, "NAVIGATION").
    aoso_hud_hint(p, "Orbit, target, and burn node. GOTO = transfer autopilot state. Does not retarget.").
    aoso_hud_lab(p, "nav_soi", "SPHERE OF INFLUENCE  -").
    aoso_hud_lab(p, "nav_orb", "ORBIT  -").
    aoso_hud_lab(p, "nav_tgt", "TARGET  NO TARGET").
    aoso_hud_lab(p, "nav_rel", "REL VEL  -").
    aoso_hud_lab(p, "nav_patch", "PATCH  -").
    aoso_hud_lab(p, "nav_node", "NODE  -").
    aoso_hud_lab(p, "nav_burn", "BURN  -").
    aoso_hud_lab(p, "nav_goto", "GOTO  -").
}

FUNCTION aoso_hud_gui_build_mission {
    PARAMETER p.
    aoso_hud_title(p, "MISSION CONTROL").
    aoso_hud_hint(p, "Grand-tour plan AOSO is flying. This page does not pick destinations.").
    aoso_hud_lab(p, "msn_name", "MISSION  -").
    aoso_hud_lab(p, "msn_prog", "PROGRESS  -").
    aoso_hud_lab(p, "msn_cur", "CURRENT  -").
    aoso_hud_lab(p, "msn_phase", "PHASE  -").
    aoso_hud_lab(p, "msn_next", "NEXT  -").
    aoso_hud_lab(p, "msn_obj", "OBJECTIVE  -").
    aoso_hud_lab(p, "msn_ret", "RETURN  KERBIN -> KSC").
    aoso_hud_lab(p, "msn_stat", "STATUS  -").
    aoso_hud_lab(p, "msn_feas", "FEASIBLE  -").
    aoso_hud_lab(p, "msn_class", "CLASS  -").
    aoso_hud_lab(p, "msn_time", "ROUTE  -").
    aoso_hud_lab(p, "msn_legend", "now = current hop.  done = already visited.  unmarked = still ahead.").
    aoso_hud_lab(p, "msn_skip", "").
}

FUNCTION aoso_hud_gui_build_vehicle {
    PARAMETER p.
    aoso_hud_title(p, "VEHICLE").
    aoso_hud_hint(p, "What this ship is and what AOSO thinks it can do.").
    aoso_hud_lab(p, "veh_id", "SHIP  -").
    aoso_hud_lab(p, "veh_cls", "CLASS  -").
    aoso_hud_lab(p, "veh_crew", "CREW  -").
    aoso_hud_lab(p, "veh_hw", "HARDWARE  -").
    aoso_hud_lab(p, "veh_mob", "MOBILITY  -").
    aoso_hud_lab(p, "veh_cap", "CAPABILITIES  -").
    aoso_hud_lab(p, "veh_pwr", "POWER  -").
    aoso_hud_lab(p, "veh_twin", "TWIN  -").
}

FUNCTION aoso_hud_gui_build_prop {
    PARAMETER p.
    aoso_hud_title(p, "PROPULSION").
    aoso_hud_hint(p, "Fuel and engines. LF=liquid fuel  OX=oxidizer  MP=monopropellant  EC=electric charge  dV=delta-v. Does not throttle.").
    aoso_hud_lab(p, "prp_thr", "THRUST  -").
    aoso_hud_lab(p, "prp_twr", "TWR / STAGE  -").
    aoso_hud_lab(p, "prp_dv", "DELTA-V  -").
    aoso_hud_lab(p, "prp_eng", "ENGINES  -").
    aoso_hud_lab(p, "prp_lf", "LIQUID FUEL  -").
    aoso_hud_lab(p, "prp_ox", "OXIDIZER  -").
    aoso_hud_lab(p, "prp_mp", "MONOPROP  -").
    aoso_hud_lab(p, "prp_ec", "ELECTRIC  -").
    aoso_hud_lab(p, "prp_next", "NEXT STAGE  -").
}

FUNCTION aoso_hud_gui_build_land {
    PARAMETER p.
    aoso_hud_title(p, "LANDING").
    aoso_hud_hint(p, "Landing radar and suicide-burn numbers. The LAND light is an arrow, not a land command. AOSO flies the landing.").
    aoso_hud_lab(p, "lnd_st", "LANDING SYSTEM  STANDBY").
    aoso_hud_lab(p, "lnd_site", "SITE  -").
    aoso_hud_lab(p, "lnd_alt", "RADAR  -").
    aoso_hud_lab(p, "lnd_spd", "VSPD / HSPD  -").
    aoso_hud_lab(p, "lnd_twr", "TWR / THROTTLE  -").
    aoso_hud_lab(p, "lnd_trig", "SUICIDE  -").
    aoso_hud_lab(p, "lnd_dv", "LANDING dV  -").
    aoso_hud_lab(p, "lnd_gear", "GEAR  -").
    aoso_hud_lab(p, "lnd_ret0", "").
    aoso_hud_lab(p, "lnd_ret1", "").
    aoso_hud_lab(p, "lnd_ret2", "").
    aoso_hud_lab(p, "lnd_ret3", "").
}

FUNCTION aoso_hud_gui_build_stg {
    PARAMETER p.
    aoso_hud_title(p, "STAGING").
    aoso_hud_hint(p, "Current stage fuel and thrust. AOSO stages by itself — this page does not press SPACE.").
    aoso_hud_lab(p, "stg_cur", "CURRENT  -").
    aoso_hud_lab(p, "stg_fuel", "STAGE FUEL  -").
    aoso_hud_lab(p, "stg_thr", "THRUST  -").
    aoso_hud_lab(p, "stg_eng", "ENGINES  -").
    aoso_hud_lab(p, "stg_conf", "READY  -").
}

FUNCTION aoso_hud_gui_build_sys {
    PARAMETER p.
    aoso_hud_title(p, "SYSTEMS").
    aoso_hud_hint(p, "Health board. NOMINAL=ok  DEGRADED=weak  FAIL=broken. WHY is the reason. CPU busy is not a ship failure.").
    aoso_hud_lab(p, "sys_roll", "AOSO  -").
    aoso_hud_lab(p, "sys_why", "").
    aoso_hud_lab(p, "sys_cpu_note", "").
    aoso_hud_lab(p, "sys_guid", "GUIDANCE     -").
    aoso_hud_lab(p, "sys_nav", "NAVIGATION   -").
    aoso_hud_lab(p, "sys_steer", "STEERING     -").
    aoso_hud_lab(p, "sys_thr", "THROTTLE     -").
    aoso_hud_lab(p, "sys_stg", "STAGING      -").
    aoso_hud_lab(p, "sys_msn", "MISSION      -").
    aoso_hud_lab(p, "sys_lnd", "LANDING      -").
    aoso_hud_lab(p, "sys_pwr", "POWER        -").
    aoso_hud_lab(p, "sys_com", "COMMS        -").
    aoso_hud_lab(p, "sys_wd", "WATCHDOG     -").
    aoso_hud_lab(p, "sys_cpu", "CPU          -").
}

FUNCTION aoso_hud_gui_build_log {
    PARAMETER p.
    aoso_hud_title(p, "EVENT LOG").
    aoso_hud_hint(p, "Latest AOSO decisions and events. Newest at the bottom.").
    aoso_hud_lab(p, "log_0", "-").
    aoso_hud_lab(p, "log_1", "-").
    aoso_hud_lab(p, "log_2", "-").
    aoso_hud_lab(p, "log_3", "-").
    aoso_hud_lab(p, "log_4", "-").
    aoso_hud_lab(p, "log_5", "-").
    aoso_hud_lab(p, "log_6", "-").
    aoso_hud_lab(p, "log_7", "-").
    aoso_hud_lab(p, "log_8", "-").
    aoso_hud_lab(p, "log_9", "-").
}

FUNCTION aoso_hud_gui_build_dbg {
    PARAMETER p.
    aoso_hud_title(p, "DEBUG  (entire HUD)").
    aoso_hud_hint(p, "Internal HUD clocks and dump. DUMP HUD writes 0:/aoso_hud.json on the kOS archive.").
    LOCAL row IS p:ADDHLAYOUT().
    LOCAL dump_btn IS row:ADDBUTTON("DUMP HUD").
    SET dump_btn:ONCLICK TO aoso_hud_debug_dump@.
    aoso_hud_lab(p, "dbg_cpu", "CPU  -").
    aoso_hud_lab(p, "dbg_ipu", "IPU  -").
    aoso_hud_lab(p, "dbg_page", "PAGE  -").
    aoso_hud_lab(p, "dbg_ctx", "CTX  -").
    aoso_hud_lab(p, "dbg_gui", "GUI  -").
    aoso_hud_lab(p, "dbg_sys", "SYS  -").
    aoso_hud_lab(p, "dbg_fd", "FD  -").
    aoso_hud_lab(p, "dbg_st", "STATE  -").
    aoso_hud_lab(p, "dbg_do", "DOING  -").
    aoso_hud_lab(p, "dbg_flt", "FLT  -").
    aoso_hud_lab(p, "dbg_warn", "WARN  -").
    aoso_hud_lab(p, "dbg_err", "ERR  -").
    aoso_hud_lab(p, "dbg_last", "LAST  -").
    aoso_hud_lab(p, "dbg_twin", "TWIN  -").
    aoso_hud_lab(p, "dbg_file", "FILE  0:/aoso_hud.json").
}

FUNCTION aoso_hud_gui_build_help {
    PARAMETER p.
    aoso_hud_title(p, "HOW TO USE THIS HUD").
    aoso_hud_hint(p, "This window is a display. AOSO flies the ship. Nothing here STAGES, ABORTS, or LANDS.").
    aoso_hud_hint(p, "TABS  FLT=flight  NAV=orbit/target  MSN=mission plan  VEH=this ship  PRP=fuel  LND=landing view  STG=staging  SYS=health  TWIN=tanks/engines  LOG=events  DBG=dump").
    aoso_hud_hint(p, "GREEN LIGHTS  3D arrows drawn on the ship. They do not steer. PRO=prograde (where you are going)  RET=retrograde (opposite)  NML=orbit-normal (out of plane)  TGT=toward target  REL=relative velocity  BURN=maneuver node  LAND=surface-retrograde.").
    aoso_hud_hint(p, "FD master switch turns all arrows off. Lights that are on still only draw; AOSO keeps flying.").
    aoso_hud_hint(p, "CPU HIGH / load-shed  kOS is using most of its instruction budget (usually during a burn or staging). AOSO pauses extra HUD/profile work so steering and staging still run. Not a hardware failure. SYS tab has the WHY line.").
    aoso_hud_hint(p, "SYS  NOMINAL=all good  DEGRADED=something weak  FAIL=something broken. Open SYS and read WHY.").
    aoso_hud_hint(p, "ROUTE  (now)=current hop  (done)=already visited  unmarked=still ahead.").
    aoso_hud_hint(p, "CHROME  BACK=previous tab  HOME=flight page  HELP=this page  A-/A+=size  X=collapse to header  OPEN=expand.").
    aoso_hud_hint(p, "MODES  TAC=terminal strip only  GUI=this computer  ENG=engineering + twin. Drag the window by its top.").
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

    LOCAL hdr IS g:ADDLABEL("<b><size=16><color=#7EC8FF>AOSO</color></size>  MISSION COMPUTER</b>").
    SET hdr:STYLE:HSTRETCH TO TRUE.
    SET AOSO_HUD_HDR_TITLE TO hdr.
    aoso_hud_lab(g, "hdr_sys", "SYS  NOMINAL").
    aoso_hud_lab(g, "hdr_twin", "TWIN  -").
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

    LOCAL body IS g:ADDVLAYOUT().
    SET AOSO_HUD_BODY TO body.

    LOCAL modes IS body:ADDHLAYOUT().
    LOCAL b_tac IS modes:ADDBUTTON("TAC").
    SET b_tac:ONCLICK TO aoso_hud_mode_tactical@.
    LOCAL b_gui IS modes:ADDBUTTON("GUI").
    SET b_gui:ONCLICK TO aoso_hud_mode_computer@.
    LOCAL b_eng IS modes:ADDBUTTON("ENG").
    SET b_eng:ONCLICK TO aoso_hud_mode_eng@.
    LOCAL b_fd IS modes:ADDCHECKBOX("FD", TRUE).
    SET b_fd:ONTOGGLE TO aoso_hud_fd_cb_master@.

    LOCAL fdrow IS body:ADDHLAYOUT().
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
    aoso_hud_hint(body, "FD lights draw 3D arrows on the ship. They do not fly it. PRO=prograde  RET=retrograde  NML=orbit-normal  TGT=target  REL=relative vel  BURN=node  LAND=surface-retro. HELP tab explains all of this.").

    LOCAL row1 IS body:ADDHLAYOUT().
    aoso_hud_add_tab(row1, "FLT", "FLT").
    aoso_hud_add_tab(row1, "NAV", "NAV").
    aoso_hud_add_tab(row1, "MSN", "MSN").
    aoso_hud_add_tab(row1, "VEH", "VEH").
    aoso_hud_add_tab(row1, "PRP", "PRP").
    LOCAL row2 IS body:ADDHLAYOUT().
    aoso_hud_add_tab(row2, "LND", "LND").
    aoso_hud_add_tab(row2, "STG", "STG").
    aoso_hud_add_tab(row2, "SYS", "SYS").
    aoso_hud_add_tab(row2, "TWIN", "TWIN").
    aoso_hud_add_tab(row2, "LOG", "LOG").
    aoso_hud_add_tab(row2, "DBG", "DBG").
    aoso_hud_add_tab(row2, "HELP", "HELP").

    SET AOSO_HUD_STACK TO body:ADDVLAYOUT().
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

    aoso_hud_apply_scale().
    aoso_hud_set_compact(AOSO_HUD_COMPACT).
    aoso_hud_show_page("FLT", FALSE).
    SET AOSO_HUD_GUI_ON TO TRUE.
    g:SHOW().
    aoso_hud_trace_log("GUI online").
}

FUNCTION aoso_hud_gui_hide {
    IF AOSO_HUD_GUI:ISTYPE("GUI") { AOSO_HUD_GUI:HIDE(). }
    SET AOSO_HUD_GUI_ON TO FALSE.
}

FUNCTION aoso_hud_gui_show {
    IF AOSO_HUD_GUI:ISTYPE("GUI") { AOSO_HUD_GUI:SHOW(). }
    SET AOSO_HUD_GUI_ON TO TRUE.
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
}

FUNCTION aoso_hud_tabs_adapt {
    LOCAL veh IS AOSO_HUD_DATA["vehicle"].
    LOCAL show_lnd IS FALSE.
    IF veh:HASKEY("land") {
        IF veh["land"] { SET show_lnd TO TRUE. }
        IF veh["gear"] { SET show_lnd TO TRUE. }
        IF veh["chutes"] { SET show_lnd TO TRUE. }
    }
    IF AOSO_HUD_DATA["landing"]:HASKEY("active") {
        IF AOSO_HUD_DATA["landing"]["active"] { SET show_lnd TO TRUE. }
    }
    IF AOSO_HUD_TABS:HASKEY("LND") {
        IF show_lnd <> AOSO_HUD_SHOW_LND {
            SET AOSO_HUD_TABS["LND"]:VISIBLE TO show_lnd.
            SET AOSO_HUD_SHOW_LND TO show_lnd.
            aoso_hud_trace("tab LND visible=" + show_lnd).
        }
        IF NOT show_lnd {
            IF AOSO_HUD_PAGE = "LND" { aoso_hud_show_page("FLT"). }
        }
    }
    LOCAL show_prp IS TRUE.
    IF veh:HASKEY("engines") {
        IF veh["engines"] <= 0 {
            IF AOSO_HUD_DATA["res"]:HASKEY("lf_has") {
                IF NOT AOSO_HUD_DATA["res"]["lf_has"] { SET show_prp TO FALSE. }
            }
        }
    }
    IF AOSO_HUD_TABS:HASKEY("PRP") {
        IF show_prp <> AOSO_HUD_SHOW_PRP {
            SET AOSO_HUD_TABS["PRP"]:VISIBLE TO show_prp.
            SET AOSO_HUD_SHOW_PRP TO show_prp.
            aoso_hud_trace("tab PRP visible=" + show_prp).
        }
        IF NOT show_prp {
            IF AOSO_HUD_PAGE = "PRP" { aoso_hud_show_page("FLT"). }
        }
    }
}

FUNCTION aoso_hud_gui_upd_flight {
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
    aoso_hud_set("sys_cpu", "CPU          " + aoso_hud_st_glyph(s["cpu"]) + "  " + AOSO_HUD_DATA["debug"]["cpu"] + aoso_hud_sys_suffix("cpu", s)).
    LOCAL cpu_note IS "CPU has spare instructions. HUD running at full rate.".
    IF s["cpu"] = "DEG" { SET cpu_note TO "kOS is busy (often a burn). Extra HUD/profile work is paused so steering and staging keep running. Not a ship failure.". }
    IF s["cpu"] = "FAIL" { SET cpu_note TO "kOS is overloaded. HUD may skip frames so burns/staging still run. Not a ship failure.". }
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
    aoso_hud_set("dbg_ipu", "IPU  " + snap["ipu"] + "   left " + snap["left"]).
    aoso_hud_set("dbg_page", "PAGE  " + snap["page"] + "   MODE " + snap["mode"] + "   ready=" + snap["ready"]).
    aoso_hud_set("dbg_ctx", "CTX  " + snap["ctx"] + "   PHASE " + d["phase"] + "   body " + snap["body"] + " " + snap["status"]).
    aoso_hud_set("dbg_gui", "GUI  on=" + snap["gui_on"] + "  collect hi/md/lo age " + ROUND(snap["hi_age"], 1) + "/" + ROUND(snap["md_age"], 1) + "/" + ROUND(snap["lo_age"], 1) + "s").
    LOCAL why IS snap["why"].
    IF why = "" { SET why TO "nominal". }
    aoso_hud_set("dbg_sys", "SYS  " + snap["sys"] + "  " + why).
    aoso_hud_set("dbg_fd", "FD  " + snap["fd"]).
    aoso_hud_set("dbg_st", "MSN " + m["mission"] + " / " + m["step"] + "  TOUR " + m["tour"] + "  GOTO " + m["goto"] + "  ASC " + m["ascent"]).
    aoso_hud_set("dbg_do", "DOING  " + snap["doing"] + "  " + snap["detail"]).
    aoso_hud_set("dbg_flt", "FLT  alt " + ROUND(snap["alt"], 0) + "  vs " + ROUND(snap["vs"], 1) + "  twr " + ROUND(snap["twr"], 2) + "  thr " + ROUND(100 * snap["throttle"], 0) + "%  stg " + snap["stage"]).
    aoso_hud_set("dbg_warn", "WARN  " + snap["warn_n"] + "  " + snap["last_warn"]).
    aoso_hud_set("dbg_err", "ERR   " + snap["err_n"] + "  " + snap["last_err"]).
    aoso_hud_set("dbg_last", "LAST  " + snap["last_evt"]).
    aoso_hud_set("dbg_twin", "TWIN  " + snap["twin"] + "  n=" + snap["twin_n"] + "  " + snap["twin_reason"]).
    LOCAL age IS TIME:SECONDS - AOSO_HUD_LAST_DUMP.
    aoso_hud_set("dbg_file", "FILE  0:/aoso_hud.json  last dump " + ROUND(age, 0) + "s ago  (DUMP HUD writes now)").
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
        RETURN.
    }
    IF NOT AOSO_HUD_GUI_ON { aoso_hud_gui_show(). }
    aoso_hud_gui_upd_header().
    LOCAL pg IS AOSO_HUD_PAGE.
    IF pg = "FLT" { aoso_hud_gui_upd_flight(). RETURN. }
    IF pg = "NAV" { aoso_hud_gui_upd_nav(). RETURN. }
    IF pg = "MSN" { aoso_hud_gui_upd_mission(). RETURN. }
    IF pg = "VEH" { aoso_hud_gui_upd_vehicle(). RETURN. }
    IF pg = "PRP" { aoso_hud_gui_upd_prop(). RETURN. }
    IF pg = "LND" { aoso_hud_gui_upd_land(). RETURN. }
    IF pg = "STG" { aoso_hud_gui_upd_stg(). RETURN. }
    IF pg = "SYS" { aoso_hud_gui_upd_sys(). RETURN. }
    IF pg = "TWIN" { aoso_twin_view_tick(). RETURN. }
    IF pg = "LOG" { aoso_hud_gui_upd_log(). RETURN. }
    IF pg = "DBG" { aoso_hud_gui_upd_dbg(). RETURN. }
    IF pg = "HELP" { RETURN. }
}
