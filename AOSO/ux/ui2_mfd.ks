// AOSO/ux/ui2_mfd.ks
// UI v2 Mission, Systems, and Vehicle MFD pages.
//
// This is the only owner of the graphical Mission/Systems/Vehicle pages.
// It consumes existing AOSO models and is display-only: callbacks below may
// change UI/twin presentation or highlight parts, but never steer, throttle,
// stage, warp, retarget, or change mission state.

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

GLOBAL AOSO_UI2_VEH_MAIN IS 0.
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

    // Two rows of eight route annunciators. They are intentionally not
    // clickable: AOSO chooses the route; the MFD only reports it.
    SET AOSO_UI2_MSN_ROUTE TO LIST().
    LOCAL route_row1 IS AOSO_UI2_MSN_MAIN:ADDHLAYOUT().
    SET route_row1:STYLE:WIDTH TO 400.
    LOCAL route_row2 IS AOSO_UI2_MSN_MAIN:ADDHLAYOUT().
    SET route_row2:STYLE:WIDTH TO 400.
    LOCAL route_i IS 0.
    UNTIL route_i >= 16 {
        LOCAL route_row IS route_row1.
        IF route_i >= 8 { SET route_row TO route_row2. }
        LOCAL route_box IS route_row:ADDBUTTON("---").
        SET route_box:STYLE:WIDTH TO 49.
        SET route_box:STYLE:HEIGHT TO 28.
        SET route_box:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "button_stby.png".
        AOSO_UI2_MSN_ROUTE:ADD(route_box).
        SET route_i TO route_i + 1.
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
    IF NOT AOSO_UI2_MSN_MAIN:ISTYPE("BOX") { RETURN. }

    LOCAL mission_data IS AOSO_HUD_DATA["mission"].
    LOCAL resource_data IS AOSO_HUD_DATA["res"].

    LOCAL phase_txt IS mission_data["tour"].
    IF phase_txt = "" { SET phase_txt TO mission_data["goto"]. }
    IF phase_txt = "" { SET phase_txt TO mission_data["mission"]. }
    IF phase_txt = "" { SET phase_txt TO "STANDBY". }
    SET AOSO_UI2_MSN_PHASE:TEXT TO "PHASE  " + phase_txt +
        "   BODY  " + SHIP:BODY:NAME.

    LOCAL targets IS LIST().
    LOCAL target_idx IS -1.
    LOCAL accomplished IS LEXICON().
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            LOCAL tour_data IS AOSO_TOUR["data"].
            IF tour_data:HASKEY("targets") { SET targets TO tour_data["targets"]. }
            IF tour_data:HASKEY("index") { SET target_idx TO tour_data["index"]. }
            IF tour_data:HASKEY("accomplished") { SET accomplished TO tour_data["accomplished"]. }
        }
    }
    IF targets:LENGTH = 0 {
        IF DEFINED AOSO_PLAN_LAST {
            IF AOSO_PLAN_LAST:HASKEY("targets") { SET targets TO AOSO_PLAN_LAST["targets"]. }
        }
    }

    LOCAL route_i IS 0.
    UNTIL route_i >= AOSO_UI2_MSN_ROUTE:LENGTH {
        LOCAL route_box IS AOSO_UI2_MSN_ROUTE[route_i].
        IF route_i < targets:LENGTH {
            LOCAL body_name IS targets[route_i].
            SET route_box:TEXT TO aoso_ui2_short_body(body_name).
            SET route_box:VISIBLE TO TRUE.

            LOCAL bg_img IS AOSO_UI2_ASSET_ROOT + "button_off.png".
            IF route_i = target_idx { SET bg_img TO AOSO_UI2_ASSET_ROOT + "button_warn.png". }
            IF accomplished:HASKEY(body_name) {
                LOCAL accomplishment IS accomplished[body_name].
                IF accomplishment = "LANDED" OR accomplishment = "ORBITED" {
                    SET bg_img TO AOSO_UI2_ASSET_ROOT + "button_on.png".
                }
                IF accomplishment = "SKIPPED" {
                    SET bg_img TO AOSO_UI2_ASSET_ROOT + "button_stby.png".
                }
            } ELSE {
                IF target_idx >= 0 {
                    IF route_i < target_idx { SET bg_img TO AOSO_UI2_ASSET_ROOT + "button_on.png". }
                }
            }
            SET route_box:STYLE:BG TO bg_img.
        } ELSE {
            SET route_box:TEXT TO "".
            SET route_box:VISIBLE TO FALSE.
        }
        SET route_i TO route_i + 1.
    }

    LOCAL current_body IS mission_data["goal"].
    IF current_body = "" { SET current_body TO mission_data["next"]. }
    IF current_body = "" { SET current_body TO SHIP:BODY:NAME. }
    SET AOSO_UI2_MSN_HEAD:TEXT TO "<b>" + mission_data["mission"] +
        "   →   " + current_body + "</b>".

    LOCAL done_n IS 0.
    FOR body_key IN accomplished:KEYS {
        LOCAL accomplishment2 IS accomplished[body_key].
        IF accomplishment2 = "LANDED" OR accomplishment2 = "ORBITED" {
            SET done_n TO done_n + 1.
        }
    }
    IF done_n = 0 {
        IF target_idx > 0 { SET done_n TO target_idx. }
    }

    LOCAL total_n IS targets:LENGTH.
    IF total_n < done_n { SET total_n TO done_n. }
    LOCAL progress_frac IS 0.
    IF total_n > 0 { SET progress_frac TO aoso_ui2_clamp(done_n / total_n, 0, 1). }
    SET AOSO_UI2_MSN_PROGRESS:TEXT TO "TOUR  " +
        aoso_ui2_bar(progress_frac, 26) + "  " +
        ROUND(progress_frac * 100, 0) + "%".

    LOCAL objective_txt IS AOSO_HUD_DATA["flight"]["doing"].
    IF objective_txt = "" { SET objective_txt TO mission_data["step"]. }
    SET AOSO_UI2_MSN_OBJECTIVE:TEXT TO "OBJECTIVE  " + objective_txt.

    LOCAL assure_txt IS mission_data["feas"].
    IF assure_txt = "" { SET assure_txt TO "evaluating". }
    IF mission_data["skip"] <> "" { SET assure_txt TO mission_data["skip"]. }

    SET AOSO_UI2_MSN_DV:TEXT TO "MISSION dV  " +
        ROUND(resource_data["mission_dv"], 0) + " m/s   TOTAL " +
        ROUND(resource_data["total_dv"], 0) + "   EC " +
        ROUND(resource_data["ec"], 0) + "%   " + assure_txt.
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
    LOCAL sys_row1 IS AOSO_UI2_SYS_MAIN:ADDHLAYOUT().
    LOCAL sys_row2 IS AOSO_UI2_SYS_MAIN:ADDHLAYOUT().
    LOCAL sys_i IS 0.
    FOR sys_key IN AOSO_UI2_SYS_ORDER {
        LOCAL sys_row IS sys_row1.
        IF sys_i >= 5 { SET sys_row TO sys_row2. }
        LOCAL sys_box IS sys_row:ADDBUTTON(AOSO_UI2_SYS_LABELS[sys_key]).
        SET sys_box:STYLE:WIDTH TO 80.
        SET sys_box:STYLE:HEIGHT TO 28.
        SET sys_box:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "button_stby.png".
        SET AOSO_UI2_SYS_BOXES[sys_key] TO sys_box.
        SET sys_i TO sys_i + 1.
    }

    SET AOSO_UI2_SYS_WHY TO AOSO_UI2_SYS_MAIN:ADDLABEL("").
    SET AOSO_UI2_SYS_WHY:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_SYS_WHY:STYLE:WORDWRAP TO TRUE.
    SET AOSO_UI2_SYS_CPU TO AOSO_UI2_SYS_MAIN:ADDLABEL("").
    SET AOSO_UI2_SYS_CPU:STYLE:HSTRETCH TO TRUE.
}

FUNCTION aoso_ui2_system_bg {
    PARAMETER state_text.
    IF state_text = "NOM" { RETURN AOSO_UI2_ASSET_ROOT + "button_on.png". }
    IF state_text = "FAIL" { RETURN AOSO_UI2_ASSET_ROOT + "button_fail.png". }
    IF state_text = "DEG" { RETURN AOSO_UI2_ASSET_ROOT + "button_warn.png". }
    RETURN AOSO_UI2_ASSET_ROOT + "button_stby.png".
}

FUNCTION aoso_ui2_systems_update {
    IF NOT AOSO_UI2_SYS_MAIN:ISTYPE("BOX") { RETURN. }

    LOCAL system_data IS AOSO_HUD_DATA["systems"].
    FOR sys_key IN AOSO_UI2_SYS_ORDER {
        IF AOSO_UI2_SYS_BOXES:HASKEY(sys_key) {
            LOCAL state_text IS "STBY".
            IF system_data:HASKEY(sys_key) { SET state_text TO system_data[sys_key]. }
            SET AOSO_UI2_SYS_BOXES[sys_key]:STYLE:BG TO aoso_ui2_system_bg(state_text).
            SET AOSO_UI2_SYS_BOXES[sys_key]:TEXT TO
                AOSO_UI2_SYS_LABELS[sys_key] + CHAR(10) + state_text.
        }
    }

    LOCAL rollup_txt IS system_data["rollup"].
    IF rollup_txt = "FAIL" {
        SET AOSO_UI2_SYS_MASTER:TEXT TO
            aoso_ui2_color_state("FAIL", "<b>MASTER WARNING · SYSTEM FAILURE</b>").
    } ELSE {
        IF rollup_txt = "DEGRADED" {
            SET AOSO_UI2_SYS_MASTER:TEXT TO
                aoso_ui2_color_state("WARN", "<b>MASTER CAUTION · DEGRADED</b>").
        } ELSE {
            SET AOSO_UI2_SYS_MASTER:TEXT TO
                aoso_ui2_color_state("SAFE", "<b>ALL SYSTEMS NOMINAL</b>").
        }
    }

    LOCAL why_txt IS "".
    IF system_data:HASKEY("why") { SET why_txt TO system_data["why"]. }
    IF why_txt = "" { SET why_txt TO "No active fault reason.". }
    SET AOSO_UI2_SYS_WHY:TEXT TO "WHY  " + why_txt.

    LOCAL debug_data IS AOSO_HUD_DATA["debug"].
    LOCAL cpu_band IS "".
    IF debug_data:HASKEY("band") { SET cpu_band TO debug_data["band"]. }
    LOCAL ui_cost_txt IS "".
    IF DEFINED AOSO_UI2_LAST_RENDER_MS {
        SET ui_cost_txt TO "   UI " + AOSO_UI2_LAST_RENDER_PAGE + " " +
            ROUND(AOSO_UI2_LAST_RENDER_MS, 2) + "ms/" +
            AOSO_UI2_LAST_RENDER_OP + "op".
    }
    SET AOSO_UI2_SYS_CPU:TEXT TO "CPU " + debug_data["cpu"] + " " +
        cpu_band + "   " + ROUND(100 * debug_data["frac"], 0) +
        "% / " + debug_data["ipu"] + " IPU   LEFT " + debug_data["left"] +
        "   EC " + ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%" + ui_cost_txt.
}

FUNCTION aoso_ui2_build_vehicle_frame {
    PARAMETER page.
    SET AOSO_UI2_VEH_MAIN TO page:ADDVLAYOUT().
    SET AOSO_UI2_VEH_MAIN:STYLE:WIDTH TO 420.
    SET AOSO_UI2_VEH_MAIN:STYLE:HEIGHT TO 250.
    SET AOSO_UI2_VEH_MAIN:STYLE:ALIGN TO "center".
    SET AOSO_UI2_VEH_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "twin_frame.png".
    RETURN AOSO_UI2_VEH_MAIN.
}

FUNCTION aoso_ui2_twin_click {
    PARAMETER uid.
    aoso_twin_select(uid).
}

FUNCTION aoso_ui2_vehicle_build {
    PARAMETER page.
    aoso_hud_title(page, "VEHICLE / DIGITAL TWIN").
    aoso_ui2_build_vehicle_frame(page).

    SET AOSO_UI2_TWIN_SUMMARY TO AOSO_UI2_VEH_MAIN:ADDLABEL("DIGITAL TWIN  UPDATING").
    SET AOSO_UI2_TWIN_SUMMARY:STYLE:HSTRETCH TO TRUE.
    SET AOSO_UI2_TWIN_SUMMARY:STYLE:ALIGN TO "center".

    SET AOSO_UI2_TWIN_BOX TO AOSO_UI2_VEH_MAIN:ADDVLAYOUT().
    SET AOSO_UI2_TWIN_BOX:STYLE:WIDTH TO 400.
    SET AOSO_UI2_TWIN_BOX:STYLE:ALIGN TO "center".
    SET AOSO_UI2_TWIN_SIG TO "".
}

FUNCTION aoso_ui2_twin_clear {
    IF NOT AOSO_UI2_TWIN_BOX:ISTYPE("BOX") { RETURN. }
    LOCAL child_widgets IS AOSO_UI2_TWIN_BOX:WIDGETS.
    FOR child_widget IN child_widgets { child_widget:DISPOSE(). }
    SET AOSO_UI2_TWIN_W TO LEXICON().
    SET AOSO_UI2_TWIN_LAST TO LEXICON().
}

FUNCTION aoso_ui2_vehicle_bands {
    IF DEFINED AOSO_TWIN {
        IF AOSO_TWIN:HASKEY("disp") {
            RETURN aoso_twin_bands_stage(AOSO_TWIN["disp"]).
        }
    }
    RETURN LIST().
}

FUNCTION aoso_ui2_twin_rebuild {
    IF NOT AOSO_UI2_TWIN_BOX:ISTYPE("BOX") { RETURN. }

    aoso_ui2_twin_clear().
    LOCAL bands IS aoso_ui2_vehicle_bands().
    IF bands:LENGTH = 0 {
        AOSO_UI2_TWIN_BOX:ADDLABEL("No topology nodes available.").
        SET AOSO_UI2_TWIN_SIG TO "".
        RETURN.
    }

    LOCAL max_bands IS 6.
    LOCAL band_i IS 0.
    UNTIL band_i >= bands:LENGTH OR band_i >= max_bands {
        LOCAL twin_row IS AOSO_UI2_TWIN_BOX:ADDHLAYOUT().
        SET twin_row:STYLE:WIDTH TO 390.
        LOCAL band IS bands[band_i].
        LOCAL node_n IS band:LENGTH.
        LOCAL node_width IS 92.
        IF node_n > 0 {
            SET node_width TO FLOOR(380 / MIN(node_n, 4)).
            IF node_width < 72 { SET node_width TO 72. }
        }

        LOCAL shown_n IS 0.
        FOR twin_node IN band {
            IF shown_n >= 4 { BREAK. }
            LOCAL uid IS twin_node["uid"].
            LOCAL node_box IS twin_row:ADDBUTTON(aoso_twin_node_txt(twin_node)).
            SET node_box:STYLE:WIDTH TO node_width.
            SET node_box:STYLE:HEIGHT TO 28.
            SET node_box:ONCLICK TO aoso_ui2_twin_click@:BIND(uid).
            SET AOSO_UI2_TWIN_W[uid] TO node_box.
            SET AOSO_UI2_TWIN_LAST[uid] TO node_box:TEXT.
            SET shown_n TO shown_n + 1.
        }
        IF band:LENGTH > shown_n {
            LOCAL more_lab IS twin_row:ADDLABEL("+" + (band:LENGTH - shown_n)).
            SET more_lab:STYLE:WIDTH TO 35.
        }
        SET band_i TO band_i + 1.
    }

    IF bands:LENGTH > max_bands {
        AOSO_UI2_TWIN_BOX:ADDLABEL("… " + (bands:LENGTH - max_bands) +
            " lower stage band(s) hidden; ENG/TWIN has the full topology.").
    }
    SET AOSO_UI2_TWIN_SIG TO aoso_twin_disp_sig() + "|" + STAGE:NUMBER.
}

FUNCTION aoso_ui2_vehicle_update {
    IF NOT AOSO_UI2_VEH_MAIN:ISTYPE("BOX") { RETURN. }
    IF DEFINED AOSO_TWIN {
        IF NOT AOSO_TWIN:HASKEY("disp") { RETURN. }
    } ELSE {
        RETURN.
    }

    SET AOSO_UI2_TWIN_SUMMARY:TEXT TO aoso_twin_status_txt() +
        "   PARTS " + AOSO_TWIN["part_n"] +
        "   ENGINES " + AOSO_TWIN["engines_on"] + "/" +
        AOSO_TWIN["engines_total"] + "   STAGE " + STAGE:NUMBER.

    LOCAL current_sig IS aoso_twin_disp_sig() + "|" + STAGE:NUMBER.
    IF current_sig <> AOSO_UI2_TWIN_SIG {
        aoso_ui2_twin_rebuild().
        RETURN.
    }

    FOR twin_node IN AOSO_TWIN["disp"] {
        LOCAL uid IS twin_node["uid"].
        IF AOSO_UI2_TWIN_W:HASKEY(uid) {
            LOCAL node_txt IS aoso_twin_node_txt(twin_node).
            IF NOT AOSO_UI2_TWIN_LAST:HASKEY(uid) {
                SET AOSO_UI2_TWIN_W[uid]:TEXT TO node_txt.
                SET AOSO_UI2_TWIN_LAST[uid] TO node_txt.
            } ELSE {
                IF AOSO_UI2_TWIN_LAST[uid] <> node_txt {
                    SET AOSO_UI2_TWIN_W[uid]:TEXT TO node_txt.
                    SET AOSO_UI2_TWIN_LAST[uid] TO node_txt.
                }
            }
        }
    }
}
