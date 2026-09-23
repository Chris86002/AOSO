// AOSO/ux/ui2_instruments.ks
// AOSO UI v2 graphical instruments.
//
// Clean-room AOSO implementation inspired by the *techniques* demonstrated
// by kOS-Shuttle-OPS3: layered kOS GUI layouts, image-backed instruments,
// movable bugs/pippers, trail markers, context-sensitive annunciators and
// update-in-place widgets. No OPS3 source or image asset is copied.
//
// This module is presentation-only. It reads AOSO_HUD_DATA and guidance
// globals but never stages, throttles, steers, retargets, warps, or mutates
// mission state.

GLOBAL AOSO_UI2_ASSET_ROOT IS "AOSO/ux/ui2_assets/".

GLOBAL AOSO_UI2_PFD_MAIN IS 0.
GLOBAL AOSO_UI2_PFD_PIPPER IS 0.
GLOBAL AOSO_UI2_PFD_PX IS 210.
GLOBAL AOSO_UI2_PFD_PY IS 125.
GLOBAL AOSO_UI2_PFD_MODE IS 0.
GLOBAL AOSO_UI2_PFD_HDG IS 0.
GLOBAL AOSO_UI2_PFD_LEFT IS 0.
GLOBAL AOSO_UI2_PFD_RIGHT IS 0.
GLOBAL AOSO_UI2_PFD_BOTTOM IS 0.
GLOBAL AOSO_UI2_PFD_WARN IS 0.

GLOBAL AOSO_UI2_NAV_MAIN IS 0.
GLOBAL AOSO_UI2_NAV_SHIP IS 0.
GLOBAL AOSO_UI2_NAV_TARGET IS 0.
GLOBAL AOSO_UI2_NAV_NODE IS 0.
GLOBAL AOSO_UI2_NAV_TITLE IS 0.
GLOBAL AOSO_UI2_NAV_COURSE IS 0.
GLOBAL AOSO_UI2_NAV_LEFT IS 0.
GLOBAL AOSO_UI2_NAV_RIGHT IS 0.
GLOBAL AOSO_UI2_NAV_TRAIL IS LIST().
GLOBAL AOSO_UI2_NAV_TRAIL_X IS LIST().
GLOBAL AOSO_UI2_NAV_TRAIL_Y IS LIST().
GLOBAL AOSO_UI2_NAV_LAST_TRAIL_UT IS -1.

GLOBAL AOSO_UI2_SURF_MAIN IS 0.
GLOBAL AOSO_UI2_SURF_SHIP IS 0.
GLOBAL AOSO_UI2_SURF_SITE IS 0.
GLOBAL AOSO_UI2_SURF_TITLE IS 0.
GLOBAL AOSO_UI2_SURF_LEFT IS 0.
GLOBAL AOSO_UI2_SURF_RIGHT IS 0.
GLOBAL AOSO_UI2_SURF_BOTTOM IS 0.

GLOBAL AOSO_UI2_VEH_MAIN IS 0.

FUNCTION aoso_ui2_marker {
    PARAMETER parent.
    PARAMETER image_path.
    PARAMETER width.
    LOCAL holder IS parent:ADDVLAYOUT().
    SET holder:STYLE:ALIGN TO "center".
    SET holder:STYLE:WIDTH TO 1.
    SET holder:STYLE:HEIGHT TO 1.
    LOCAL marker IS holder:ADDLABEL().
    SET marker:IMAGE TO image_path.
    SET marker:STYLE:WIDTH TO width.
    RETURN marker.
}

FUNCTION aoso_ui2_overlay_label {
    PARAMETER parent.
    PARAMETER txt.
    PARAMETER x.
    PARAMETER y.
    LOCAL holder IS parent:ADDVLAYOUT().
    SET holder:STYLE:WIDTH TO 1.
    SET holder:STYLE:HEIGHT TO 1.
    LOCAL lab IS holder:ADDLABEL(txt).
    SET lab:STYLE:MARGIN:H TO x.
    SET lab:STYLE:MARGIN:V TO y.
    RETURN lab.
}

FUNCTION aoso_ui2_clamp01 {
    PARAMETER x.
    IF x < 0 { RETURN 0. }
    IF x > 1 { RETURN 1. }
    RETURN x.
}

FUNCTION aoso_ui2_bar {
    PARAMETER value.
    PARAMETER width IS 12.
    LOCAL pct IS aoso_ui2_clamp01(value).
    LOCAL fill IS ROUND(pct * width, 0).
    LOCAL out IS "".
    LOCAL i IS 0.
    UNTIL i >= width {
        IF i < fill { SET out TO out + "█". }
        ELSE { SET out TO out + "░". }
        SET i TO i + 1.
    }
    RETURN out.
}

FUNCTION aoso_ui2_color_state {
    PARAMETER state.
    PARAMETER txt.
    IF state = "FAIL" OR state = "CRIT" { RETURN "<color=#FF5A46>" + txt + "</color>". }
    IF state = "DEG" OR state = "WARN" { RETURN "<color=#FFCD46>" + txt + "</color>". }
    IF state = "NOM" OR state = "SAFE" { RETURN "<color=#50FF96>" + txt + "</color>". }
    RETURN "<color=#7EC8FF>" + txt + "</color>".
}

FUNCTION aoso_ui2_steer_target_vector {
    IF AOSO_STEER_MODE = "CMD" { RETURN AOSO_CMD_STEERING:VECTOR. }
    IF AOSO_STEER_MODE = "PROGRADE" { RETURN SHIP:PROGRADE:VECTOR. }
    IF AOSO_STEER_MODE = "SRF_RETROGRADE" { RETURN SHIP:SRFRETROGRADE:VECTOR. }
    IF AOSO_STEER_MODE = "UP" { RETURN SHIP:UP:VECTOR. }
    RETURN SHIP:FACING:VECTOR.
}

FUNCTION aoso_ui2_build_pfd {
    PARAMETER page.

    LOCAL title IS page:ADDLABEL("<b><size=18>PRIMARY FLIGHT DISPLAY</size></b>").
    SET title:STYLE:ALIGN TO "center".
    SET title:STYLE:HSTRETCH TO TRUE.

    LOCAL top IS page:ADDHLAYOUT().
    SET top:STYLE:WIDTH TO 420.
    SET top:STYLE:ALIGN TO "center".
    SET AOSO_UI2_PFD_MODE TO top:ADDLABEL("GUIDANCE  STANDBY").
    SET AOSO_UI2_PFD_MODE:STYLE:WIDTH TO 280.
    SET AOSO_UI2_PFD_HDG TO top:ADDLABEL("HDG ---").
    SET AOSO_UI2_PFD_HDG:STYLE:WIDTH TO 120.
    SET AOSO_UI2_PFD_HDG:STYLE:ALIGN TO "right".

    SET AOSO_UI2_PFD_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_PFD_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_PFD_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_PFD_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_PFD_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "pfd_frame.png".

    SET AOSO_UI2_PFD_PIPPER TO aoso_ui2_marker(
        AOSO_UI2_PFD_MAIN,
        AOSO_UI2_ASSET_ROOT + "diamond.png",
        22).
    SET AOSO_UI2_PFD_PIPPER:STYLE:MARGIN:H TO AOSO_UI2_PFD_PX.
    SET AOSO_UI2_PFD_PIPPER:STYLE:MARGIN:V TO AOSO_UI2_PFD_PY.

    // Side tapes are text-driven so they remain legible at every GUI scale.
    SET AOSO_UI2_PFD_LEFT TO aoso_ui2_overlay_label(AOSO_UI2_PFD_MAIN, "VEL", 14, 54).
    SET AOSO_UI2_PFD_RIGHT TO aoso_ui2_overlay_label(AOSO_UI2_PFD_MAIN, "ALT", 337, 54).
    SET AOSO_UI2_PFD_BOTTOM TO aoso_ui2_overlay_label(AOSO_UI2_PFD_MAIN, "", 88, 205).
    SET AOSO_UI2_PFD_WARN TO aoso_ui2_overlay_label(AOSO_UI2_PFD_MAIN, "", 125, 20).

    LOCAL annunciators IS page:ADDHLAYOUT().
    SET annunciators:STYLE:WIDTH TO 420.
    SET annunciators:STYLE:ALIGN TO "center".
    aoso_hud_lab(annunciators, "ui2_pfd_att", "PITCH --  ROLL --").
    aoso_hud_lab(annunciators, "ui2_pfd_prop", "TWR --  THR --").
    aoso_hud_lab(page, "ui2_pfd_phase", "").
}

FUNCTION aoso_ui2_pfd_update {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL res IS AOSO_HUD_DATA["res"].

    LOCAL mode IS AOSO_HUD_CTX.
    IF mode = "IDLE" { SET mode TO f["status"]. }
    SET AOSO_UI2_PFD_MODE:TEXT TO "<b>" + mode + "</b>  " + f["doing"].
    SET AOSO_UI2_PFD_HDG:TEXT TO "HDG " + ROUND(f["hdg"], 0).

    LOCAL vel IS f["orb"].
    IF f["in_atm"] { SET vel TO f["srf"]. }
    SET AOSO_UI2_PFD_LEFT:TEXT TO "<size=16>" + ROUND(vel, 0) + "</size>" + CHAR(10) +
        "VS " + ROUND(f["vs"], 1).

    LOCAL alt_txt IS aoso_hud_km(f["alt"]).
    IF AOSO_HUD_CTX = "LANDING" {
        SET alt_txt TO ROUND(AOSO_HUD_DATA["landing"]["radar"], 0) + "m RAD".
    }
    SET AOSO_UI2_PFD_RIGHT:TEXT TO "<size=16>" + alt_txt + "</size>" + CHAR(10) +
        "AP " + aoso_hud_km(o["ap"]).

    LOCAL fuel IS MAX(res["lf"], res["ox"]).
    LOCAL fuel_txt IS "PROP " + aoso_ui2_bar(fuel / 100, 16) + " " + ROUND(fuel, 0) + "%".
    SET AOSO_UI2_PFD_BOTTOM:TEXT TO fuel_txt.

    LOCAL warning IS "".
    IF sys["worst"] = "FAIL" { SET warning TO aoso_ui2_color_state("FAIL", "MASTER WARNING"). }
    ELSE {
        IF sys["worst"] = "DEG" { SET warning TO aoso_ui2_color_state("WARN", "CAUTION"). }
    }
    SET AOSO_UI2_PFD_WARN:TEXT TO warning.

    aoso_hud_set("ui2_pfd_att", "PITCH " + ROUND(f["pitch"], 1) + "°   ROLL " +
        ROUND(f["roll"], 1) + "°   AoA " + ROUND(f["aoa"], 1) + "°").
    aoso_hud_set("ui2_pfd_prop", "TWR " + ROUND(f["twr"], 2) + "   THR " +
        ROUND(f["throttle"] * 100, 0) + "%").
    aoso_hud_set("ui2_pfd_phase", "STEER " + sys["steer_mode"] + "   " +
        f["warp"] + "   STAGE " + f["stage"]).

    // OPS3-style movable guidance diamond, projected into the vessel frame.
    // The marker shows commanded attitude error; it is NOT a control input.
    LOCAL target IS aoso_ui2_steer_target_vector().
    IF target:MAG > 0.001 {
        LOCAL u IS target:NORMALIZED.
        LOCAL hx IS VDOT(u, SHIP:FACING:STARVECTOR).
        LOCAL vy IS VDOT(u, SHIP:FACING:TOPVECTOR).
        LOCAL want_x IS 210 + CLAMP(hx, -0.75, 0.75) * 155.
        LOCAL want_y IS 125 - CLAMP(vy, -0.75, 0.75) * 88.
        LOCAL smooth IS aoso_config_get("UI2_MARKER_SMOOTH", 0.28).
        IF smooth < 0.05 { SET smooth TO 0.05. }
        IF smooth > 1 { SET smooth TO 1. }
        SET AOSO_UI2_PFD_PX TO AOSO_UI2_PFD_PX + smooth * (want_x - AOSO_UI2_PFD_PX).
        SET AOSO_UI2_PFD_PY TO AOSO_UI2_PFD_PY + smooth * (want_y - AOSO_UI2_PFD_PY).
        SET AOSO_UI2_PFD_PIPPER:STYLE:MARGIN:H TO AOSO_UI2_PFD_PX.
        SET AOSO_UI2_PFD_PIPPER:STYLE:MARGIN:V TO AOSO_UI2_PFD_PY.
    }
}

FUNCTION aoso_ui2_build_nav_display {
    PARAMETER page.

    SET AOSO_UI2_NAV_TITLE TO page:ADDLABEL("<b><size=18>NAVIGATION DISPLAY</size></b>").
    SET AOSO_UI2_NAV_TITLE:STYLE:ALIGN TO "center".
    SET AOSO_UI2_NAV_TITLE:STYLE:HSTRETCH TO TRUE.

    SET AOSO_UI2_NAV_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_NAV_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_NAV_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_NAV_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_NAV_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "nav_frame.png".

    LOCAL trail_n IS ROUND(aoso_config_get("UI2_TRAIL_POINTS", 10), 0).
    IF trail_n < 0 { SET trail_n TO 0. }
    IF trail_n > 16 { SET trail_n TO 16. }
    SET AOSO_UI2_NAV_TRAIL TO LIST().
    SET AOSO_UI2_NAV_TRAIL_X TO LIST().
    SET AOSO_UI2_NAV_TRAIL_Y TO LIST().
    LOCAL i IS 0.
    UNTIL i >= trail_n {
        LOCAL mark IS aoso_ui2_marker(AOSO_UI2_NAV_MAIN, AOSO_UI2_ASSET_ROOT + "target_bug.png", 6).
        SET mark:VISIBLE TO FALSE.
        AOSO_UI2_NAV_TRAIL:ADD(mark).
        SET i TO i + 1.
    }

    SET AOSO_UI2_NAV_SHIP TO aoso_ui2_marker(AOSO_UI2_NAV_MAIN, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_NAV_TARGET TO aoso_ui2_marker(AOSO_UI2_NAV_MAIN, AOSO_UI2_ASSET_ROOT + "target_bug.png", 16).
    SET AOSO_UI2_NAV_NODE TO aoso_ui2_marker(AOSO_UI2_NAV_MAIN, AOSO_UI2_ASSET_ROOT + "diamond.png", 16).

    SET AOSO_UI2_NAV_LEFT TO aoso_ui2_overlay_label(AOSO_UI2_NAV_MAIN, "", 14, 24).
    SET AOSO_UI2_NAV_RIGHT TO aoso_ui2_overlay_label(AOSO_UI2_NAV_MAIN, "", 292, 24).
    SET AOSO_UI2_NAV_COURSE TO aoso_ui2_overlay_label(AOSO_UI2_NAV_MAIN, "", 110, 207).

    aoso_hud_lab(page, "ui2_nav_detail", "").
    aoso_hud_lab(page, "ui2_nav_burn", "").
}

FUNCTION aoso_ui2_nav_xy {
    PARAMETER frac.
    // Schematic normalized orbit position. This is deliberately labelled
    // SCHEMATIC: it communicates timing/course state, not a map-view ephemeris.
    LOCAL ang IS frac * 360.
    RETURN LIST(210 + COS(ang) * 145, 125 + SIN(ang) * 68).
}

FUNCTION aoso_ui2_nav_update {
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL res IS AOSO_HUD_DATA["res"].

    LOCAL period IS o["period"].
    LOCAL frac IS 0.
    IF period > 1 {
        SET frac TO o["ap_eta"] / period.
        SET frac TO frac - FLOOR(frac).
    }
    LOCAL pos IS aoso_ui2_nav_xy(frac).
    SET AOSO_UI2_NAV_SHIP:STYLE:MARGIN:H TO pos[0].
    SET AOSO_UI2_NAV_SHIP:STYLE:MARGIN:V TO pos[1].

    LOCAL target_frac IS frac + 0.25.
    IF o["patch"] <> "" {
        IF period > 1 {
            SET target_frac TO frac + o["patch_eta"] / period.
        }
    } ELSE {
        IF o["node"] {
            IF period > 1 { SET target_frac TO frac + o["node_eta"] / period. }
        }
    }
    SET target_frac TO target_frac - FLOOR(target_frac).
    LOCAL tpos IS aoso_ui2_nav_xy(target_frac).
    SET AOSO_UI2_NAV_TARGET:STYLE:MARGIN:H TO tpos[0].
    SET AOSO_UI2_NAV_TARGET:STYLE:MARGIN:V TO tpos[1].
    SET AOSO_UI2_NAV_TARGET:VISIBLE TO (o["patch"] <> "" OR m["goal"] <> "" OR m["hop"] <> "").

    IF o["node"] {
        LOCAL nfrac IS frac.
        IF period > 1 { SET nfrac TO frac + o["node_eta"] / period. }
        SET nfrac TO nfrac - FLOOR(nfrac).
        LOCAL npos IS aoso_ui2_nav_xy(nfrac).
        SET AOSO_UI2_NAV_NODE:STYLE:MARGIN:H TO npos[0].
        SET AOSO_UI2_NAV_NODE:STYLE:MARGIN:V TO npos[1].
        SET AOSO_UI2_NAV_NODE:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_NAV_NODE:VISIBLE TO FALSE.
    }

    // Trail of recent schematic positions, matching OPS3's useful "where
    // have I been on this display" visual language without copying its code.
    LOCAL now IS TIME:SECONDS.
    IF AOSO_UI2_NAV_TRAIL:LENGTH > 0 {
        IF AOSO_UI2_NAV_LAST_TRAIL_UT < 0 OR now - AOSO_UI2_NAV_LAST_TRAIL_UT >= 2 {
            SET AOSO_UI2_NAV_LAST_TRAIL_UT TO now.
            AOSO_UI2_NAV_TRAIL_X:ADD(pos[0]).
            AOSO_UI2_NAV_TRAIL_Y:ADD(pos[1]).
            IF AOSO_UI2_NAV_TRAIL_X:LENGTH > AOSO_UI2_NAV_TRAIL:LENGTH {
                AOSO_UI2_NAV_TRAIL_X:REMOVE(0).
                AOSO_UI2_NAV_TRAIL_Y:REMOVE(0).
            }
        }
        LOCAL j IS 0.
        UNTIL j >= AOSO_UI2_NAV_TRAIL:LENGTH {
            IF j < AOSO_UI2_NAV_TRAIL_X:LENGTH {
                SET AOSO_UI2_NAV_TRAIL[j]:VISIBLE TO TRUE.
                SET AOSO_UI2_NAV_TRAIL[j]:STYLE:MARGIN:H TO AOSO_UI2_NAV_TRAIL_X[j].
                SET AOSO_UI2_NAV_TRAIL[j]:STYLE:MARGIN:V TO AOSO_UI2_NAV_TRAIL_Y[j].
            } ELSE {
                SET AOSO_UI2_NAV_TRAIL[j]:VISIBLE TO FALSE.
            }
            SET j TO j + 1.
        }
    }

    LOCAL goal IS m["goal"].
    IF goal = "" { SET goal TO m["hop"]. }
    IF goal = "" { SET goal TO "NO TARGET". }
    SET AOSO_UI2_NAV_TITLE:TEXT TO "<b><size=18>" + o["body"] + " → " + goal + "</size></b>".

    SET AOSO_UI2_NAV_LEFT:TEXT TO "AP " + aoso_hud_km(o["ap"]) + CHAR(10) + "PE " +
        aoso_hud_km(o["pe"]) + CHAR(10) + "INC " + ROUND(o["inc"], 1) + "°".

    LOCAL patch_txt IS "NO PATCH".
    IF o["patch"] <> "" {
        SET patch_txt TO o["patch"] + CHAR(10) + "PE " + aoso_hud_km(o["patch_pe"]) +
            "\nT-" + aoso_hud_eta(o["patch_eta"]).
    }
    SET AOSO_UI2_NAV_RIGHT:TEXT TO patch_txt.

    LOCAL quality IS "MONITOR".
    IF o["patch"] <> "" {
        SET quality TO "ROUGH / SAFE".
        IF m["goal"] <> "" {
            IF o["patch"] <> m["goal"] AND o["patch"] <> m["hop"] {
                SET quality TO "UNEXPECTED PATCH".
            }
        }
    }
    IF o["node"] { SET quality TO "MANEUVER READY". }
    IF o["burning"] { SET quality TO "BURN EXECUTION". }
    LOCAL quality_state IS "SAFE".
    IF quality = "UNEXPECTED PATCH" { SET quality_state TO "WARN". }
    SET AOSO_UI2_NAV_COURSE:TEXT TO aoso_ui2_color_state(quality_state, quality).

    LOCAL detail IS "SCHEMATIC  dV " + ROUND(res["mission_dv"], 0) + " m/s".
    IF o["patch"] <> "" {
        SET detail TO detail + "   PATCH PE " + aoso_hud_km(o["patch_pe"]).
    }
    aoso_hud_set("ui2_nav_detail", detail).

    LOCAL burn_txt IS "NO MANEUVER".
    IF o["node"] {
        LOCAL left IS o["node_dv"].
        IF o["burning"] { SET left TO o["burn_left"]. }
        SET burn_txt TO "NODE " + ROUND(o["node_dv"], 1) + " m/s   LEFT " +
            ROUND(left, 1) + "   T-" + aoso_hud_eta(o["node_eta"]).
    }
    aoso_hud_set("ui2_nav_burn", burn_txt).
}

FUNCTION aoso_ui2_geo_xy {
    PARAMETER lat.
    PARAMETER lng.
    LOCAL lon IS lng.
    UNTIL lon >= -180 { SET lon TO lon + 360. }
    UNTIL lon <= 180 { SET lon TO lon - 360. }
    LOCAL x IS 35 + ((lon + 180) / 360) * 350.
    LOCAL y IS 25 + ((90 - CLAMP(lat, -90, 90)) / 180) * 200.
    RETURN LIST(x, y).
}

FUNCTION aoso_ui2_build_surface_display {
    PARAMETER page.

    SET AOSO_UI2_SURF_TITLE TO page:ADDLABEL("<b><size=18>SURFACE / LANDING</size></b>").
    SET AOSO_UI2_SURF_TITLE:STYLE:ALIGN TO "center".
    SET AOSO_UI2_SURF_TITLE:STYLE:HSTRETCH TO TRUE.

    SET AOSO_UI2_SURF_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_SURF_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_SURF_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_SURF_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_SURF_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "survey_frame.png".

    SET AOSO_UI2_SURF_SHIP TO aoso_ui2_marker(AOSO_UI2_SURF_MAIN, AOSO_UI2_ASSET_ROOT + "ship_bug.png", 18).
    SET AOSO_UI2_SURF_SITE TO aoso_ui2_marker(AOSO_UI2_SURF_MAIN, AOSO_UI2_ASSET_ROOT + "site_bug.png", 20).

    SET AOSO_UI2_SURF_LEFT TO aoso_ui2_overlay_label(AOSO_UI2_SURF_MAIN, "", 12, 24).
    SET AOSO_UI2_SURF_RIGHT TO aoso_ui2_overlay_label(AOSO_UI2_SURF_MAIN, "", 290, 24).
    SET AOSO_UI2_SURF_BOTTOM TO aoso_ui2_overlay_label(AOSO_UI2_SURF_MAIN, "", 92, 207).

    aoso_hud_lab(page, "ui2_surf_detail", "").
    aoso_hud_lab(page, "ui2_surf_energy", "").
}

FUNCTION aoso_ui2_surface_update {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL l IS AOSO_HUD_DATA["landing"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL res IS AOSO_HUD_DATA["res"].

    LOCAL ship_geo IS SHIP:GEOPOSITION.
    LOCAL spos IS aoso_ui2_geo_xy(ship_geo:LAT, ship_geo:LNG).
    SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:H TO spos[0].
    SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:V TO spos[1].

    LOCAL have_site IS FALSE.
    LOCAL slat IS 0.
    LOCAL slng IS 0.
    LOCAL site_score IS -1.
    LOCAL rough IS 0.
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            LOCAL td IS AOSO_TOUR["data"].
            IF td:HASKEY("site_lat") {
                SET have_site TO TRUE.
                SET slat TO td["site_lat"].
                SET slng TO td["site_lng"].
                IF td:HASKEY("site_score") { SET site_score TO td["site_score"]. }
                IF td:HASKEY("site_roughness") { SET rough TO td["site_roughness"]. }
            }
        }
    }

    IF have_site {
        LOCAL p IS aoso_ui2_geo_xy(slat, slng).
        SET AOSO_UI2_SURF_SITE:STYLE:MARGIN:H TO p[0].
        SET AOSO_UI2_SURF_SITE:STYLE:MARGIN:V TO p[1].
        SET AOSO_UI2_SURF_SITE:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_SURF_SITE:VISIBLE TO FALSE.
    }

    LOCAL phase IS "SURVEY".
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] <> "" { SET phase TO AOSO_TOUR["current"]. }
    }
    IF l["active"] { SET phase TO l["state"]. }
    SET AOSO_UI2_SURF_TITLE:TEXT TO "<b><size=18>" + SHIP:BODY:NAME + "  " + phase + "</size></b>".

    SET AOSO_UI2_SURF_LEFT:TEXT TO "LAT " + ROUND(ship_geo:LAT, 1) + "°" + CHAR(10) + "LON " +
        ROUND(ship_geo:LNG, 1) + "°" + CHAR(10) + "INC " + ROUND(o["inc"], 1) + "°".
    IF have_site {
        SET AOSO_UI2_SURF_RIGHT:TEXT TO "SITE " + ROUND(slat, 1) + "°" + CHAR(10) +
            ROUND(slng, 1) + "°" + CHAR(10) + "SCORE " + ROUND(site_score, 1).
    } ELSE {
        SET AOSO_UI2_SURF_RIGHT:TEXT TO "SITE" + CHAR(10) + "SEARCHING" + CHAR(10) + "---".
    }

    LOCAL bottom IS "POLAR SURVEY / GROUND TRACK".
    IF l["active"] {
        SET bottom TO "RAD " + ROUND(l["radar"], 0) + "m   VS " +
            ROUND(f["vs"], 1) + "m/s".
    }
    SET AOSO_UI2_SURF_BOTTOM:TEXT TO bottom.

    LOCAL site_txt IS "NO CANDIDATE".
    IF have_site {
        SET site_txt TO "BEST SITE  score " + ROUND(site_score, 2) +
            "   rough " + ROUND(rough, 0) + "m".
    }
    aoso_hud_set("ui2_surf_detail", site_txt).

    LOCAL margin IS l["radar"] - l["trig"].
    LOCAL energy_txt IS "LAND dV " + ROUND(res["land_dv"], 0) +
        " / HAVE " + ROUND(res["mission_dv"], 0) + " m/s".
    IF l["active"] {
        SET energy_txt TO energy_txt + "   BURN MARGIN " + ROUND(margin, 0) + "m".
    }
    aoso_hud_set("ui2_surf_energy", energy_txt).
}

FUNCTION aoso_ui2_build_vehicle_frame {
    PARAMETER page.
    SET AOSO_UI2_VEH_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_VEH_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_VEH_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_VEH_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_VEH_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "vehicle_frame.png".
}
