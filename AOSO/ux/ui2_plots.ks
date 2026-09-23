// AOSO/ux/ui2_plots.ks
// CRT phase plots. The plate PNG is the instrument. Live text and bugs are
// pinned onto it. Display only. Does not fly the ship.
//
// Plot rectangle baked into the plates and repeated here:
// origin (36, 52), size 460 x 280, on a 740 x 400 page.
// Side-box values: x=524, y=74 + 52*row. Same pixels as the plate art.

GLOBAL AOSO_UI2_ASC_MAIN IS 0.
GLOBAL AOSO_UI2_ASC_INFO IS 0.
GLOBAL AOSO_CRT_ASC_Q IS 0.
GLOBAL AOSO_CRT_ASC_AOA IS 0.
GLOBAL AOSO_CRT_ASC_TWR IS 0.
GLOBAL AOSO_CRT_ASC_PITCH IS 0.
GLOBAL AOSO_CRT_ASC_STG IS 0.
GLOBAL AOSO_CRT_ASC_LF IS 0.
GLOBAL AOSO_UI2_ASC_SHIP IS 0.
GLOBAL AOSO_UI2_ASC_ATM IS 0.
GLOBAL AOSO_UI2_ASC_AP IS 0.
GLOBAL AOSO_UI2_ASC_TRAIL IS LIST().
GLOBAL AOSO_UI2_ASC_SKETCH IS LIST().
GLOBAL AOSO_UI2_ASC_ATMLINE IS LIST().

GLOBAL AOSO_UI2_VS_MAIN IS 0.
GLOBAL AOSO_UI2_VS_INFO IS 0.
GLOBAL AOSO_CRT_VS_HDOT IS 0.
GLOBAL AOSO_CRT_VS_TWR IS 0.
GLOBAL AOSO_CRT_VS_MAR IS 0.
GLOBAL AOSO_CRT_VS_SITE IS 0.
GLOBAL AOSO_CRT_VS_RAD IS 0.
GLOBAL AOSO_CRT_VS_DV IS 0.
GLOBAL AOSO_UI2_VS_SHIP IS 0.
GLOBAL AOSO_UI2_VS_HIGH IS LIST().
GLOBAL AOSO_UI2_VS_NOM IS LIST().
GLOBAL AOSO_UI2_VS_LOW IS LIST().

GLOBAL AOSO_UI2_RTE_MAIN IS 0.
GLOBAL AOSO_UI2_RTE_HEAD IS 0.
GLOBAL AOSO_UI2_RTE_WIN IS 0.
GLOBAL AOSO_UI2_RTE_PILLS IS LIST().
GLOBAL AOSO_CRT_RTE_HOP IS 0.
GLOBAL AOSO_CRT_RTE_WIN IS 0.
GLOBAL AOSO_CRT_RTE_CLASS IS 0.
GLOBAL AOSO_CRT_RTE_END IS 0.
GLOBAL AOSO_CRT_RTE_RET IS 0.
GLOBAL AOSO_CRT_RTE_ABT IS 0.
GLOBAL AOSO_UI2_WIN_UT IS -1.
GLOBAL AOSO_UI2_WIN_KEY IS "".
GLOBAL AOSO_UI2_WIN_TXT IS "WINDOW  ---".
GLOBAL AOSO_UI2_WIN_SHORT IS "---".

GLOBAL AOSO_UI2_BDG_MAIN IS 0.
GLOBAL AOSO_UI2_BDG_ROWS IS LIST().
GLOBAL AOSO_UI2_BDG_INFO IS 0.
GLOBAL AOSO_CRT_BDG_NOW IS 0.
GLOBAL AOSO_CRT_BDG_UNU IS 0.
GLOBAL AOSO_CRT_BDG_RES IS 0.
GLOBAL AOSO_CRT_BDG_LAND IS 0.
GLOBAL AOSO_CRT_BDG_RET IS 0.
GLOBAL AOSO_CRT_BDG_ABT IS 0.

GLOBAL AOSO_UI2_RND_MAIN IS 0.
GLOBAL AOSO_UI2_RND_INFO IS 0.
GLOBAL AOSO_UI2_RND_SHIP IS 0.
GLOBAL AOSO_UI2_RND_TGT IS 0.
GLOBAL AOSO_CRT_RND_NAME IS 0.
GLOBAL AOSO_CRT_RND_DIST IS 0.
GLOBAL AOSO_CRT_RND_RATE IS 0.
GLOBAL AOSO_CRT_RND_BRG IS 0.
GLOBAL AOSO_CRT_RND_PORT IS 0.
GLOBAL AOSO_CRT_RND_REL IS 0.

FUNCTION aoso_ui2_plots_clear {
    SET AOSO_UI2_ASC_MAIN TO 0.
    SET AOSO_UI2_VS_MAIN TO 0.
    SET AOSO_UI2_RTE_MAIN TO 0.
    SET AOSO_UI2_BDG_MAIN TO 0.
    SET AOSO_UI2_RND_MAIN TO 0.
    SET AOSO_UI2_ASC_TRAIL TO LIST().
    SET AOSO_UI2_ASC_SKETCH TO LIST().
    SET AOSO_UI2_ASC_ATMLINE TO LIST().
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
    RETURN LIST(36 + nx * 460, 52 + (1 - ny) * 280).
}

FUNCTION aoso_ui2_plot_put {
    PARAMETER mark.
    PARAMETER px.
    PARAMETER py.
    PARAMETER show.
    PARAMETER slot IS 0.
    IF NOT mark:ISTYPE("LABEL") { RETURN. }
    SET mark:VISIBLE TO show.
    IF show {
        LOCAL sz IS mark:STYLE:WIDTH.
        IF sz < 4 { SET sz TO 12. }
        aoso_crt_move(mark, px - sz * 0.5, py - sz * 0.5, sz, sz).
    }
}

FUNCTION aoso_crt_page {
    PARAMETER page.
    PARAMETER image_name.
    aoso_crt_zero(page).
    SET page:STYLE:HSTRETCH TO FALSE.
    SET page:STYLE:VSTRETCH TO FALSE.
    SET page:STYLE:WIDTH TO 740.
    SET page:STYLE:HEIGHT TO 400.
    SET page:STYLE:BG TO AOSO_UI2_ASSET_ROOT + image_name.
}

FUNCTION aoso_crt_side {
    PARAMETER parent.
    PARAMETER index.
    RETURN aoso_crt_label(parent, 524, 74 + index * 52, 188).
}

FUNCTION aoso_ui2_plot_pool {
    PARAMETER parent.
    PARAMETER image_name.
    PARAMETER count.
    PARAMETER width.
    LOCAL pool IS LIST().
    LOCAL i IS 0.
    UNTIL i >= count {
        pool:ADD(aoso_crt_bug(parent, AOSO_UI2_ASSET_ROOT + image_name, width)).
        SET i TO i + 1.
    }
    RETURN pool.
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
    aoso_crt_page(page, "crt_asc.png").
    SET AOSO_UI2_ASC_MAIN TO page.
    SET AOSO_UI2_ASC_SHIP TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_ASC_SKETCH TO aoso_ui2_plot_pool(page, "pred_bug.png", 8, 8).
    SET AOSO_UI2_ASC_TRAIL TO aoso_ui2_plot_pool(page, "trail_bug.png", 12, 10).
    SET AOSO_UI2_ASC_ATMLINE TO aoso_ui2_plot_pool(page, "pred_bug.png", 8, 6).
    SET AOSO_UI2_ASC_ATM TO aoso_crt_label(page, 44, 80, 70).
    SET AOSO_UI2_ASC_AP TO aoso_crt_label(page, 44, 96, 70).
    SET AOSO_CRT_ASC_Q TO aoso_crt_side(page, 0).
    SET AOSO_CRT_ASC_AOA TO aoso_crt_side(page, 1).
    SET AOSO_CRT_ASC_TWR TO aoso_crt_side(page, 2).
    SET AOSO_CRT_ASC_PITCH TO aoso_crt_side(page, 3).
    SET AOSO_CRT_ASC_STG TO aoso_crt_side(page, 4).
    SET AOSO_CRT_ASC_LF TO aoso_crt_side(page, 5).
    SET AOSO_UI2_ASC_INFO TO aoso_crt_label(page, 40, 358, 460).
}

FUNCTION aoso_ui2_asc_update {
    IF NOT AOSO_UI2_ASC_MAIN:ISTYPE("WIDGET") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL x_max IS aoso_lex_num(tr, "xmax_km", 80).
    LOCAL y_max IS aoso_lex_num(tr, "ymax_km", 80).
    IF x_max < 5 { SET x_max TO 5. }
    IF y_max < 1 { SET y_max TO 1. }
    LOCAL ap_km IS aoso_lex_num(tr, "ap_km", 0).
    LOCAL atm_km IS aoso_lex_num(tr, "atm_km", 0).
    LOCAL down_km IS aoso_lex_num(tr, "down_km", 0).
    LOCAL alt_km IS aoso_lex_num(tr, "alt_km", 0).

    LOCAL i IS 0.
    UNTIL i >= AOSO_UI2_ASC_SKETCH:LENGTH {
        LOCAL frac IS i / (AOSO_UI2_ASC_SKETCH:LENGTH - 1).
        LOCAL remain IS 1 - frac.
        LOCAL y_km IS ap_km * (1 - (remain * remain)).
        IF ap_km < 0.2 { SET y_km TO y_max * 0.7 * (1 - (remain * remain)). }
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

    LOCAL bug_pt IS aoso_ui2_plot_px(down_km, alt_km, 0, x_max, 0, y_max).
    aoso_ui2_plot_put(AOSO_UI2_ASC_SHIP, bug_pt[0], bug_pt[1], TRUE).

    LOCAL k IS 0.
    UNTIL k >= AOSO_UI2_ASC_ATMLINE:LENGTH {
        IF atm_km > 0.05 {
            LOCAL atm_x IS aoso_ui2_plot_px(x_max * k / (AOSO_UI2_ASC_ATMLINE:LENGTH - 1), atm_km, 0, x_max, 0, y_max).
            aoso_ui2_plot_put(AOSO_UI2_ASC_ATMLINE[k], atm_x[0], atm_x[1], TRUE).
        } ELSE {
            aoso_ui2_plot_put(AOSO_UI2_ASC_ATMLINE[k], 0, 0, FALSE).
        }
        SET k TO k + 1.
    }

    IF atm_km > 0.05 {
        LOCAL atm_pt IS aoso_ui2_plot_px(0, atm_km, 0, x_max, 0, y_max).
        aoso_crt_move(AOSO_UI2_ASC_ATM, 44, atm_pt[1] - 8, 70, 22).
        aoso_ui2_set_text(AOSO_UI2_ASC_ATM, "asc_atm", "ATM").
        SET AOSO_UI2_ASC_ATM:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_ASC_ATM:VISIBLE TO FALSE.
    }
    IF ap_km > 0.05 {
        LOCAL ap_pt IS aoso_ui2_plot_px(0, ap_km, 0, x_max, 0, y_max).
        aoso_crt_move(AOSO_UI2_ASC_AP, 90, ap_pt[1] - 8, 70, 22).
        aoso_ui2_set_text(AOSO_UI2_ASC_AP, "asc_ap", "AP").
        SET AOSO_UI2_ASC_AP:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_ASC_AP:VISIBLE TO FALSE.
    }

    LOCAL in_air IS aoso_lex_bool(tr, "in_atm").
    LOCAL qtxt IS "".
    LOCAL aoa_txt IS "".
    IF in_air {
        SET qtxt TO ROUND(aoso_lex_num(f, "q", 0), 2) + "".
        SET aoa_txt TO ROUND(aoso_lex_num(f, "aoa", 0), 1) + "".
    }
    LOCAL pitch_txt IS ROUND(aoso_lex_num(f, "pitch", 0), 0) + "".
    IF aoso_lex_bool(tr, "has_cmd") {
        SET pitch_txt TO pitch_txt + "/" + ROUND(aoso_lex_num(tr, "pitch_cmd", 0), 0).
    }
    LOCAL best_txt IS ROUND(aoso_lex_num(tr, "lf", 0), 0) + "".
    LOCAL best_lf IS aoso_lex_num(tr, "lf_best", -1).
    IF best_lf >= 0 { SET best_txt TO best_txt + "/" + ROUND(best_lf, 0). }
    aoso_ui2_set_text(AOSO_CRT_ASC_Q, "asc_q", qtxt).
    aoso_ui2_set_text(AOSO_CRT_ASC_AOA, "asc_aoa", aoa_txt).
    aoso_ui2_set_text(AOSO_CRT_ASC_TWR, "asc_twr", ROUND(aoso_lex_num(f, "twr", 0), 2) + "").
    aoso_ui2_set_text(AOSO_CRT_ASC_PITCH, "asc_pitch", pitch_txt).
    aoso_ui2_set_text(AOSO_CRT_ASC_STG, "asc_stg", aoso_lex_num(f, "stage", 0) + "").
    aoso_ui2_set_text(AOSO_CRT_ASC_LF, "asc_lf", best_txt).
    LOCAL origin_txt IS "PAD LOCK".
    LOCAL has_pad IS aoso_lex_bool(tr, "has_origin").
    IF NOT has_pad { SET origin_txt TO "NO LOCK". }
    aoso_ui2_set_text(AOSO_UI2_ASC_INFO, "asc_info", origin_txt + "  " + ROUND(down_km, 1) + " km  " + ROUND(alt_km, 1) + " km").
}

FUNCTION aoso_ui2_asc_ship_fast {
    IF NOT AOSO_UI2_ASC_SHIP:ISTYPE("LABEL") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL x_max IS aoso_lex_num(tr, "xmax_km", 80).
    LOCAL y_max IS aoso_lex_num(tr, "ymax_km", 80).
    IF x_max < 5 { SET x_max TO 5. }
    IF y_max < 1 { SET y_max TO 1. }
    LOCAL bug_pt IS aoso_ui2_plot_px(aoso_lex_num(tr, "down_km", 0), aoso_lex_num(tr, "alt_km", 0), 0, x_max, 0, y_max).
    aoso_ui2_plot_put(AOSO_UI2_ASC_SHIP, bug_pt[0], bug_pt[1], TRUE).
}

FUNCTION aoso_ui2_vs_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_vs.png").
    SET AOSO_UI2_VS_MAIN TO page.
    SET AOSO_UI2_VS_SHIP TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_VS_HIGH TO aoso_ui2_plot_pool(page, "pred_bug.png", 5, 8).
    SET AOSO_UI2_VS_NOM TO aoso_ui2_plot_pool(page, "pred_bug.png", 5, 8).
    SET AOSO_UI2_VS_LOW TO aoso_ui2_plot_pool(page, "trail_bug.png", 5, 10).
    SET AOSO_CRT_VS_HDOT TO aoso_crt_side(page, 0).
    SET AOSO_CRT_VS_TWR TO aoso_crt_side(page, 1).
    SET AOSO_CRT_VS_MAR TO aoso_crt_side(page, 2).
    SET AOSO_CRT_VS_SITE TO aoso_crt_side(page, 3).
    SET AOSO_CRT_VS_RAD TO aoso_crt_side(page, 4).
    SET AOSO_CRT_VS_DV TO aoso_crt_side(page, 5).
    SET AOSO_UI2_VS_INFO TO aoso_crt_label(page, 40, 358, 460).
}

FUNCTION aoso_ui2_vs_corridor {
    PARAMETER pool.
    PARAMETER x_max.
    PARAMETER y_max.
    PARAMETER gain.
    PARAMETER show.
    PARAMETER slot_base IS 0.
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
    IF NOT AOSO_UI2_VS_MAIN:ISTYPE("WIDGET") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL lnd IS AOSO_HUD_DATA["landing"].
    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL margin IS aoso_lex_num(tr, "dv_margin", 0).
    LOCAL band IS "NOM".
    IF margin < 150 { SET band TO "MARGIN". }
    IF margin < 0 { SET band TO "ABORT". }
    aoso_ui2_set_text(AOSO_CRT_VS_HDOT, "vs_hdot", ROUND(aoso_lex_num(f, "vs", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_VS_TWR, "vs_twr", ROUND(aoso_lex_num(f, "twr", 0), 2) + "").
    aoso_ui2_set_text(AOSO_CRT_VS_MAR, "vs_mar", band + " " + ROUND(margin, 0)).
    aoso_ui2_set_text(AOSO_CRT_VS_DV, "vs_dv", ROUND(aoso_lex_num(res, "land_dv", 0), 0) + "").

    LOCAL alt_km IS aoso_lex_num(tr, "alt_km", 0).
    IF aoso_lex_bool(tr, "site_ok") {
        LOCAL site_km IS aoso_lex_num(tr, "site_km", 0).
        LOCAL x_max IS site_km * 1.15.
        IF x_max < 5 { SET x_max TO 5. }
        LOCAL y_max IS MAX(alt_km, x_max * 0.15 * 1.4) * 1.1.
        IF y_max < 1 { SET y_max TO 1. }
        aoso_ui2_vs_corridor(AOSO_UI2_VS_HIGH, x_max, y_max, 1.4, TRUE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_NOM, x_max, y_max, 1.0, TRUE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_LOW, x_max, y_max, 0.55, TRUE).
        LOCAL bug_pt IS aoso_ui2_plot_px(x_max - site_km, alt_km, 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_VS_SHIP, bug_pt[0], bug_pt[1], TRUE).
        aoso_ui2_set_text(AOSO_CRT_VS_SITE, "vs_site", ROUND(site_km, 1) + " km").
        LOCAL radar_now IS aoso_lex_num(lnd, "radar", 0).
        LOCAL radar_txt IS "".
        IF radar_now > 0 {
            IF radar_now < 8000 { SET radar_txt TO ROUND(radar_now, 0) + " m". }
        }
        aoso_ui2_set_text(AOSO_CRT_VS_RAD, "vs_rad", radar_txt).
        aoso_ui2_set_text(AOSO_UI2_VS_INFO, "vs_info", aoso_lex_str(lnd, "state", "") + "  " + ROUND(alt_km, 1) + " km").
    } ELSE {
        aoso_ui2_vs_corridor(AOSO_UI2_VS_HIGH, 1, 1, 1, FALSE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_NOM, 1, 1, 1, FALSE).
        aoso_ui2_vs_corridor(AOSO_UI2_VS_LOW, 1, 1, 1, FALSE).
        LOCAL eta_pe IS aoso_lex_num(AOSO_HUD_DATA["orbit"], "pe_eta", 0).
        LOCAL x_max IS MAX(eta_pe, 30).
        LOCAL y_max IS MAX(alt_km, 1) * 1.1.
        LOCAL bug_pt IS aoso_ui2_plot_px(x_max - MIN(eta_pe, x_max), alt_km, 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_VS_SHIP, bug_pt[0], bug_pt[1], TRUE).
        aoso_ui2_set_text(AOSO_CRT_VS_SITE, "vs_site", "PE-REL").
        aoso_ui2_set_text(AOSO_CRT_VS_RAD, "vs_rad", "").
        aoso_ui2_set_text(AOSO_UI2_VS_INFO, "vs_info", "NO SITE  T-" + ROUND(eta_pe, 0) + " s").
    }
}

FUNCTION aoso_ui2_vs_ship_fast {
    IF NOT AOSO_UI2_VS_SHIP:ISTYPE("LABEL") { RETURN. }
    IF NOT AOSO_HUD_DATA:HASKEY("traj") { RETURN. }
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    IF aoso_lex_bool(tr, "site_ok") {
        LOCAL site_km IS aoso_lex_num(tr, "site_km", 0).
        LOCAL alt_km IS aoso_lex_num(tr, "alt_km", 0).
        LOCAL x_max IS site_km * 1.15.
        IF x_max < 5 { SET x_max TO 5. }
        LOCAL y_max IS MAX(alt_km, x_max * 0.21) * 1.1.
        IF y_max < 1 { SET y_max TO 1. }
        LOCAL bug_pt IS aoso_ui2_plot_px(x_max - site_km, alt_km, 0, x_max, 0, y_max).
        aoso_ui2_plot_put(AOSO_UI2_VS_SHIP, bug_pt[0], bug_pt[1], TRUE).
    }
}

FUNCTION aoso_ui2_rte_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_rte.png").
    SET AOSO_UI2_RTE_MAIN TO page.
    SET AOSO_UI2_RTE_PILLS TO LIST().
    LOCAL i IS 0.
    UNTIL i >= 8 {
        LOCAL col IS i - FLOOR(i / 4) * 4.
        LOCAL row_n IS FLOOR(i / 4).
        LOCAL pill IS aoso_crt_label(page, 52 + col * 108, 78 + row_n * 32, 100, 13).
        SET pill:VISIBLE TO FALSE.
        AOSO_UI2_RTE_PILLS:ADD(pill).
        SET i TO i + 1.
    }
    SET AOSO_UI2_RTE_HEAD TO aoso_crt_label(page, 52, 190, 430, 14).
    SET AOSO_UI2_RTE_WIN TO aoso_crt_label(page, 52, 216, 430, 14).
    SET AOSO_CRT_RTE_HOP TO aoso_crt_side(page, 0).
    SET AOSO_CRT_RTE_WIN TO aoso_crt_side(page, 1).
    SET AOSO_CRT_RTE_CLASS TO aoso_crt_side(page, 2).
    SET AOSO_CRT_RTE_END TO aoso_crt_side(page, 3).
    SET AOSO_CRT_RTE_RET TO aoso_crt_side(page, 4).
    SET AOSO_CRT_RTE_ABT TO aoso_crt_side(page, 5).
}

FUNCTION aoso_ui2_rte_window {
    PARAMETER here_name.
    PARAMETER dest_name.
    IF dest_name = "" {
        SET AOSO_UI2_WIN_SHORT TO "---".
        RETURN "NO NEXT BODY".
    }
    IF DEFINED aoso_feas_planet_of {
        IF aoso_feas_planet_of(here_name) = aoso_feas_planet_of(dest_name) {
            SET AOSO_UI2_WIN_SHORT TO "LOCAL".
            RETURN "LOCAL HOP  " + here_name + " -> " + dest_name.
        }
    } ELSE {
        SET AOSO_UI2_WIN_SHORT TO "---".
        RETURN "PLANNER NOT LOADED".
    }
    LOCAL key IS here_name + ">" + dest_name.
    LOCAL now_ut IS TIME:SECONDS.
    LOCAL cpu_hot IS FALSE.
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 { SET cpu_hot TO TRUE. }
    }
    IF cpu_hot { RETURN AOSO_UI2_WIN_TXT. }
    IF DEFINED aoso_window_evaluate {
        IF key = AOSO_UI2_WIN_KEY {
            IF AOSO_UI2_WIN_UT >= 0 {
                IF now_ut - AOSO_UI2_WIN_UT < 8 { RETURN AOSO_UI2_WIN_TXT. }
            }
        }
        LOCAL ev IS aoso_window_evaluate(here_name, dest_name).
        SET AOSO_UI2_WIN_KEY TO key.
        SET AOSO_UI2_WIN_UT TO now_ut.
        SET AOSO_UI2_WIN_SHORT TO ev["wait_days"] + " d".
        SET AOSO_UI2_WIN_TXT TO here_name + " -> " + dest_name +
            "   T+" + ev["wait_days"] + " d   err " + ev["phase_err"] +
            " deg   dV " + ROUND(ev["now_dv"], 0).
        RETURN AOSO_UI2_WIN_TXT.
    }
    SET AOSO_UI2_WIN_SHORT TO "---".
    RETURN "WINDOW NOT LOADED".
}

FUNCTION aoso_ui2_rte_update {
    IF NOT AOSO_UI2_RTE_MAIN:ISTYPE("WIDGET") { RETURN. }
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
    LOCAL idx IS aoso_lex_num(AOSO_HUD_DATA["mission"], "idx", 0).
    LOCAL next_name IS "".
    IF idx >= 0 {
        IF idx < targets:LENGTH { SET next_name TO targets[idx]. }
    }

    LOCAL i IS 0.
    UNTIL i >= AOSO_UI2_RTE_PILLS:LENGTH {
        LOCAL pill IS AOSO_UI2_RTE_PILLS[i].
        IF i < targets:LENGTH {
            LOCAL body_name IS targets[i].
            LOCAL tag IS "CAP".
            SET pill:STYLE:TEXTCOLOR TO RGB(0.72, 1, 0.62).
            IF aoso_ui2_list_has(orbit_only, body_name) {
                SET tag TO "ORB".
                SET pill:STYLE:TEXTCOLOR TO RGB(0.49, 0.78, 1).
            }
            IF aoso_ui2_list_has(skipped, body_name) {
                SET tag TO "SKIP".
                SET pill:STYLE:TEXTCOLOR TO RGB(0.45, 0.45, 0.45).
            }
            IF i < idx {
                SET tag TO "DONE".
                SET pill:STYLE:TEXTCOLOR TO RGB(0.35, 0.55, 0.4).
            }
            IF i = idx {
                SET tag TO "NOW".
                SET pill:STYLE:TEXTCOLOR TO RGB(1, 0.8, 0.28).
            }
            aoso_ui2_set_text(pill, "rte_p" + i, aoso_ui2_short_body(body_name) + " " + tag).
            SET pill:VISIBLE TO TRUE.
        } ELSE {
            SET pill:VISIBLE TO FALSE.
        }
        SET i TO i + 1.
    }

    IF have_plan {
        aoso_ui2_set_text(AOSO_UI2_RTE_HEAD, "rte_head", plan_from + " -> " + next_name + "   " + (idx + 1) + "/" + targets:LENGTH).
    } ELSE {
        aoso_ui2_set_text(AOSO_UI2_RTE_HEAD, "rte_head", "NO PLAN").
    }
    aoso_ui2_set_text(AOSO_UI2_RTE_WIN, "rte_win", aoso_ui2_rte_window(SHIP:BODY:NAME, next_name)).

    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL end_dv IS -1.
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("end_dv") { SET end_dv TO AOSO_PROJECT_LAST["end_dv"]. }
    }
    LOCAL end_txt IS "---".
    IF end_dv >= 0 { SET end_txt TO ROUND(end_dv, 0) + "". }
    aoso_ui2_set_text(AOSO_CRT_RTE_HOP, "rte_hop", aoso_crt_fit(aoso_ui2_short_body(next_name), 10)).
    aoso_ui2_set_text(AOSO_CRT_RTE_WIN, "rte_wside", AOSO_UI2_WIN_SHORT).
    aoso_ui2_set_text(AOSO_CRT_RTE_CLASS, "rte_class", aoso_crt_fit(plan_class, 10)).
    aoso_ui2_set_text(AOSO_CRT_RTE_END, "rte_end", end_txt).
    aoso_ui2_set_text(AOSO_CRT_RTE_RET, "rte_ret", ROUND(aoso_lex_num(res, "return_dv", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_RTE_ABT, "rte_abt", ROUND(aoso_lex_num(res, "abort_dv", 0), 0) + "").
}

FUNCTION aoso_ui2_bdg_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_bdg.png").
    SET AOSO_UI2_BDG_MAIN TO page.
    SET AOSO_UI2_BDG_ROWS TO LIST().
    LOCAL i IS 0.
    UNTIL i >= 8 {
        LOCAL row IS aoso_crt_label(page, 48, 80 + i * 28, 450, 14).
        AOSO_UI2_BDG_ROWS:ADD(row).
        SET i TO i + 1.
    }
    SET AOSO_UI2_BDG_INFO TO aoso_crt_label(page, 48, 308, 450, 14).
    SET AOSO_CRT_BDG_NOW TO aoso_crt_side(page, 0).
    SET AOSO_CRT_BDG_UNU TO aoso_crt_side(page, 1).
    SET AOSO_CRT_BDG_RES TO aoso_crt_side(page, 2).
    SET AOSO_CRT_BDG_LAND TO aoso_crt_side(page, 3).
    SET AOSO_CRT_BDG_RET TO aoso_crt_side(page, 4).
    SET AOSO_CRT_BDG_ABT TO aoso_crt_side(page, 5).
}

FUNCTION aoso_ui2_bdg_line {
    PARAMETER label_txt.
    PARAMETER dv.
    PARAMETER state_name.
    LOCAL width IS 12.
    LOCAL span IS 4000.
    IF dv > span { SET span TO dv. }
    LOCAL frac IS 0.
    IF span > 0 { SET frac TO dv / span. }
    IF frac < 0 { SET frac TO 0. }
    IF frac > 1 { SET frac TO 1. }
    LOCAL fill IS ROUND(frac * width, 0).
    LOCAL bar IS "".
    LOCAL i IS 0.
    UNTIL i >= width {
        IF i < fill { SET bar TO bar + "#". }
        ELSE { SET bar TO bar + "-". }
        SET i TO i + 1.
    }
    RETURN aoso_ui2_color_state(state_name, aoso_crt_fit(label_txt, 10)) + " " + bar + " " + ROUND(dv, 0).
}

FUNCTION aoso_ui2_bdg_update {
    IF NOT AOSO_UI2_BDG_MAIN:ISTYPE("WIDGET") { RETURN. }
    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL now_dv IS aoso_lex_num(res, "mission_dv", 0).
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
    IF have_legs {
        IF NOT stale {
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
                    IF did_refuel { SET bump TO "+ISRU". }
                    lines:ADD(aoso_ui2_bdg_line(aoso_ui2_short_body(body_name) + bump, leg["leftover_out"], state_name)).
                }
                SET i TO i + 1.
            }
        }
    }
    LOCAL row_i IS 0.
    UNTIL row_i >= AOSO_UI2_BDG_ROWS:LENGTH {
        IF row_i < lines:LENGTH {
            aoso_ui2_set_text(AOSO_UI2_BDG_ROWS[row_i], "bdg_r" + row_i, lines[row_i]).
        } ELSE {
            aoso_ui2_set_text(AOSO_UI2_BDG_ROWS[row_i], "bdg_r" + row_i, "").
        }
        SET row_i TO row_i + 1.
    }
    LOCAL stamp IS "LIVE BUDGET".
    IF have_legs {
        IF stale { SET stamp TO "STALE". }
        ELSE { SET stamp TO "PROJECT LIVE". }
    } ELSE {
        SET stamp TO "STALE  NO LEDGER".
    }
    aoso_ui2_set_text(AOSO_UI2_BDG_INFO, "bdg_info", stamp).
    aoso_ui2_set_text(AOSO_CRT_BDG_NOW, "bdg_now", ROUND(now_dv, 0) + "").
    aoso_ui2_set_text(AOSO_CRT_BDG_UNU, "bdg_unu", ROUND(aoso_lex_num(res, "unusable_dv", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_BDG_RES, "bdg_res", ROUND(aoso_lex_num(res, "reserve_dv", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_BDG_LAND, "bdg_land", ROUND(aoso_lex_num(res, "land_dv", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_BDG_RET, "bdg_ret", ROUND(aoso_lex_num(res, "return_dv", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_BDG_ABT, "bdg_abt", ROUND(aoso_lex_num(res, "abort_dv", 0), 0) + "").
}

FUNCTION aoso_ui2_rnd_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_rnd.png").
    SET AOSO_UI2_RND_MAIN TO page.
    SET AOSO_UI2_RND_SHIP TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_RND_TGT TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "target_bug.png", 16).
    aoso_crt_move(AOSO_UI2_RND_SHIP, 70, 180, 18, 18).
    SET AOSO_UI2_RND_SHIP:VISIBLE TO TRUE.
    SET AOSO_UI2_RND_INFO TO aoso_crt_label(page, 48, 300, 450, 14).
    SET AOSO_CRT_RND_NAME TO aoso_crt_side(page, 0).
    SET AOSO_CRT_RND_DIST TO aoso_crt_side(page, 1).
    SET AOSO_CRT_RND_RATE TO aoso_crt_side(page, 2).
    SET AOSO_CRT_RND_BRG TO aoso_crt_side(page, 3).
    SET AOSO_CRT_RND_PORT TO aoso_crt_side(page, 4).
    SET AOSO_CRT_RND_REL TO aoso_crt_side(page, 5).
}

FUNCTION aoso_ui2_rnd_update {
    IF NOT AOSO_UI2_RND_MAIN:ISTYPE("WIDGET") { RETURN. }
    LOCAL tgt IS AOSO_HUD_DATA["target"].
    IF NOT aoso_lex_bool(tgt, "has") {
        SET AOSO_UI2_RND_TGT:VISIBLE TO FALSE.
        aoso_ui2_set_text(AOSO_UI2_RND_INFO, "rnd_info", "NO TARGET").
        aoso_ui2_set_text(AOSO_CRT_RND_NAME, "rnd_name", "").
        aoso_ui2_set_text(AOSO_CRT_RND_DIST, "rnd_dist", "").
        aoso_ui2_set_text(AOSO_CRT_RND_RATE, "rnd_rate", "").
        aoso_ui2_set_text(AOSO_CRT_RND_BRG, "rnd_brg", "").
        aoso_ui2_set_text(AOSO_CRT_RND_PORT, "rnd_port", "").
        aoso_ui2_set_text(AOSO_CRT_RND_REL, "rnd_rel", "").
        RETURN.
    }
    LOCAL dist_m IS aoso_lex_num(tgt, "dist", 0).
    LOCAL scale_m IS MAX(dist_m, 100).
    LOCAL nx IS aoso_ui2_clamp(dist_m / scale_m, 0, 1).
    SET AOSO_UI2_RND_TGT:VISIBLE TO TRUE.
    aoso_crt_move(AOSO_UI2_RND_TGT, 80 + nx * 400, 180, 16, 16).
    LOCAL rel_spd IS aoso_lex_num(tgt, "rel", 0).
    LOCAL port_txt IS "FAR".
    IF dist_m < 200 { SET port_txt TO "NEAR". }
    aoso_ui2_set_text(AOSO_CRT_RND_NAME, "rnd_name", aoso_crt_fit(aoso_lex_str(tgt, "name", ""), 12)).
    aoso_ui2_set_text(AOSO_CRT_RND_DIST, "rnd_dist", ROUND(dist_m, 0) + " m").
    aoso_ui2_set_text(AOSO_CRT_RND_RATE, "rnd_rate", ROUND(rel_spd, 2) + "").
    aoso_ui2_set_text(AOSO_CRT_RND_BRG, "rnd_brg", ROUND(aoso_lex_num(tgt, "bearing", 0), 0) + "").
    aoso_ui2_set_text(AOSO_CRT_RND_PORT, "rnd_port", port_txt).
    aoso_ui2_set_text(AOSO_CRT_RND_REL, "rnd_rel", ROUND(rel_spd, 1) + " m/s").
    aoso_ui2_set_text(AOSO_UI2_RND_INFO, "rnd_info", aoso_lex_str(tgt, "name", "")).
}
