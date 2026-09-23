// AOSO/ux/ui2_plots.ks
// Phase plots for any vessel: ascent arc, vertical situation, route,
// projected dV budget, rendezvous. Display only. Consumes hud_data and
// existing planner/budget/project models. Does not fly the ship.
//
// kOS has no polyline canvas. Curves are capped pools of image bugs
// positioned with STYLE:MARGIN, same as the NAV situation display.

GLOBAL AOSO_UI2_ASC_MAIN IS 0.
GLOBAL AOSO_UI2_ASC_INFO IS 0.
GLOBAL AOSO_UI2_ASC_SHIP IS 0.
GLOBAL AOSO_UI2_ASC_ATM IS 0.
GLOBAL AOSO_UI2_ASC_AP IS 0.
GLOBAL AOSO_UI2_ASC_TRAIL IS LIST().
GLOBAL AOSO_UI2_ASC_SKETCH IS LIST().

GLOBAL AOSO_UI2_VS_MAIN IS 0.
GLOBAL AOSO_UI2_VS_INFO IS 0.
GLOBAL AOSO_UI2_VS_SHIP IS 0.
GLOBAL AOSO_UI2_VS_HIGH IS LIST().
GLOBAL AOSO_UI2_VS_NOM IS LIST().
GLOBAL AOSO_UI2_VS_LOW IS LIST().

GLOBAL AOSO_UI2_RTE_MAIN IS 0.
GLOBAL AOSO_UI2_RTE_HEAD IS 0.
GLOBAL AOSO_UI2_RTE_WIN IS 0.
GLOBAL AOSO_UI2_RTE_PILLS IS LIST().
GLOBAL AOSO_UI2_RTE_SIDE IS 0.
GLOBAL AOSO_UI2_WIN_UT IS -1.
GLOBAL AOSO_UI2_WIN_KEY IS "".
GLOBAL AOSO_UI2_WIN_TXT IS "WINDOW  ---".

GLOBAL AOSO_UI2_BDG_MAIN IS 0.
GLOBAL AOSO_UI2_BDG_ROWS IS LIST().
GLOBAL AOSO_UI2_BDG_SIDE IS 0.

GLOBAL AOSO_UI2_RND_MAIN IS 0.
GLOBAL AOSO_UI2_RND_INFO IS 0.
GLOBAL AOSO_UI2_RND_SHIP IS 0.
GLOBAL AOSO_UI2_RND_TGT IS 0.

FUNCTION aoso_ui2_plots_clear {
    SET AOSO_UI2_ASC_MAIN TO 0.
    SET AOSO_UI2_VS_MAIN TO 0.
    SET AOSO_UI2_RTE_MAIN TO 0.
    SET AOSO_UI2_BDG_MAIN TO 0.
    SET AOSO_UI2_RND_MAIN TO 0.
    SET AOSO_UI2_ASC_TRAIL TO LIST().
    SET AOSO_UI2_ASC_SKETCH TO LIST().
    SET AOSO_UI2_VS_HIGH TO LIST().
    SET AOSO_UI2_VS_NOM TO LIST().
    SET AOSO_UI2_VS_LOW TO LIST().
    SET AOSO_UI2_RTE_PILLS TO LIST().
    SET AOSO_UI2_BDG_ROWS TO LIST().
}

FUNCTION aoso_ui2_plot_px {
    PARAMETER x_val.
    PARAMETER y_val.
    PARAMETER x_min.
    PARAMETER x_max.
    PARAMETER y_min.
    PARAMETER y_max.
    LOCAL x_span IS x_max - x_min.
    IF x_span < 0.001 { SET x_span TO 0.001. }
    LOCAL y_span IS y_max - y_min.
    IF y_span < 0.001 { SET y_span TO 0.001. }
    LOCAL nx IS aoso_ui2_clamp((x_val - x_min) / x_span, 0, 1).
    LOCAL ny IS aoso_ui2_clamp((y_val - y_min) / y_span, 0, 1).
    RETURN LIST(40 + nx * 250, 16 + (1 - ny) * 168).
}

FUNCTION aoso_ui2_plot_put {
    PARAMETER mark.
    PARAMETER px.
    PARAMETER py.
    PARAMETER show.
    IF NOT mark:ISTYPE("LABEL") { RETURN. }
    SET mark:VISIBLE TO show.
    IF show {
        SET mark:STYLE:MARGIN:H TO px.
        SET mark:STYLE:MARGIN:V TO py.
    }
}

FUNCTION aoso_ui2_plot_pool {
    PARAMETER parent.
    PARAMETER image_name.
    PARAMETER count.
    PARAMETER width.
    LOCAL pool IS LIST().
    LOCAL i IS 0.
    UNTIL i >= count {
        LOCAL mark IS aoso_ui2_marker(parent, AOSO_UI2_ASSET_ROOT + image_name, width).
        SET mark:VISIBLE TO FALSE.
        pool:ADD(mark).
        SET i TO i + 1.
    }
    RETURN pool.
}

FUNCTION aoso_ui2_plot_frame {
    PARAMETER page.
    PARAMETER image_name.
    LOCAL frame IS page:ADDVLAYOUT().
    SET frame:STYLE:ALIGN TO "center".
    SET frame:STYLE:WIDTH TO 420.
    SET frame:STYLE:HEIGHT TO 210.
    SET frame:STYLE:BG TO AOSO_UI2_ASSET_ROOT + image_name.
    RETURN frame.
}

FUNCTION aoso_ui2_list_has {
    PARAMETER items.
    PARAMETER name.
    IF NOT items:ISTYPE("LIST") { RETURN FALSE. }
    LOCAL i IS 0.
    UNTIL i >= items:LENGTH {
        IF items[i] = name { RETURN TRUE. }
        SET i TO i + 1.
    }
    RETURN FALSE.
}

FUNCTION aoso_ui2_asc_build {
    PARAMETER page.
    aoso_hud_title(page, "ASC TRAJ  /  ALTITUDE vs DOWNRANGE").
    SET AOSO_UI2_ASC_MAIN TO aoso_ui2_plot_frame(page, "pfd_frame.png").
    SET AOSO_UI2_ASC_SKETCH TO aoso_ui2_plot_pool(AOSO_UI2_ASC_MAIN, "pred_bug.png", 8, 8).
    SET AOSO_UI2_ASC_TRAIL TO aoso_ui2_plot_pool(AOSO_UI2_ASC_MAIN, "trail_bug.png", 12, 8).
    SET AOSO_UI2_ASC_SHIP TO aoso_ui2_marker(AOSO_UI2_ASC_MAIN, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_ASC_ATM TO aoso_ui2_overlay_label(AOSO_UI2_ASC_MAIN, "", 250, 20).
    SET AOSO_UI2_ASC_AP TO aoso_ui2_overlay_label(AOSO_UI2_ASC_MAIN, "", 250, 36).
    SET AOSO_UI2_ASC_INFO TO page:ADDLABEL("ASC  waiting for telemetry").
    SET AOSO_UI2_ASC_INFO:STYLE:HSTRETCH TO TRUE.
}

FUNCTION aoso_ui2_asc_update {
    IF NOT AOSO_UI2_ASC_MAIN:ISTYPE("BOX") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL x_max IS tr["xmax_km"].
    LOCAL y_max IS tr["ymax_km"].
    IF x_max < 5 { SET x_max TO 5. }
    IF y_max < 1 { SET y_max TO 1. }

    LOCAL i IS 0.
    UNTIL i >= AOSO_UI2_ASC_SKETCH:LENGTH {
        LOCAL frac IS i / (AOSO_UI2_ASC_SKETCH:LENGTH - 1).
        LOCAL remain IS 1 - frac.
        LOCAL y_km IS tr["ap_km"] * (1 - (remain * remain)).
        IF tr["ap_km"] < 0.2 { SET y_km TO y_max * 0.7 * (1 - (remain * remain)). }
        LOCAL spot IS aoso_ui2_plot_px(frac * x_max, y_km, 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_ASC_SKETCH[i], spot[0], spot[1], TRUE).
        SET i TO i + 1.
    }

    LOCAL n_trail IS AOSO_HUD_ASC_X:LENGTH.
    LOCAL j IS 0.
    UNTIL j >= AOSO_UI2_ASC_TRAIL:LENGTH {
        IF j < n_trail {
            LOCAL flown IS aoso_ui2_plot_px(AOSO_HUD_ASC_X[j], AOSO_HUD_ASC_Y[j], 0, x_max, 0, y_max).
            aoso_ui2_plot_put(AOSO_UI2_ASC_TRAIL[j], flown[0], flown[1], TRUE).
        } ELSE {
            aoso_ui2_plot_put(AOSO_UI2_ASC_TRAIL[j], 0, 0, FALSE).
        }
        SET j TO j + 1.
    }

    LOCAL ship IS aoso_ui2_plot_px(tr["down_km"], tr["alt_km"], 0, x_max, 0, y_max).
    aoso_ui2_plot_put(AOSO_UI2_ASC_SHIP, ship[0], ship[1], TRUE).

    IF tr["atm_km"] > 0.05 {
        LOCAL atm_pt IS aoso_ui2_plot_px(0, tr["atm_km"], 0, x_max, 0, y_max).
        SET AOSO_UI2_ASC_ATM:STYLE:MARGIN:H TO 292.
        SET AOSO_UI2_ASC_ATM:STYLE:MARGIN:V TO atm_pt[1].
        SET AOSO_UI2_ASC_ATM:TEXT TO "ATM".
        SET AOSO_UI2_ASC_ATM:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_ASC_ATM:VISIBLE TO FALSE.
    }
    IF tr["ap_km"] > 0.05 {
        LOCAL ap_pt IS aoso_ui2_plot_px(0, tr["ap_km"], 0, x_max, 0, y_max).
        SET AOSO_UI2_ASC_AP:STYLE:MARGIN:H TO 292.
        SET AOSO_UI2_ASC_AP:STYLE:MARGIN:V TO ap_pt[1].
        SET AOSO_UI2_ASC_AP:TEXT TO "AP".
        SET AOSO_UI2_ASC_AP:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_ASC_AP:VISIBLE TO FALSE.
    }

    LOCAL origin_txt IS "PAD LOCK".
    IF NOT tr["has_origin"] { SET origin_txt TO "NO PAD LOCK". }
    LOCAL cmd_txt IS "PITCH ---".
    IF tr["has_cmd"] { SET cmd_txt TO "PITCH CMD " + ROUND(tr["pitch_cmd"], 0). }
    LOCAL best_txt IS "BEST --".
    IF tr["lf_best"] >= 0 { SET best_txt TO "BEST LF " + ROUND(tr["lf_best"], 0). }
    LOCAL aero_txt IS "VACUUM".
    IF tr["in_atm"] { SET aero_txt TO "Q " + ROUND(f["q"], 1) + " kPa  AoA " + ROUND(f["aoa"], 1). }
    SET AOSO_UI2_ASC_INFO:TEXT TO origin_txt + "  X " + ROUND(tr["down_km"], 1) + " km  Y " +
        ROUND(tr["alt_km"], 1) + " km  " + aero_txt + "  TWR " + ROUND(f["twr"], 2) +
        "  " + cmd_txt + "  STG " + f["stage"] + "  LF " + ROUND(tr["lf"], 0) + "  " + best_txt +
        "  SKETCH=target Ap, not a certified profile".
}

FUNCTION aoso_ui2_asc_ship_fast {
    IF NOT AOSO_UI2_ASC_SHIP:ISTYPE("LABEL") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL x_max IS tr["xmax_km"].
    LOCAL y_max IS tr["ymax_km"].
    IF x_max < 5 { SET x_max TO 5. }
    IF y_max < 1 { SET y_max TO 1. }
    LOCAL ship IS aoso_ui2_plot_px(tr["down_km"], tr["alt_km"], 0, x_max, 0, y_max).
    aoso_ui2_plot_put(AOSO_UI2_ASC_SHIP, ship[0], ship[1], TRUE).
}

FUNCTION aoso_ui2_vs_build {
    PARAMETER page.
    aoso_hud_title(page, "VSIT  /  ALTITUDE vs RANGE TO SITE").
    SET AOSO_UI2_VS_MAIN TO aoso_ui2_plot_frame(page, "descent_frame.png").
    SET AOSO_UI2_VS_HIGH TO aoso_ui2_plot_pool(AOSO_UI2_VS_MAIN, "pred_bug.png", 5, 8).
    SET AOSO_UI2_VS_NOM TO aoso_ui2_plot_pool(AOSO_UI2_VS_MAIN, "pred_bug.png", 5, 8).
    SET AOSO_UI2_VS_LOW TO aoso_ui2_plot_pool(AOSO_UI2_VS_MAIN, "trail_bug.png", 5, 8).
    SET AOSO_UI2_VS_SHIP TO aoso_ui2_marker(AOSO_UI2_VS_MAIN, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_VS_INFO TO page:ADDLABEL("VSIT  waiting for telemetry").
    SET AOSO_UI2_VS_INFO:STYLE:HSTRETCH TO TRUE.
}

FUNCTION aoso_ui2_vs_corridor {
    PARAMETER pool.
    PARAMETER x_max.
    PARAMETER y_max.
    PARAMETER gain.
    PARAMETER show.
    LOCAL i IS 0.
    UNTIL i >= pool:LENGTH {
        IF NOT show {
            aoso_ui2_plot_put(pool[i], 0, 0, FALSE).
        } ELSE {
            LOCAL frac IS i / (pool:LENGTH - 1).
            LOCAL range_km IS x_max * (1 - frac).
            LOCAL y_km IS range_km * 0.15 * gain.
            LOCAL spot IS aoso_ui2_plot_px(frac * x_max, y_km, 0, x_max, 0, y_max).
            aoso_ui2_plot_put(pool[i], spot[0], spot[1], TRUE).
        }
        SET i TO i + 1.
    }
}

FUNCTION aoso_ui2_vs_update {
    IF NOT AOSO_UI2_VS_MAIN:ISTYPE("BOX") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL lnd IS AOSO_HUD_DATA["landing"].
    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL margin IS tr["dv_margin"].
    LOCAL band IS "NOM".
    LOCAL band_state IS "SAFE".
    IF margin < 150 { SET band TO "MARGIN". SET band_state TO "WARN". }
    IF margin < 0 { SET band TO "ABORT". SET band_state TO "FAIL". }

    IF tr["site_ok"] {
        LOCAL x_max IS tr["site_km"] * 1.15.
        IF x_max < 5 { SET x_max TO 5. }
        LOCAL y_max IS MAX(tr["alt_km"], x_max * 0.15 * 1.4) * 1.1.
        IF y_max < 1 { SET y_max TO 1. }
        aoso_ui2_vs_corridor(AOSO_UI2_VS_HIGH, x_max, y_max, 1.4, TRUE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_NOM, x_max, y_max, 1.0, TRUE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_LOW, x_max, y_max, 0.55, TRUE).
        LOCAL x_plot IS x_max - tr["site_km"].
        LOCAL ship IS aoso_ui2_plot_px(x_plot, tr["alt_km"], 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_VS_SHIP, ship[0], ship[1], TRUE).
        SET AOSO_UI2_VS_INFO:TEXT TO "SITE " + ROUND(tr["site_km"], 1) + " km  ALT " +
            ROUND(tr["alt_km"], 1) + " km  HDOT " + ROUND(f["vs"], 0) + " m/s  TWR " +
            ROUND(f["twr"], 2) + "  " + lnd["state"] + "  dV MARGIN " +
            aoso_ui2_color_state(band_state, band + " " + ROUND(margin, 0) + " m/s") +
            "  LAND " + ROUND(res["land_dv"], 0) + "  HAVE " + ROUND(res["mission_dv"], 0) +
            "  GUIDE SKETCH 0.15 km alt per km range".
    } ELSE {
        aoso_ui2_vs_corridor(AOSO_UI2_VS_HIGH, 1, 1, 1, FALSE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_NOM, 1, 1, 1, FALSE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_LOW, 1, 1, 1, FALSE).
        LOCAL eta_pe IS 0.
        IF AOSO_HUD_DATA["orbit"]:HASKEY("pe_eta") { SET eta_pe TO AOSO_HUD_DATA["orbit"]["pe_eta"]. }
        LOCAL x_max IS MAX(eta_pe, 30).
        LOCAL y_max IS MAX(tr["alt_km"], 1) * 1.1.
        LOCAL ship IS aoso_ui2_plot_px(x_max - MIN(eta_pe, x_max), tr["alt_km"], 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_VS_SHIP, ship[0], ship[1], TRUE).
        SET AOSO_UI2_VS_INFO:TEXT TO "PE-REL  no landing site yet  T-Pe " +
            ROUND(eta_pe, 0) + " s  ALT " + ROUND(tr["alt_km"], 1) + " km  HDOT " +
            ROUND(f["vs"], 0) + "  dV MARGIN " +
            aoso_ui2_color_state(band_state, band + " " + ROUND(margin, 0) + " m/s").
    }
}

FUNCTION aoso_ui2_vs_ship_fast {
    IF NOT AOSO_UI2_VS_SHIP:ISTYPE("LABEL") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    IF tr["site_ok"] {
        LOCAL x_max IS tr["site_km"] * 1.15.
        IF x_max < 5 { SET x_max TO 5. }
        LOCAL y_max IS MAX(tr["alt_km"], x_max * 0.21) * 1.1.
        IF y_max < 1 { SET y_max TO 1. }
        LOCAL ship IS aoso_ui2_plot_px(x_max - tr["site_km"], tr["alt_km"], 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_VS_SHIP, ship[0], ship[1], TRUE).
    }
}

FUNCTION aoso_ui2_rte_build {
    PARAMETER page.
    aoso_hud_title(page, "ROUTE  /  WINDOWS").
    SET AOSO_UI2_RTE_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_RTE_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_RTE_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_RTE_HEAD TO AOSO_UI2_RTE_MAIN:ADDLABEL("ROUTE  ---").
    SET AOSO_UI2_RTE_HEAD:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_RTE_WIN TO AOSO_UI2_RTE_MAIN:ADDLABEL("WINDOW  ---").
    SET AOSO_UI2_RTE_WIN:STYLE:HSTRETCH TO TRUE.
    LOCAL row_a IS AOSO_UI2_RTE_MAIN:ADDHLAYOUT().
    LOCAL row_b IS AOSO_UI2_RTE_MAIN:ADDHLAYOUT().
    SET AOSO_UI2_RTE_PILLS TO LIST().
    LOCAL i IS 0.
    UNTIL i >= 12 {
        LOCAL row IS row_a.
        IF i >= 6 { SET row TO row_b. }
        LOCAL pill IS row:ADDLABEL("---").
        SET pill:STYLE:WIDTH TO 64.
        SET pill:VISIBLE TO FALSE.
        AOSO_UI2_RTE_PILLS:ADD(pill).
        SET i TO i + 1.
    }
    SET AOSO_UI2_RTE_SIDE TO page:ADDLABEL("").
    SET AOSO_UI2_RTE_SIDE:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_RTE_SIDE:STYLE:WORDWRAP TO TRUE.
}

FUNCTION aoso_ui2_rte_window {
    PARAMETER here_name.
    PARAMETER dest_name.
    IF dest_name = "" { RETURN "WINDOW  no next body". }
    // kOS allows NOT or DEFINED, not both. Nest the check.
    IF DEFINED aoso_feas_planet_of {
        IF aoso_feas_planet_of(here_name) = aoso_feas_planet_of(dest_name) {
            RETURN "LOCAL HOP  " + here_name + " -> " + dest_name + "  window n/a".
        }
    } ELSE {
        RETURN "WINDOW  planner not loaded".
    }
    LOCAL key IS here_name + ">" + dest_name.
    LOCAL now_ut IS TIME:SECONDS.
    LOCAL cpu_hot IS FALSE.
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 { SET cpu_hot TO TRUE. }
    }
    IF cpu_hot { RETURN AOSO_UI2_WIN_TXT + "  (held, CPU)". }
    IF DEFINED aoso_window_evaluate {
        IF key = AOSO_UI2_WIN_KEY {
            IF AOSO_UI2_WIN_UT >= 0 {
                IF now_ut - AOSO_UI2_WIN_UT < 8 { RETURN AOSO_UI2_WIN_TXT. }
            }
        }
        LOCAL ev IS aoso_window_evaluate(here_name, dest_name).
        SET AOSO_UI2_WIN_KEY TO key.
        SET AOSO_UI2_WIN_UT TO now_ut.
        SET AOSO_UI2_WIN_TXT TO "WINDOW  " + here_name + " -> " + dest_name +
            "  open " + ev["wait_days"] + " d  phase err " + ev["phase_err"] +
            " deg  dV~ " + ROUND(ev["now_dv"], 0) + " m/s".
        RETURN AOSO_UI2_WIN_TXT.
    }
    RETURN "WINDOW  not loaded".
}

FUNCTION aoso_ui2_rte_update {
    IF NOT AOSO_UI2_RTE_MAIN:ISTYPE("BOX") { RETURN. }
    LOCAL targets IS LIST().
    LOCAL skipped IS LIST().
    LOCAL orbit_only IS LIST().
    LOCAL plan_class IS "".
    LOCAL plan_from IS SHIP:BODY:NAME.
    LOCAL have_plan IS FALSE.
    IF DEFINED AOSO_PLAN_LAST {
        IF AOSO_PLAN_LAST:HASKEY("targets") {
            SET targets TO AOSO_PLAN_LAST["targets"].
            SET have_plan TO TRUE.
        }
        IF AOSO_PLAN_LAST:HASKEY("skipped") { SET skipped TO AOSO_PLAN_LAST["skipped"]. }
        IF AOSO_PLAN_LAST:HASKEY("orbit_only") { SET orbit_only TO AOSO_PLAN_LAST["orbit_only"]. }
        IF AOSO_PLAN_LAST:HASKEY("class") { SET plan_class TO AOSO_PLAN_LAST["class"]. }
        IF AOSO_PLAN_LAST:HASKEY("from") { SET plan_from TO AOSO_PLAN_LAST["from"]. }
    }
    LOCAL idx IS 0.
    IF AOSO_HUD_DATA["mission"]:HASKEY("idx") { SET idx TO AOSO_HUD_DATA["mission"]["idx"]. }
    LOCAL next_name IS "".
    IF idx >= 0 {
        IF idx < targets:LENGTH { SET next_name TO targets[idx]. }
    }

    LOCAL i IS 0.
    UNTIL i >= AOSO_UI2_RTE_PILLS:LENGTH {
        LOCAL pill IS AOSO_UI2_RTE_PILLS[i].
        IF i < targets:LENGTH {
            LOCAL body_name IS targets[i].
            LOCAL tag IS "CAPABLE".
            LOCAL col IS "#50FF96".
            IF aoso_ui2_list_has(orbit_only, body_name) {
                SET tag TO "ORBIT".
                SET col TO "#7EC8FF".
            }
            IF aoso_ui2_list_has(skipped, body_name) {
                SET tag TO "SKIP".
                SET col TO "#8A8A8A".
            }
            IF i < idx { SET tag TO "DONE". }
            IF i = idx { SET tag TO "NOW". SET col TO "#FFCD46". }
            SET pill:TEXT TO "<color=" + col + ">" + aoso_ui2_short_body(body_name) + "</color>" + CHAR(10) + tag.
            SET pill:VISIBLE TO TRUE.
        } ELSE {
            SET pill:VISIBLE TO FALSE.
        }
        SET i TO i + 1.
    }

    IF have_plan {
        SET AOSO_UI2_RTE_HEAD:TEXT TO "HOP  " + plan_from + " -> " + next_name +
            "   " + (idx + 1) + "/" + targets:LENGTH + "   CLASS " + plan_class.
    } ELSE {
        SET AOSO_UI2_RTE_HEAD:TEXT TO "NO PLAN  route not built yet".
    }
    SET AOSO_UI2_RTE_WIN:TEXT TO aoso_ui2_rte_window(SHIP:BODY:NAME, next_name).

    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL end_dv IS -1.
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("end_dv") { SET end_dv TO AOSO_PROJECT_LAST["end_dv"]. }
    }
    LOCAL end_txt IS "LEDGER  waiting for project".
    IF end_dv >= 0 { SET end_txt TO "LEDGER END " + ROUND(end_dv, 0) + " m/s". }
    SET AOSO_UI2_RTE_SIDE:TEXT TO end_txt + "   MISSION " + ROUND(res["mission_dv"], 0) +
        "   RETURN " + ROUND(res["return_dv"], 0) + "   ABORT " + ROUND(res["abort_dv"], 0) +
        "   " + AOSO_HUD_DATA["mission"]["feas"].
}

FUNCTION aoso_ui2_bdg_build {
    PARAMETER page.
    aoso_hud_title(page, "BUDGET  /  PROJECTED STATE").
    SET AOSO_UI2_BDG_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_BDG_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_BDG_ROWS TO LIST().
    LOCAL i IS 0.
    UNTIL i >= 8 {
        LOCAL row IS AOSO_UI2_BDG_MAIN:ADDLABEL("").
        SET row:STYLE:HSTRETCH TO TRUE.
        AOSO_UI2_BDG_ROWS:ADD(row).
        SET i TO i + 1.
    }
    SET AOSO_UI2_BDG_SIDE TO page:ADDLABEL("").
    SET AOSO_UI2_BDG_SIDE:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_BDG_SIDE:STYLE:WORDWRAP TO TRUE.
}

FUNCTION aoso_ui2_bdg_line {
    PARAMETER label_txt.
    PARAMETER dv.
    PARAMETER state_name.
    LOCAL width IS 18.
    LOCAL span IS 4000.
    IF dv > span { SET span TO dv. }
    LOCAL frac IS 0.
    IF span > 0 { SET frac TO dv / span. }
    IF frac < 0 { SET frac TO 0. }
    RETURN aoso_ui2_color_state(state_name, label_txt) + "  " + aoso_ui2_bar(frac, width) + "  " + ROUND(dv, 0).
}

FUNCTION aoso_ui2_bdg_update {
    IF NOT AOSO_UI2_BDG_MAIN:ISTYPE("BOX") { RETURN. }
    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL now_dv IS res["mission_dv"].
    LOCAL targets IS LIST().
    LOCAL legs IS LEXICON().
    LOCAL have_legs IS FALSE.
    LOCAL stale IS TRUE.
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("legs") {
            SET legs TO AOSO_PROJECT_LAST["legs"].
            SET have_legs TO TRUE.
        }
        IF AOSO_PROJECT_LAST:HASKEY("order") { SET targets TO AOSO_PROJECT_LAST["order"]. }
        IF AOSO_PROJECT_LAST:HASKEY("at") {
            IF TIME:SECONDS - AOSO_PROJECT_LAST["at"] < 600 { SET stale TO FALSE. }
        }
    }
    LOCAL lines IS LIST().
    lines:ADD(aoso_ui2_bdg_line("NOW", now_dv, "SAFE")).
    LOCAL i IS 0.
    UNTIL i >= targets:LENGTH {
        IF lines:LENGTH >= 8 { BREAK. }
        LOCAL body_name IS targets[i].
        IF legs:HASKEY(body_name) {
            LOCAL leg IS legs[body_name].
            LOCAL state_name IS "SAFE".
            IF NOT leg["ok"] { SET state_name TO "FAIL". }
            ELSE {
                IF leg["margin"] < 200 { SET state_name TO "WARN". }
            }
            LOCAL did_refuel IS FALSE.
            IF leg:HASKEY("refueled") { SET did_refuel TO leg["refueled"]. }
            LOCAL bump IS "".
            IF did_refuel { SET bump TO " +ISRU". }
            lines:ADD(aoso_ui2_bdg_line(aoso_ui2_short_body(body_name) + bump, leg["leftover_out"], state_name)).
        }
        SET i TO i + 1.
    }
    LOCAL row_i IS 0.
    UNTIL row_i >= AOSO_UI2_BDG_ROWS:LENGTH {
        IF row_i < lines:LENGTH {
            SET AOSO_UI2_BDG_ROWS[row_i]:TEXT TO lines[row_i].
        } ELSE {
            SET AOSO_UI2_BDG_ROWS[row_i]:TEXT TO "".
        }
        SET row_i TO row_i + 1.
    }
    LOCAL stamp IS "SOURCE budget.ks".
    IF have_legs {
        SET stamp TO "SOURCE project.ks leftover ledger".
        IF stale { SET stamp TO "STALE  " + stamp. }
    } ELSE {
        SET stamp TO "STALE  planner has not projected the route".
    }
    SET AOSO_UI2_BDG_SIDE:TEXT TO stamp + CHAR(10) +
        "MISSION " + ROUND(res["mission_dv"], 0) + "   UNUSABLE " + ROUND(res["unusable_dv"], 0) +
        "   RESERVE " + ROUND(res["reserve_dv"], 0) + "   LAND " + ROUND(res["land_dv"], 0) +
        "   RETURN " + ROUND(res["return_dv"], 0) + "   ABORT " + ROUND(res["abort_dv"], 0) +
        "   TOTAL " + ROUND(res["total_dv"], 0).
}

FUNCTION aoso_ui2_rnd_build {
    PARAMETER page.
    aoso_hud_title(page, "RNDZ  /  RELATIVE NAV").
    SET AOSO_UI2_RND_MAIN TO aoso_ui2_plot_frame(page, "nav_frame.png").
    SET AOSO_UI2_RND_SHIP TO aoso_ui2_marker(AOSO_UI2_RND_MAIN, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_RND_TGT TO aoso_ui2_marker(AOSO_UI2_RND_MAIN, AOSO_UI2_ASSET_ROOT + "target_bug.png", 16).
    SET AOSO_UI2_RND_SHIP:STYLE:MARGIN:H TO 70.
    SET AOSO_UI2_RND_SHIP:STYLE:MARGIN:V TO 96.
    SET AOSO_UI2_RND_INFO TO page:ADDLABEL("RNDZ  NO TGT") .
    SET AOSO_UI2_RND_INFO:STYLE:HSTRETCH TO TRUE.
}

FUNCTION aoso_ui2_rnd_update {
    IF NOT AOSO_UI2_RND_MAIN:ISTYPE("BOX") { RETURN. }
    LOCAL tgt IS AOSO_HUD_DATA["target"].
    IF NOT tgt["has"] {
        SET AOSO_UI2_RND_TGT:VISIBLE TO FALSE.
        SET AOSO_UI2_RND_INFO:TEXT TO "NO TGT  select a vessel or docking step".
        RETURN.
    }
    LOCAL dist_m IS tgt["dist"].
    LOCAL scale_m IS MAX(dist_m, 100).
    LOCAL nx IS aoso_ui2_clamp(dist_m / scale_m, 0, 1).
    SET AOSO_UI2_RND_TGT:VISIBLE TO TRUE.
    SET AOSO_UI2_RND_TGT:STYLE:MARGIN:H TO 70 + nx * 220.
    SET AOSO_UI2_RND_TGT:STYLE:MARGIN:V TO 96.
    LOCAL closing IS 0.
    IF dist_m > 1 { SET closing TO 1 - aoso_ui2_clamp(dist_m / 10000, 0, 1). }
    SET AOSO_UI2_RND_INFO:TEXT TO tgt["name"] + "  RANGE " + ROUND(dist_m, 0) + " m  REL " +
        ROUND(tgt["rel"], 2) + " m/s  BRG " + ROUND(tgt["bearing"], 0) + "  CLOSE " +
        aoso_ui2_bar(closing, 12).
}
