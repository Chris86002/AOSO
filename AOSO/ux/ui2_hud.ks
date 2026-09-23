// AOSO/ux/ui2_hud.ks
// Glass CRT. The plate is crt_glass.png (740x400). The pitch ladder is
// baked at (190, 62). Live numbers are pinned into the SPEED / ALT / VS /
// AUTH / GUID / NOTE boxes. Presentation only. Never commands flight.

GLOBAL AOSO_UI2_HUD_GUI IS 0.
GLOBAL AOSO_UI2_HUD_MAIN IS 0.
GLOBAL AOSO_UI2_HUD_PIPPER IS 0.
GLOBAL AOSO_UI2_HUD_PHASE IS 0.
GLOBAL AOSO_UI2_HUD_VS IS 0.
GLOBAL AOSO_UI2_HUD_MODE IS 0.
GLOBAL AOSO_UI2_HUD_HDG IS 0.
GLOBAL AOSO_UI2_HUD_SPD IS 0.
GLOBAL AOSO_UI2_HUD_ALT IS 0.
GLOBAL AOSO_UI2_HUD_ATT IS 0.
GLOBAL AOSO_UI2_HUD_EVENT IS 0.
GLOBAL AOSO_UI2_HUD_BOTTOM IS 0.
GLOBAL AOSO_UI2_HUD_DIAG IS 0.
GLOBAL AOSO_UI2_HUD_DCL IS 0.
GLOBAL AOSO_UI2_HUD_TEST_BUTTON IS 0.
GLOBAL AOSO_UI2_HUD_TEST IS 0.
GLOBAL AOSO_UI2_HUD_VISIBLE IS FALSE.
GLOBAL AOSO_UI2_HUD_DECLUTTER IS FALSE.
GLOBAL AOSO_UI2_HUD_PX IS 180.
GLOBAL AOSO_UI2_HUD_PY IS 120.
GLOBAL AOSO_UI2_HUD_LAST_FAST_RT IS -1.
GLOBAL AOSO_UI2_HUD_LAST_FULL_RT IS -1.
GLOBAL AOSO_UI2_HUD_LAST_LIGHT IS "".

FUNCTION aoso_ui2_hud_mfd {
    aoso_hud_mode_computer().
}

FUNCTION aoso_ui2_hud_toggle_declutter {
    SET AOSO_UI2_HUD_DECLUTTER TO NOT AOSO_UI2_HUD_DECLUTTER.
    IF AOSO_UI2_HUD_DCL:ISTYPE("BUTTON") {
        aoso_crt_key_face(AOSO_UI2_HUD_DCL, "dcl", AOSO_UI2_HUD_DECLUTTER).
    }
}

FUNCTION aoso_ui2_hud_cycle_test {
    SET AOSO_UI2_HUD_TEST TO AOSO_UI2_HUD_TEST + 1.
    IF AOSO_UI2_HUD_TEST > 2 { SET AOSO_UI2_HUD_TEST TO 0. }
    IF AOSO_UI2_HUD_TEST_BUTTON:ISTYPE("BUTTON") {
        aoso_crt_key_face(AOSO_UI2_HUD_TEST_BUTTON, "test", AOSO_UI2_HUD_TEST > 0).
    }
    SET AOSO_UI2_HUD_LAST_FAST_RT TO -1.
    SET AOSO_UI2_HUD_LAST_FULL_RT TO -1.
}

FUNCTION aoso_ui2_hud_recenter {
    IF NOT AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }
    SET AOSO_UI2_HUD_GUI:X TO aoso_config_get("UI2_HUD_X", 990).
    SET AOSO_UI2_HUD_GUI:Y TO aoso_config_get("UI2_HUD_Y", 80).
}

FUNCTION aoso_ui2_hud_dispose {
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") { AOSO_UI2_HUD_GUI:DISPOSE(). }
    SET AOSO_UI2_HUD_GUI TO 0.
    SET AOSO_UI2_HUD_MAIN TO 0.
    SET AOSO_UI2_HUD_PIPPER TO 0.
    SET AOSO_UI2_HUD_PHASE TO 0.
    SET AOSO_UI2_HUD_VS TO 0.
    SET AOSO_UI2_HUD_MODE TO 0.
    SET AOSO_UI2_HUD_HDG TO 0.
    SET AOSO_UI2_HUD_SPD TO 0.
    SET AOSO_UI2_HUD_ALT TO 0.
    SET AOSO_UI2_HUD_ATT TO 0.
    SET AOSO_UI2_HUD_EVENT TO 0.
    SET AOSO_UI2_HUD_BOTTOM TO 0.
    SET AOSO_UI2_HUD_DIAG TO 0.
    SET AOSO_UI2_HUD_DCL TO 0.
    SET AOSO_UI2_HUD_TEST_BUTTON TO 0.
    SET AOSO_UI2_HUD_TEST TO 0.
    SET AOSO_UI2_HUD_PX TO 180.
    SET AOSO_UI2_HUD_PY TO 120.
    SET AOSO_UI2_HUD_VISIBLE TO FALSE.
}

FUNCTION aoso_ui2_hud_pipper_at {
    PARAMETER px.
    PARAMETER py.
    IF NOT AOSO_UI2_HUD_PIPPER:ISTYPE("LABEL") { RETURN. }
    // Bore baked at (190, 62), 360x240. px/py are bore-local, center 180,120.
    aoso_crt_move(AOSO_UI2_HUD_PIPPER, 190 + px - 11, 62 + py - 11, 22, 22).
}

FUNCTION aoso_ui2_hud_phase_at {
    PARAMETER code.
    IF NOT AOSO_UI2_HUD_PHASE:ISTYPE("LABEL") { RETURN. }
    LOCAL px IS 268.
    IF code = "ASC" OR code = "HLD" { SET px TO 210. }
    IF code = "ORB" { SET px TO 268. }
    IF code = "XFR" { SET px TO 326. }
    IF code = "RNDZ" { SET px TO 390. }
    IF code = "DSC" { SET px TO 468. }
    IF code = "LND" { SET px TO 536. }
    aoso_crt_move(AOSO_UI2_HUD_PHASE, px, 54, 18, 4).
    SET AOSO_UI2_HUD_PHASE:VISIBLE TO TRUE.
}

FUNCTION aoso_ui2_hud_build {
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }

    LOCAL g IS GUI(800).
    SET g:X TO aoso_config_get("UI2_HUD_X", 80).
    SET g:Y TO aoso_config_get("UI2_HUD_Y", 40).
    SET g:DRAGGABLE TO TRUE.
    SET g:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "crt_black.png".
    SET g:STYLE:PADDING:LEFT TO 6.
    SET g:STYLE:PADDING:RIGHT TO 6.
    SET g:STYLE:PADDING:BOTTOM TO 4.
    SET g:SKIN:LABEL:TEXTCOLOR TO RGB(0.72, 1, 0.62).
    SET g:SKIN:LABEL:FONTSIZE TO 16.
    SET AOSO_UI2_HUD_GUI TO g.

    LOCAL root IS g:ADDVLAYOUT().
    aoso_crt_zero(root).
    SET AOSO_UI2_HUD_MAIN TO root:ADDVLAYOUT().
    aoso_crt_zero(AOSO_UI2_HUD_MAIN).
    SET AOSO_UI2_HUD_MAIN:STYLE:HSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_MAIN:STYLE:VSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_MAIN:STYLE:WIDTH TO 740.
    SET AOSO_UI2_HUD_MAIN:STYLE:HEIGHT TO 400.
    SET AOSO_UI2_HUD_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "crt_glass.png".

    SET AOSO_UI2_HUD_PIPPER TO aoso_crt_bug(AOSO_UI2_HUD_MAIN, AOSO_UI2_ASSET_ROOT + "diamond.png", 22).
    SET AOSO_UI2_HUD_PIPPER:VISIBLE TO TRUE.
    aoso_ui2_hud_pipper_at(180, 120).
    SET AOSO_UI2_HUD_PHASE TO aoso_crt_bug(AOSO_UI2_HUD_MAIN, AOSO_UI2_ASSET_ROOT + "phase_mark.png", 18, 4).
    aoso_ui2_hud_phase_at("ORB").

    SET AOSO_UI2_HUD_SPD TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 32, 150, 130, 22).
    SET AOSO_UI2_HUD_HDG TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 32, 188, 130, 14).
    SET AOSO_UI2_HUD_ALT TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 578, 150, 130, 22).
    SET AOSO_UI2_HUD_VS TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 28, 348, 130, 16).
    SET AOSO_UI2_HUD_BOTTOM TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 190, 348, 140, 16).
    SET AOSO_UI2_HUD_MODE TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 350, 348, 140, 16).
    SET AOSO_UI2_HUD_EVENT TO aoso_crt_label(AOSO_UI2_HUD_MAIN, 530, 348, 180, 14).
    SET AOSO_UI2_HUD_ATT TO AOSO_UI2_HUD_EVENT.
    SET AOSO_UI2_HUD_DIAG TO AOSO_UI2_HUD_EVENT.

    LOCAL keys IS root:ADDHLAYOUT().
    SET keys:STYLE:MARGIN:TOP TO 4.
    SET keys:STYLE:MARGIN:LEFT TO 8.
    SET AOSO_UI2_HUD_DCL TO keys:ADDBUTTON("").
    SET AOSO_UI2_HUD_DCL:ONCLICK TO aoso_ui2_hud_toggle_declutter@.
    aoso_crt_key_face(AOSO_UI2_HUD_DCL, "dcl", FALSE).
    LOCAL b_rec IS keys:ADDBUTTON("").
    SET b_rec:ONCLICK TO aoso_ui2_hud_recenter@.
    aoso_crt_key_face(b_rec, "rec", FALSE).
    SET AOSO_UI2_HUD_TEST_BUTTON TO keys:ADDBUTTON("").
    SET AOSO_UI2_HUD_TEST_BUTTON:ONCLICK TO aoso_ui2_hud_cycle_test@.
    aoso_crt_key_face(AOSO_UI2_HUD_TEST_BUTTON, "test", FALSE).
    LOCAL b_dump IS keys:ADDBUTTON("").
    SET b_dump:ONCLICK TO aoso_hud_debug_dump@.
    aoso_crt_key_face(b_dump, "dump", FALSE).
    LOCAL b_mfd IS keys:ADDBUTTON("").
    SET b_mfd:ONCLICK TO aoso_ui2_hud_mfd@.
    aoso_crt_key_face(b_mfd, "mfd", FALSE).

    g:HIDE().
}

FUNCTION aoso_ui2_hud_phase_code {
    IF aoso_launch_blocked() { RETURN "HLD". }
    LOCAL ctx IS AOSO_HUD_CTX.
    IF ctx = "LAUNCH" { RETURN "ASC". }
    IF ctx = "TRANSFER" { RETURN "XFR". }
    IF ctx = "BURN" { RETURN "XFR". }
    IF ctx = "DOCK" { RETURN "RNDZ". }
    IF ctx = "LANDING" { RETURN "LND". }
    IF ctx = "RETURN" { RETURN "DSC". }
    RETURN "ORB".
}

FUNCTION aoso_ui2_hud_show {
    IF NOT aoso_config_get("UI2_ENABLED", TRUE) { RETURN. }
    aoso_ui2_hud_build().
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") {
        AOSO_UI2_HUD_GUI:SHOW().
        SET AOSO_UI2_HUD_VISIBLE TO TRUE.
    }
}

FUNCTION aoso_ui2_hud_hide {
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") { AOSO_UI2_HUD_GUI:HIDE(). }
    SET AOSO_UI2_HUD_VISIBLE TO FALSE.
}

FUNCTION aoso_ui2_hud_pipper_fast {
    IF NOT AOSO_UI2_HUD_VISIBLE { RETURN. }
    IF NOT AOSO_UI2_HUD_PIPPER:ISTYPE("LABEL") { RETURN. }

    IF AOSO_UI2_HUD_TEST > 0 {
        SET AOSO_UI2_HUD_PX TO 180.
        SET AOSO_UI2_HUD_PY TO 120.
        IF AOSO_UI2_HUD_TEST = 2 {
            SET AOSO_UI2_HUD_PX TO 314.
            SET AOSO_UI2_HUD_PY TO 35.
        }
        aoso_ui2_hud_pipper_at(AOSO_UI2_HUD_PX, AOSO_UI2_HUD_PY).
        RETURN.
    }

    LOCAL target IS aoso_ui2_steer_target_vector().
    IF target:MAG < 0.001 { RETURN. }
    LOCAL u IS target:NORMALIZED.
    LOCAL hx IS VDOT(u, SHIP:FACING:STARVECTOR).
    LOCAL vy IS VDOT(u, SHIP:FACING:TOPVECTOR).
    LOCAL want_x IS 180 + aoso_ui2_clamp(hx, -0.75, 0.75) * 135.
    LOCAL want_y IS 120 - aoso_ui2_clamp(vy, -0.75, 0.75) * 85.
    LOCAL smooth IS aoso_config_get("UI2_MARKER_SMOOTH", 0.28).
    IF smooth < 0.05 { SET smooth TO 0.05. }
    IF smooth > 1 { SET smooth TO 1. }
    SET AOSO_UI2_HUD_PX TO AOSO_UI2_HUD_PX + smooth * (want_x - AOSO_UI2_HUD_PX).
    SET AOSO_UI2_HUD_PY TO AOSO_UI2_HUD_PY + smooth * (want_y - AOSO_UI2_HUD_PY).
    LOCAL bug_key IS ROUND(AOSO_UI2_HUD_PX, 0) + "," + ROUND(AOSO_UI2_HUD_PY, 0).
    LOCAL bug_moved IS TRUE.
    IF AOSO_UI2_TXT:HASKEY("hud_bug") {
        IF AOSO_UI2_TXT["hud_bug"] = bug_key { SET bug_moved TO FALSE. }
    }
    IF bug_moved {
        SET AOSO_UI2_TXT["hud_bug"] TO bug_key.
        aoso_ui2_hud_pipper_at(AOSO_UI2_HUD_PX, AOSO_UI2_HUD_PY).
    }
}

FUNCTION aoso_ui2_hud_fast {
    IF NOT AOSO_UI2_HUD_VISIBLE { RETURN. }

    LOCAL fast_rt IS KUNIVERSE:REALTIME.
    LOCAL fast_gap IS 0.05.
    IF WARP > 0 { SET fast_gap TO 0.20. }
    IF AOSO_UI2_HUD_LAST_FAST_RT >= 0 {
        IF fast_rt - AOSO_UI2_HUD_LAST_FAST_RT < fast_gap { RETURN. }
    }
    SET AOSO_UI2_HUD_LAST_FAST_RT TO fast_rt.

    aoso_ui2_hud_pipper_fast().
    IF AOSO_UI2_HUD_TEST > 0 {
        aoso_ui2_set_text(AOSO_UI2_HUD_HDG, "hud_hdg", "HDG 090").
        aoso_ui2_set_text(AOSO_UI2_HUD_VS, "hud_vs", "+75").
        aoso_ui2_set_text(AOSO_UI2_HUD_SPD, "hud_spd", "250").
        aoso_ui2_set_text(AOSO_UI2_HUD_ALT, "hud_alt", "10.0km").
        RETURN.
    }

    LOCAL f IS AOSO_HUD_DATA["flight"].
    IF NOT f:HASKEY("hdg") { RETURN. }
    aoso_ui2_set_text(AOSO_UI2_HUD_HDG, "hud_hdg", "HDG " + ROUND(f["hdg"], 0)).
    aoso_ui2_set_text(AOSO_UI2_HUD_VS, "hud_vs", ROUND(aoso_lex_num(f, "vs", 0), 0) + "").
    LOCAL vel IS aoso_lex_num(f, "orb", 0).
    IF aoso_lex_bool(f, "in_atm") { SET vel TO aoso_lex_num(f, "srf", vel). }
    aoso_ui2_set_text(AOSO_UI2_HUD_SPD, "hud_spd", ROUND(vel, 0) + "").

    LOCAL alt_txt IS "".
    IF AOSO_HUD_CTX = "LANDING" {
        SET alt_txt TO ROUND(aoso_lex_num(AOSO_HUD_DATA["landing"], "radar", 0), 0) + "m".
    } ELSE {
        SET alt_txt TO aoso_hud_km(aoso_lex_num(f, "alt", 0)).
    }
    aoso_ui2_set_text(AOSO_UI2_HUD_ALT, "hud_alt", alt_txt).
}

FUNCTION aoso_ui2_hud_update {
    IF NOT AOSO_UI2_HUD_VISIBLE { RETURN. }
    IF NOT AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }

    LOCAL full_rt IS KUNIVERSE:REALTIME.
    LOCAL full_gap IS 0.10.
    IF WARP > 0 { SET full_gap TO 0.25. }
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 { SET full_gap TO MAX(full_gap, 0.20). }
        IF AOSO_CPU_LEVEL >= 3 { SET full_gap TO MAX(full_gap, 0.35). }
    }
    IF AOSO_UI2_HUD_LAST_FULL_RT >= 0 {
        IF full_rt - AOSO_UI2_HUD_LAST_FULL_RT < full_gap { RETURN. }
    }
    SET AOSO_UI2_HUD_LAST_FULL_RT TO full_rt.
    aoso_ui2_hud_fast().

    IF AOSO_UI2_HUD_TEST > 0 {
        aoso_ui2_hud_phase_at("ASC").
        aoso_ui2_set_text(AOSO_UI2_HUD_BOTTOM, "hud_auth", "TEST").
        aoso_ui2_set_text(AOSO_UI2_HUD_MODE, "hud_guid", "ASC").
        aoso_ui2_set_text(AOSO_UI2_HUD_EVENT, "hud_note", "NO COMMANDS").
        RETURN.
    }

    LOCAL f IS AOSO_HUD_DATA["flight"].
    IF NOT f:HASKEY("pitch") { RETURN. }
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL phase IS aoso_ui2_hud_phase_code().
    aoso_ui2_hud_phase_at(phase).

    LOCAL auth_who IS aoso_auth_owner("STEERING").
    IF auth_who = "" { SET auth_who TO "OPEN". }
    aoso_ui2_set_text(AOSO_UI2_HUD_BOTTOM, "hud_auth", aoso_crt_fit(auth_who, 12)).
    aoso_ui2_set_text(AOSO_UI2_HUD_MODE, "hud_guid", phase).

    LOCAL cue IS "".
    IF aoso_lex_bool(o, "burning") {
        SET cue TO "BURN " + ROUND(aoso_lex_num(o, "burn_left", 0), 0).
    } ELSE {
        IF aoso_lex_bool(o, "node") {
            SET cue TO "T-" + aoso_hud_eta(aoso_lex_num(o, "node_eta", 0)).
        } ELSE {
            IF aoso_lex_bool(f, "in_atm") {
                SET cue TO "P " + ROUND(f["pitch"], 0) + " AoA " + ROUND(aoso_lex_num(f, "aoa", 0), 0).
            } ELSE {
                SET cue TO "P " + ROUND(f["pitch"], 0).
            }
        }
    }
    IF aoso_lex_str(sys, "worst", "") = "FAIL" { SET cue TO "WARNING". }
    IF AOSO_UI2_HUD_DECLUTTER { SET cue TO phase. }
    aoso_ui2_set_text(AOSO_UI2_HUD_EVENT, "hud_note", aoso_crt_fit(cue, 16)).
    SET AOSO_UI2_HUD_HDG:VISIBLE TO NOT AOSO_UI2_HUD_DECLUTTER.

    LOCAL goal IS aoso_lex_str(m, "goal", "").
    IF goal = "" { SET goal TO aoso_lex_str(m, "hop", ""). }
    IF goal <> "" {
        IF NOT AOSO_UI2_HUD_DECLUTTER {
            aoso_ui2_set_text(AOSO_UI2_HUD_MODE, "hud_guid", aoso_crt_fit(goal, 12)).
        }
    }
}
