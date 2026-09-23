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
GLOBAL AOSO_UI2_NAV_LAST_TRAIL_RT IS -1.
GLOBAL AOSO_UI2_NAV_PRED IS LIST().
GLOBAL AOSO_UI2_NAV_LAST_PRED_RT IS -1.
GLOBAL AOSO_UI2_NAV_BASIS_BODY IS "".
GLOBAL AOSO_UI2_NAV_BASIS_X IS V(1, 0, 0).
GLOBAL AOSO_UI2_NAV_BASIS_Y IS V(0, 1, 0).
GLOBAL AOSO_UI2_NAV_SCALE IS 1.

GLOBAL AOSO_UI2_SURF_MAIN IS 0.
GLOBAL AOSO_UI2_SURF_SHIP IS 0.
GLOBAL AOSO_UI2_SURF_SITE IS 0.
GLOBAL AOSO_UI2_SURF_PRED IS 0.
GLOBAL AOSO_UI2_SURF_TITLE IS 0.
GLOBAL AOSO_UI2_SURF_LEFT IS 0.
GLOBAL AOSO_UI2_SURF_RIGHT IS 0.
GLOBAL AOSO_UI2_SURF_BOTTOM IS 0.
GLOBAL AOSO_UI2_SURF_VSIT IS 0.
GLOBAL AOSO_UI2_SURF_ALTBUG IS 0.
GLOBAL AOSO_UI2_SURF_TRIGBUG IS 0.
GLOBAL AOSO_UI2_SURF_VSINFO IS 0.

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

    SET AOSO_UI2_NAV_TITLE TO page:ADDLABEL("<b><size=18>NAVIGATION SITUATION DISPLAY</size></b>").
    SET AOSO_UI2_NAV_TITLE:STYLE:ALIGN TO "center".
    SET AOSO_UI2_NAV_TITLE:STYLE:HSTRETCH TO TRUE.

    SET AOSO_UI2_NAV_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_NAV_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_NAV_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_NAV_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_NAV_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "nav_frame.png".

    // Predicted conic samples: sparse image bugs updated in-place about once
    // per second. This is the real osculating/patched-conic geometry inside
    // the current SOI, not a decorative ellipse.
    SET AOSO_UI2_NAV_PRED TO LIST().
    LOCAL pred_n IS ROUND(aoso_config_get("UI2_NAV_PRED_POINTS", 16), 0).
    IF pred_n < 6 { SET pred_n TO 6. }
    IF pred_n > 24 { SET pred_n TO 24. }
    LOCAL pi IS 0.
    UNTIL pi >= pred_n {
        LOCAL pm IS aoso_ui2_marker(AOSO_UI2_NAV_MAIN, AOSO_UI2_ASSET_ROOT + "pred_bug.png", 8).
        SET pm:VISIBLE TO FALSE.
        AOSO_UI2_NAV_PRED:ADD(pm).
        SET pi TO pi + 1.
    }

    // Recent flown trail. Unlike the prediction this is historical position.
    LOCAL trail_n IS ROUND(aoso_config_get("UI2_TRAIL_POINTS", 10), 0).
    IF trail_n < 0 { SET trail_n TO 0. }
    IF trail_n > 16 { SET trail_n TO 16. }
    SET AOSO_UI2_NAV_TRAIL TO LIST().
    SET AOSO_UI2_NAV_TRAIL_X TO LIST().
    SET AOSO_UI2_NAV_TRAIL_Y TO LIST().
    LOCAL i IS 0.
    UNTIL i >= trail_n {
        LOCAL mark IS aoso_ui2_marker(AOSO_UI2_NAV_MAIN, AOSO_UI2_ASSET_ROOT + "trail_bug.png", 8).
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

    SET AOSO_UI2_NAV_LAST_PRED_RT TO -1.
    SET AOSO_UI2_NAV_BASIS_BODY TO "".
}

FUNCTION aoso_ui2_nav_basis_ensure {
    IF AOSO_UI2_NAV_BASIS_BODY = SHIP:BODY:NAME { RETURN. }

    LOCAL pos_vec IS aoso_orbit_position_now(SHIP).
    IF pos_vec:MAG < 1 {
        SET AOSO_UI2_NAV_BASIS_X TO V(1, 0, 0).
        SET AOSO_UI2_NAV_BASIS_Y TO V(0, 1, 0).
    } ELSE {
        SET AOSO_UI2_NAV_BASIS_X TO pos_vec:NORMALIZED.
        LOCAL n IS aoso_orbit_normal_now(SHIP).
        LOCAL y IS VCRS(n, AOSO_UI2_NAV_BASIS_X).
        IF y:MAG < 0.001 { SET y TO V(0, 1, 0). }
        SET AOSO_UI2_NAV_BASIS_Y TO y:NORMALIZED.
    }
    SET AOSO_UI2_NAV_BASIS_BODY TO SHIP:BODY:NAME.
    SET AOSO_UI2_NAV_LAST_PRED_RT TO -1.
    SET AOSO_UI2_NAV_TRAIL_X TO LIST().
    SET AOSO_UI2_NAV_TRAIL_Y TO LIST().
}

FUNCTION aoso_ui2_nav_project {
    PARAMETER pos_vec.
    LOCAL scale IS MAX(1, AOSO_UI2_NAV_SCALE).
    LOCAL px IS VDOT(pos_vec, AOSO_UI2_NAV_BASIS_X) / scale.
    LOCAL py IS VDOT(pos_vec, AOSO_UI2_NAV_BASIS_Y) / scale.
    RETURN LIST(
        210 + CLAMP(px, -1, 1) * 158,
        125 - CLAMP(py, -1, 1) * 78
    ).
}

FUNCTION aoso_ui2_nav_predict {
    // Visual conic sampling is intentionally wall-clock throttled. TIME:SECONDS
    // may advance thousands of seconds per rendered frame in rails warp, which
    // would otherwise make the HUD recalculate the trajectory every frame.
    LOCAL now_rt IS KUNIVERSE:REALTIME.
    LOCAL refresh IS aoso_config_get("UI2_NAV_PRED_REFRESH_S", 1).
    IF refresh < 0.25 { SET refresh TO 0.25. }

    IF WARP > 0 {
        IF refresh < 2 { SET refresh TO 2. }
    }
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 { RETURN. }
        IF AOSO_CPU_LEVEL >= 2 {
            IF refresh < 3 { SET refresh TO 3. }
        }
    }

    IF AOSO_UI2_NAV_LAST_PRED_RT >= 0 {
        IF now_rt - AOSO_UI2_NAV_LAST_PRED_RT < refresh { RETURN. }
    }
    SET AOSO_UI2_NAV_LAST_PRED_RT TO now_rt.
    aoso_ui2_nav_basis_ensure().

    LOCAL now_ut IS TIME:SECONDS.
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL horizon IS o["period"].
    IF horizon <= 1 { SET horizon TO 3600. }
    IF o["patch"] <> "" {
        IF o["patch_eta"] > 1 { SET horizon TO o["patch_eta"]. }
    }
    IF horizon < 60 { SET horizon TO 60. }

    LOCAL pts IS LIST().
    LOCAL max_r IS MAX(1, aoso_orbit_position_now(SHIP):MAG).
    LOCAL n IS AOSO_UI2_NAV_PRED:LENGTH.
    LOCAL i IS 0.
    UNTIL i >= n {
        LOCAL frac IS 0.
        IF n > 1 { SET frac TO i / (n - 1). }
        LOCAL sample_ut IS now_ut + horizon * frac.
        LOCAL sample_vec IS aoso_orbit_position_at(SHIP, sample_ut).
        pts:ADD(sample_vec).
        IF sample_vec:MAG > max_r { SET max_r TO sample_vec:MAG. }
        SET i TO i + 1.
    }
    SET AOSO_UI2_NAV_SCALE TO max_r * 1.08.

    SET i TO 0.
    UNTIL i >= n {
        LOCAL p IS aoso_ui2_nav_project(pts[i]).
        SET AOSO_UI2_NAV_PRED[i]:STYLE:MARGIN:H TO p[0].
        SET AOSO_UI2_NAV_PRED[i]:STYLE:MARGIN:V TO p[1].
        SET AOSO_UI2_NAV_PRED[i]:VISIBLE TO TRUE.
        SET i TO i + 1.
    }
}

FUNCTION aoso_ui2_nav_update {
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL res IS AOSO_HUD_DATA["res"].

    aoso_ui2_nav_basis_ensure().
    aoso_ui2_nav_predict().

    LOCAL ship_r IS aoso_orbit_position_now(SHIP).
    LOCAL pos IS aoso_ui2_nav_project(ship_r).
    SET AOSO_UI2_NAV_SHIP:STYLE:MARGIN:H TO pos[0].
    SET AOSO_UI2_NAV_SHIP:STYLE:MARGIN:V TO pos[1].

    // The target bug marks the actual next SOI boundary point on the current
    // conic. This makes a Minmus/Mun encounter visibly different before SOI.
    IF o["patch"] <> "" AND o["patch_eta"] > 0 {
        LOCAL pr IS aoso_orbit_position_at(SHIP, TIME:SECONDS + o["patch_eta"]).
        LOCAL pp IS aoso_ui2_nav_project(pr).
        SET AOSO_UI2_NAV_TARGET:STYLE:MARGIN:H TO pp[0].
        SET AOSO_UI2_NAV_TARGET:STYLE:MARGIN:V TO pp[1].
        SET AOSO_UI2_NAV_TARGET:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_NAV_TARGET:VISIBLE TO FALSE.
    }

    IF o["node"] {
        LOCAL nr IS aoso_orbit_position_at(SHIP, TIME:SECONDS + MAX(0, o["node_eta"])).
        LOCAL np IS aoso_ui2_nav_project(nr).
        SET AOSO_UI2_NAV_NODE:STYLE:MARGIN:H TO np[0].
        SET AOSO_UI2_NAV_NODE:STYLE:MARGIN:V TO np[1].
        SET AOSO_UI2_NAV_NODE:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_NAV_NODE:VISIBLE TO FALSE.
    }

    // Flown trail.
    LOCAL trail_rt IS KUNIVERSE:REALTIME.
    IF AOSO_UI2_NAV_TRAIL:LENGTH > 0 {
        IF AOSO_UI2_NAV_LAST_TRAIL_RT < 0 OR trail_rt - AOSO_UI2_NAV_LAST_TRAIL_RT >= 2 {
            SET AOSO_UI2_NAV_LAST_TRAIL_RT TO trail_rt.
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
            CHAR(10) + "T-" + aoso_hud_eta(o["patch_eta"]).
    }
    SET AOSO_UI2_NAV_RIGHT:TEXT TO patch_txt.

    LOCAL quality IS "MONITOR".
    LOCAL quality_state IS "SAFE".
    IF o["patch"] <> "" {
        SET quality TO "ENCOUNTER / CORRECT".
        IF goal <> "NO TARGET" {
            IF o["patch"] <> goal AND o["patch"] <> m["hop"] {
                SET quality TO "UNEXPECTED PATCH".
                SET quality_state TO "WARN".
            } ELSE {
                IF o["patch"] = goal {
                    LOCAL patch_body IS BODY(o["patch"]).
                    IF aoso_rendezvous_pe_ok_value(o["patch_pe"], patch_body) {
                        SET quality TO "CAPTURE CORRIDOR".
                    } ELSE {
                        IF aoso_rendezvous_pe_rough_ok_value(o["patch_pe"], patch_body) {
                            SET quality TO "ROUGH / SAFE".
                        }
                    }
                } ELSE {
                    SET quality TO "ROUTE PATCH".
                }
            }
        }
    }
    IF o["node"] { SET quality TO "MANEUVER READY". }
    IF o["burning"] { SET quality TO "BURN EXECUTION". }
    SET AOSO_UI2_NAV_COURSE:TEXT TO aoso_ui2_color_state(quality_state, quality).

    LOCAL detail IS "PREDICTED CONIC  " + AOSO_UI2_NAV_PRED:LENGTH +
        " samples   dV " + ROUND(res["mission_dv"], 0) + " m/s".
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
    SET AOSO_UI2_SURF_PRED TO aoso_ui2_marker(AOSO_UI2_SURF_MAIN, AOSO_UI2_ASSET_ROOT + "pred_bug.png", 10).
    SET AOSO_UI2_SURF_PRED:VISIBLE TO FALSE.

    SET AOSO_UI2_SURF_LEFT TO aoso_ui2_overlay_label(AOSO_UI2_SURF_MAIN, "", 12, 24).
    SET AOSO_UI2_SURF_RIGHT TO aoso_ui2_overlay_label(AOSO_UI2_SURF_MAIN, "", 290, 24).
    SET AOSO_UI2_SURF_BOTTOM TO aoso_ui2_overlay_label(AOSO_UI2_SURF_MAIN, "", 92, 207).

    aoso_hud_lab(page, "ui2_surf_detail", "").
    aoso_hud_lab(page, "ui2_surf_energy", "").

    LOCAL vt IS page:ADDLABEL("<b>VERTICAL SITUATION / DESCENT ENERGY</b>").
    SET vt:STYLE:HSTRETCH TO TRUE.
    SET vt:STYLE:ALIGN TO "center".
    SET AOSO_UI2_SURF_VSIT TO page:ADDVLAYOUT().
    SET AOSO_UI2_SURF_VSIT:STYLE:WIDTH TO 420.
    SET AOSO_UI2_SURF_VSIT:STYLE:HEIGHT TO 120.
    SET AOSO_UI2_SURF_VSIT:STYLE:ALIGN TO "center".
    SET AOSO_UI2_SURF_VSIT:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "descent_frame.png".
    SET AOSO_UI2_SURF_ALTBUG TO aoso_ui2_marker(
        AOSO_UI2_SURF_VSIT,
        AOSO_UI2_ASSET_ROOT + "ship_bug.png",
        18).
    SET AOSO_UI2_SURF_TRIGBUG TO aoso_ui2_marker(
        AOSO_UI2_SURF_VSIT,
        AOSO_UI2_ASSET_ROOT + "site_bug.png",
        16).
    SET AOSO_UI2_SURF_VSINFO TO aoso_ui2_overlay_label(AOSO_UI2_SURF_VSIT, "", 78, 12).
    SET AOSO_UI2_SURF_VSIT:VISIBLE TO FALSE.
}

FUNCTION aoso_ui2_surface_update {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    LOCAL l IS AOSO_HUD_DATA["landing"].
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    LOCAL res IS AOSO_HUD_DATA["res"].

    LOCAL phase IS "SURVEY".
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] <> "" { SET phase TO AOSO_TOUR["current"]. }
    }
    IF l["active"] { SET phase TO l["state"]. }

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

    LOCAL descent_mode IS FALSE.
    IF l["active"] { SET descent_mode TO TRUE. }
    IF phase = "DEORBIT" OR phase = "DESCEND" { SET descent_mode TO TRUE. }

    IF descent_mode {
        SET AOSO_UI2_SURF_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "descent_frame.png".
        SET AOSO_UI2_SURF_TITLE:TEXT TO "<b><size=18>" + SHIP:BODY:NAME + "  DESCENT DIRECTOR</size></b>".

        // Site is the center of the local display. Ship position is projected
        // into local east/north error so the pilot can see convergence.
        SET AOSO_UI2_SURF_SITE:STYLE:MARGIN:H TO 210.
        SET AOSO_UI2_SURF_SITE:STYLE:MARGIN:V TO 60.
        SET AOSO_UI2_SURF_SITE:VISIBLE TO have_site.

        LOCAL err_e IS 0.
        LOCAL err_n IS 0.
        LOCAL err_m IS 0.
        IF have_site {
            LOCAL site_geo IS LATLNG(slat, slng).
            LOCAL delta IS site_geo:POSITION - SHIP:POSITION.
            LOCAL upv IS SHIP:UP:VECTOR.
            LOCAL northv IS SHIP:NORTH:VECTOR.
            LOCAL eastv IS VCRS(upv, northv).
            LOCAL horiz IS VXCL(upv, delta).
            SET err_e TO VDOT(horiz, eastv).
            SET err_n TO VDOT(horiz, northv).
            SET err_m TO horiz:MAG.

            LOCAL span IS MAX(1000, MIN(50000, err_m * 1.25)).
            LOCAL sx IS CLAMP(err_e / span, -1, 1).
            LOCAL sy IS CLAMP(err_n / span, -1, 1).
            SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:H TO 210 - sx * 155.
            SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:V TO 60 + sy * 72.
        } ELSE {
            SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:H TO 210.
            SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:V TO 132.
        }

        // Cheap coast prediction bug. This is intentionally not guidance:
        // it shows where the current ballistic trend points if thrust stopped.
        SET AOSO_UI2_SURF_PRED:VISIBLE TO FALSE.
        IF have_site {
            IF f["vs"] < -0.5 AND l["radar"] > 1 {
                LOCAL tti IS l["radar"] / MAX(1, -f["vs"]).
                IF tti > 0 { 
                    LOCAL pred_cap IS aoso_config_get("UI2_DESCENT_PRED_MAX_S", 180).
                    IF pred_cap < 10 { SET pred_cap TO 10. }
                    IF tti > pred_cap { SET tti TO pred_cap. }
                    LOCAL pred_geo IS SHIP:BODY:GEOPOSITIONOF(POSITIONAT(SHIP, TIME:SECONDS + tti)).
                    LOCAL pred_site_geo IS LATLNG(slat, slng).
                    LOCAL pdelta IS pred_geo:POSITION - pred_site_geo:POSITION.
                    LOCAL pup IS SHIP:UP:VECTOR.
                    LOCAL pnorth IS SHIP:NORTH:VECTOR.
                    LOCAL peast IS VCRS(pup, pnorth).
                    LOCAL ph IS VXCL(pup, pdelta).
                    LOCAL pe IS VDOT(ph, peast).
                    LOCAL pn IS VDOT(ph, pnorth).
                    LOCAL pspan IS MAX(1000, MIN(50000, MAX(err_m, ph:MAG) * 1.25)).
                    SET AOSO_UI2_SURF_PRED:STYLE:MARGIN:H TO 210 + CLAMP(pe / pspan, -1, 1) * 155.
                    SET AOSO_UI2_SURF_PRED:STYLE:MARGIN:V TO 60 - CLAMP(pn / pspan, -1, 1) * 72.
                    SET AOSO_UI2_SURF_PRED:VISIBLE TO TRUE.
                }
            }
        }

        SET AOSO_UI2_SURF_LEFT:TEXT TO "RAD " + ROUND(l["radar"], 0) + "m" + CHAR(10) +
            "VS " + ROUND(f["vs"], 1) + "m/s" + CHAR(10) +
            "H " + ROUND(f["gs"], 1) + "m/s".
        SET AOSO_UI2_SURF_RIGHT:TEXT TO "SITE ERR" + CHAR(10) +
            ROUND(err_m, 0) + "m" + CHAR(10) +
            "E " + ROUND(err_e, 0) + " N " + ROUND(err_n, 0).

        LOCAL margin IS l["radar"] - l["trig"].
        SET AOSO_UI2_SURF_BOTTOM:TEXT TO "SUICIDE " + ROUND(l["trig"], 0) +
            "m   MARGIN " + ROUND(margin, 0) + "m".

        // Vertical situation inset: altitude and suicide-burn trigger share
        // one scale so the closing margin is visible at a glance.
        SET AOSO_UI2_SURF_VSIT:VISIBLE TO TRUE.
        LOCAL alt_scale IS MAX(100, MAX(l["radar"], l["trig"]) * 1.15).
        LOCAL alt_frac IS CLAMP(l["radar"] / alt_scale, 0, 1).
        LOCAL trig_frac IS CLAMP(l["trig"] / alt_scale, 0, 1).
        SET AOSO_UI2_SURF_ALTBUG:STYLE:MARGIN:H TO 210.
        SET AOSO_UI2_SURF_ALTBUG:STYLE:MARGIN:V TO 105 - alt_frac * 82.
        SET AOSO_UI2_SURF_TRIGBUG:STYLE:MARGIN:H TO 236.
        SET AOSO_UI2_SURF_TRIGBUG:STYLE:MARGIN:V TO 105 - trig_frac * 82.
        LOCAL margin_state IS "SAFE".
        IF margin < 150 { SET margin_state TO "WARN". }
        IF margin < 0 { SET margin_state TO "FAIL". }
        SET AOSO_UI2_SURF_VSINFO:TEXT TO "RAD " + ROUND(l["radar"], 0) +
            "m   TRIG " + ROUND(l["trig"], 0) + "m   " +
            aoso_ui2_color_state(margin_state, "MARGIN " + ROUND(margin, 0) + "m").

        aoso_hud_set("ui2_surf_detail", "SITE score " + ROUND(site_score, 2) +
            "   rough " + ROUND(rough, 0) + "m   coast bug = small square").
        aoso_hud_set("ui2_surf_energy", "TWR " + ROUND(f["twr"], 2) +
            "   THR " + ROUND(f["throttle"] * 100, 0) + "%   LAND dV " +
            ROUND(res["land_dv"], 0) + " / HAVE " + ROUND(res["mission_dv"], 0) + " m/s").
        RETURN.
    }

    // Polar survey mode: global latitude/longitude situation display.
    SET AOSO_UI2_SURF_VSIT:VISIBLE TO FALSE.
    SET AOSO_UI2_SURF_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "survey_frame.png".
    SET AOSO_UI2_SURF_TITLE:TEXT TO "<b><size=18>" + SHIP:BODY:NAME + "  POLAR SURVEY</size></b>".
    SET AOSO_UI2_SURF_PRED:VISIBLE TO FALSE.

    LOCAL ship_geo IS SHIP:GEOPOSITION.
    LOCAL spos IS aoso_ui2_geo_xy(ship_geo:LAT, ship_geo:LNG).
    SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:H TO spos[0].
    SET AOSO_UI2_SURF_SHIP:STYLE:MARGIN:V TO spos[1].

    IF have_site {
        LOCAL p IS aoso_ui2_geo_xy(slat, slng).
        SET AOSO_UI2_SURF_SITE:STYLE:MARGIN:H TO p[0].
        SET AOSO_UI2_SURF_SITE:STYLE:MARGIN:V TO p[1].
        SET AOSO_UI2_SURF_SITE:VISIBLE TO TRUE.
    } ELSE {
        SET AOSO_UI2_SURF_SITE:VISIBLE TO FALSE.
    }

    SET AOSO_UI2_SURF_LEFT:TEXT TO "LAT " + ROUND(ship_geo:LAT, 1) + "°" + CHAR(10) +
        "LON " + ROUND(ship_geo:LNG, 1) + "°" + CHAR(10) +
        "INC " + ROUND(o["inc"], 1) + "°".
    IF have_site {
        SET AOSO_UI2_SURF_RIGHT:TEXT TO "SITE " + ROUND(slat, 1) + "°" + CHAR(10) +
            ROUND(slng, 1) + "°" + CHAR(10) + "SCORE " + ROUND(site_score, 1).
    } ELSE {
        SET AOSO_UI2_SURF_RIGHT:TEXT TO "SITE" + CHAR(10) + "SEARCHING" + CHAR(10) + "---".
    }
    SET AOSO_UI2_SURF_BOTTOM:TEXT TO "GROUND TRACK  ·  BEST CANDIDATE ★".

    LOCAL site_txt IS "NO CANDIDATE".
    IF have_site {
        SET site_txt TO "BEST SITE  score " + ROUND(site_score, 2) +
            "   rough " + ROUND(rough, 0) + "m".
    }
    aoso_hud_set("ui2_surf_detail", site_txt).
    aoso_hud_set("ui2_surf_energy", "POLAR " + ROUND(o["inc"], 1) +
        "°   AP " + aoso_hud_km(o["ap"]) + "   PE " + aoso_hud_km(o["pe"])).
}
