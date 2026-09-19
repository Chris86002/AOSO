// AOSO/ux/hud_data.ks
// HUD telemetry cache. Collectors only. Rendering lives elsewhere.
// High/medium/low rate gates so the HUD never walks PARTS or replans.

GLOBAL AOSO_HUD_DATA IS LEXICON().
GLOBAL AOSO_HUD_LAST_HI IS 0.
GLOBAL AOSO_HUD_LAST_MD IS 0.
GLOBAL AOSO_HUD_LAST_LO IS 0.
GLOBAL AOSO_HUD_CTX IS "IDLE".

FUNCTION aoso_hud_data_init {
    SET AOSO_HUD_DATA TO LEXICON(
        "flight", LEXICON(),
        "orbit", LEXICON(),
        "target", LEXICON(),
        "prop", LEXICON(),
        "res", LEXICON(),
        "mission", LEXICON(),
        "landing", LEXICON(),
        "staging", LEXICON(),
        "systems", LEXICON(),
        "debug", LEXICON(),
        "vehicle", LEXICON()
    ).
    SET AOSO_HUD_LAST_HI TO 0.
    SET AOSO_HUD_LAST_MD TO 0.
    SET AOSO_HUD_LAST_LO TO 0.
    SET AOSO_HUD_CTX TO "IDLE".
}

FUNCTION aoso_hud_rates {
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl >= 3 {
        RETURN LEXICON("hi", 0.45, "md", 2.5, "lo", 10, "gui", FALSE, "fd", FALSE, "term", TRUE).
    }
    IF lvl >= 2 {
        RETURN LEXICON("hi", 0.22, "md", 1.0, "lo", 5, "gui", TRUE, "fd", FALSE, "term", TRUE).
    }
    RETURN LEXICON("hi", 0.12, "md", 0.5, "lo", 2.5, "gui", TRUE, "fd", TRUE, "term", TRUE).
}

FUNCTION aoso_hud_local_g {
    LOCAL rad IS SHIP:BODY:RADIUS + ALTITUDE.
    IF rad <= 0 { RETURN 9.81. }
    RETURN SHIP:BODY:MU / (rad * rad).
}

FUNCTION aoso_hud_collect_flight {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    SET f["alt"] TO ALTITUDE.
    LOCAL radar IS ALT:RADAR.
    LOCAL show_radar IS FALSE.
    IF radar > 0 {
        IF radar < ALTITUDE * 0.6 { SET show_radar TO TRUE. }
    }
    IF SHIP:STATUS = "FLYING" { SET show_radar TO TRUE. }
    IF SHIP:STATUS = "LANDED" { SET show_radar TO TRUE. }
    SET f["radar"] TO radar.
    SET f["show_radar"] TO show_radar.
    SET f["vs"] TO VERTICALSPEED.
    SET f["gs"] TO SHIP:GROUNDSPEED.
    SET f["srf"] TO SHIP:VELOCITY:SURFACE:MAG.
    SET f["orb"] TO SHIP:VELOCITY:ORBIT:MAG.
    SET f["hdg"] TO aoso_hud_heading_deg().
    SET f["pitch"] TO aoso_hud_pitch_deg().
    SET f["roll"] TO aoso_hud_roll_deg().
    SET f["aoa"] TO aoso_hud_aoa_deg().
    SET f["q"] TO SHIP:Q.
    SET f["throttle"] TO THROTTLE.
    SET f["mass"] TO SHIP:MASS.
    SET f["thrust"] TO SHIP:AVAILABLETHRUST.
    LOCAL g IS aoso_hud_local_g().
    LOCAL twr IS 0.
    IF SHIP:MASS > 0 {
        IF g > 0 { SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * g). }
    }
    SET f["twr"] TO twr.
    SET f["body"] TO SHIP:BODY:NAME.
    SET f["status"] TO SHIP:STATUS.
    SET f["atm"] TO SHIP:BODY:ATM:EXISTS.
    SET f["in_atm"] TO FALSE.
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT { SET f["in_atm"] TO TRUE. }
    }
    SET f["stage"] TO STAGE:NUMBER.
    SET f["sas"] TO SAS.
    SET f["rcs"] TO RCS.
    SET f["gear"] TO GEAR.
    SET f["lights"] TO LIGHTS.
    SET f["warp"] TO aoso_warp_diag_txt().
    SET f["doing"] TO AOSO_UI["doing"].
    SET f["detail"] TO AOSO_UI["detail"].
}

FUNCTION aoso_hud_collect_orbit {
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    SET o["body"] TO SHIP:BODY:NAME.
    SET o["inc"] TO SHIP:ORBIT:INCLINATION.
    SET o["ecc"] TO SHIP:ORBIT:ECCENTRICITY.
    SET o["pe"] TO PERIAPSIS.
    SET o["ap"] TO aoso_orbit_apoapsis_alt().
    SET o["period"] TO aoso_orbit_period_s().
    SET o["ap_eta"] TO aoso_orbit_eta_apoapsis().
    SET o["pe_eta"] TO 0.
    IF SHIP:ORBIT:ECCENTRICITY < 1 { SET o["pe_eta"] TO ETA:PERIAPSIS. }
    SET o["hyper"] TO aoso_orbit_is_hyperbolic().
    SET o["patch"] TO "".
    SET o["patch_pe"] TO 0.
    SET o["patch_eta"] TO 0.
    IF SHIP:ORBIT:HASNEXTPATCH {
        SET o["patch"] TO SHIP:ORBIT:NEXTPATCH:BODY:NAME.
        SET o["patch_pe"] TO SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
        SET o["patch_eta"] TO SHIP:ORBIT:NEXTPATCHETA.
    }
    SET o["node"] TO FALSE.
    SET o["node_dv"] TO 0.
    SET o["node_eta"] TO 0.
    SET o["node_pro"] TO 0.
    SET o["node_nml"] TO 0.
    SET o["node_rad"] TO 0.
    SET o["burn_left"] TO 0.
    SET o["burning"] TO AOSO_MANEUVER_BURNING.
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        SET o["node"] TO TRUE.
        SET o["node_dv"] TO nd:DELTAV:MAG.
        SET o["node_eta"] TO nd:ETA.
        SET o["node_pro"] TO nd:PROGRADE.
        SET o["node_nml"] TO nd:NORMAL.
        SET o["node_rad"] TO nd:RADIALOUT.
        SET o["burn_left"] TO AOSO_MANEUVER_LAST_REMAINING.
        IF o["burning"] {
            IF o["burn_left"] <= 0 { SET o["burn_left"] TO nd:DELTAV:MAG. }
        }
        SET o["burn_s"] TO aoso_perf_burn_time_for_dv(nd:DELTAV:MAG).
    } ELSE {
        SET o["burn_s"] TO 0.
    }
}

FUNCTION aoso_hud_collect_target {
    LOCAL t IS AOSO_HUD_DATA["target"].
    SET t["has"] TO FALSE.
    SET t["name"] TO "".
    SET t["dist"] TO 0.
    SET t["rel"] TO 0.
    SET t["bearing"] TO 0.
    IF HASTARGET {
        SET t["has"] TO TRUE.
        SET t["name"] TO TARGET:NAME.
        SET t["dist"] TO TARGET:DISTANCE.
        SET t["rel"] TO (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT):MAG.
        IF TARGET:ISTYPE("Vessel") {
            SET t["bearing"] TO TARGET:BEARING.
        }
    }
}

FUNCTION aoso_hud_collect_res {
    LOCAL rsrc IS AOSO_HUD_DATA["res"].
    SET rsrc["lf"] TO aoso_resource_pct("LiquidFuel").
    SET rsrc["ox"] TO aoso_resource_pct("Oxidizer").
    SET rsrc["mp"] TO aoso_resource_pct("MonoPropellant").
    SET rsrc["ec"] TO aoso_power_ec_pct().
    SET rsrc["ore"] TO aoso_resource_pct("Ore").
    SET rsrc["stage_pct"] TO aoso_stage_propellant_pct().
    SET rsrc["lf_has"] TO aoso_resource_capacity("LiquidFuel") > 0.
    SET rsrc["ox_has"] TO aoso_resource_capacity("Oxidizer") > 0.
    SET rsrc["mp_has"] TO aoso_resource_capacity("MonoPropellant") > 0.
    SET rsrc["ore_has"] TO aoso_resource_capacity("Ore") > 0.
    LOCAL mission_dv IS 0.
    LOCAL total_dv IS 0.
    LOCAL land_dv IS 0.
    IF DEFINED AOSO_BUDGET {
        IF AOSO_BUDGET:HASKEY("mission_dv") { SET mission_dv TO AOSO_BUDGET["mission_dv"]. }
        IF AOSO_BUDGET:HASKEY("total_dv") { SET total_dv TO AOSO_BUDGET["total_dv"]. }
        IF AOSO_BUDGET:HASKEY("landing_dv") { SET land_dv TO AOSO_BUDGET["landing_dv"]. }
    }
    SET rsrc["mission_dv"] TO mission_dv.
    SET rsrc["total_dv"] TO total_dv.
    SET rsrc["land_dv"] TO land_dv.
    SET rsrc["twr_now"] TO 0.
    SET rsrc["twr_next"] TO 0.
    SET rsrc["role_next"] TO "".
    LOCAL pred IS aoso_capabilities_predict_next().
    SET rsrc["twr_now"] TO pred["twr_now"].
    SET rsrc["twr_next"] TO pred["twr_next"].
    SET rsrc["role_next"] TO pred["role_next"].
}

FUNCTION aoso_hud_collect_mission {
    LOCAL m IS AOSO_HUD_DATA["mission"].
    SET m["mission"] TO "".
    SET m["step"] TO "".
    SET m["tour"] TO "".
    SET m["goto"] TO "".
    SET m["goal"] TO "".
    SET m["hop"] TO "".
    SET m["idx"] TO 0.
    SET m["n"] TO 0.
    SET m["next"] TO "".
    SET m["feas"] TO "".
    SET m["class"] TO "".
    SET m["timeline"] TO "".
    SET m["skip"] TO "".
    IF DEFINED AOSO_MISSION {
        SET m["mission"] TO AOSO_MISSION["current"].
        SET m["step"] TO aoso_mission_current_step_name().
    }
    IF DEFINED AOSO_TOUR {
        SET m["tour"] TO AOSO_TOUR["current"].
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("targets") {
                SET m["n"] TO AOSO_TOUR["data"]["targets"]:LENGTH.
                SET m["idx"] TO AOSO_TOUR["data"]["index"].
                IF m["idx"] >= 0 {
                    IF m["idx"] < m["n"] {
                        SET m["next"] TO AOSO_TOUR["data"]["targets"][m["idx"]].
                    }
                }
            }
        }
    }
    IF DEFINED AOSO_GOTO {
        SET m["goto"] TO AOSO_GOTO["current"].
        IF AOSO_GOTO:HASKEY("data") {
            IF AOSO_GOTO["data"]:HASKEY("goal") { SET m["goal"] TO AOSO_GOTO["data"]["goal"]. }
            IF AOSO_GOTO["data"]:HASKEY("hop") { SET m["hop"] TO AOSO_GOTO["data"]["hop"]. }
        }
    }
    IF DEFINED AOSO_ASCENT {
        SET m["ascent"] TO AOSO_ASCENT["current"].
    } ELSE {
        SET m["ascent"] TO "".
    }
    IF DEFINED AOSO_CLASS_LAST {
        IF AOSO_CLASS_LAST:HASKEY("class") { SET m["class"] TO AOSO_CLASS_LAST["class"]. }
    }
    IF DEFINED AOSO_FEAS_LAST {
        IF AOSO_FEAS_LAST:HASKEY("body") {
            SET m["feas"] TO AOSO_FEAS_LAST["body"] + ": " + AOSO_FEAS_LAST["result"].
        }
    }
    SET m["timeline"] TO aoso_hud_timeline_txt().
    SET m["skip"] TO "".
    IF DEFINED AOSO_FEAS_LAST {
        IF AOSO_FEAS_LAST:HASKEY("result") {
            IF AOSO_FEAS_LAST["result"] = "SKIP" {
                SET m["skip"] TO AOSO_FEAS_LAST["body"] + ": " + AOSO_FEAS_LAST["reason"].
            }
            IF AOSO_FEAS_LAST["result"] = "ORBIT_ONLY" {
                SET m["skip"] TO AOSO_FEAS_LAST["body"] + " orbit-only: " + AOSO_FEAS_LAST["reason"].
            }
        }
    }
}

FUNCTION aoso_hud_timeline_txt {
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("targets") {
                LOCAL targets IS AOSO_TOUR["data"]["targets"].
                LOCAL idx IS AOSO_TOUR["data"]["index"].
                LOCAL out IS "".
                LOCAL i IS 0.
                UNTIL i >= targets:LENGTH {
                    LOCAL mark IS "o".
                    IF i < idx { SET mark TO "x". }
                    IF i = idx { SET mark TO "*". }
                    IF out <> "" { SET out TO out + " ". }
                    SET out TO out + mark + targets[i].
                    SET i TO i + 1.
                    IF i >= 12 {
                        SET out TO out + " ...".
                        BREAK.
                    }
                }
                RETURN out.
            }
        }
    }
    RETURN "".
}

FUNCTION aoso_hud_collect_landing {
    LOCAL l IS AOSO_HUD_DATA["landing"].
    SET l["active"] TO FALSE.
    SET l["state"] TO "STANDBY".
    SET l["radar"] TO 0.
    SET l["trig"] TO 0.
    SET l["site"] TO "".
    SET l["drift_e"] TO 0.
    SET l["drift_n"] TO 0.
    IF DEFINED AOSO_DESCENT {
        IF AOSO_DESCENT["current"] <> "" {
            IF AOSO_DESCENT["current"] <> "TOUCHDOWN" {
                IF AOSO_DESCENT["current"] <> "ABORTED" {
                    SET l["active"] TO TRUE.
                    SET l["state"] TO AOSO_DESCENT["current"].
                } ELSE {
                    SET l["state"] TO AOSO_DESCENT["current"].
                }
            } ELSE {
                SET l["state"] TO "TOUCHDOWN".
            }
        }
    }
    IF l["active"] {
        SET l["radar"] TO aoso_descent_true_radar().
        SET l["trig"] TO aoso_descent_burn_trigger_alt().
        LOCAL srf IS SHIP:VELOCITY:SURFACE.
        LOCAL upv IS SHIP:UP:VECTOR.
        LOCAL horiz IS VXCL(upv, srf).
        SET l["drift_e"] TO VDOT(horiz, VCRS(upv, SHIP:NORTH:VECTOR)).
        SET l["drift_n"] TO VDOT(horiz, SHIP:NORTH:VECTOR).
    }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("site_lat") {
                SET l["site"] TO ROUND(AOSO_TOUR["data"]["site_lat"], 2) + " / " + ROUND(AOSO_TOUR["data"]["site_lng"], 2).
            }
        }
    }
}

FUNCTION aoso_hud_collect_systems {
    LOCAL s IS AOSO_HUD_DATA["systems"].
    LOCAL cpu_st IS "NOM".
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 3 { SET cpu_st TO "FAIL". }
        ELSE {
            IF AOSO_CPU_LEVEL >= 2 { SET cpu_st TO "DEG". }
        }
    }
    SET s["cpu"] TO cpu_st.
    LOCAL ec IS AOSO_HUD_DATA["res"]["ec"].
    LOCAL pwr_st IS "NOM".
    IF ec <= aoso_config_get("WATCHDOG_EC_CRITICAL_PCT", 5) { SET pwr_st TO "FAIL". }
    ELSE {
        IF ec <= aoso_config_get("LOW_EC_PCT", 20) { SET pwr_st TO "DEG". }
    }
    SET s["pwr"] TO pwr_st.
    LOCAL wd_st IS "NOM".
    IF aoso_watchdog_is_tripped() { SET wd_st TO "FAIL". }
    SET s["wd"] TO wd_st.
    LOCAL stg_st IS "NOM".
    IF SHIP:AVAILABLETHRUST <= 0 {
        IF SHIP:STATUS = "FLYING" { SET stg_st TO "DEG". }
        IF SHIP:STATUS = "SUB_ORBITAL" { SET stg_st TO "DEG". }
    }
    SET s["stg"] TO stg_st.
    LOCAL steer_st IS "STBY".
    IF AOSO_STEER_MODE <> "OFF" { SET steer_st TO "NOM". }
    IF AOSO_MANEUVER_BURNING {
        IF AOSO_STEER_MODE = "OFF" { SET steer_st TO "DEG". }
    }
    SET s["steer"] TO steer_st.
    SET s["steer_mode"] TO AOSO_STEER_MODE.
    LOCAL thr_st IS "STBY".
    IF AOSO_THROTTLE_MODE <> "OFF" { SET thr_st TO "NOM". }
    SET s["thr"] TO thr_st.
    SET s["thr_mode"] TO AOSO_THROTTLE_MODE.
    LOCAL nav_st IS "STBY".
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] <> "" { SET nav_st TO "NOM". }
        IF AOSO_GOTO["current"] = "ABORTED" { SET nav_st TO "FAIL". }
        IF AOSO_GOTO["current"] = "PLAN" { SET nav_st TO "NOM". }
        IF AOSO_GOTO["current"] = "COAST" { SET nav_st TO "NOM". }
        IF AOSO_GOTO["current"] = "BURN" { SET nav_st TO "NOM". }
    }
    SET s["nav"] TO nav_st.
    LOCAL msn_st IS "STBY".
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] = "RUNNING" { SET msn_st TO "NOM". }
        IF AOSO_MISSION["current"] = "ABORTED" { SET msn_st TO "FAIL". }
        IF AOSO_MISSION["current"] = "DONE" { SET msn_st TO "NOM". }
    }
    SET s["msn"] TO msn_st.
    LOCAL lnd_st IS "STBY".
    IF AOSO_HUD_DATA["landing"]["active"] { SET lnd_st TO "NOM". }
    IF AOSO_HUD_DATA["landing"]["state"] = "ABORTED" { SET lnd_st TO "FAIL". }
    SET s["lnd"] TO lnd_st.
    LOCAL com_st IS "NOM".
    LOCAL net IS aoso_world_network_summary().
    IF NOT net["has_antenna"] { SET com_st TO "DEG". }
    IF net["blackout_risk"] { SET com_st TO "DEG". }
    SET s["com"] TO com_st.
    SET s["com_home"] TO net["in_home_soi"].
    SET s["guid"] TO "NOM".
    LOCAL worst IS "NOM".
    LOCAL fail_n IS 0.
    LOCAL deg_n IS 0.
    LOCAL keys IS LIST("cpu", "pwr", "wd", "stg", "steer", "nav", "msn", "lnd", "com", "guid").
    FOR k IN keys {
        LOCAL st IS s[k].
        IF st = "FAIL" {
            SET worst TO "FAIL".
            SET fail_n TO fail_n + 1.
        } ELSE {
            IF st = "DEG" {
                IF worst <> "FAIL" { SET worst TO "DEG". }
                SET deg_n TO deg_n + 1.
            }
        }
    }
    SET s["worst"] TO worst.
    SET s["fail_n"] TO fail_n.
    SET s["deg_n"] TO deg_n.
    IF worst = "FAIL" { SET s["rollup"] TO "FAIL". }
    ELSE {
        IF worst = "DEG" { SET s["rollup"] TO "DEGRADED". }
        ELSE { SET s["rollup"] TO "NOMINAL". }
    }
}

FUNCTION aoso_hud_collect_vehicle {
    LOCAL veh IS AOSO_HUD_DATA["vehicle"].
    SET veh["name"] TO SHIP:NAME.
    SET veh["type"] TO SHIP:TYPE.
    SET veh["crew"] TO SHIP:CREW:LENGTH.
    SET veh["crew_cap"] TO SHIP:CREWCAPACITY.
    SET veh["parts"] TO 0.
    SET veh["engines"] TO 0.
    SET veh["class"] TO "".
    SET veh["land"] TO FALSE.
    SET veh["isru"] TO FALSE.
    SET veh["dock"] TO FALSE.
    SET veh["orbit"] TO FALSE.
    SET veh["launch"] TO FALSE.
    SET veh["home"] TO FALSE.
    SET veh["gear"] TO FALSE.
    SET veh["chutes"] TO FALSE.
    SET veh["antenna"] TO FALSE.
    SET veh["solar"] TO 0.
    SET veh["rcs"] TO FALSE.
    IF DEFINED AOSO_PROFILE {
        IF AOSO_PROFILE:HASKEY("part_count") { SET veh["parts"] TO AOSO_PROFILE["part_count"]. }
        IF AOSO_PROFILE:HASKEY("propulsion") {
            SET veh["engines"] TO AOSO_PROFILE["propulsion"]["engines"].
            SET veh["rcs"] TO AOSO_PROFILE["propulsion"]["has_rcs"].
        }
        IF AOSO_PROFILE:HASKEY("mobility") {
            SET veh["gear"] TO AOSO_PROFILE["mobility"]["has_gear"].
            SET veh["chutes"] TO AOSO_PROFILE["mobility"]["has_parachutes"].
        }
        IF AOSO_PROFILE:HASKEY("navigation") {
            SET veh["antenna"] TO AOSO_PROFILE["navigation"]["has_antenna"].
        }
        IF AOSO_PROFILE:HASKEY("power") {
            SET veh["solar"] TO AOSO_PROFILE["power"]["solar_count"].
        }
        SET veh["land"] TO aoso_profile_capable("can_land").
        SET veh["isru"] TO aoso_profile_capable("can_isru").
        SET veh["dock"] TO aoso_profile_capable("can_dock").
        SET veh["orbit"] TO aoso_profile_capable("can_orbit").
        SET veh["launch"] TO aoso_profile_capable("can_launch").
        SET veh["home"] TO aoso_profile_capable("can_return_to_kerbin").
    }
    IF DEFINED AOSO_CLASS_LAST {
        IF AOSO_CLASS_LAST:HASKEY("class") { SET veh["class"] TO AOSO_CLASS_LAST["class"]. }
    }
}

FUNCTION aoso_hud_collect_debug {
    LOCAL d IS AOSO_HUD_DATA["debug"].
    SET d["ipu"] TO CONFIG:IPU.
    SET d["left"] TO OPCODESLEFT.
    LOCAL used IS 0.
    LOCAL frac IS 0.
    LOCAL cname IS "NORMAL".
    IF DEFINED AOSO_CPU_USED { SET used TO AOSO_CPU_USED. }
    IF DEFINED AOSO_CPU_FRAC { SET frac TO AOSO_CPU_FRAC. }
    IF DEFINED AOSO_CPU_NAME { SET cname TO AOSO_CPU_NAME. }
    SET d["used"] TO used.
    SET d["frac"] TO frac.
    SET d["cpu"] TO cname.
    SET d["spills"] TO 0.
    IF DEFINED AOSO_CPU_SPILLS { SET d["spills"] TO AOSO_CPU_SPILLS. }
    SET d["page"] TO "".
    SET d["mode"] TO "".
    IF DEFINED AOSO_HUD_PAGE { SET d["page"] TO AOSO_HUD_PAGE. }
    IF DEFINED AOSO_HUD_MODE { SET d["mode"] TO AOSO_HUD_MODE. }
    SET d["phase"] TO AOSO_OBS_PHASE.
    SET d["ctx"] TO AOSO_HUD_CTX.
    SET d["twin"] TO "".
    SET d["twin_parts"] TO 0.
    SET d["twin_reason"] TO "".
    IF DEFINED AOSO_TWIN {
        IF AOSO_TWIN:HASKEY("status") {
            SET d["twin"] TO AOSO_TWIN["status"].
            SET d["twin_parts"] TO AOSO_TWIN["part_n"].
            SET d["twin_reason"] TO AOSO_TWIN["reason"].
        }
    }
}

FUNCTION aoso_hud_refresh_context {
    LOCAL ctx IS "ORBIT".
    IF SHIP:STATUS = "PRELAUNCH" { SET ctx TO "LAUNCH". }
    IF SHIP:STATUS = "FLYING" { SET ctx TO "LAUNCH". }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" { SET ctx TO "LAUNCH". }
        }
    }
    IF AOSO_HUD_DATA["orbit"]["burning"] { SET ctx TO "BURN". }
    ELSE {
        IF AOSO_HUD_DATA["orbit"]["node"] {
            IF AOSO_HUD_DATA["orbit"]["node_eta"] < 90 { SET ctx TO "BURN". }
        }
    }
    IF DEFINED AOSO_GOTO {
        IF AOSO_GOTO["current"] = "COAST" { SET ctx TO "TRANSFER". }
        IF AOSO_GOTO["current"] = "WAIT" { SET ctx TO "TRANSFER". }
        IF AOSO_GOTO["current"] = "PLAN" { SET ctx TO "TRANSFER". }
        IF AOSO_GOTO["current"] = "CAPTURE" { SET ctx TO "BURN". }
    }
    IF AOSO_HUD_DATA["landing"]["active"] { SET ctx TO "LANDING". }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] = "REFUEL" { SET ctx TO "REFUEL". }
        IF AOSO_TOUR["current"] = "KSC" { SET ctx TO "RETURN". }
        IF AOSO_TOUR["current"] = "RETURN" { SET ctx TO "RETURN". }
        IF AOSO_TOUR["current"] = "DESCEND" { SET ctx TO "LANDING". }
        IF AOSO_TOUR["current"] = "DEORBIT" { SET ctx TO "LANDING". }
    }
    IF DEFINED AOSO_DOCKING {
        IF AOSO_DOCKING["current"] <> "" {
            IF AOSO_DOCKING["current"] <> "DONE" {
                IF AOSO_DOCKING["current"] <> "ABORTED" { SET ctx TO "DOCK". }
            }
        }
    }
    SET AOSO_HUD_CTX TO ctx.
}

FUNCTION aoso_hud_collect {
    PARAMETER force_all IS FALSE.
    LOCAL rates IS aoso_hud_rates().
    LOCAL now IS TIME:SECONDS.
    IF force_all {
        aoso_hud_collect_flight().
        aoso_hud_collect_orbit().
        aoso_hud_collect_target().
        aoso_hud_collect_res().
        aoso_hud_collect_mission().
        aoso_hud_collect_landing().
        aoso_hud_collect_systems().
        aoso_hud_collect_vehicle().
        aoso_hud_collect_debug().
        aoso_hud_refresh_context().
        SET AOSO_HUD_LAST_HI TO now.
        SET AOSO_HUD_LAST_MD TO now.
        SET AOSO_HUD_LAST_LO TO now.
        RETURN rates.
    }
    IF (now - AOSO_HUD_LAST_HI) >= rates["hi"] {
        aoso_hud_collect_flight().
        SET AOSO_HUD_LAST_HI TO now.
    }
    IF (now - AOSO_HUD_LAST_MD) >= rates["md"] {
        aoso_hud_collect_orbit().
        aoso_hud_collect_target().
        aoso_hud_collect_res().
        aoso_hud_collect_mission().
        aoso_hud_collect_landing().
        aoso_hud_collect_systems().
        aoso_hud_collect_debug().
        aoso_hud_refresh_context().
        SET AOSO_HUD_LAST_MD TO now.
    }
    IF (now - AOSO_HUD_LAST_LO) >= rates["lo"] {
        aoso_hud_collect_vehicle().
        SET AOSO_HUD_LAST_LO TO now.
    }
    RETURN rates.
}
