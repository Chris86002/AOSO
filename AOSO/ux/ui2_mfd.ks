// AOSO/ux/ui2_mfd.ks
// UI v2 mission, systems, and vehicle MFD pages.
// These are graphical presentation surfaces backed by existing AOSO models.
// No mission/control authority lives here.

GLOBAL AOSO_UI2_MSN_MAIN IS 0.
GLOBAL AOSO_UI2_MSN_ROUTE IS LIST().
GLOBAL AOSO_UI2_MSN_HEAD IS 0.
GLOBAL AOSO_UI2_MSN_PHASE IS 0.
GLOBAL AOSO_UI2_MSN_PROGRESS IS 0.
GLOBAL AOSO_UI2_MSN_OBJECTIVE IS 0.
GLOBAL AOSO_UI2_MSN_DV IS 0.

GLOBAL AOSO_UI2_SYS_MAIN IS 0.
GLOBAL AOSO_UI2_SYS_BOXES IS LEXICON().
GLOBAL AOSO_UI2_SYS_MASTER IS 0.
GLOBAL AOSO_UI2_SYS_WHY IS 0.
GLOBAL AOSO_UI2_SYS_CPU IS 0.
GLOBAL AOSO_UI2_SYS_ORDER IS LIST(
    "guid", "nav", "steer", "thr", "stg",
    "msn", "lnd", "pwr", "com", "wd"
).
GLOBAL AOSO_UI2_SYS_LABELS IS LEXICON(
    "guid", "GUID",
    "nav", "NAV",
    "steer", "STEER",
    "thr", "THR",
    "stg", "STAGE",
    "msn", "MISSION",
    "lnd", "LAND",
    "pwr", "POWER",
    "com", "COMMS",
    "wd", "WATCH"
).

GLOBAL AOSO_UI2_TWIN_BOX IS 0.
GLOBAL AOSO_UI2_TWIN_W IS LEXICON().
GLOBAL AOSO_UI2_TWIN_LAST IS LEXICON().
GLOBAL AOSO_UI2_TWIN_SIG IS "".
GLOBAL AOSO_UI2_TWIN_SUMMARY IS 0.

FUNCTION aoso_ui2_short_body {
    PARAMETER name.
    IF name:LENGTH <= 6 { RETURN name:TOUPPER. }
    RETURN name:SUBSTRING(0, 6):TOUPPER.
}

FUNCTION aoso_ui2_mission_build {
    PARAMETER page.
    aoso_hud_title(page, "MISSION / GRAND TOUR").

    SET AOSO_UI2_MSN_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_MSN_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_MSN_MAIN:STYLE:HEIGHT TO 180.
    SET AOSO_UI2_MSN_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_MSN_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "mission_frame.png".

    SET AOSO_UI2_MSN_HEAD TO AOSO_UI2_MSN_MAIN:ADDLABEL("<b>MISSION ROUTE</b>").
    SET AOSO_UI2_MSN_HEAD:STYLE:ALIGN TO "center".
    SET AOSO_UI2_MSN_HEAD:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_MSN_PHASE TO AOSO_UI2_MSN_MAIN:ADDLABEL("PHASE ---").
    SET AOSO_UI2_MSN_PHASE:STYLE:ALIGN TO "center".
    SET AOSO_UI2_MSN_PHASE:STYLE:HSTRETCH TO TRUE.

    SET AOSO_UI2_MSN_ROUTE TO LIST().
    LOCAL row1 IS AOSO_UI2_MSN_MAIN:ADDHLAYOUT().
    SET row1:STYLE:WIDTH TO 400.
    LOCAL row2 IS AOSO_UI2_MSN_MAIN:ADDHLAYOUT().
    SET row2:STYLE:WIDTH TO 400.
    LOCAL i IS 0.
    UNTIL i >= 16 {
        LOCAL row IS row1.
        IF i >= 8 { SET row TO row2. }
        LOCAL b IS row:ADDBUTTON("---").
        SET b:STYLE:WIDTH TO 49.
        SET b:STYLE:HEIGHT TO 28.
        SET b:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "button_stby.png".
        AOSO_UI2_MSN_ROUTE:ADD(b).
        SET i TO i + 1.
    }

    SET AOSO_UI2_MSN_PROGRESS TO AOSO_UI2_MSN_MAIN:ADDLABEL("").
    SET AOSO_UI2_MSN_PROGRESS:STYLE:ALIGN TO "center".
    SET AOSO_UI2_MSN_PROGRESS:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_MSN_OBJECTIVE TO AOSO_UI2_MSN_MAIN:ADDLABEL("").
    SET AOSO_UI2_MSN_OBJECTIVE:STYLE:ALIGN TO "center".
    SET AOSO_UI2_MSN_OBJECTIVE:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_MSN_DV TO AOSO_UI2_MSN_MAIN:ADDLABEL("").
    SET AOSO_UI2_MSN_DV:STYLE:ALIGN TO "center".
    SET AOSO_UI2_MSN_DV:STYLE:HSTRETCH TO TRUE.
}

FUNCTION aoso_ui2_mission_update {
    IF NOT AOSO_UI2_MSN_MAIN:ISTYPE("Box") { RETURN. }
    LOCAL m IS AOSO_HUD_DATA["mission"].
    LOCAL r IS AOSO_HUD_DATA["res"].

    LOCAL phase IS m["tour"].
    IF phase = "" { SET phase TO m["goto"]. }
    IF phase = "" { SET phase TO m["mission"]. }
    SET AOSO_UI2_MSN_PHASE:TEXT TO "PHASE  " + phase + "   BODY  " + SHIP:BODY:NAME.

    LOCAL targets IS LIST().
    LOCAL idx IS -1.
    LOCAL accomplished IS LEXICON().
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            LOCAL td IS AOSO_TOUR["data"].
            IF td:HASKEY("targets") { SET targets TO td["targets"]. }
            IF td:HASKEY("index") { SET idx TO td["index"]. }
            IF td:HASKEY("accomplished") { SET accomplished TO td["accomplished"]. }
        }
    }
    IF targets:LENGTH = 0 {
        IF DEFINED AOSO_PLAN_LAST {
            IF AOSO_PLAN_LAST:HASKEY("targets") { SET targets TO AOSO_PLAN_LAST["targets"]. }
        }
    }

    LOCAL i IS 0.
    UNTIL i >= AOSO_UI2_MSN_ROUTE:LENGTH {
        LOCAL b IS AOSO_UI2_MSN_ROUTE[i].
        IF i < targets:LENGTH {
            LOCAL nm IS targets[i].
            SET b:TEXT TO aoso_ui2_short_body(nm).
            SET b:VISIBLE TO TRUE.
            LOCAL bg IS AOSO_UI2_ASSET_ROOT + "button_off.png".
            IF i = idx { SET bg TO AOSO_UI2_ASSET_ROOT + "button_warn.png". }
            IF accomplished:HASKEY(nm) {
                IF accomplished[nm] = "LANDED" OR accomplished[nm] = "ORBITED" {
                    SET bg TO AOSO_UI2_ASSET_ROOT + "button_on.png".
                }
                IF accomplished[nm] = "SKIPPED" {
                    SET bg TO AOSO_UI2_ASSET_ROOT + "button_stby.png".
                }
            } ELSE {
                IF i < idx { SET bg TO AOSO_UI2_ASSET_ROOT + "button_on.png". }
            }
            SET b:STYLE:BG TO bg.
        } ELSE {
            SET b:TEXT TO "".
            SET b:VISIBLE TO FALSE.
        }
        SET i TO i + 1.
    }

    LOCAL current IS m["goal"].
    IF current = "" { SET current TO m["next"]. }
    IF current = "" { SET current TO SHIP:BODY:NAME. }
    SET AOSO_UI2_MSN_HEAD:TEXT TO "<b>" + m["mission"] + "   →   " + current + "</b>".

    LOCAL done IS 0.
    LOCAL total IS targets:LENGTH.
    IF idx > 0 { SET done TO idx. }
    FOR k IN accomplished:KEYS {
        IF accomplished[k] = "LANDED" OR accomplished[k] = "ORBITED" { SET done TO done + 1. }
    }
    IF total < done { SET total TO done. }
    LOCAL pct IS 0.
    IF total > 0 { SET pct TO CLAMP(done / total, 0, 1). }
    SET AOSO_UI2_MSN_PROGRESS:TEXT TO "TOUR  " + aoso_ui2_bar(pct, 26) +
        "  " + ROUND(pct * 100, 0) + "%".

    LOCAL obj IS AOSO_HUD_DATA["flight"]["doing"].
    IF obj = "" { SET obj TO m["step"]. }
    SET AOSO_UI2_MSN_OBJECTIVE:TEXT TO "OBJECTIVE  " + obj.
    SET AOSO_UI2_MSN_DV:TEXT TO "MISSION dV  " + ROUND(r["mission_dv"], 0) +
        " m/s   TOTAL " + ROUND(r["total_dv"], 0) +
        "   EC " + ROUND(r["ec"], 0) + "%".
}

FUNCTION aoso_ui2_systems_build {
    PARAMETER page.
    aoso_hud_title(page, "SYSTEMS / CAUTION & WARNING").

    SET AOSO_UI2_SYS_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_SYS_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_SYS_MAIN:STYLE:HEIGHT TO 180.
    SET AOSO_UI2_SYS_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_SYS_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "systems_frame.png".

    SET AOSO_UI2_SYS_MASTER TO AOSO_UI2_SYS_MAIN:ADDLABEL("<b>ALL SYSTEMS NOMINAL</b>").
    SET AOSO_UI2_SYS_MASTER:STYLE:ALIGN TO "center".
    SET AOSO_UI2_SYS_MASTER:STYLE:HSTRETCH TO TRUE.

    SET AOSO_UI2_SYS_BOXES TO LEXICON().
    LOCAL row1 IS AOSO_UI2_SYS_MAIN:ADDHLAYOUT().
    LOCAL row2 IS AOSO_UI2_SYS_MAIN:ADDHLAYOUT().
    LOCAL i IS 0.
    FOR key IN AOSO_UI2_SYS_ORDER {
        LOCAL row IS row1.
        IF i >= 5 { SET row TO row2. }
        LOCAL b IS row:ADDBUTTON(AOSO_UI2_SYS_LABELS[key]).
        SET b:STYLE:WIDTH TO 80.
        SET b:STYLE:HEIGHT TO 28.
        SET b:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "button_stby.png".
        SET AOSO_UI2_SYS_BOXES[key] TO b.
        SET i TO i + 1.
    }

    SET AOSO_UI2_SYS_WHY TO AOSO_UI2_SYS_MAIN:ADDLABEL("").
    SET AOSO_UI2_SYS_WHY:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_SYS_WHY:STYLE:WORDWRAP TO TRUE.
    SET AOSO_UI2_SYS_CPU TO AOSO_UI2_SYS_MAIN:ADDLABEL("").
    SET AOSO_UI2_SYS_CPU:STYLE:HSTRETCH TO TRUE.
}

FUNCTION aoso_ui2_system_bg {
    PARAMETER st.
    IF st = "NOM" { RETURN AOSO_UI2_ASSET_ROOT + "button_on.png". }
    IF st = "FAIL" { RETURN AOSO_UI2_ASSET_ROOT + "button_fail.png". }
    IF st = "DEG" { RETURN AOSO_UI2_ASSET_ROOT + "button_warn.png". }
    RETURN AOSO_UI2_ASSET_ROOT + "button_stby.png".
}

FUNCTION aoso_ui2_systems_update {
    IF NOT AOSO_UI2_SYS_MAIN:ISTYPE("Box") { RETURN. }
    LOCAL s IS AOSO_HUD_DATA["systems"].
    FOR key IN AOSO_UI2_SYS_ORDER {
        IF AOSO_UI2_SYS_BOXES:HASKEY(key) {
            LOCAL st IS "STBY".
            IF s:HASKEY(key) { SET st TO s[key]. }
            SET AOSO_UI2_SYS_BOXES[key]:STYLE:BG TO aoso_ui2_system_bg(st).
            SET AOSO_UI2_SYS_BOXES[key]:TEXT TO AOSO_UI2_SYS_LABELS[key] + CHAR(10) + st.
        }
    }

    LOCAL roll IS s["rollup"].
    IF roll = "FAIL" {
        SET AOSO_UI2_SYS_MASTER:TEXT TO aoso_ui2_color_state("FAIL", "<b>MASTER WARNING · SYSTEM FAILURE</b>").
    } ELSE {
        IF roll = "DEGRADED" {
            SET AOSO_UI2_SYS_MASTER:TEXT TO aoso_ui2_color_state("WARN", "<b>MASTER CAUTION · DEGRADED</b>").
        } ELSE {
            SET AOSO_UI2_SYS_MASTER:TEXT TO aoso_ui2_color_state("SAFE", "<b>ALL SYSTEMS NOMINAL</b>").
        }
    }

    LOCAL why IS "".
    IF s:HASKEY("why") { SET why TO s["why"]. }
    IF why = "" { SET why TO "No active fault reason.". }
    SET AOSO_UI2_SYS_WHY:TEXT TO "WHY  " + why.

    LOCAL d IS AOSO_HUD_DATA["debug"].
    SET AOSO_UI2_SYS_CPU:TEXT TO "CPU " + d["cpu"] + "  " +
        ROUND(100 * d["frac"], 0) + "% / " + d["ipu"] +
        " IPU   LEFT " + d["left"] + "   EC " +
        ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%".
}

FUNCTION aoso_ui2_twin_click {
    PARAMETER uid.
    aoso_twin_select(uid).
}

FUNCTION aoso_ui2_vehicle_build {
    PARAMETER page.
    aoso_ui2_build_vehicle_frame(page).
    SET AOSO_UI2_VEH_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "twin_frame.png".

    SET AOSO_UI2_TWIN_SUMMARY TO AOSO_UI2_VEH_MAIN:ADDLABEL("DIGITAL TWIN  UPDATING").
    SET AOSO_UI2_TWIN_SUMMARY:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_TWIN_SUMMARY:STYLE:ALIGN TO "center".
    SET AOSO_UI2_TWIN_BOX TO AOSO_UI2_VEH_MAIN:ADDVLAYOUT().
    SET AOSO_UI2_TWIN_BOX:STYLE:WIDTH TO 400.
    SET AOSO_UI2_TWIN_BOX:STYLE:ALIGN TO "center".
    SET AOSO_UI2_TWIN_SIG TO "".
}

FUNCTION aoso_ui2_twin_clear {
    IF NOT AOSO_UI2_TWIN_BOX:ISTYPE("Box") { RETURN. }
    LOCAL kids IS AOSO_UI2_TWIN_BOX:WIDGETS.
    FOR w IN kids { w:DISPOSE(). }
    SET AOSO_UI2_TWIN_W TO LEXICON().
    SET AOSO_UI2_TWIN_LAST TO LEXICON().
}

FUNCTION aoso_ui2_twin_rebuild {
    IF NOT AOSO_UI2_TWIN_BOX:ISTYPE("Box") { RETURN. }
    aoso_ui2_twin_clear().
    IF NOT DEFINED AOSO_TWIN { RETURN. }

    LOCAL bands IS AOSO_TWIN["bands"].
    IF bands:LENGTH = 0 {
        AOSO_UI2_TWIN_BOX:ADDLABEL("No topology nodes available.").
        RETURN.
    }

    LOCAL max_bands IS 6.
    LOCAL bi IS 0.
    UNTIL bi >= bands:LENGTH OR bi >= max_bands {
        LOCAL row IS AOSO_UI2_TWIN_BOX:ADDHLAYOUT().
        SET row:STYLE:WIDTH TO 390.
        LOCAL band IS bands[bi].
        LOCAL n IS band:LENGTH.
        LOCAL width IS 92.
        IF n > 0 {
            SET width TO FLOOR(380 / MIN(n, 4)).
            IF width < 72 { SET width TO 72. }
        }
        LOCAL shown IS 0.
        FOR tnode IN band {
            IF shown >= 4 { BREAK. }
            LOCAL uid IS tnode["uid"].
            LOCAL b IS row:ADDBUTTON(aoso_twin_node_txt(tnode)).
            SET b:STYLE:WIDTH TO width.
            SET b:STYLE:HEIGHT TO 28.
            SET b:ONCLICK TO aoso_ui2_twin_click@:BIND(uid).
            SET AOSO_UI2_TWIN_W[uid] TO b.
            SET AOSO_UI2_TWIN_LAST[uid] TO b:TEXT.
            SET shown TO shown + 1.
        }
        IF band:LENGTH > shown {
            LOCAL more IS row:ADDLABEL("+" + (band:LENGTH - shown)).
            SET more:STYLE:WIDTH TO 35.
        }
        SET bi TO bi + 1.
    }
    IF bands:LENGTH > max_bands {
        AOSO_UI2_TWIN_BOX:ADDLABEL("… " + (bands:LENGTH - max_bands) + " lower topology band(s) hidden; ENG/TWIN has full view.").
    }
    SET AOSO_UI2_TWIN_SIG TO aoso_twin_disp_sig().
}

FUNCTION aoso_ui2_vehicle_update {
    IF NOT AOSO_UI2_VEH_MAIN:ISTYPE("Box") { RETURN. }
    IF NOT DEFINED AOSO_TWIN { RETURN. }

    SET AOSO_UI2_TWIN_SUMMARY:TEXT TO aoso_twin_status_txt() +
        "   PARTS " + AOSO_TWIN["part_n"] +
        "   ENGINES " + AOSO_TWIN["engines_on"] + "/" + AOSO_TWIN["engines_total"] +
        "   STAGE " + STAGE:NUMBER.

    LOCAL sig IS aoso_twin_disp_sig().
    IF sig <> AOSO_UI2_TWIN_SIG {
        aoso_ui2_twin_rebuild().
        RETURN.
    }

    FOR tnode IN AOSO_TWIN["disp"] {
        LOCAL uid IS tnode["uid"].
        IF AOSO_UI2_TWIN_W:HASKEY(uid) {
            LOCAL txt IS aoso_twin_node_txt(tnode).
            IF NOT AOSO_UI2_TWIN_LAST:HASKEY(uid) {
                SET AOSO_UI2_TWIN_W[uid]:TEXT TO txt.
                SET AOSO_UI2_TWIN_LAST[uid] TO txt.
            } ELSE {
                IF AOSO_UI2_TWIN_LAST[uid] <> txt {
                    SET AOSO_UI2_TWIN_W[uid]:TEXT TO txt.
                    SET AOSO_UI2_TWIN_LAST[uid] TO txt.
                }
            }
        }
    }
}
