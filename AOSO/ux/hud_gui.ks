// AOSO/ux/hud_gui.ks
// Movable AOSO computer. Built once; pages live in an ADDSTACK and are
// swapped with SHOWONLY. Labels update only when the text actually changed.

GLOBAL AOSO_HUD_GUI IS 0.
GLOBAL AOSO_HUD_STACK IS 0.
GLOBAL AOSO_HUD_PAGES IS LEXICON().
GLOBAL AOSO_HUD_TABS IS LEXICON().
GLOBAL AOSO_HUD_W IS LEXICON().
GLOBAL AOSO_HUD_LAST IS LEXICON().
GLOBAL AOSO_HUD_PAGE IS "FLT".
GLOBAL AOSO_HUD_GUI_ON IS TRUE.

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

FUNCTION aoso_hud_gui_dispose {
    IF AOSO_HUD_GUI:ISTYPE("GUI") {
        AOSO_HUD_GUI:DISPOSE().
    }
    SET AOSO_HUD_GUI TO 0.
    SET AOSO_HUD_STACK TO 0.
    SET AOSO_HUD_PAGES TO LEXICON().
    SET AOSO_HUD_TABS TO LEXICON().
    SET AOSO_HUD_W TO LEXICON().
    SET AOSO_HUD_LAST TO LEXICON().
}

FUNCTION aoso_hud_add_page {
    PARAMETER name.
    LOCAL p IS AOSO_HUD_STACK:ADDVLAYOUT().
    SET AOSO_HUD_PAGES[name] TO p.
    RETURN p.
}

FUNCTION aoso_hud_show_page {
    PARAMETER name.
    IF NOT AOSO_HUD_PAGES:HASKEY(name) { RETURN. }
    AOSO_HUD_STACK:SHOWONLY(AOSO_HUD_PAGES[name]).
    SET AOSO_HUD_PAGE TO name.
    IF AOSO_HUD_TABS:HASKEY(name) {
        SET AOSO_HUD_TABS[name]:PRESSED TO TRUE.
    }
}

FUNCTION aoso_hud_add_tab {
    PARAMETER row.
    PARAMETER name.
    PARAMETER label.
    LOCAL b IS row:ADDBUTTON(label).
    SET b:TOGGLE TO TRUE.
    SET b:EXCLUSIVE TO TRUE.
    SET b:ONCLICK TO aoso_hud_show_page@:BIND(name).
    SET AOSO_HUD_TABS[name] TO b.
    RETURN b.
}

FUNCTION aoso_hud_gui_build_flight {
    PARAMETER p.
    aoso_hud_title(p, "FLIGHT").
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
}

FUNCTION aoso_hud_gui_build_nav {
    PARAMETER p.
    aoso_hud_title(p, "NAVIGATION").
    aoso_hud_lab(p, "nav_soi", "SOI  -").
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
    aoso_hud_lab(p, "msn_name", "MISSION  -").
    aoso_hud_lab(p, "msn_prog", "PROGRESS  -").
    aoso_hud_lab(p, "msn_cur", "CURRENT  -").
    aoso_hud_lab(p, "msn_phase", "PHASE  -").
    aoso_hud_lab(p, "msn_next", "NEXT  -").
    aoso_hud_lab(p, "msn_obj", "OBJECTIVE  -").
    aoso_hud_lab(p, "msn_ret", "RETURN  KERBIN -> KSC").
    aoso_hud_lab(p, "msn_stat", "STATUS  -").
    aoso_hud_lab(p, "msn_feas", "FEAS  -").
    aoso_hud_lab(p, "msn_class", "CLASS  -").
}

FUNCTION aoso_hud_gui_build_vehicle {
    PARAMETER p.
    aoso_hud_title(p, "VEHICLE").
    aoso_hud_lab(p, "veh_id", "SHIP  -").
    aoso_hud_lab(p, "veh_cls", "CLASS  -").
    aoso_hud_lab(p, "veh_crew", "CREW  -").
    aoso_hud_lab(p, "veh_hw", "HARDWARE  -").
    aoso_hud_lab(p, "veh_mob", "MOBILITY  -").
    aoso_hud_lab(p, "veh_cap", "CAPABLE  -").
    aoso_hud_lab(p, "veh_pwr", "POWER  -").
}

FUNCTION aoso_hud_gui_build_prop {
    PARAMETER p.
    aoso_hud_title(p, "PROPULSION").
    aoso_hud_lab(p, "prp_thr", "THRUST  -").
    aoso_hud_lab(p, "prp_twr", "TWR / STAGE  -").
    aoso_hud_lab(p, "prp_dv", "dV  -").
    aoso_hud_lab(p, "prp_eng", "ENGINES  -").
    aoso_hud_lab(p, "prp_lf", "LF   -").
    aoso_hud_lab(p, "prp_ox", "OX   -").
    aoso_hud_lab(p, "prp_mp", "MP   -").
    aoso_hud_lab(p, "prp_ec", "EC   -").
}

FUNCTION aoso_hud_gui_build_land {
    PARAMETER p.
    aoso_hud_title(p, "LANDING").
    aoso_hud_lab(p, "lnd_st", "LANDING SYSTEM  STANDBY").
    aoso_hud_lab(p, "lnd_site", "SITE  -").
    aoso_hud_lab(p, "lnd_alt", "RADAR  -").
    aoso_hud_lab(p, "lnd_spd", "VSPD / HSPD  -").
    aoso_hud_lab(p, "lnd_twr", "TWR / THROTTLE  -").
    aoso_hud_lab(p, "lnd_trig", "SUICIDE  -").
    aoso_hud_lab(p, "lnd_dv", "LANDING dV  -").
    aoso_hud_lab(p, "lnd_gear", "GEAR  -").
}

FUNCTION aoso_hud_gui_build_stg {
    PARAMETER p.
    aoso_hud_title(p, "STAGING").
    aoso_hud_lab(p, "stg_cur", "CURRENT  -").
    aoso_hud_lab(p, "stg_fuel", "STAGE FUEL  -").
    aoso_hud_lab(p, "stg_thr", "THRUST  -").
    aoso_hud_lab(p, "stg_eng", "ENGINES  -").
    aoso_hud_lab(p, "stg_conf", "READY  -").
}

FUNCTION aoso_hud_gui_build_sys {
    PARAMETER p.
    aoso_hud_title(p, "SYSTEMS").
    aoso_hud_lab(p, "sys_roll", "AOSO  -").
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
    aoso_hud_title(p, "DEBUG").
    aoso_hud_lab(p, "dbg_cpu", "CPU  -").
    aoso_hud_lab(p, "dbg_ipu", "IPU  -").
    aoso_hud_lab(p, "dbg_page", "PAGE  -").
    aoso_hud_lab(p, "dbg_ctx", "CTX  -").
    aoso_hud_lab(p, "dbg_st", "STATE  -").
    aoso_hud_lab(p, "dbg_warn", "WARN  -").
    aoso_hud_lab(p, "dbg_err", "ERR  -").
    aoso_hud_lab(p, "dbg_last", "LAST  -").
}

FUNCTION aoso_hud_fd_cb_pro { PARAMETER on. aoso_hud_fd_set("PRO", on). }
FUNCTION aoso_hud_fd_cb_tgt { PARAMETER on. aoso_hud_fd_set("TGT", on). }
FUNCTION aoso_hud_fd_cb_burn { PARAMETER on. aoso_hud_fd_set("BURN", on). }
FUNCTION aoso_hud_fd_cb_land { PARAMETER on. aoso_hud_fd_set("LAND", on). }

FUNCTION aoso_hud_gui_init {
    aoso_hud_gui_dispose().
    LOCAL g IS GUI(460).
    SET g:X TO 20.
    SET g:Y TO 60.
    SET g:DRAGGABLE TO TRUE.
    SET AOSO_HUD_GUI TO g.

    LOCAL hdr IS g:ADDLABEL("<b><size=16><color=#7EC8FF>AOSO</color></size>  MISSION COMPUTER</b>").
    SET hdr:STYLE:HSTRETCH TO TRUE.
    aoso_hud_lab(g, "hdr_sys", "SYS  NOMINAL").
    aoso_hud_lab(g, "hdr_do", "DOING  -").
    aoso_hud_lab(g, "hdr_dt", "").

    LOCAL modes IS g:ADDHLAYOUT().
    LOCAL b_tac IS modes:ADDBUTTON("TAC").
    SET b_tac:ONCLICK TO aoso_hud_mode_tactical@.
    LOCAL b_gui IS modes:ADDBUTTON("GUI").
    SET b_gui:ONCLICK TO aoso_hud_mode_computer@.
    LOCAL b_eng IS modes:ADDBUTTON("ENG").
    SET b_eng:ONCLICK TO aoso_hud_mode_eng@.
    LOCAL b_fd IS modes:ADDCHECKBOX("FD", TRUE).
    SET b_fd:ONTOGGLE TO aoso_hud_fd_enable@.

    LOCAL fdrow IS g:ADDHLAYOUT().
    LOCAL c1 IS fdrow:ADDCHECKBOX("PRO", TRUE).
    SET c1:ONTOGGLE TO aoso_hud_fd_cb_pro@.
    LOCAL c2 IS fdrow:ADDCHECKBOX("TGT", TRUE).
    SET c2:ONTOGGLE TO aoso_hud_fd_cb_tgt@.
    LOCAL c3 IS fdrow:ADDCHECKBOX("BURN", TRUE).
    SET c3:ONTOGGLE TO aoso_hud_fd_cb_burn@.
    LOCAL c4 IS fdrow:ADDCHECKBOX("LAND", TRUE).
    SET c4:ONTOGGLE TO aoso_hud_fd_cb_land@.

    LOCAL row1 IS g:ADDHLAYOUT().
    aoso_hud_add_tab(row1, "FLT", "FLT").
    aoso_hud_add_tab(row1, "NAV", "NAV").
    aoso_hud_add_tab(row1, "MSN", "MSN").
    aoso_hud_add_tab(row1, "VEH", "VEH").
    aoso_hud_add_tab(row1, "PRP", "PRP").
    LOCAL row2 IS g:ADDHLAYOUT().
    aoso_hud_add_tab(row2, "LND", "LND").
    aoso_hud_add_tab(row2, "STG", "STG").
    aoso_hud_add_tab(row2, "SYS", "SYS").
    aoso_hud_add_tab(row2, "LOG", "LOG").
    aoso_hud_add_tab(row2, "DBG", "DBG").

    SET AOSO_HUD_STACK TO g:ADDSTACK().
    aoso_hud_gui_build_flight(aoso_hud_add_page("FLT")).
    aoso_hud_gui_build_nav(aoso_hud_add_page("NAV")).
    aoso_hud_gui_build_mission(aoso_hud_add_page("MSN")).
    aoso_hud_gui_build_vehicle(aoso_hud_add_page("VEH")).
    aoso_hud_gui_build_prop(aoso_hud_add_page("PRP")).
    aoso_hud_gui_build_land(aoso_hud_add_page("LND")).
    aoso_hud_gui_build_stg(aoso_hud_add_page("STG")).
    aoso_hud_gui_build_sys(aoso_hud_add_page("SYS")).
    aoso_hud_gui_build_log(aoso_hud_add_page("LOG")).
    aoso_hud_gui_build_dbg(aoso_hud_add_page("DBG")).

    SET AOSO_HUD_TABS["FLT"]:PRESSED TO TRUE.
    aoso_hud_show_page("FLT").
    SET AOSO_HUD_GUI_ON TO TRUE.
    g:SHOW().
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
    aoso_hud_set("hdr_sys", "SYS  " + col_roll + "   " + f["body"] + "  " + f["status"] + "   " + f["warp"]).
    LOCAL doing IS f["doing"].
    IF doing = "" { SET doing TO aoso_hud_doing_text(). }
    aoso_hud_set("hdr_do", "DOING  " + doing).
    aoso_hud_set("hdr_dt", f["detail"]).
}

FUNCTION aoso_hud_gui_upd_flight {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL radar_txt IS "".
    IF f["show_radar"] { SET radar_txt TO "  RAD " + aoso_hud_km(f["radar"]). }
    aoso_hud_set("flt_body", "BODY  " + f["body"] + "   " + f["status"]).
    aoso_hud_set("flt_alt", "ALT  " + aoso_hud_km(f["alt"]) + radar_txt + "   VS " + ROUND(f["vs"], 1) + " m/s").
    aoso_hud_set("flt_spd", "ORB " + ROUND(f["orb"], 0) + "  SRF " + ROUND(f["srf"], 0) + "  GS " + ROUND(f["gs"], 0) + " m/s").
    aoso_hud_set("flt_att", "HDG " + ROUND(f["hdg"], 0) + "  PITCH " + ROUND(f["pitch"], 1) + "  ROLL " + ROUND(f["roll"], 1)).
    LOCAL ap_txt IS aoso_hud_km(o["ap"]).
    IF o["hyper"] { SET ap_txt TO "hyper". }
    aoso_hud_set("flt_orb", "AP " + ap_txt + "  PE " + aoso_hud_km(o["pe"]) + "  INC " + ROUND(o["inc"], 1) + "  e " + ROUND(o["ecc"], 3)).
    aoso_hud_set("flt_twr", "TWR " + ROUND(f["twr"], 2) + "  THR " + ROUND(f["throttle"] * 100, 0) + "%  MASS " + ROUND(f["mass"], 2) + " t  STG " + f["stage"]).
    aoso_hud_set("flt_guid", "GUIDANCE     " + aoso_hud_st_glyph(sys["guid"])).
    aoso_hud_set("flt_steer", "STEERING     " + aoso_hud_st_glyph(sys["steer"]) + "  " + sys["steer_mode"]).
    aoso_hud_set("flt_thr", "THROTTLE     " + aoso_hud_st_glyph(sys["thr"]) + "  " + sys["thr_mode"]).
    aoso_hud_set("flt_nav", "NAVIGATION   " + aoso_hud_st_glyph(sys["nav"])).
}

FUNCTION aoso_hud_gui_upd_nav {
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL t IS AOSO_HUD_DATA["target"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    aoso_hud_set("nav_soi", "SOI  " + o["body"]).
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
    aoso_hud_set("msn_name", "MISSION  GRAND TOUR").
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
    aoso_hud_set("msn_feas", "FEAS  " + m["feas"]).
    aoso_hud_set("msn_class", "CLASS  " + m["class"]).
}

FUNCTION aoso_hud_gui_upd_vehicle {
    LOCAL v IS AOSO_HUD_DATA["vehicle"].
    aoso_hud_set("veh_id", "SHIP  " + v["name"] + "   TYPE " + v["type"] + "   PARTS " + v["parts"]).
    aoso_hud_set("veh_cls", "CLASS  " + v["class"]).
    aoso_hud_set("veh_crew", "CREW  " + v["crew"] + " / " + v["crew_cap"]).
    LOCAL hw IS "ENG " + v["engines"].
    IF v["antenna"] { SET hw TO hw + "  ANT Y". } ELSE { SET hw TO hw + "  ANT n". }
    IF v["rcs"] { SET hw TO hw + "  RCS Y". } ELSE { SET hw TO hw + "  RCS n". }
    aoso_hud_set("veh_hw", "HARDWARE  " + hw).
    LOCAL mob IS "".
    IF v["gear"] { SET mob TO mob + "GEAR  ". } ELSE { SET mob TO mob + "GEAR n  ". }
    IF v["chutes"] { SET mob TO mob + "CHUTES  ". } ELSE { SET mob TO mob + "CHUTES n  ". }
    aoso_hud_set("veh_mob", "MOBILITY  " + mob).
    LOCAL cap IS "".
    IF v["land"] { SET cap TO cap + "LAND Y  ". } ELSE { SET cap TO cap + "LAND n  ". }
    IF v["isru"] { SET cap TO cap + "ISRU Y  ". } ELSE { SET cap TO cap + "ISRU n  ". }
    IF v["dock"] { SET cap TO cap + "DOCK Y". } ELSE { SET cap TO cap + "DOCK n". }
    aoso_hud_set("veh_cap", "CAPABLE  " + cap).
    aoso_hud_set("veh_pwr", "POWER  SOLAR " + v["solar"] + "  EC " + ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%").
}

FUNCTION aoso_hud_gui_upd_prop {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL r IS AOSO_HUD_DATA["res"].
    LOCAL v IS AOSO_HUD_DATA["vehicle"].
    aoso_hud_set("prp_thr", "THRUST  " + ROUND(f["thrust"], 1) + " kN   THROTTLE " + ROUND(f["throttle"] * 100, 0) + "%").
    aoso_hud_set("prp_twr", "TWR " + ROUND(f["twr"], 2) + "   STAGE " + f["stage"]).
    aoso_hud_set("prp_dv", "dV  " + ROUND(r["mission_dv"], 0) + " / " + ROUND(r["total_dv"], 0) + " m/s").
    aoso_hud_set("prp_eng", "ENGINES  " + v["engines"]).
    IF r["lf_has"] { aoso_hud_set("prp_lf", "LF   " + aoso_hud_bar(r["lf"])). }
    ELSE { aoso_hud_set("prp_lf", "LF   " + aoso_hud_na()). }
    IF r["ox_has"] { aoso_hud_set("prp_ox", "OX   " + aoso_hud_bar(r["ox"])). }
    ELSE { aoso_hud_set("prp_ox", "OX   " + aoso_hud_na()). }
    IF r["mp_has"] { aoso_hud_set("prp_mp", "MP   " + aoso_hud_bar(r["mp"])). }
    ELSE { aoso_hud_set("prp_mp", "MP   " + aoso_hud_na()). }
    aoso_hud_set("prp_ec", "EC   " + aoso_hud_bar(r["ec"])).
}

FUNCTION aoso_hud_gui_upd_land {
    LOCAL l IS AOSO_HUD_DATA["landing"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL r IS AOSO_HUD_DATA["res"].
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
    aoso_hud_set("lnd_dv", "LANDING dV  need " + ROUND(r["land_dv"], 0) + "   have " + ROUND(r["mission_dv"], 0) + " m/s").
    LOCAL gtxt IS "UP".
    IF f["gear"] { SET gtxt TO "DOWN". }
    IF NOT AOSO_HUD_DATA["vehicle"]["gear"] { SET gtxt TO "NOT INSTALLED". }
    aoso_hud_set("lnd_gear", "GEAR  " + gtxt).
}

FUNCTION aoso_hud_gui_upd_stg {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL r IS AOSO_HUD_DATA["res"].
    LOCAL v IS AOSO_HUD_DATA["vehicle"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    aoso_hud_set("stg_cur", "CURRENT  STAGE " + f["stage"]).
    aoso_hud_set("stg_fuel", "STAGE FUEL  " + aoso_hud_bar(r["stage_pct"])).
    aoso_hud_set("stg_thr", "THRUST  " + ROUND(f["thrust"], 1) + " kN").
    aoso_hud_set("stg_eng", "ENGINES  " + v["engines"]).
    LOCAL ready IS aoso_hud_ok("READY").
    IF sys["stg"] = "DEG" { SET ready TO aoso_hud_warn("NO THRUST"). }
    IF sys["stg"] = "FAIL" { SET ready TO aoso_hud_bad("FAIL"). }
    aoso_hud_set("stg_conf", "STATUS  " + ready).
}

FUNCTION aoso_hud_gui_upd_sys {
    LOCAL s IS AOSO_HUD_DATA["systems"].
    aoso_hud_set("sys_roll", "AOSO  " + s["rollup"]).
    aoso_hud_set("sys_guid", "GUIDANCE     " + aoso_hud_st_glyph(s["guid"])).
    aoso_hud_set("sys_nav", "NAVIGATION   " + aoso_hud_st_glyph(s["nav"])).
    aoso_hud_set("sys_steer", "STEERING     " + aoso_hud_st_glyph(s["steer"]) + "  " + s["steer_mode"]).
    aoso_hud_set("sys_thr", "THROTTLE     " + aoso_hud_st_glyph(s["thr"]) + "  " + s["thr_mode"]).
    aoso_hud_set("sys_stg", "STAGING      " + aoso_hud_st_glyph(s["stg"])).
    aoso_hud_set("sys_msn", "MISSION      " + aoso_hud_st_glyph(s["msn"])).
    aoso_hud_set("sys_lnd", "LANDING      " + aoso_hud_st_glyph(s["lnd"])).
    aoso_hud_set("sys_pwr", "POWER        " + aoso_hud_st_glyph(s["pwr"]) + "  " + ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%").
    aoso_hud_set("sys_com", "COMMS        " + aoso_hud_st_glyph(s["com"])).
    aoso_hud_set("sys_wd", "WATCHDOG     " + aoso_hud_st_glyph(s["wd"])).
    aoso_hud_set("sys_cpu", "CPU          " + aoso_hud_st_glyph(s["cpu"]) + "  " + AOSO_HUD_DATA["debug"]["cpu"]).
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
    LOCAL d IS AOSO_HUD_DATA["debug"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    aoso_hud_set("dbg_cpu", "CPU  " + d["cpu"] + "  " + ROUND(100 * d["frac"], 0) + "%  spills " + d["spills"]).
    aoso_hud_set("dbg_ipu", "IPU  " + d["ipu"] + "   used " + ROUND(d["used"], 0) + "   left " + d["left"]).
    aoso_hud_set("dbg_page", "PAGE  " + d["page"] + "   MODE " + d["mode"]).
    aoso_hud_set("dbg_ctx", "CTX  " + d["ctx"] + "   PHASE " + d["phase"]).
    aoso_hud_set("dbg_st", "MSN " + m["mission"] + " / " + m["step"] + "  TOUR " + m["tour"] + "  GOTO " + m["goto"] + "  ASC " + m["ascent"]).
    aoso_hud_set("dbg_warn", "WARN  " + AOSO_HUD_WARN_N + "  " + AOSO_HUD_LAST_WARN).
    aoso_hud_set("dbg_err", "ERR   " + AOSO_HUD_ERR_N + "  " + AOSO_HUD_LAST_ERR).
    aoso_hud_set("dbg_last", "LAST  " + AOSO_HUD_LAST_EVT).
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
    IF pg = "LOG" { aoso_hud_gui_upd_log(). RETURN. }
    IF pg = "DBG" { aoso_hud_gui_upd_dbg(). RETURN. }
}
