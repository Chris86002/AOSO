// AOSO/ux/ui2_plots.ks
// CRT phase plots. The plate PNG is the instrument. Live text and bugs are
// pinned onto it. Display only. Does not fly the ship.
//
// Route and budget plates are not the shared 460x280 plot.
// Route transfer plot: origin (70, 186), size 400 x 158, x 0..70 days, y 0..8000 m/s.
// Pills sit at (16 + i*90, 88). Budget bars sit in y=88..182, columns x=22+i*76.

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
GLOBAL AOSO_UI2_RTE_MODE IS 0.
GLOBAL AOSO_UI2_RTE_HOP IS 0.
GLOBAL AOSO_UI2_RTE_WHEN IS 0.
GLOBAL AOSO_UI2_RTE_DVH IS 0.
GLOBAL AOSO_UI2_RTE_PILLS IS LIST().
GLOBAL AOSO_UI2_RTE_TAGS IS LIST().
GLOBAL AOSO_UI2_RTE_KIND IS LEXICON().
GLOBAL AOSO_UI2_RTE_DIA IS 0.
GLOBAL AOSO_UI2_RTE_FEAS IS 0.
GLOBAL AOSO_UI2_RTE_LEFT IS 0.
GLOBAL AOSO_UI2_RTE_RET IS 0.
GLOBAL AOSO_UI2_RTE_ABT IS 0.
GLOBAL AOSO_UI2_RTE_CLASS IS 0.
GLOBAL AOSO_UI2_RTE_CONF IS 0.
GLOBAL AOSO_UI2_WIN_UT IS -1.
GLOBAL AOSO_UI2_WIN_KEY IS "".
GLOBAL AOSO_UI2_WIN_TXT IS "WINDOW  ---".
GLOBAL AOSO_UI2_WIN_SHORT IS "---".
GLOBAL AOSO_UI2_WIN_WAIT IS 0.
GLOBAL AOSO_UI2_WIN_DV IS 0.
GLOBAL AOSO_UI2_WIN_EFF IS 0.

GLOBAL AOSO_UI2_BDG_MAIN IS 0.
GLOBAL AOSO_UI2_BDG_NAMES IS LIST().
GLOBAL AOSO_UI2_BDG_NUMS IS LIST().
GLOBAL AOSO_UI2_BDG_BARS IS LIST().
GLOBAL AOSO_UI2_BDG_WARN IS 0.
GLOBAL AOSO_UI2_BDG_STEP IS LIST().
GLOBAL AOSO_UI2_BDG_STATE IS LIST().
GLOBAL AOSO_UI2_BDG_WHY IS LIST().
GLOBAL AOSO_UI2_BDG_BIG IS 0.
GLOBAL AOSO_UI2_BDG_UNU IS 0.
GLOBAL AOSO_UI2_BDG_RES IS 0.
GLOBAL AOSO_UI2_BDG_LAND IS 0.
GLOBAL AOSO_UI2_BDG_RET IS 0.
GLOBAL AOSO_UI2_BDG_ABT IS 0.
GLOBAL AOSO_UI2_BDG_MUSE IS 0.
GLOBAL AOSO_UI2_BDG_MUNU IS 0.
GLOBAL AOSO_UI2_BDG_MRES IS 0.
GLOBAL AOSO_UI2_BDG_MLND IS 0.
GLOBAL AOSO_UI2_BDG_MRET IS 0.
GLOBAL AOSO_UI2_BDG_MABT IS 0.
GLOBAL AOSO_UI2_BDG_CLOCK IS 0.
GLOBAL AOSO_UI2_BDG_PHASE IS 0.
GLOBAL AOSO_UI2_METER_SIG IS LEXICON().

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
    SET AOSO_UI2_RTE_TAGS TO LIST().
    SET AOSO_UI2_RTE_KIND TO LEXICON().
    SET AOSO_UI2_BDG_NAMES TO LIST().
    SET AOSO_UI2_BDG_NUMS TO LIST().
    SET AOSO_UI2_BDG_BARS TO LIST().
    SET AOSO_UI2_BDG_STEP TO LIST().
    SET AOSO_UI2_BDG_STATE TO LIST().
    SET AOSO_UI2_BDG_WHY TO LIST().
    SET AOSO_UI2_METER_SIG TO LEXICON().
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

FUNCTION aoso_ui2_kind_rgb {
    PARAMETER kind.
    IF kind = "NOW" OR kind = "MARGIN" { RETURN RGB(1, 0.8, 0.28). }
    IF kind = "ORB" { RETURN RGB(0.45, 0.78, 1). }
    IF kind = "SKIP" OR kind = "DONE" { RETURN RGB(0.55, 0.55, 0.55). }
    IF kind = "FAIL" { RETURN RGB(1, 0.35, 0.28). }
    RETURN RGB(0.72, 1, 0.62).
}

FUNCTION aoso_ui2_rte_face {
    PARAMETER widget.
    PARAMETER kind.
    LOCAL file IS "pill_cap.png".
    IF kind = "NOW" { SET file TO "pill_now.png". }
    IF kind = "NEXT" { SET file TO "pill_next.png". }
    IF kind = "MARGIN" { SET file TO "pill_mar.png". }
    IF kind = "ORB" { SET file TO "pill_orb.png". }
    IF kind = "SKIP" OR kind = "DONE" { SET file TO "pill_skip.png". }
    IF kind = "FAIL" { SET file TO "pill_bad.png". }
    LOCAL art IS AOSO_UI2_ASSET_ROOT + file.
    SET widget:STYLE:BG TO art.
    SET widget:STYLE:HOVER:BG TO art.
    SET widget:STYLE:FOCUSED:BG TO art.
    SET widget:STYLE:ACTIVE:BG TO art.
    SET widget:STYLE:BORDER:LEFT TO 0.
    SET widget:STYLE:BORDER:RIGHT TO 0.
    SET widget:STYLE:BORDER:TOP TO 0.
    SET widget:STYLE:BORDER:BOTTOM TO 0.
    SET widget:STYLE:PADDING:LEFT TO 0.
    SET widget:STYLE:PADDING:RIGHT TO 0.
    SET widget:STYLE:PADDING:TOP TO 2.
    SET widget:STYLE:PADDING:BOTTOM TO 0.
    SET widget:STYLE:TEXTCOLOR TO aoso_ui2_kind_rgb(kind).
}

FUNCTION aoso_ui2_rte_tag {
    PARAMETER kind.
    IF kind = "NOW" { RETURN "CURRENT". }
    IF kind = "NEXT" { RETURN "NEXT". }
    IF kind = "MARGIN" { RETURN "MARGIN". }
    IF kind = "ORB" { RETURN "ORBIT". }
    IF kind = "SKIP" { RETURN "SKIP". }
    IF kind = "DONE" { RETURN "DONE". }
    IF kind = "FAIL" { RETURN "FAIL". }
    RETURN "CAPABLE".
}

FUNCTION aoso_ui2_when_text {
    PARAMETER wait_s.
    PARAMETER short_txt.
    IF short_txt = "LOCAL" { RETURN "LOCAL HOP". }
    IF short_txt = "---" { RETURN "NO WINDOW". }
    IF wait_s <= 90 { RETURN "OPEN". }
    IF wait_s < 21600 {
        LOCAL hrs IS FLOOR(wait_s / 3600).
        LOCAL mins IS FLOOR(MOD(wait_s, 3600) / 60).
        RETURN hrs + "h " + mins + "m".
    }
    RETURN ROUND(wait_s / 21600, 1) + " d".
}

FUNCTION aoso_ui2_bar_file {
    PARAMETER tone.
    IF tone = "WARN" { RETURN "bar_warn.png". }
    IF tone = "FAIL" { RETURN "bar_bad.png". }
    RETURN "bar_go.png".
}

FUNCTION aoso_ui2_bar_place {
    PARAMETER key.
    PARAMETER bar.
    PARAMETER x.
    PARAMETER y.
    PARAMETER w.
    PARAMETER h.
    PARAMETER tone.
    IF w < 2 { SET w TO 2. }
    LOCAL sig IS tone + "@" + ROUND(x, 0) + "," + ROUND(y, 0) + "x" + ROUND(w, 0).
    SET bar:VISIBLE TO TRUE.
    IF AOSO_UI2_METER_SIG:HASKEY(key) {
        IF AOSO_UI2_METER_SIG[key] = sig { RETURN. }
    }
    SET AOSO_UI2_METER_SIG[key] TO sig.
    LOCAL art IS AOSO_UI2_ASSET_ROOT + aoso_ui2_bar_file(tone).
    SET bar:IMAGE TO art.
    SET bar:STYLE:BG TO art.
    aoso_crt_move(bar, x, y, w, h).
}

FUNCTION aoso_ui2_rte_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_rte.png").
    SET AOSO_UI2_RTE_MAIN TO page.
    SET AOSO_UI2_RTE_PILLS TO LIST().
    SET AOSO_UI2_RTE_TAGS TO LIST().
    SET AOSO_UI2_RTE_KIND TO LEXICON().
    SET AOSO_UI2_RTE_MODE TO aoso_crt_label(page, 500, 12, 210, 13).
    SET AOSO_UI2_RTE_MODE:STYLE:ALIGN TO "right".
    SET AOSO_UI2_RTE_MODE:STYLE:TEXTCOLOR TO RGB(1, 0.7, 0.18).
    SET AOSO_UI2_RTE_HOP TO aoso_crt_label(page, 20, 58, 270, 14).
    SET AOSO_UI2_RTE_WHEN TO aoso_crt_label(page, 300, 58, 230, 14).
    SET AOSO_UI2_RTE_DVH TO aoso_crt_label(page, 590, 54, 120, 16).
    SET AOSO_UI2_RTE_DVH:STYLE:TEXTCOLOR TO RGB(1, 0.84, 0.27).
    LOCAL i IS 0.
    UNTIL i >= 8 {
        LOCAL pill IS aoso_crt_label(page, 16 + i * 90, 88, 74, 12).
        SET pill:STYLE:ALIGN TO "center".
        aoso_crt_move(pill, 16 + i * 90, 88, 74, 26).
        SET pill:VISIBLE TO FALSE.
        AOSO_UI2_RTE_PILLS:ADD(pill).
        LOCAL tag IS aoso_crt_label(page, 12 + i * 90, 116, 84, 10).
        SET tag:STYLE:ALIGN TO "center".
        SET tag:VISIBLE TO FALSE.
        AOSO_UI2_RTE_TAGS:ADD(tag).
        SET i TO i + 1.
    }
    SET AOSO_UI2_RTE_DIA TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "diamond.png", 16).
    SET AOSO_UI2_RTE_FEAS TO aoso_crt_label(page, 526, 160, 180, 12).
    SET AOSO_UI2_RTE_LEFT TO aoso_crt_label(page, 526, 192, 180, 22).
    SET AOSO_UI2_RTE_RET TO aoso_crt_label(page, 526, 248, 180, 16).
    SET AOSO_UI2_RTE_ABT TO aoso_crt_label(page, 526, 294, 180, 16).
    SET AOSO_UI2_RTE_CLASS TO aoso_crt_label(page, 526, 340, 180, 13).
    SET AOSO_UI2_RTE_CONF TO aoso_crt_label(page, 600, 352, 100, 16).
}

FUNCTION aoso_ui2_rte_window {
    PARAMETER here_name.
    PARAMETER dest_name.
    IF dest_name = "" {
        SET AOSO_UI2_WIN_SHORT TO "---".
        SET AOSO_UI2_WIN_WAIT TO 0.
        SET AOSO_UI2_WIN_DV TO 0.
        SET AOSO_UI2_WIN_EFF TO 0.
        RETURN "NO NEXT BODY".
    }
    // Never write DEFINED on a function name. kOS calls the bare name with
    // zero arguments (KOS#2159). aoso_feas_planet_of needs a body, so that
    // check aborted the script the moment the route page painted.
    IF aoso_feas_planet_of(here_name) = aoso_feas_planet_of(dest_name) {
        SET AOSO_UI2_WIN_SHORT TO "LOCAL".
        SET AOSO_UI2_WIN_WAIT TO 0.
        SET AOSO_UI2_WIN_DV TO 80.
        SET AOSO_UI2_WIN_EFF TO 1.
        RETURN "LOCAL HOP  " + here_name + " -> " + dest_name.
    }
    LOCAL key IS here_name + ">" + dest_name.
    LOCAL now_ut IS TIME:SECONDS.
    LOCAL cpu_hot IS FALSE.
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 { SET cpu_hot TO TRUE. }
    }
    IF cpu_hot { RETURN AOSO_UI2_WIN_TXT. }
    IF key = AOSO_UI2_WIN_KEY {
        IF AOSO_UI2_WIN_UT >= 0 {
            IF now_ut - AOSO_UI2_WIN_UT < 8 { RETURN AOSO_UI2_WIN_TXT. }
        }
    }
    LOCAL ev IS aoso_window_evaluate(here_name, dest_name).
    SET AOSO_UI2_WIN_KEY TO key.
    SET AOSO_UI2_WIN_UT TO now_ut.
    SET AOSO_UI2_WIN_WAIT TO ev["wait_s"].
    SET AOSO_UI2_WIN_DV TO ev["now_dv"].
    SET AOSO_UI2_WIN_EFF TO ev["efficiency"].
    SET AOSO_UI2_WIN_SHORT TO ev["wait_days"] + " d".
    SET AOSO_UI2_WIN_TXT TO here_name + " -> " + dest_name +
        "   T+" + ev["wait_days"] + " d   err " + ev["phase_err"] +
        " deg   dV " + ROUND(ev["now_dv"], 0).
    RETURN AOSO_UI2_WIN_TXT.
}

FUNCTION aoso_ui2_hop_kind {
    PARAMETER body_name.
    PARAMETER slot_i.
    PARAMETER idx.
    PARAMETER skipped.
    PARAMETER orbit_only.
    PARAMETER legs.
    IF slot_i < idx { RETURN "DONE". }
    IF aoso_ui2_list_has(skipped, body_name) { RETURN "SKIP". }
    IF aoso_ui2_list_has(orbit_only, body_name) { RETURN "ORB". }
    LOCAL margin IS 99999.
    LOCAL ok_leg IS TRUE.
    IF legs:ISTYPE("LEXICON") {
        IF legs:HASKEY(body_name) {
            SET margin TO aoso_lex_num(legs[body_name], "margin", 99999).
            SET ok_leg TO aoso_lex_bool(legs[body_name], "ok").
        }
    }
    IF NOT ok_leg { RETURN "FAIL". }
    IF margin < 200 { RETURN "MARGIN". }
    IF slot_i = idx { RETURN "NOW". }
    IF slot_i = idx + 1 { RETURN "NEXT". }
    RETURN "CAP".
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
    LOCAL legs IS LEXICON().
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("legs") { SET legs TO AOSO_PROJECT_LAST["legs"]. }
    }
    LOCAL idx IS aoso_lex_num(AOSO_HUD_DATA["mission"], "idx", 0).
    LOCAL next_name IS "".
    IF idx >= 0 {
        IF idx < targets:LENGTH { SET next_name TO targets[idx]. }
    }
    LOCAL start IS 0.
    IF targets:LENGTH > 8 {
        SET start TO idx - 1.
        IF start < 0 { SET start TO 0. }
        LOCAL last_start IS targets:LENGTH - 8.
        IF start > last_start { SET start TO last_start. }
    }

    LOCAL i IS 0.
    UNTIL i >= AOSO_UI2_RTE_PILLS:LENGTH {
        LOCAL pill IS AOSO_UI2_RTE_PILLS[i].
        LOCAL tag_w IS AOSO_UI2_RTE_TAGS[i].
        IF start + i < targets:LENGTH {
            LOCAL body_name IS targets[start + i].
            LOCAL slot_i IS start + i.
            LOCAL kind IS aoso_ui2_hop_kind(body_name, slot_i, idx, skipped, orbit_only, legs).
            LOCAL key_i IS "" + i.
            LOCAL prev IS "".
            IF AOSO_UI2_RTE_KIND:HASKEY(key_i) { SET prev TO AOSO_UI2_RTE_KIND[key_i]. }
            IF prev <> kind {
                SET AOSO_UI2_RTE_KIND[key_i] TO kind.
                aoso_ui2_rte_face(pill, kind).
            }
            SET pill:STYLE:TEXTCOLOR TO aoso_ui2_kind_rgb(kind).
            SET tag_w:STYLE:TEXTCOLOR TO aoso_ui2_kind_rgb(kind).
            aoso_ui2_set_text(pill, "rte_p" + i, aoso_ui2_short_body(body_name)).
            aoso_ui2_set_text(tag_w, "rte_t" + i, aoso_ui2_rte_tag(kind)).
            SET pill:VISIBLE TO TRUE.
            SET tag_w:VISIBLE TO TRUE.
        } ELSE {
            SET pill:VISIBLE TO FALSE.
            SET tag_w:VISIBLE TO FALSE.
        }
        SET i TO i + 1.
    }

    aoso_ui2_rte_window(SHIP:BODY:NAME, next_name).
    LOCAL hop_dv IS AOSO_UI2_WIN_DV.
    LOCAL left_dv IS aoso_lex_num(AOSO_HUD_DATA["res"], "mission_dv", 0).
    IF next_name <> "" {
        IF legs:HASKEY(next_name) {
            LOCAL leg IS legs[next_name].
            LOCAL spent IS aoso_lex_num(leg, "have_in", 0) - aoso_lex_num(leg, "leftover_out", 0).
            IF spent > 1 { SET hop_dv TO spent. }
            SET left_dv TO aoso_lex_num(leg, "leftover_out", left_dv).
        }
    }
    SET AOSO_UI2_WIN_DV TO hop_dv.

    LOCAL hop_txt IS "NO PLAN".
    IF have_plan {
        SET hop_txt TO plan_from + " > " + next_name + "   " + ROUND(idx + 1, 0) + "/" + targets:LENGTH.
    }
    aoso_ui2_set_text(AOSO_UI2_RTE_HOP, "rte_hop", hop_txt).
    aoso_ui2_set_text(AOSO_UI2_RTE_WHEN, "rte_when", aoso_ui2_when_text(AOSO_UI2_WIN_WAIT, AOSO_UI2_WIN_SHORT)).
    aoso_ui2_set_text(AOSO_UI2_RTE_DVH, "rte_dvh", ROUND(hop_dv, 0) + "").
    LOCAL mode_txt IS plan_class.
    IF mode_txt = "" { SET mode_txt TO "ROUTE". }
    aoso_ui2_set_text(AOSO_UI2_RTE_MODE, "rte_mode", aoso_crt_fit(mode_txt:TOUPPER, 16)).

    LOCAL cur_kind IS "CAP".
    IF next_name <> "" {
        SET cur_kind TO aoso_ui2_hop_kind(next_name, idx, idx, skipped, orbit_only, legs).
    }
    aoso_ui2_set_text(AOSO_UI2_RTE_FEAS, "rte_feas", aoso_ui2_rte_tag(cur_kind)).
    SET AOSO_UI2_RTE_FEAS:STYLE:TEXTCOLOR TO aoso_ui2_kind_rgb(cur_kind).
    LOCAL left_rgb IS aoso_ui2_kind_rgb("CAP").
    IF left_dv < 0 { SET left_rgb TO aoso_ui2_kind_rgb("FAIL"). }
    ELSE {
        IF left_dv < 200 { SET left_rgb TO aoso_ui2_kind_rgb("MARGIN"). }
    }
    SET AOSO_UI2_RTE_LEFT:STYLE:TEXTCOLOR TO left_rgb.
    aoso_ui2_set_text(AOSO_UI2_RTE_LEFT, "rte_left", ROUND(left_dv, 0) + " m/s").
    LOCAL res IS AOSO_HUD_DATA["res"].
    aoso_ui2_set_text(AOSO_UI2_RTE_RET, "rte_ret", ROUND(aoso_lex_num(res, "return_dv", 0), 0) + " m/s").
    aoso_ui2_set_text(AOSO_UI2_RTE_ABT, "rte_abt", ROUND(aoso_lex_num(res, "abort_dv", 0), 0) + " m/s").
    LOCAL class_txt IS plan_class.
    IF class_txt = "" { SET class_txt TO "---". }
    aoso_ui2_set_text(AOSO_UI2_RTE_CLASS, "rte_class", aoso_crt_fit(class_txt, 18)).
    aoso_ui2_set_text(AOSO_UI2_RTE_CONF, "rte_conf", ROUND(AOSO_UI2_WIN_EFF, 2) + "").

    LOCAL days IS 0.
    IF AOSO_UI2_WIN_WAIT > 0 { SET days TO AOSO_UI2_WIN_WAIT / 21600. }
    LOCAL spot_x IS 70 + aoso_ui2_clamp(days / 70, 0, 1) * 400.
    LOCAL spot_y IS 186 + 158 - aoso_ui2_clamp(hop_dv / 8000, 0, 1) * 158.
    aoso_ui2_plot_put(AOSO_UI2_RTE_DIA, spot_x, spot_y, next_name <> "").
}

FUNCTION aoso_ui2_bdg_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_bdg.png").
    SET AOSO_UI2_BDG_MAIN TO page.
    SET AOSO_UI2_BDG_NAMES TO LIST().
    SET AOSO_UI2_BDG_NUMS TO LIST().
    SET AOSO_UI2_BDG_BARS TO LIST().
    SET AOSO_UI2_BDG_STEP TO LIST().
    SET AOSO_UI2_BDG_STATE TO LIST().
    SET AOSO_UI2_BDG_WHY TO LIST().
    LOCAL i IS 0.
    UNTIL i >= 6 {
        AOSO_UI2_BDG_NAMES:ADD(aoso_crt_label(page, 22 + i * 76, 66, 70, 11)).
        AOSO_UI2_BDG_NUMS:ADD(aoso_crt_label(page, 22 + i * 76, 186, 70, 11)).
        AOSO_UI2_BDG_BARS:ADD(aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_go.png", 58, 8)).
        AOSO_UI2_BDG_STEP:ADD(aoso_crt_label(page, 24, 246 + i * 22, 120, 12)).
        LOCAL state_w IS aoso_crt_label(page, 150, 244 + i * 22, 90, 10).
        SET state_w:STYLE:ALIGN TO "center".
        aoso_crt_move(state_w, 150, 244 + i * 22, 90, 18).
        AOSO_UI2_BDG_STATE:ADD(state_w).
        AOSO_UI2_BDG_WHY:ADD(aoso_crt_label(page, 252, 246 + i * 22, 220, 12)).
        SET i TO i + 1.
    }
    SET AOSO_UI2_BDG_WARN TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "warn_tri.png", 14).
    SET AOSO_UI2_BDG_BIG TO aoso_crt_label(page, 524, 64, 186, 22).
    SET AOSO_UI2_BDG_BIG:STYLE:ALIGN TO "right".
    SET AOSO_UI2_BDG_UNU TO aoso_crt_label(page, 600, 116, 46, 12).
    SET AOSO_UI2_BDG_RES TO aoso_crt_label(page, 600, 138, 46, 12).
    SET AOSO_UI2_BDG_LAND TO aoso_crt_label(page, 600, 160, 46, 12).
    SET AOSO_UI2_BDG_RET TO aoso_crt_label(page, 524, 218, 186, 16).
    SET AOSO_UI2_BDG_RET:STYLE:ALIGN TO "right".
    SET AOSO_UI2_BDG_RET:STYLE:TEXTCOLOR TO RGB(1, 0.75, 0.25).
    SET AOSO_UI2_BDG_ABT TO aoso_crt_label(page, 600, 264, 110, 14).
    SET AOSO_UI2_BDG_ABT:STYLE:ALIGN TO "right".
    SET AOSO_UI2_BDG_MUSE TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_go.png", 8, 8).
    SET AOSO_UI2_BDG_MUNU TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_go.png", 8, 8).
    SET AOSO_UI2_BDG_MRES TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_go.png", 8, 8).
    SET AOSO_UI2_BDG_MLND TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_go.png", 8, 8).
    SET AOSO_UI2_BDG_MRET TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_warn.png", 8, 8).
    SET AOSO_UI2_BDG_MABT TO aoso_crt_bug(page, AOSO_UI2_ASSET_ROOT + "bar_go.png", 8, 8).
    SET AOSO_UI2_BDG_CLOCK TO aoso_crt_label(page, 610, 324, 100, 13).
    SET AOSO_UI2_BDG_PHASE TO aoso_crt_label(page, 610, 354, 100, 13).
}

FUNCTION aoso_ui2_bdg_pick {
    PARAMETER order.
    PARAMETER idx.
    PARAMETER weakest.
    LOCAL picked IS LIST().
    IF NOT order:ISTYPE("LIST") { RETURN picked. }
    IF order:LENGTH = 0 { RETURN picked. }
    LOCAL i0 IS idx.
    IF i0 < 0 { SET i0 TO 0. }
    IF i0 >= order:LENGTH { SET i0 TO 0. }
    LOCAL i IS i0.
    UNTIL picked:LENGTH >= 4 OR i >= order:LENGTH {
        picked:ADD(order[i]).
        SET i TO i + 1.
    }
    IF weakest = "" { RETURN picked. }
    IF aoso_ui2_list_has(picked, weakest) { RETURN picked. }
    IF picked:LENGTH < 4 {
        picked:ADD(weakest).
        RETURN picked.
    }
    LOCAL swapped IS LIST().
    LOCAL n IS 0.
    UNTIL n >= picked:LENGTH {
        IF n = 3 { swapped:ADD(weakest). }
        ELSE { swapped:ADD(picked[n]). }
        SET n TO n + 1.
    }
    RETURN swapped.
}

FUNCTION aoso_ui2_bdg_tone {
    PARAMETER dv.
    PARAMETER ok_leg.
    PARAMETER margin.
    IF dv < 0 { RETURN "FAIL". }
    IF NOT ok_leg { RETURN "FAIL". }
    IF margin < 200 { RETURN "WARN". }
    RETURN "GO".
}

FUNCTION aoso_ui2_bdg_word {
    PARAMETER tone.
    IF tone = "WARN" { RETURN "MARGIN". }
    IF tone = "FAIL" { RETURN "FAIL". }
    RETURN "FEASIBLE".
}

FUNCTION aoso_ui2_bdg_kind {
    PARAMETER tone.
    IF tone = "WARN" { RETURN "MARGIN". }
    IF tone = "FAIL" { RETURN "FAIL". }
    RETURN "CAP".
}

FUNCTION aoso_ui2_bdg_update {
    IF NOT AOSO_UI2_BDG_MAIN:ISTYPE("WIDGET") { RETURN. }
    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL now_dv IS aoso_lex_num(res, "mission_dv", 0).
    LOCAL order IS LIST().
    LOCAL legs IS LEXICON().
    LOCAL weakest IS "".
    LOCAL end_dv IS now_dv.
    LOCAL ok_all IS TRUE.
    IF DEFINED AOSO_PROJECT_LAST {
        IF AOSO_PROJECT_LAST:HASKEY("legs") { SET legs TO AOSO_PROJECT_LAST["legs"]. }
        IF AOSO_PROJECT_LAST:HASKEY("order") { SET order TO AOSO_PROJECT_LAST["order"]. }
        IF AOSO_PROJECT_LAST:HASKEY("weakest") { SET weakest TO AOSO_PROJECT_LAST["weakest"]. }
        IF AOSO_PROJECT_LAST:HASKEY("end_dv") { SET end_dv TO AOSO_PROJECT_LAST["end_dv"]. }
        IF AOSO_PROJECT_LAST:HASKEY("ok") { SET ok_all TO AOSO_PROJECT_LAST["ok"]. }
    }
    IF order:LENGTH = 0 {
        IF DEFINED AOSO_PLAN_LAST {
            IF AOSO_PLAN_LAST:HASKEY("targets") { SET order TO AOSO_PLAN_LAST["targets"]. }
        }
    }
    LOCAL idx IS aoso_lex_num(AOSO_HUD_DATA["mission"], "idx", 0).
    LOCAL picked IS aoso_ui2_bdg_pick(order, idx, weakest).

    LOCAL names IS LIST().
    LOCAL dvs IS LIST().
    LOCAL tones IS LIST().
    LOCAL notes IS LIST().
    LOCAL words IS LIST().
    names:ADD("NOW").
    dvs:ADD(now_dv).
    LOCAL now_tone IS aoso_ui2_bdg_tone(now_dv, TRUE, now_dv).
    tones:ADD(now_tone).
    notes:ADD("---").
    words:ADD(aoso_ui2_bdg_word(now_tone)).

    LOCAL p IS 0.
    UNTIL p >= 4 {
        IF p < picked:LENGTH {
            LOCAL body_name IS picked[p].
            LOCAL dv IS 0.
            LOCAL ok_leg IS TRUE.
            LOCAL margin IS 0.
            LOCAL why_txt IS "".
            IF legs:HASKEY(body_name) {
                LOCAL leg IS legs[body_name].
                SET dv TO aoso_lex_num(leg, "leftover_out", 0).
                SET ok_leg TO aoso_lex_bool(leg, "ok").
                SET margin TO aoso_lex_num(leg, "margin", 0).
                IF NOT ok_leg {
                    SET why_txt TO aoso_lex_str(leg, "fail_step", "FAIL").
                } ELSE {
                    IF aoso_lex_bool(leg, "refueled") {
                        LOCAL delta IS dv - aoso_lex_num(leg, "have_in", 0).
                        IF delta > 1 { SET why_txt TO "+" + ROUND(delta, 0) + " ISRU". }
                    }
                    IF why_txt = "" { SET why_txt TO "MARGIN " + ROUND(margin, 0). }
                }
            }
            LOCAL plus IS "".
            IF legs:HASKEY(body_name) {
                IF aoso_lex_bool(legs[body_name], "refueled") { SET plus TO "+". }
            }
            names:ADD(aoso_ui2_short_body(body_name) + plus).
            dvs:ADD(dv).
            LOCAL tone IS aoso_ui2_bdg_tone(dv, ok_leg, margin).
            tones:ADD(tone).
            notes:ADD(why_txt).
            words:ADD(aoso_ui2_bdg_word(tone)).
        } ELSE {
            names:ADD("").
            dvs:ADD(0).
            tones:ADD("").
            notes:ADD("").
            words:ADD("").
        }
        SET p TO p + 1.
    }
    names:ADD("END").
    dvs:ADD(end_dv).
    LOCAL end_tone IS aoso_ui2_bdg_tone(end_dv, ok_all, end_dv).
    tones:ADD(end_tone).
    IF ok_all { notes:ADD("PLAN"). }
    ELSE { notes:ADD(aoso_crt_fit(weakest, 12)). }
    words:ADD(aoso_ui2_bdg_word(end_tone)).

    LOCAL peak IS 1000.
    LOCAL i IS 0.
    UNTIL i >= dvs:LENGTH {
        IF dvs[i] > peak { SET peak TO dvs[i]. }
        SET i TO i + 1.
    }
    LOCAL warn_i IS -1.
    SET i TO 0.
    UNTIL i >= tones:LENGTH {
        IF warn_i < 0 {
            IF tones[i] = "FAIL" OR tones[i] = "WARN" { SET warn_i TO i. }
        }
        SET i TO i + 1.
    }
    LOCAL warn_x IS 0.
    LOCAL warn_y IS 0.

    SET i TO 0.
    UNTIL i >= 6 {
        LOCAL tone IS tones[i].
        LOCAL rgb IS aoso_ui2_kind_rgb("CAP").
        IF tone = "WARN" { SET rgb TO aoso_ui2_kind_rgb("MARGIN"). }
        IF tone = "FAIL" { SET rgb TO aoso_ui2_kind_rgb("FAIL"). }
        SET AOSO_UI2_BDG_NAMES[i]:STYLE:TEXTCOLOR TO rgb.
        SET AOSO_UI2_BDG_NUMS[i]:STYLE:TEXTCOLOR TO rgb.
        SET AOSO_UI2_BDG_STEP[i]:STYLE:TEXTCOLOR TO rgb.
        SET AOSO_UI2_BDG_WHY[i]:STYLE:TEXTCOLOR TO rgb.
        IF names[i] = "" {
            aoso_ui2_set_text(AOSO_UI2_BDG_NAMES[i], "bdg_n" + i, "").
            aoso_ui2_set_text(AOSO_UI2_BDG_NUMS[i], "bdg_v" + i, "").
            aoso_ui2_set_text(AOSO_UI2_BDG_STEP[i], "bdg_s" + i, "").
            aoso_ui2_set_text(AOSO_UI2_BDG_WHY[i], "bdg_w" + i, "").
            aoso_ui2_set_text(AOSO_UI2_BDG_STATE[i], "bdg_t" + i, "").
            SET AOSO_UI2_BDG_STATE[i]:VISIBLE TO FALSE.
            SET AOSO_UI2_BDG_BARS[i]:VISIBLE TO FALSE.
        } ELSE {
            aoso_ui2_set_text(AOSO_UI2_BDG_NAMES[i], "bdg_n" + i, names[i]).
            aoso_ui2_set_text(AOSO_UI2_BDG_NUMS[i], "bdg_v" + i, ROUND(dvs[i], 0) + "").
            aoso_ui2_set_text(AOSO_UI2_BDG_STEP[i], "bdg_s" + i, names[i]).
            aoso_ui2_set_text(AOSO_UI2_BDG_WHY[i], "bdg_w" + i, aoso_crt_fit(notes[i], 18)).
            SET AOSO_UI2_BDG_STATE[i]:VISIBLE TO TRUE.
            SET AOSO_UI2_BDG_STATE[i]:STYLE:TEXTCOLOR TO rgb.
            aoso_ui2_set_text(AOSO_UI2_BDG_STATE[i], "bdg_t" + i, words[i]).
            LOCAL face_key IS "st" + i.
            LOCAL changed IS TRUE.
            IF AOSO_UI2_METER_SIG:HASKEY(face_key) {
                IF AOSO_UI2_METER_SIG[face_key] = words[i] { SET changed TO FALSE. }
            }
            IF changed {
                SET AOSO_UI2_METER_SIG[face_key] TO words[i].
                aoso_ui2_rte_face(AOSO_UI2_BDG_STATE[i], aoso_ui2_bdg_kind(tone)).
            }
            LOCAL frac IS 0.
            IF peak > 0 { SET frac TO dvs[i] / peak. }
            IF frac < 0 { SET frac TO 0. }
            IF frac > 1 { SET frac TO 1. }
            LOCAL bar_y IS 174 - frac * 86.
            aoso_ui2_bar_place("wf" + i, AOSO_UI2_BDG_BARS[i], 30 + i * 76, bar_y, 58, 8, tone).
            IF i = warn_i {
                SET warn_x TO 30 + i * 76 + 48.
                SET warn_y TO bar_y - 2.
            }
        }
        SET i TO i + 1.
    }
    IF warn_i < 0 {
        SET AOSO_UI2_BDG_WARN:VISIBLE TO FALSE.
    } ELSE {
        aoso_crt_move(AOSO_UI2_BDG_WARN, warn_x, warn_y, 14, 14).
        SET AOSO_UI2_BDG_WARN:VISIBLE TO TRUE.
    }

    LOCAL unu IS aoso_lex_num(res, "unusable_dv", 0).
    LOCAL reserve IS aoso_lex_num(res, "reserve_dv", 0).
    LOCAL land_dv IS aoso_lex_num(res, "land_dv", 0).
    LOCAL ret_dv IS aoso_lex_num(res, "return_dv", 0).
    LOCAL abt_dv IS aoso_lex_num(res, "abort_dv", 0).
    aoso_ui2_set_text(AOSO_UI2_BDG_BIG, "bdg_big", ROUND(now_dv, 0) + " m/s").
    aoso_ui2_set_text(AOSO_UI2_BDG_UNU, "bdg_unu", ROUND(unu, 0) + "").
    aoso_ui2_set_text(AOSO_UI2_BDG_RES, "bdg_res", ROUND(reserve, 0) + "").
    aoso_ui2_set_text(AOSO_UI2_BDG_LAND, "bdg_land", ROUND(land_dv, 0) + "").
    aoso_ui2_set_text(AOSO_UI2_BDG_RET, "bdg_ret", ROUND(ret_dv, 0) + " m/s").
    aoso_ui2_set_text(AOSO_UI2_BDG_ABT, "bdg_abt", ROUND(abt_dv, 0) + " m/s").
    LOCAL span IS now_dv.
    IF unu > span { SET span TO unu. }
    IF reserve > span { SET span TO reserve. }
    IF land_dv > span { SET span TO land_dv. }
    IF ret_dv > span { SET span TO ret_dv. }
    IF abt_dv > span { SET span TO abt_dv. }
    IF span < 1 { SET span TO 1. }
    aoso_ui2_bar_place("muse", AOSO_UI2_BDG_MUSE, 524, 102, MAX(2, ROUND(186 * now_dv / span, 0)), 8, "GO").
    aoso_ui2_bar_place("munu", AOSO_UI2_BDG_MUNU, 648, 122, MAX(2, ROUND(62 * unu / span, 0)), 8, "GO").
    aoso_ui2_bar_place("mres", AOSO_UI2_BDG_MRES, 648, 144, MAX(2, ROUND(62 * reserve / span, 0)), 8, "GO").
    aoso_ui2_bar_place("mlnd", AOSO_UI2_BDG_MLND, 648, 166, MAX(2, ROUND(62 * land_dv / span, 0)), 8, "GO").
    aoso_ui2_bar_place("mret", AOSO_UI2_BDG_MRET, 524, 248, MAX(2, ROUND(186 * ret_dv / span, 0)), 8, "WARN").
    aoso_ui2_bar_place("mabt", AOSO_UI2_BDG_MABT, 524, 288, MAX(2, ROUND(186 * abt_dv / span, 0)), 8, "GO").
    aoso_ui2_set_text(AOSO_UI2_BDG_CLOCK, "bdg_clk", TIME:CLOCK).
    LOCAL phase_txt IS "NOMINAL".
    IF DEFINED AOSO_OBS_PHASE { SET phase_txt TO AOSO_OBS_PHASE. }
    aoso_ui2_set_text(AOSO_UI2_BDG_PHASE, "bdg_ph", aoso_crt_fit(phase_txt, 12)).
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
