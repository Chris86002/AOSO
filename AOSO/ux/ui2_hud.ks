// AOSO/ux/ui2_hud.ks
// OPS-style flight HUD. All values come from AOSO telemetry; test mode only
// paints known geometry and never changes flight state.
//
// Separate lightweight HUD inspired by the interaction patterns of high-end
// kOS avionics: image-backed flight director, movable guidance bug, vertical
// speed tape, burn/phase annunciation, decluttering, day/night brightness and
// a one-click return to the full MFD. Presentation only; never commands flight.

GLOBAL AOSO_UI2_HUD_GUI IS 0.
GLOBAL AOSO_UI2_HUD_MAIN IS 0.
GLOBAL AOSO_UI2_HUD_PIPPER IS 0.
GLOBAL AOSO_UI2_HUD_VS IS 0.
GLOBAL AOSO_UI2_HUD_BURN IS 0.
GLOBAL AOSO_UI2_HUD_MODE IS 0.
GLOBAL AOSO_UI2_HUD_HDG IS 0.
GLOBAL AOSO_UI2_HUD_SPD IS 0.
GLOBAL AOSO_UI2_HUD_ALT IS 0.
GLOBAL AOSO_UI2_HUD_ATT IS 0.
GLOBAL AOSO_UI2_HUD_EVENT IS 0.
GLOBAL AOSO_UI2_HUD_BOTTOM IS 0.
GLOBAL AOSO_UI2_HUD_DIAG IS 0.
GLOBAL AOSO_UI2_HUD_STRIP IS 0.
GLOBAL AOSO_UI2_HUD_TEST_BUTTON IS 0.
GLOBAL AOSO_UI2_HUD_TEST IS 0.
GLOBAL AOSO_UI2_HUD_VISIBLE IS FALSE.
GLOBAL AOSO_UI2_HUD_DECLUTTER IS FALSE.
GLOBAL AOSO_UI2_HUD_PX IS 180.
GLOBAL AOSO_UI2_HUD_PY IS 120.
GLOBAL AOSO_UI2_HUD_LAST_LIGHT IS "".
GLOBAL AOSO_UI2_HUD_LAST_FAST_RT IS -1.
GLOBAL AOSO_UI2_HUD_LAST_FULL_RT IS -1.

FUNCTION aoso_ui2_hud_mfd {
    aoso_hud_mode_computer().
}

FUNCTION aoso_ui2_hud_toggle_declutter {
    SET AOSO_UI2_HUD_DECLUTTER TO NOT AOSO_UI2_HUD_DECLUTTER.
}

FUNCTION aoso_ui2_hud_cycle_test {
    SET AOSO_UI2_HUD_TEST TO AOSO_UI2_HUD_TEST + 1.
    IF AOSO_UI2_HUD_TEST > 2 { SET AOSO_UI2_HUD_TEST TO 0. }
    IF AOSO_UI2_HUD_TEST = 0 { SET AOSO_UI2_HUD_TEST_BUTTON:TEXT TO "TEST". }
    IF AOSO_UI2_HUD_TEST = 1 { SET AOSO_UI2_HUD_TEST_BUTTON:TEXT TO "CTR". }
    IF AOSO_UI2_HUD_TEST = 2 { SET AOSO_UI2_HUD_TEST_BUTTON:TEXT TO "EDGE". }
    SET AOSO_UI2_HUD_LAST_FAST_RT TO -1.
    SET AOSO_UI2_HUD_LAST_FULL_RT TO -1.
}

FUNCTION aoso_ui2_hud_recenter {
    IF NOT AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }
    // Safe 1440p-friendly default. The HUD remains draggable for any
    // resolution/aspect ratio and REC always restores a known-good position.
    SET AOSO_UI2_HUD_GUI:X TO aoso_config_get("UI2_HUD_X", 990).
    SET AOSO_UI2_HUD_GUI:Y TO aoso_config_get("UI2_HUD_Y", 525).
}

FUNCTION aoso_ui2_hud_dispose {
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") { AOSO_UI2_HUD_GUI:DISPOSE(). }
    SET AOSO_UI2_HUD_GUI TO 0.
    SET AOSO_UI2_HUD_MAIN TO 0.
    SET AOSO_UI2_HUD_PIPPER TO 0.
    SET AOSO_UI2_HUD_VS TO 0.
    SET AOSO_UI2_HUD_BURN TO 0.
    SET AOSO_UI2_HUD_MODE TO 0.
    SET AOSO_UI2_HUD_HDG TO 0.
    SET AOSO_UI2_HUD_SPD TO 0.
    SET AOSO_UI2_HUD_ALT TO 0.
    SET AOSO_UI2_HUD_ATT TO 0.
    SET AOSO_UI2_HUD_EVENT TO 0.
    SET AOSO_UI2_HUD_BOTTOM TO 0.
    SET AOSO_UI2_HUD_DIAG TO 0.
    SET AOSO_UI2_HUD_STRIP TO 0.
    SET AOSO_UI2_HUD_TEST_BUTTON TO 0.
    SET AOSO_UI2_HUD_TEST TO 0.
    SET AOSO_UI2_HUD_PX TO 180.
    SET AOSO_UI2_HUD_PY TO 120.
    SET AOSO_UI2_HUD_VISIBLE TO FALSE.
}

FUNCTION aoso_ui2_hud_build {
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }

    LOCAL g IS GUI(580, 390).
    SET g:X TO aoso_config_get("UI2_HUD_X", 990).
    SET g:Y TO aoso_config_get("UI2_HUD_Y", 525).
    SET g:DRAGGABLE TO TRUE.
    SET g:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "hud_clear.png".
    SET g:SKIN:LABEL:TEXTCOLOR TO RGB(0.28, 1.0, 0.36).
    SET g:SKIN:BUTTON:BG TO AOSO_UI2_ASSET_ROOT + "button_off.png".
    SET g:SKIN:BUTTON:HOVER:BG TO AOSO_UI2_ASSET_ROOT + "button_hover.png".
    SET g:SKIN:BUTTON:FOCUSED:BG TO AOSO_UI2_ASSET_ROOT + "button_hover.png".
    SET g:SKIN:BUTTON:ACTIVE:BG TO AOSO_UI2_ASSET_ROOT + "button_on.png".
    SET g:SKIN:VERTICALSLIDER:BG TO AOSO_UI2_ASSET_ROOT + "vscale.png".
    SET g:SKIN:VERTICALSLIDERTHUMB:BG TO AOSO_UI2_ASSET_ROOT + "diamond.png".
    SET g:SKIN:VERTICALSLIDERTHUMB:WIDTH TO 18.
    SET g:SKIN:VERTICALSLIDERTHUMB:HEIGHT TO 14.
    SET g:SKIN:HORIZONTALSLIDER:BG TO AOSO_UI2_ASSET_ROOT + "hscale.png".
    SET g:SKIN:HORIZONTALSLIDERTHUMB:BG TO AOSO_UI2_ASSET_ROOT + "diamond.png".
    SET g:SKIN:HORIZONTALSLIDERTHUMB:WIDTH TO 16.
    SET g:SKIN:HORIZONTALSLIDERTHUMB:HEIGHT TO 16.
    SET AOSO_UI2_HUD_GUI TO g.

    LOCAL top IS g:ADDHLAYOUT().
    SET top:STYLE:WIDTH TO 560.
    SET AOSO_UI2_HUD_MODE TO top:ADDLABEL("<b>AOSO OPS HUD / LIVE</b>").
    SET AOSO_UI2_HUD_MODE:STYLE:WIDTH TO 180.
    SET AOSO_UI2_HUD_HDG TO top:ADDLABEL("HDG ---").
    SET AOSO_UI2_HUD_HDG:STYLE:WIDTH TO 65.
    SET AOSO_UI2_HUD_HDG:STYLE:ALIGN TO "right".
    LOCAL b_declutter IS top:ADDBUTTON("DCL").
    SET b_declutter:STYLE:WIDTH TO 42.
    SET b_declutter:ONCLICK TO aoso_ui2_hud_toggle_declutter@.
    LOCAL b_rec IS top:ADDBUTTON("REC").
    SET b_rec:STYLE:WIDTH TO 42.
    SET b_rec:ONCLICK TO aoso_ui2_hud_recenter@.
    SET AOSO_UI2_HUD_TEST_BUTTON TO top:ADDBUTTON("TEST").
    SET AOSO_UI2_HUD_TEST_BUTTON:STYLE:WIDTH TO 43.
    SET AOSO_UI2_HUD_TEST_BUTTON:ONCLICK TO aoso_ui2_hud_cycle_test@.
    LOCAL b_dump IS top:ADDBUTTON("DUMP").
    SET b_dump:STYLE:WIDTH TO 50.
    SET b_dump:ONCLICK TO aoso_hud_debug_dump@.
    LOCAL b_mfd IS top:ADDBUTTON("MFD").
    SET b_mfd:STYLE:WIDTH TO 42.
    SET b_mfd:ONCLICK TO aoso_ui2_hud_mfd@.

    SET AOSO_UI2_HUD_STRIP TO g:ADDLABEL("ASC  ORB  XFR  RNDZ  DSC  LND").
    SET AOSO_UI2_HUD_STRIP:STYLE:WIDTH TO 560.
    SET AOSO_UI2_HUD_STRIP:STYLE:ALIGN TO "center".

    SET AOSO_UI2_HUD_ATT TO g:ADDLABEL("PITCH ---   ROLL ---   AoA ---").
    SET AOSO_UI2_HUD_ATT:STYLE:WIDTH TO 560.
    SET AOSO_UI2_HUD_ATT:STYLE:ALIGN TO "center".

    LOCAL row IS g:ADDHLAYOUT().
    SET row:STYLE:WIDTH TO 560.
    SET row:STYLE:HEIGHT TO 240.

    LOCAL speed_bank IS row:ADDVBOX().
    SET speed_bank:STYLE:WIDTH TO 80.
    SET speed_bank:STYLE:HEIGHT TO 240.
    LOCAL speed_heading IS speed_bank:ADDLABEL("SPEED m/s").
    SET speed_heading:STYLE:WIDTH TO 78.
    SET AOSO_UI2_HUD_SPD TO speed_bank:ADDLABEL("---").
    SET AOSO_UI2_HUD_SPD:STYLE:WIDTH TO 78.
    SET AOSO_UI2_HUD_SPD:STYLE:ALIGN TO "center".

    SET AOSO_UI2_HUD_MAIN TO row:ADDHBOX().
    SET AOSO_UI2_HUD_MAIN:STYLE:WIDTH TO 360.
    SET AOSO_UI2_HUD_MAIN:STYLE:HEIGHT TO 240.
    SET AOSO_UI2_HUD_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_HUD_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "hud_overlay.png".

    SET AOSO_UI2_HUD_PIPPER TO aoso_ui2_marker(
        AOSO_UI2_HUD_MAIN,
        AOSO_UI2_ASSET_ROOT + "diamond.png",
        22).
    SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:H TO AOSO_UI2_HUD_PX.
    SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:V TO AOSO_UI2_HUD_PY.

    LOCAL alt_bank IS row:ADDVBOX().
    SET alt_bank:STYLE:WIDTH TO 80.
    SET alt_bank:STYLE:HEIGHT TO 240.
    LOCAL alt_heading IS alt_bank:ADDLABEL("ALTITUDE").
    SET alt_heading:STYLE:WIDTH TO 78.
    SET AOSO_UI2_HUD_ALT TO alt_bank:ADDLABEL("---").
    SET AOSO_UI2_HUD_ALT:STYLE:WIDTH TO 78.
    SET AOSO_UI2_HUD_ALT:STYLE:ALIGN TO "center".

    SET AOSO_UI2_HUD_VS TO row:ADDVSLIDER(0, -250, 250).
    SET AOSO_UI2_HUD_VS:STYLE:WIDTH TO 20.
    SET AOSO_UI2_HUD_VS:STYLE:HEIGHT TO 230.
    SET AOSO_UI2_HUD_VS:STYLE:VSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_VS:STYLE:HSTRETCH TO FALSE.

    SET AOSO_UI2_HUD_EVENT TO g:ADDLABEL("STANDBY").
    SET AOSO_UI2_HUD_EVENT:STYLE:WIDTH TO 560.
    SET AOSO_UI2_HUD_EVENT:STYLE:ALIGN TO "center".

    LOCAL burnrow IS g:ADDHLAYOUT().
    SET burnrow:STYLE:WIDTH TO 560.
    SET burnrow:STYLE:HEIGHT TO 22.
    LOCAL burnlabel IS burnrow:ADDLABEL("dV / PROP").
    SET burnlabel:STYLE:WIDTH TO 80.
    SET AOSO_UI2_HUD_BURN TO burnrow:ADDHSLIDER(0, 0, 1).
    SET AOSO_UI2_HUD_BURN:STYLE:WIDTH TO 335.
    SET AOSO_UI2_HUD_BURN:STYLE:HEIGHT TO 20.
    SET AOSO_UI2_HUD_BURN:STYLE:HSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_BURN:STYLE:VSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_BOTTOM TO burnrow:ADDLABEL("").
    SET AOSO_UI2_HUD_BOTTOM:STYLE:WIDTH TO 130.
    SET AOSO_UI2_HUD_BOTTOM:STYLE:ALIGN TO "right".

    SET AOSO_UI2_HUD_DIAG TO g:ADDLABEL("HUD LIVE / waiting for telemetry").
    SET AOSO_UI2_HUD_DIAG:STYLE:WIDTH TO 560.
    SET AOSO_UI2_HUD_DIAG:STYLE:ALIGN TO "center".

    g:HIDE().
}

FUNCTION aoso_ui2_hud_phase_code {
    LOCAL ctx IS AOSO_HUD_CTX.
    IF ctx = "LAUNCH" { RETURN "ASC". }
    IF ctx = "TRANSFER" { RETURN "XFR". }
    IF ctx = "BURN" { RETURN "XFR". }
    IF ctx = "DOCK" { RETURN "RNDZ". }
    IF ctx = "LANDING" { RETURN "LND". }
    IF ctx = "RETURN" { RETURN "DSC". }
    RETURN "ORB".
}

FUNCTION aoso_ui2_hud_strip_txt {
    LOCAL cur IS aoso_ui2_hud_phase_code().
    LOCAL names IS LIST("ASC", "ORB", "XFR", "RNDZ", "DSC", "LND").
    LOCAL out IS "".
    LOCAL i IS 0.
    UNTIL i >= names:LENGTH {
        IF out <> "" { SET out TO out + "  ". }
        IF names[i] = cur {
            SET out TO out + "<b><color=#50FF96>" + names[i] + "</color></b>".
        } ELSE {
            SET out TO out + "<color=#3d6b4a>" + names[i] + "</color>".
        }
        SET i TO i + 1.
    }
    RETURN out.
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

FUNCTION aoso_ui2_hud_is_night {
    LOCAL sun_vec IS SUN:POSITION - SHIP:POSITION.
    IF sun_vec:MAG < 1 { RETURN FALSE. }
    RETURN VDOT(sun_vec:NORMALIZED, SHIP:UP:VECTOR) < -0.08.
}

FUNCTION aoso_ui2_hud_brightness {
    IF NOT AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }
    LOCAL light_mode IS "DAY".
    IF aoso_ui2_hud_is_night() { SET light_mode TO "NIGHT". }
    IF light_mode = AOSO_UI2_HUD_LAST_LIGHT { RETURN. }
    SET AOSO_UI2_HUD_LAST_LIGHT TO light_mode.
    IF light_mode = "NIGHT" {
        SET AOSO_UI2_HUD_GUI:SKIN:LABEL:TEXTCOLOR TO RGB(0.22, 0.82, 0.44).
    } ELSE {
        SET AOSO_UI2_HUD_GUI:SKIN:LABEL:TEXTCOLOR TO RGB(0.42, 1.0, 0.68).
    }
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
        SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:H TO AOSO_UI2_HUD_PX.
        SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:V TO AOSO_UI2_HUD_PY.
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
    SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:H TO AOSO_UI2_HUD_PX.
    SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:V TO AOSO_UI2_HUD_PY.
}

FUNCTION aoso_ui2_hud_fast {
    IF NOT AOSO_UI2_HUD_VISIBLE { RETURN. }

    LOCAL fast_rt IS KUNIVERSE:REALTIME.
    LOCAL fast_gap IS 0.05.
    IF WARP > 0 { SET fast_gap TO 0.20. }
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 2 { SET fast_gap TO MAX(fast_gap, 0.10). }
        IF AOSO_CPU_LEVEL >= 3 { SET fast_gap TO MAX(fast_gap, 0.25). }
    }
    IF AOSO_UI2_HUD_LAST_FAST_RT >= 0 {
        IF fast_rt - AOSO_UI2_HUD_LAST_FAST_RT < fast_gap { RETURN. }
    }
    SET AOSO_UI2_HUD_LAST_FAST_RT TO fast_rt.

    aoso_ui2_hud_pipper_fast().
    IF AOSO_UI2_HUD_TEST > 0 {
        SET AOSO_UI2_HUD_HDG:TEXT TO "HDG 090".
        SET AOSO_UI2_HUD_VS:VALUE TO 75.
        SET AOSO_UI2_HUD_SPD:TEXT TO "250" + CHAR(10) + "VS +75".
        SET AOSO_UI2_HUD_ALT:TEXT TO "10.0km" + CHAR(10) + "AP 80km".
        RETURN.
    }

    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    SET AOSO_UI2_HUD_HDG:TEXT TO "HDG " + ROUND(f["hdg"], 0).
    SET AOSO_UI2_HUD_VS:VALUE TO aoso_ui2_clamp(f["vs"], -250, 250).

    LOCAL vel IS f["orb"].
    IF f["in_atm"] { SET vel TO f["srf"]. }
    SET AOSO_UI2_HUD_SPD:TEXT TO "<size=18>" + ROUND(vel, 0) + "</size>" + CHAR(10) + "VS " + ROUND(f["vs"], 0).

    LOCAL alt_txt IS aoso_hud_km(f["alt"]).
    IF AOSO_HUD_CTX = "LANDING" {
        SET alt_txt TO ROUND(AOSO_HUD_DATA["landing"]["radar"], 0) + "m".
    }
    SET AOSO_UI2_HUD_ALT:TEXT TO "<size=18>" + alt_txt + "</size>" + CHAR(10) + "AP " + aoso_hud_km(o["ap"]).
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

    aoso_ui2_hud_brightness().
    aoso_ui2_hud_fast().

    IF AOSO_UI2_HUD_TEST > 0 {
        SET AOSO_UI2_HUD_MODE:TEXT TO "<b>AOSO / GEOM TEST</b>".
        SET AOSO_UI2_HUD_ATT:TEXT TO "PITCH +12.0   ROLL -08.0   AoA +03.0".
        SET AOSO_UI2_HUD_ATT:VISIBLE TO TRUE.
        SET AOSO_UI2_HUD_EVENT:TEXT TO "TEST ONLY - NO FLIGHT COMMANDS".
        SET AOSO_UI2_HUD_BURN:VALUE TO 0.5.
        SET AOSO_UI2_HUD_BOTTOM:TEXT TO "50% TEST".
        SET AOSO_UI2_HUD_DIAG:TEXT TO "ART 360x240  BUG " + ROUND(AOSO_UI2_HUD_PX, 0) + "," + ROUND(AOSO_UI2_HUD_PY, 0) + "  press TEST to advance".
        IF AOSO_UI2_HUD_STRIP:ISTYPE("LABEL") { SET AOSO_UI2_HUD_STRIP:TEXT TO aoso_ui2_hud_strip_txt(). }
        RETURN.
    }

    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].

    LOCAL phase IS AOSO_HUD_CTX.
    IF phase = "IDLE" { SET phase TO f["status"]. }
    SET AOSO_UI2_HUD_MODE:TEXT TO "<b>AOSO  " + aoso_ui2_hud_phase_code() + "</b>  " + f["doing"].
    IF AOSO_UI2_HUD_STRIP:ISTYPE("LABEL") { SET AOSO_UI2_HUD_STRIP:TEXT TO aoso_ui2_hud_strip_txt(). }
    LOCAL att_txt IS "P " + ROUND(f["pitch"], 1) + "°   R " + ROUND(f["roll"], 1) + "°".
    IF f["in_atm"] { SET att_txt TO att_txt + "   AoA " + ROUND(f["aoa"], 1) + "°". }
    IF AOSO_HUD_DATA:HASKEY("traj") {
        IF AOSO_HUD_DATA["traj"]["has_cmd"] {
            SET att_txt TO att_txt + "   PCMD " + ROUND(AOSO_HUD_DATA["traj"]["pitch_cmd"], 0) + "°".
        }
    }
    SET AOSO_UI2_HUD_ATT:TEXT TO att_txt.

    LOCAL event_txt IS "".
    IF o["burning"] {
        SET event_txt TO aoso_ui2_color_state("SAFE", "BURN EXECUTION").
    } ELSE {
        IF o["node"] {
            SET event_txt TO "NODE T-" + aoso_hud_eta(o["node_eta"]).
        } ELSE {
            IF o["patch"] <> "" {
                SET event_txt TO o["patch"] + " SOI T-" + aoso_hud_eta(o["patch_eta"]).
            }
        }
    }
    IF sys["worst"] = "FAIL" { SET event_txt TO aoso_ui2_color_state("FAIL", "MASTER WARNING"). }
    ELSE {
        IF sys["worst"] = "DEG" {
            IF event_txt = "" { SET event_txt TO aoso_ui2_color_state("WARN", "CAUTION"). }
        }
    }
    SET AOSO_UI2_HUD_EVENT:TEXT TO event_txt.

    LOCAL progress IS 0.
    IF o["node"] {
        LOCAL total IS o["node_dv"].
        LOCAL left IS total.
        IF o["burning"] { SET left TO o["burn_left"]. }
        IF total > 0.01 { SET progress TO 1 - aoso_ui2_clamp(left / total, 0, 1). }
        SET AOSO_UI2_HUD_BOTTOM:TEXT TO ROUND(left, 0) + "m/s".
    } ELSE {
        LOCAL pct IS MAX(AOSO_HUD_DATA["res"]["lf"], AOSO_HUD_DATA["res"]["ox"]) / 100.
        SET progress TO aoso_ui2_clamp(pct, 0, 1).
        SET AOSO_UI2_HUD_BOTTOM:TEXT TO "PROP " + ROUND(pct * 100, 0) + "%".
    }
    SET AOSO_UI2_HUD_BURN:VALUE TO progress.
    LOCAL auth_who IS aoso_auth_owner("STEERING").
    IF auth_who = "" { SET auth_who TO "OPEN". }
    SET AOSO_UI2_HUD_DIAG:TEXT TO "AUTH " + auth_who + "  STEER " + sys["steer_mode"] +
        "  GUID " + phase + "  BUG " + ROUND(AOSO_UI2_HUD_PX, 0) + "," + ROUND(AOSO_UI2_HUD_PY, 0).

    // Automatic declutter in high-workload terminal phases; the operator can
    // also toggle DCL manually. Primary speed/altitude/pipper always remain.
    LOCAL auto_declutter IS FALSE.
    IF AOSO_HUD_CTX = "LANDING" { SET auto_declutter TO TRUE. }
    IF o["burning"] { SET auto_declutter TO TRUE. }
    LOCAL declutter IS AOSO_UI2_HUD_DECLUTTER OR auto_declutter.
    SET AOSO_UI2_HUD_ATT:VISIBLE TO NOT declutter.
    IF declutter {
        IF event_txt = "" { SET AOSO_UI2_HUD_EVENT:TEXT TO phase. }
    }

    LOCAL goal IS m["goal"].
    IF goal = "" { SET goal TO m["hop"]. }
    IF goal <> "" {
        IF NOT declutter {
            SET AOSO_UI2_HUD_MODE:TEXT TO "<b>AOSO  " + phase + "</b>  → " + goal.
        }
    }
}
