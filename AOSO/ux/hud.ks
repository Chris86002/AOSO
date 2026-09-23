// AOSO/ux/hud.ks
// HUD coordinator. Presentation only: cache -> terminal strip / GUI /
// VECDRAW / HUDTEXT. Callers still use aoso_ui_set / aoso_ui_pulse.
//
// Modes:
//   COMPUTER    - GUI window + compact terminal + flight director
//   TACTICAL    - GUI hidden, compact flight HUD, vectors, alerts
//   ENGINEERING - GUI forced to SYS/DBG density
//
// Do not RUN this file alone; main.ks loads hud_fmt/data/alert/fd/gui first.

GLOBAL AOSO_HUD_ROWS IS 8.
GLOBAL AOSO_HUD_SPACES IS "                                                                                                    ".
GLOBAL AOSO_UI IS LEXICON("doing", "", "detail", "").
GLOBAL AOSO_HUD_MODE IS "COMPUTER".
GLOBAL AOSO_HUD_READY IS FALSE.
GLOBAL AOSO_HUD_LAST_DUMP IS 0.
GLOBAL AOSO_HUD_BUS_LAST IS "".
GLOBAL AOSO_HUD_BUS_UT IS 0.
GLOBAL AOSO_HUD_PEER IS FALSE.
GLOBAL AOSO_HUD_FAST_SKIP IS 0.

FUNCTION aoso_ui_set {
    PARAMETER doing.
    PARAMETER detail IS "".
    SET AOSO_UI["doing"] TO doing.
    SET AOSO_UI["detail"] TO detail.
}

FUNCTION aoso_ui_clear {
    SET AOSO_UI["doing"] TO "".
    SET AOSO_UI["detail"] TO "".
}

FUNCTION aoso_ui_pulse {
    PARAMETER doing.
    PARAMETER detail IS "".
    aoso_ui_set(doing, detail).
}

FUNCTION aoso_hud_line {
    PARAMETER row.
    PARAMETER text.
    LOCAL width IS 64.
    IF TERMINAL:WIDTH > 0 { SET width TO TERMINAL:WIDTH. }
    IF width > 100 { SET width TO 100. }
    LOCAL out IS text.
    IF out:LENGTH > width { SET out TO out:SUBSTRING(0, width). }
    IF out:LENGTH < width {
        SET out TO out + AOSO_HUD_SPACES:SUBSTRING(0, width - out:LENGTH).
    }
    PRINT out AT(0, row).
}

FUNCTION aoso_hud_prepare_terminal {
    IF TERMINAL:WIDTH < 64 { SET TERMINAL:WIDTH TO 64. }
    IF TERMINAL:HEIGHT < 36 { SET TERMINAL:HEIGHT TO 36. }
}

FUNCTION aoso_hud_doing_text {
    IF AOSO_MANEUVER_BURNING {
        RETURN "BURNING  " + ROUND(AOSO_MANEUVER_LAST_REMAINING, 1) + " m/s left".
    }
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        RETURN "Node T-" + aoso_hud_eta(nd:ETA) + "  " + ROUND(nd:DELTAV:MAG, 1) + " m/s  " + aoso_warp_diag_txt().
    }
    IF AOSO_UI["doing"] <> "" { RETURN AOSO_UI["doing"]. }
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] = "COAST" {
            IF SHIP:ORBIT:HASNEXTPATCH {
                RETURN "Coasting to " + SHIP:ORBIT:NEXTPATCH:BODY:NAME + "  SOI " + aoso_hud_eta(SHIP:ORBIT:NEXTPATCHETA).
            }
            RETURN "Coasting".
        }
        IF AOSO_GOTO["current"] = "CAPTURE" { RETURN "Capture at PE". }
        IF AOSO_GOTO["current"] = "PLAN" { RETURN "Planning hop". }
        IF AOSO_GOTO["current"] = "WAIT" { RETURN "Transfer window". }
        IF AOSO_GOTO["current"] = "BURN" { RETURN "Transfer burn". }
        IF AOSO_GOTO["current"] = "LAUNCH" { RETURN "Launching". }
    }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] = "POLAR" { RETURN "Polar insertion". }
        IF AOSO_TOUR["current"] = "SCAN" { RETURN "Scanning sites". }
        IF AOSO_TOUR["current"] = "DEORBIT" { RETURN "Deorbit wait". }
        IF AOSO_TOUR["current"] = "DESCEND" { RETURN "Descent". }
        IF AOSO_TOUR["current"] = "REFUEL" { RETURN "ISRU refuel". }
        IF AOSO_TOUR["current"] = "RETURN" { RETURN "Return home". }
        IF AOSO_TOUR["current"] = "KSC" { RETURN "KSC return". }
    }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" { RETURN "Ascent  " + AOSO_ASCENT["current"]. }
        }
    }
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "" {
            RETURN AOSO_MISSION["current"] + " / " + aoso_mission_current_step_name().
        }
    }
    RETURN "idle".
}

FUNCTION aoso_hud_trace {
    PARAMETER msg.
    aoso_hud_event_push("INFO", msg).
}

FUNCTION aoso_hud_trace_log {
    PARAMETER msg.
    aoso_hud_event_push("INFO", msg).
    aoso_log_info("HUD", msg).
}

FUNCTION aoso_hud_mode_tactical {
    SET AOSO_HUD_MODE TO "TACTICAL".
    aoso_hud_gui_hide().
    aoso_hud_trace_log("mode TACTICAL").
    aoso_hud_alert("mode", "INFO", "TACTICAL HUD", 4, 2).
}

FUNCTION aoso_hud_mode_computer {
    SET AOSO_HUD_MODE TO "COMPUTER".
    aoso_hud_gui_show().
    aoso_hud_trace_log("mode COMPUTER").
    aoso_hud_alert("mode", "INFO", "MISSION COMPUTER", 4, 2).
}

FUNCTION aoso_hud_mode_eng {
    SET AOSO_HUD_MODE TO "ENGINEERING".
    aoso_hud_gui_show().
    aoso_hud_show_page("TWIN").
    aoso_hud_trace_log("mode ENGINEERING").
    aoso_hud_alert("mode", "INFO", "ENGINEERING HUD", 4, 2).
}

FUNCTION aoso_hud_term_tick {
    PARAMETER compact.
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL rsrc IS AOSO_HUD_DATA["res"].
    LOCAL s IS AOSO_HUD_DATA["systems"].
    LOCAL d IS AOSO_HUD_DATA["debug"].
    LOCAL roll IS "NOMINAL".
    IF s:HASKEY("rollup") { SET roll TO s["rollup"]. }
    LOCAL doing IS f["doing"].
    IF doing = "" { SET doing TO aoso_hud_doing_text(). }

    IF compact {
        aoso_hud_line(0, "AOSO  " + roll + "  " + d["cpu"] + "  " + ROUND(100 * d["frac"], 0) + "%/" + d["ipu"]).
        aoso_hud_line(1, SHIP:NAME + "  " + doing).
        aoso_hud_line(2, "EC " + ROUND(rsrc["ec"], 0) + "%  " + f["body"] + "  " + f["status"]).
        aoso_hud_line(3, "").
        RETURN.
    }

    LOCAL ap_txt IS aoso_hud_km(o["ap"]).
    IF o["hyper"] { SET ap_txt TO "hyper". }
    LOCAL node_txt IS "Node none".
    IF o["node"] {
        SET node_txt TO "Node T-" + aoso_hud_eta(o["node_eta"]) + "  " + ROUND(o["node_dv"], 1) + " m/s".
        IF o["burning"] { SET node_txt TO "BURN  " + ROUND(o["burn_left"], 1) + " m/s left". }
    }
    LOCAL patch_txt IS "Patch none".
    IF o["patch"] <> "" { SET patch_txt TO "Patch " + o["patch"] + "  " + aoso_hud_eta(o["patch_eta"]). }

    aoso_hud_line(0, "AOSO  " + roll + "  " + AOSO_HUD_MODE + "  " + AOSO_HUD_CTX + "  " + f["warp"]).
    aoso_hud_line(1, "DOING  " + doing).
    aoso_hud_line(2, "ALT " + aoso_hud_km(f["alt"]) + "  VS " + ROUND(f["vs"], 1) + "  GS " + ROUND(f["gs"], 0) + "  TWR " + ROUND(f["twr"], 2) + "  HDG " + ROUND(f["hdg"], 0)).
    aoso_hud_line(3, "AP " + ap_txt + "  PE " + aoso_hud_km(o["pe"]) + "  " + node_txt).
    aoso_hud_line(4, "EC " + ROUND(rsrc["ec"], 0) + "%  LF " + ROUND(rsrc["lf"], 0) + "%  dV " + ROUND(rsrc["mission_dv"], 0) + "/" + ROUND(rsrc["total_dv"], 0) + "  " + patch_txt).
    LOCAL n IS 5.
    IF AOSO_HUD_MODE = "ENGINEERING" {
        aoso_hud_line(5, "CPU " + d["cpu"] + " " + ROUND(100 * d["frac"], 0) + "%/" + d["ipu"] + "  PWR " + s["pwr"] + "  WD " + s["wd"] + "  NAV " + s["nav"] + "  MSN " + s["msn"]).
        aoso_hud_line(6, f["detail"]).
        SET n TO 7.
    } ELSE {
        aoso_hud_line(5, f["detail"]).
        SET n TO 6.
    }
    aoso_hud_line(n, "").
}

FUNCTION aoso_hud_tick {
    IF NOT AOSO_HUD_READY { RETURN. }
    LOCAL rates IS aoso_hud_collect().
    LOCAL compact IS FALSE.
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 {
            IF AOSO_HUD_PAGE = "TWIN" OR AOSO_HUD_PAGE = "VEH" { SET compact TO TRUE. }
        }
    }
    IF rates["term"] {
        IF NOT AOSO_HUD_GUI_ON {
            IF NOT AOSO_UI2_HUD_VISIBLE { aoso_hud_term_tick(compact). }
        }
    }
    IF NOT compact {
        aoso_hud_watch_alerts().
        aoso_hud_fd_tick(rates["fd"]).
        LOCAL want_twin IS FALSE.
        IF AOSO_HUD_PAGE = "TWIN" OR AOSO_HUD_PAGE = "VEH" {
            IF NOT AOSO_HUD_COMPACT { SET want_twin TO TRUE. }
        }
        IF rates["lo"] > 0 {
            IF TIME:SECONDS - AOSO_HUD_LAST_LO >= rates["lo"] { SET want_twin TO TRUE. }
        }
        IF want_twin {
            LOCAL twin_geom IS TRUE.
            LOCAL twin_fill IS TRUE.
            IF DEFINED AOSO_CPU_LEVEL {
                IF AOSO_CPU_LEVEL >= 2 { SET twin_geom TO FALSE. }
            }
            IF AOSO_HUD_PAGE <> "TWIN" AND AOSO_HUD_PAGE <> "VEH" { SET twin_geom TO FALSE. }
            aoso_twin_tick(twin_geom, twin_fill).
        }
    }
    aoso_hud_gui_tick(TRUE).
    aoso_log_every(20, "HUD_HB", aoso_hud_debug_line()).
    IF AOSO_HUD_PAGE = "DBG" {
        IF TIME:SECONDS - AOSO_HUD_LAST_DUMP >= 20 { aoso_hud_debug_write(). }
    }
}

FUNCTION aoso_hud_bus_line {
    LOCAL doing IS aoso_hud_doing_fast().
    LOCAL sysr IS "NOMINAL".
    IF AOSO_HUD_DATA["systems"]:HASKEY("rollup") { SET sysr TO AOSO_HUD_DATA["systems"]["rollup"]. }
    LOCAL cpu_n IS "NORMAL".
    IF DEFINED AOSO_CPU_NAME { SET cpu_n TO AOSO_CPU_NAME. }
    RETURN doing + "|" + AOSO_UI["detail"] + "|" + sysr + "|" + cpu_n + "|" + AOSO_HUD_PAGE + "|" + ROUND(ALTITUDE, 0) + "|" + ROUND(VERTICALSPEED, 1).
}

FUNCTION aoso_hud_bus_write {
    IF NOT AOSO_HUD_PEER { RETURN. }
    IF TIME:SECONDS - AOSO_HUD_BUS_UT < 0.25 { RETURN. }
    LOCAL line IS aoso_hud_bus_line().
    IF line = AOSO_HUD_BUS_LAST { RETURN. }
    SET AOSO_HUD_BUS_LAST TO line.
    SET AOSO_HUD_BUS_UT TO TIME:SECONDS.
    LOCAL pth IS "0:/aoso_hud_bus.txt".
    IF EXISTS(pth) {
        LOCAL f IS OPEN(pth).
        f:CLEAR().
        f:WRITELN(line).
    } ELSE {
        LOCAL f2 IS CREATE(pth).
        f2:WRITELN(line).
    }
}

FUNCTION aoso_hud_fast_tick {
    IF NOT AOSO_HUD_READY { RETURN. }
    IF OPCODESLEFT < 100 { RETURN. }
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 {
            SET AOSO_HUD_FAST_SKIP TO AOSO_HUD_FAST_SKIP + 1.
            IF AOSO_HUD_FAST_SKIP < 2 { RETURN. }
            SET AOSO_HUD_FAST_SKIP TO 0.
        }
    }
    aoso_hud_collect_fast().
    aoso_hud_gui_fast().
    aoso_hud_bus_write().
}

FUNCTION aoso_hud_draw {
    aoso_hud_tick().
}

FUNCTION aoso_hud_peer_note {
    LOCAL n IS 0.
    LIST PROCESSORS IN procs.
    FOR p IN procs { SET n TO n + 1. }
    IF n <= 1 {
        aoso_log_info("HUD", "One kOS CPU. Flight tasks run first each physics frame; the HUD paints with leftover IPU. A second processor tagged HUD running AOSO/ux/hud_cpu.ks is the only way to get a full extra IPU for the glass cockpit.").
        RETURN.
    }
    SET AOSO_HUD_PEER TO TRUE.
    aoso_log_info("HUD", n + " kOS CPUs. Tag a spare core HUD and set its boot file to AOSO/ux/hud_cpu.ks for a second IPU. This core will keep flying.").
}

FUNCTION aoso_hud_init {
    aoso_hud_prepare_terminal().
    aoso_hud_data_init().
    aoso_hud_alert_init().
    aoso_hud_fd_init().
    aoso_twin_init().
    aoso_ui2_hud_dispose().
    aoso_hud_gui_init().
    SET AOSO_HUD_MODE TO "COMPUTER".
    SET AOSO_HUD_READY TO TRUE.
    aoso_hud_collect(TRUE).
    aoso_hud_term_tick(FALSE).
    aoso_hud_event_push("INFO", "HUD online  IPU " + CONFIG:IPU).
    aoso_hud_trace_log("HUD online IPU=" + CONFIG:IPU).
    aoso_hud_alert("boot", "OK", "AOSO HUD ONLINE", 8, 3).
    aoso_hud_peer_note().
}

FUNCTION aoso_hud_register_task {
    PARAMETER interval_s IS 0.25.
    aoso_hud_init().
    aoso_sched_add("hud", interval_s, aoso_hud_tick@).
}

FUNCTION aoso_hud_debug_snap {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL d IS AOSO_HUD_DATA["debug"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL now IS TIME:SECONDS.
    LOCAL why IS "".
    IF sys:HASKEY("why") { SET why TO sys["why"]. }
    LOCAL roll IS "".
    IF sys:HASKEY("rollup") { SET roll TO sys["rollup"]. }
    LOCAL gui_on IS FALSE.
    IF DEFINED AOSO_HUD_GUI_ON { SET gui_on TO AOSO_HUD_GUI_ON. }
    LOCAL fd_txt IS "OFF".
    IF DEFINED AOSO_HUD_FD { SET fd_txt TO aoso_hud_fd_status_txt(). }
    LOCAL hud_dt IS 0.
    FOR tsk IN AOSO_TASKS:COPY {
        IF tsk["name"] = "hud" { SET hud_dt TO tsk["last_dt"]. }
    }
    RETURN LEXICON(
        "ut", now,
        "met", MISSIONTIME,
        "ready", AOSO_HUD_READY,
        "mode", AOSO_HUD_MODE,
        "page", AOSO_HUD_PAGE,
        "ctx", AOSO_HUD_CTX,
        "gui_on", gui_on,
        "doing", AOSO_HUD_DATA["flight"]["doing"],
        "detail", AOSO_HUD_DATA["flight"]["detail"],
        "sys", roll,
        "why", why,
        "cpu", d["cpu"],
        "ipu", d["ipu"],
        "used", d["used"],
        "left", d["left"],
        "spills", d["spills"],
        "fd", fd_txt,
        "twin", d["twin"],
        "twin_n", d["twin_parts"],
        "twin_reason", d["twin_reason"],
        "body", f["body"],
        "status", f["status"],
        "alt", f["alt"],
        "vs", f["vs"],
        "twr", f["twr"],
        "throttle", f["throttle"],
        "stage", f["stage"],
        "mission", m["mission"],
        "tour", m["tour"],
        "goto_st", m["goto"],
        "ascent", m["ascent"],
        "warn_n", AOSO_HUD_WARN_N,
        "err_n", AOSO_HUD_ERR_N,
        "last_evt", AOSO_HUD_LAST_EVT,
        "last_warn", AOSO_HUD_LAST_WARN,
        "last_err", AOSO_HUD_LAST_ERR,
        "hud_dt", hud_dt,
        "hi_age", now - AOSO_HUD_LAST_HI,
        "md_age", now - AOSO_HUD_LAST_MD,
        "lo_age", now - AOSO_HUD_LAST_LO,
        "scale", aoso_hud_scale_pct(),
        "compact", AOSO_HUD_COMPACT
    ).
}

FUNCTION aoso_hud_debug_line {
    PARAMETER snap IS 0.
    IF snap = 0 { SET snap TO aoso_hud_debug_snap(). }
    RETURN "page=" + snap["page"] + " mode=" + snap["mode"] + " ctx=" + snap["ctx"] + " gui=" + snap["gui_on"] + " sys=" + snap["sys"] + " why=[" + snap["why"] + "] fd=" + snap["fd"] + " twin=" + snap["twin"] + " cpu=" + snap["cpu"] + " ipu=" + snap["ipu"] + " left=" + snap["left"] + " doing=" + snap["doing"] + " alt=" + ROUND(snap["alt"], 0) + " vs=" + ROUND(snap["vs"], 1) + " twr=" + ROUND(snap["twr"], 2) + " stg=" + snap["stage"] + " warn=" + snap["warn_n"] + " err=" + snap["err_n"] + " last=" + snap["last_evt"].
}

FUNCTION aoso_hud_debug_write {
    LOCAL snap IS aoso_hud_debug_snap().
    aoso_json_write(AOSO_CONST["HUD_FILE"], snap).
    SET AOSO_HUD_LAST_DUMP TO TIME:SECONDS.
    RETURN snap.
}

FUNCTION aoso_hud_debug_dump {
    LOCAL snap IS aoso_hud_debug_write().
    aoso_log_info("HUD_DUMP", aoso_hud_debug_line(snap)).
    aoso_hud_event_push("INFO", "HUD dump  0:/aoso_hud.json").
    aoso_hud_trace_log("dump written").
}
