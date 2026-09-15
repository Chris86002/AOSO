// AOSO/ux/hud.ks
// Operator panel. kOS GUI window (not PRINT AT) so the terminal log can
// scroll while the panel shows what the ship is actually doing: warping,
// searching an intercept, burning, waiting on a patch. Other modules set
// AOSO_UI during blocking PLAN work so a 40 s matrix does not look idle.

GLOBAL AOSO_UI IS LEXICON("doing", "", "detail", "").
GLOBAL AOSO_PANEL_READY IS FALSE.
GLOBAL AOSO_PANEL IS 0.
GLOBAL AOSO_PANEL_LBL IS LEXICON().

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
    aoso_hud_draw().
}

FUNCTION aoso_hud_km {
    PARAMETER meters.
    IF meters < 0 { RETURN ROUND(meters, 0) + " m". }
    IF meters >= 1000000 { RETURN ROUND(meters / 1000, 0) + " km". }
    IF meters >= 10000 { RETURN ROUND(meters / 1000, 1) + " km". }
    RETURN ROUND(meters, 0) + " m".
}

FUNCTION aoso_hud_eta {
    PARAMETER secs.
    IF secs < 0 { RETURN "now". }
    IF secs < 90 { RETURN ROUND(secs, 0) + "s". }
    IF secs < 3600 { RETURN ROUND(secs / 60, 1) + " min". }
    IF secs < 21600 { RETURN ROUND(secs / 3600, 1) + " h". }
    RETURN ROUND(secs / 21600, 1) + " d".
}

FUNCTION aoso_panel_add_line {
    PARAMETER key_name.
    PARAMETER start_text.
    LOCAL w IS AOSO_PANEL:ADDLABEL(start_text).
    SET w:STYLE:FONTSIZE TO 12.
    SET w:STYLE:MARGIN:TOP TO 1.
    SET w:STYLE:MARGIN:BOTTOM TO 1.
    SET AOSO_PANEL_LBL[key_name] TO w.
    RETURN w.
}

FUNCTION aoso_panel_ensure {
    IF AOSO_PANEL_READY { RETURN. }

    LOCAL panel IS GUI(400).
    SET panel:X TO 20.
    SET panel:Y TO 70.

    LOCAL title IS panel:ADDLABEL("<b><size=16><color=#7EC8FF>AOSO</color></size></b>").
    SET title:STYLE:ALIGN TO "CENTER".
    SET AOSO_PANEL_LBL["title"] TO title.

    LOCAL ship_l IS panel:ADDLABEL(SHIP:NAME).
    SET ship_l:STYLE:ALIGN TO "CENTER".
    SET ship_l:STYLE:FONTSIZE TO 12.
    SET AOSO_PANEL_LBL["ship"] TO ship_l.

    panel:ADDSPACING(6).
    LOCAL doing IS panel:ADDLABEL("<b>Starting…</b>").
    SET doing:STYLE:FONTSIZE TO 13.
    SET doing:STYLE:ALIGN TO "CENTER".
    SET AOSO_PANEL_LBL["doing"] TO doing.

    LOCAL detail IS panel:ADDLABEL("").
    SET detail:STYLE:FONTSIZE TO 11.
    SET detail:STYLE:ALIGN TO "CENTER".
    SET AOSO_PANEL_LBL["detail"] TO detail.

    panel:ADDSPACING(4).
    aoso_panel_add_line("target", "Target  —").
    aoso_panel_add_line("orbit", "Orbit   —").
    aoso_panel_add_line("node", "Node    —").
    aoso_panel_add_line("enc", "Encounter  —").
    aoso_panel_add_line("fuel", "Fuel    —").
    aoso_panel_add_line("tour", "Tour    —").
    aoso_panel_add_line("skip", "Skip    —").

    SET AOSO_PANEL TO panel.
    SET AOSO_PANEL_READY TO TRUE.
    panel:SHOW().
}

FUNCTION aoso_hud_set_line {
    PARAMETER key_name.
    PARAMETER text.
    IF AOSO_PANEL_LBL:HASKEY(key_name) {
        SET AOSO_PANEL_LBL[key_name]:TEXT TO text.
    }
}

FUNCTION aoso_hud_tour_target {
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("targets") {
                LOCAL idx IS AOSO_TOUR["data"]["index"].
                LOCAL tgts IS AOSO_TOUR["data"]["targets"].
                IF idx >= 0 {
                    IF idx < tgts:LENGTH { RETURN tgts[idx]. }
                }
            }
        }
    }
    RETURN "".
}

FUNCTION aoso_hud_goto_hop {
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO:HASKEY("data") {
            IF AOSO_GOTO["data"]:HASKEY("hop") { RETURN AOSO_GOTO["data"]["hop"]. }
        }
    }
    RETURN "".
}

FUNCTION aoso_hud_live_doing {
    IF AOSO_MANEUVER_BURNING {
        LOCAL left IS AOSO_MANEUVER_LAST_REMAINING.
        RETURN LEXICON("doing", "<b><color=#FFB347>BURNING</color></b>  " + ROUND(left, 1) + " m/s left", "detail", "Following the node. Will cut if a patch appears.").
    }
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        LOCAL eta_s IS nd:ETA.
        LOCAL dv_m IS nd:DELTAV:MAG.
        LOCAL wtxt IS "waiting".
        IF WARP > 0 {
            IF WARPMODE = "RAILS" { SET wtxt TO "rails warp". }
            IF WARPMODE = "PHYSICS" { SET wtxt TO "physics warp". }
        }
        RETURN LEXICON("doing", "<b>Node</b>  T-" + aoso_hud_eta(eta_s) + "  " + ROUND(dv_m, 1) + " m/s", "detail", wtxt + "  (physics the last 10 s so SAS can point)").
    }
    IF AOSO_UI["doing"] <> "" {
        RETURN LEXICON("doing", "<b>" + AOSO_UI["doing"] + "</b>", "detail", AOSO_UI["detail"]).
    }
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] = "COAST" {
            IF SHIP:ORBIT:HASNEXTPATCH {
                RETURN LEXICON("doing", "<b>Coasting to " + SHIP:ORBIT:NEXTPATCH:BODY:NAME + "</b>", "detail", "SOI in " + aoso_hud_eta(SHIP:ORBIT:NEXTPATCHETA)).
            }
            RETURN LEXICON("doing", "<b>Coasting</b> — no patch yet", "detail", "Will retry the intercept rather than recircularize.").
        }
        IF AOSO_GOTO["current"] = "WAIT" {
            RETURN LEXICON("doing", "<b>Waiting on transfer window</b>", "detail", AOSO_UI["detail"]).
        }
        IF AOSO_GOTO["current"] = "PLAN" {
            RETURN LEXICON("doing", "<b>Planning hop</b>", "detail", AOSO_UI["detail"]).
        }
        IF AOSO_GOTO["current"] = "CAPTURE" {
            RETURN LEXICON("doing", "<b>Capture at periapsis</b>", "detail", "Oberth: retrograde at PE, not a high-altitude circularize.").
        }
    }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" {
                RETURN LEXICON("doing", "<b>Ascent</b>  " + AOSO_ASCENT["current"], "detail", aoso_hud_ascent_opt_status()).
            }
        }
    }
    RETURN LEXICON("doing", "<b>" + aoso_hud_mission_status() + "</b>", "detail", "").
}

FUNCTION aoso_hud_encounter_text {
    IF NOT SHIP:ORBIT:HASNEXTPATCH { RETURN "Encounter  none". }
    LOCAL cur IS SHIP:ORBIT.
    LOCAL n IS 0.
    LOCAL names IS "".
    UNTIL n >= 4 {
        IF NOT cur:HASNEXTPATCH {
            SET n TO 4.
        } ELSE {
            SET cur TO cur:NEXTPATCH.
            LOCAL bit IS cur:BODY:NAME + " PE " + aoso_hud_km(cur:PERIAPSIS).
            IF names = "" { SET names TO bit. }
            ELSE { SET names TO names + " → " + bit. }
            SET n TO n + 1.
        }
    }
    LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
    RETURN "Encounter  " + names + "  in " + aoso_hud_eta(eta_p).
}

FUNCTION aoso_hud_draw {
    aoso_panel_ensure().
    IF NOT AOSO_PANEL_READY { RETURN. }

    LOCAL class_txt IS aoso_classify_name().
    LOCAL mode IS "AUTO".
    IF AOSO_CONFIG["SAFE_MODE"] { SET mode TO "SAFE". }
    aoso_hud_set_line("title", "<b><size=16><color=#7EC8FF>AOSO</color></size></b>  " + mode).
    aoso_hud_set_line("ship", SHIP:NAME + "   " + class_txt + "   " + SHIP:STATUS).

    LOCAL live IS aoso_hud_live_doing().
    aoso_hud_set_line("doing", live["doing"]).
    aoso_hud_set_line("detail", live["detail"]).

    LOCAL tgt IS aoso_hud_tour_target().
    LOCAL hop IS aoso_hud_goto_hop().
    LOCAL tgt_line IS "Target  " + SHIP:BODY:NAME.
    IF tgt <> "" { SET tgt_line TO "Target  " + tgt. }
    IF hop <> "" {
        IF hop <> tgt { SET tgt_line TO tgt_line + "   hop " + SHIP:BODY:NAME + " → " + hop. }
    }
    aoso_hud_set_line("target", tgt_line).

    LOCAL ap_txt IS aoso_hud_km(aoso_orbit_apoapsis_alt()).
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { SET ap_txt TO "hyperbolic". }
    aoso_hud_set_line("orbit", "Orbit   " + ap_txt + " × " + aoso_hud_km(PERIAPSIS) + "   e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + "   " + SHIP:BODY:NAME).

    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        aoso_hud_set_line("node", "Node    T-" + aoso_hud_eta(nd:ETA) + "   " + ROUND(nd:DELTAV:MAG, 1) + " m/s   (pro " + ROUND(nd:PROGRADE, 0) + " nml " + ROUND(nd:NORMAL, 0) + " rad " + ROUND(nd:RADIALOUT, 0) + ")").
    } ELSE {
        aoso_hud_set_line("node", "Node    none").
    }

    aoso_hud_set_line("enc", aoso_hud_encounter_text()).

    LOCAL fuel_pct IS aoso_stage_propellant_pct().
    LOCAL ec_pct IS aoso_power_ec_pct().
    aoso_hud_set_line("fuel", "Fuel    LF " + ROUND(aoso_resource_pct("LiquidFuel"), 0) + "%   stage " + ROUND(fuel_pct, 0) + "%   EC " + ROUND(ec_pct, 0) + "%   " + aoso_hud_dv_status()).

    LOCAL tour_line IS "Tour    " + aoso_hud_mission_status().
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("targets") {
            SET tour_line TO "Tour    " + aoso_route_join(AOSO_PLAN_LAST["targets"]).
        }
    }
    aoso_hud_set_line("tour", tour_line).

    LOCAL skip_line IS "Skip    none".
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("skipped") {
            IF AOSO_PLAN_LAST["skipped"]:LENGTH > 0 {
                SET skip_line TO "Skip    " + aoso_route_join(AOSO_PLAN_LAST["skipped"]).
            }
        }
    }
    aoso_hud_set_line("skip", skip_line).
}

FUNCTION aoso_hud_mission_status {
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "" {
            LOCAL step_name IS aoso_mission_current_step_name().
            RETURN AOSO_MISSION["current"] + " / " + step_name.
        }
    }
    RETURN "idle".
}

FUNCTION aoso_hud_dv_status {
    LOCAL mission_dv IS 0.
    LOCAL total_dv IS 0.
    IF DEFINED AOSO_BUDGET {
        IF AOSO_BUDGET:HASKEY("mission_dv") { SET mission_dv TO AOSO_BUDGET["mission_dv"]. }
        IF AOSO_BUDGET:HASKEY("total_dv") { SET total_dv TO AOSO_BUDGET["total_dv"]. }
    }
    RETURN "dV " + ROUND(mission_dv, 0) + "/" + ROUND(total_dv, 0).
}

FUNCTION aoso_hud_ascent_opt_status {
    IF DEFINED AOSO_ASCENT_OPT {
        RETURN aoso_ascent_opt_hud().
    }
    RETURN "".
}

FUNCTION aoso_hud_register_task {
    PARAMETER interval_s IS 0.4.
    aoso_panel_ensure().
    aoso_hud_draw().
    aoso_sched_add("hud", interval_s, aoso_hud_draw@).
}
