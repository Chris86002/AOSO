// AOSO/ux/ui2_hud.ks
// UI v2 tactical glass cockpit.
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
GLOBAL AOSO_UI2_HUD_VISIBLE IS FALSE.
GLOBAL AOSO_UI2_HUD_DECLUTTER IS FALSE.
GLOBAL AOSO_UI2_HUD_PX IS 210.
GLOBAL AOSO_UI2_HUD_PY IS 125.
GLOBAL AOSO_UI2_HUD_LAST_LIGHT IS "".

FUNCTION aoso_ui2_hud_mfd {
    aoso_hud_mode_computer().
}

FUNCTION aoso_ui2_hud_toggle_declutter {
    SET AOSO_UI2_HUD_DECLUTTER TO NOT AOSO_UI2_HUD_DECLUTTER.
}

FUNCTION aoso_ui2_hud_recenter {
    IF NOT AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }
    // Safe 1440p-friendly default. The HUD remains draggable for any
    // resolution/aspect ratio and REC always restores a known-good position.
    SET AOSO_UI2_HUD_GUI:X TO 490.
    SET AOSO_UI2_HUD_GUI:Y TO 70.
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
    SET AOSO_UI2_HUD_VISIBLE TO FALSE.
}

FUNCTION aoso_ui2_hud_build {
    IF AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }

    LOCAL g IS GUI(460, 355).
    SET g:X TO 490.
    SET g:Y TO 70.
    SET g:DRAGGABLE TO TRUE.
    SET g:SKIN:LABEL:TEXTCOLOR TO RGB(0.30, 1.0, 0.60).
    SET g:SKIN:BUTTON:BG TO AOSO_UI2_ASSET_ROOT + "button_off.png".
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
    SET top:STYLE:WIDTH TO 440.
    SET AOSO_UI2_HUD_MODE TO top:ADDLABEL("<b>AOSO FLIGHT DIRECTOR</b>").
    SET AOSO_UI2_HUD_MODE:STYLE:WIDTH TO 205.
    SET AOSO_UI2_HUD_HDG TO top:ADDLABEL("HDG ---").
    SET AOSO_UI2_HUD_HDG:STYLE:WIDTH TO 65.
    SET AOSO_UI2_HUD_HDG:STYLE:ALIGN TO "right".
    LOCAL b_declutter IS top:ADDBUTTON("DCL").
    SET b_declutter:STYLE:WIDTH TO 45.
    SET b_declutter:ONCLICK TO aoso_ui2_hud_toggle_declutter@.
    LOCAL b_rec IS top:ADDBUTTON("REC").
    SET b_rec:STYLE:WIDTH TO 45.
    SET b_rec:ONCLICK TO aoso_ui2_hud_recenter@.
    LOCAL b_mfd IS top:ADDBUTTON("MFD").
    SET b_mfd:STYLE:WIDTH TO 45.
    SET b_mfd:ONCLICK TO aoso_ui2_hud_mfd@.

    LOCAL row IS g:ADDHLAYOUT().
    SET row:STYLE:WIDTH TO 440.
    SET row:STYLE:HEIGHT TO 250.

    LOCAL vsbox IS row:ADDVLAYOUT().
    SET vsbox:STYLE:WIDTH TO 20.
    SET vsbox:STYLE:HEIGHT TO 230.
    SET vsbox:STYLE:ALIGN TO "center".
    SET AOSO_UI2_HUD_VS TO vsbox:ADDVSLIDER(0, -250, 250).
    SET AOSO_UI2_HUD_VS:STYLE:WIDTH TO 20.
    SET AOSO_UI2_HUD_VS:STYLE:HEIGHT TO 220.
    SET AOSO_UI2_HUD_VS:STYLE:VSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_VS:STYLE:HSTRETCH TO FALSE.

    SET AOSO_UI2_HUD_MAIN TO row:ADDVLAYOUT().
    SET AOSO_UI2_HUD_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_HUD_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_HUD_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_HUD_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "pfd_frame.png".

    SET AOSO_UI2_HUD_PIPPER TO aoso_ui2_marker(
        AOSO_UI2_HUD_MAIN,
        AOSO_UI2_ASSET_ROOT + "diamond.png",
        22).
    SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:H TO AOSO_UI2_HUD_PX.
    SET AOSO_UI2_HUD_PIPPER:STYLE:MARGIN:V TO AOSO_UI2_HUD_PY.

    SET AOSO_UI2_HUD_SPD TO aoso_ui2_overlay_label(AOSO_UI2_HUD_MAIN, "", 14, 55).
    SET AOSO_UI2_HUD_ALT TO aoso_ui2_overlay_label(AOSO_UI2_HUD_MAIN, "", 337, 55).
    SET AOSO_UI2_HUD_ATT TO aoso_ui2_overlay_label(AOSO_UI2_HUD_MAIN, "", 135, 18).
    SET AOSO_UI2_HUD_EVENT TO aoso_ui2_overlay_label(AOSO_UI2_HUD_MAIN, "", 112, 202).

    LOCAL burnrow IS g:ADDHLAYOUT().
    SET burnrow:STYLE:WIDTH TO 440.
    SET burnrow:STYLE:HEIGHT TO 22.
    LOCAL burnlabel IS burnrow:ADDLABEL("DV").
    SET burnlabel:STYLE:WIDTH TO 35.
    SET AOSO_UI2_HUD_BURN TO burnrow:ADDHSLIDER(0, 0, 1).
    SET AOSO_UI2_HUD_BURN:STYLE:WIDTH TO 300.
    SET AOSO_UI2_HUD_BURN:STYLE:HEIGHT TO 20.
    SET AOSO_UI2_HUD_BURN:STYLE:HSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_BURN:STYLE:VSTRETCH TO FALSE.
    SET AOSO_UI2_HUD_BOTTOM TO burnrow:ADDLABEL("").
    SET AOSO_UI2_HUD_BOTTOM:STYLE:WIDTH TO 95.
    SET AOSO_UI2_HUD_BOTTOM:STYLE:ALIGN TO "right".

    g:HIDE().
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
    IF NOT AOSO_UI2_HUD_PIPPER:ISTYPE("Label") { RETURN. }

    LOCAL target IS aoso_ui2_steer_target_vector().
    IF target:MAG < 0.001 { RETURN. }
    LOCAL u IS target:NORMALIZED.
    LOCAL hx IS VDOT(u, SHIP:FACING:STARVECTOR).
    LOCAL vy IS VDOT(u, SHIP:FACING:TOPVECTOR).
    LOCAL want_x IS 210 + CLAMP(hx, -0.75, 0.75) * 155.
    LOCAL want_y IS 125 - CLAMP(vy, -0.75, 0.75) * 88.
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
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].

    aoso_ui2_hud_pipper_fast().
    SET AOSO_UI2_HUD_HDG:TEXT TO "HDG " + ROUND(f["hdg"], 0).
    SET AOSO_UI2_HUD_VS:VALUE TO CLAMP(f["vs"], AOSO_UI2_HUD_VS:MIN, AOSO_UI2_HUD_VS:MAX).

    LOCAL vel IS f["orb"].
    IF f["in_atm"] { SET vel TO f["srf"]. }
    SET AOSO_UI2_HUD_SPD:TEXT TO "<size=17>" + ROUND(vel, 0) + "</size>\nVS " + ROUND(f["vs"], 0).

    LOCAL alt_txt IS aoso_hud_km(f["alt"]).
    IF AOSO_HUD_CTX = "LANDING" {
        SET alt_txt TO ROUND(AOSO_HUD_DATA["landing"]["radar"], 0) + "m".
    }
    SET AOSO_UI2_HUD_ALT:TEXT TO "<size=17>" + alt_txt + "</size>" + CHAR(10) + "AP " + aoso_hud_km(o["ap"]).
}

FUNCTION aoso_ui2_hud_update {
    IF NOT AOSO_UI2_HUD_VISIBLE { RETURN. }
    IF NOT AOSO_UI2_HUD_GUI:ISTYPE("GUI") { RETURN. }

    aoso_ui2_hud_brightness().
    aoso_ui2_hud_fast().

    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].

    LOCAL phase IS AOSO_HUD_CTX.
    IF phase = "IDLE" { SET phase TO f["status"]. }
    SET AOSO_UI2_HUD_MODE:TEXT TO "<b>AOSO  " + phase + "</b>  " + f["doing"].
    SET AOSO_UI2_HUD_ATT:TEXT TO "P " + ROUND(f["pitch"], 1) + "°   R " +
        ROUND(f["roll"], 1) + "°   AoA " + ROUND(f["aoa"], 1) + "°".

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
        IF total > 0.01 { SET progress TO 1 - CLAMP(left / total, 0, 1). }
        SET AOSO_UI2_HUD_BOTTOM:TEXT TO ROUND(left, 0) + "m/s".
    } ELSE {
        LOCAL pct IS MAX(AOSO_HUD_DATA["res"]["lf"], AOSO_HUD_DATA["res"]["ox"]) / 100.
        SET progress TO CLAMP(pct, 0, 1).
        SET AOSO_UI2_HUD_BOTTOM:TEXT TO "PROP " + ROUND(pct * 100, 0) + "%".
    }
    SET AOSO_UI2_HUD_BURN:VALUE TO progress.

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
