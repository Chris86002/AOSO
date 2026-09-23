// AOSO/ux/hud_data.ks
// HUD telemetry cache. Collectors only. Rendering lives elsewhere.
// High/medium/low rate gates so the HUD never walks PARTS or replans.

GLOBAL AOSO_HUD_DATA IS LEXICON().
GLOBAL AOSO_HUD_FAST_UT IS -1.
GLOBAL AOSO_HUD_LAST_HI IS 0.
GLOBAL AOSO_HUD_LAST_MD IS 0.
GLOBAL AOSO_HUD_LAST_LO IS 0.
GLOBAL AOSO_HUD_CTX IS "IDLE".
GLOBAL AOSO_HUD_ASC_LOCK IS FALSE.
GLOBAL AOSO_HUD_ASC_SEEN_PRE IS FALSE.
GLOBAL AOSO_HUD_ASC_LAT IS 0.
GLOBAL AOSO_HUD_ASC_LNG IS 0.
GLOBAL AOSO_HUD_ASC_X IS LIST().
GLOBAL AOSO_HUD_ASC_Y IS LIST().
GLOBAL AOSO_HUD_ASC_SAMPLE_UT IS -1.

FUNCTION aoso_hud_collect_fast {
    LOCAL f IS AOSO_HUD_DATA["flight"].
    SET f["alt"] TO ALTITUDE.
    SET f["vs"] TO VERTICALSPEED.
    SET f["gs"] TO SHIP:GROUNDSPEED.
    SET f["srf"] TO SHIP:VELOCITY:SURFACE:MAG.
    SET f["orb"] TO SHIP:VELOCITY:ORBIT:MAG.
    SET f["throttle"] TO THROTTLE.
    SET f["mass"] TO SHIP:MASS.
    SET f["thrust"] TO SHIP:AVAILABLETHRUST.
    SET f["stage"] TO STAGE:NUMBER.
    SET f["body"] TO SHIP:BODY:NAME.
    SET f["status"] TO SHIP:STATUS.
    SET f["doing"] TO AOSO_UI["doing"].
    SET f["detail"] TO AOSO_UI["detail"].
    LOCAL rad IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL g IS 9.81.
    IF rad > 0 { SET g TO SHIP:BODY:MU / (rad * rad). }
    LOCAL twr IS 0.
    IF SHIP:MASS > 0 {
        IF g > 0 { SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * g). }
    }
    SET f["twr"] TO twr.
    SET f["in_atm"] TO FALSE.
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT { SET f["in_atm"] TO TRUE. }
    }
    LOCAL o IS AOSO_HUD_DATA["orbit"].
    SET o["ap"] TO APOAPSIS.
    SET o["pe"] TO PERIAPSIS.
    SET o["node"] TO HASNODE.
    SET o["node_dv"] TO 0.
    SET o["node_eta"] TO 0.
    SET o["burning"] TO FALSE.
    IF DEFINED AOSO_MANEUVER_BURNING { SET o["burning"] TO AOSO_MANEUVER_BURNING. }
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        SET o["node_dv"] TO nd:DELTAV:MAG.
        SET o["node_eta"] TO nd:ETA.
    }
    SET AOSO_HUD_FAST_UT TO TIME:SECONDS.
}

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
        "vehicle", LEXICON(),
        "traj", LEXICON(
            "locked", FALSE,
            "has_origin", FALSE,
            "down_km", 0,
            "alt_km", 0,
            "xmax_km", 80,
            "ymax_km", 80,
            "atm_km", 0,
            "ap_km", 0,
            "pitch_cmd", 0,
            "has_cmd", FALSE,
            "lf", 0,
            "lf_best", -1,
            "in_atm", FALSE,
            "site_ok", FALSE,
            "site_km", 0,
            "dv_margin", 0
        )
    ).
    SET AOSO_HUD_LAST_HI TO 0.
    SET AOSO_HUD_LAST_MD TO 0.
    SET AOSO_HUD_LAST_LO TO 0.
    SET AOSO_HUD_CTX TO "IDLE".
    SET AOSO_HUD_ASC_LOCK TO FALSE.
    SET AOSO_HUD_ASC_SEEN_PRE TO FALSE.
    SET AOSO_HUD_ASC_LAT TO 0.
    SET AOSO_HUD_ASC_LNG TO 0.
    SET AOSO_HUD_ASC_X TO LIST().
    SET AOSO_HUD_ASC_Y TO LIST().
    SET AOSO_HUD_ASC_SAMPLE_UT TO -1.
}

FUNCTION aoso_hud_rates {
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl >= 3 {
        RETURN LEXICON("hi", 0.20, "md", 2.0, "lo", 6, "gui", TRUE, "fd", FALSE, "term", TRUE).
    }
    IF lvl >= 2 {
        RETURN LEXICON("hi", 0.12, "md", 1.2, "lo", 4, "gui", TRUE, "fd", FALSE, "term", TRUE).
    }
    RETURN LEXICON("hi", 0.10, "md", 0.80, "lo", 2.0, "gui", TRUE, "fd", TRUE, "term", TRUE).
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
    SET f["radar"] TO radar.
    SET f["show_radar"] TO FALSE.
    IF radar > 0 {
        IF ABS(ALTITUDE - radar) > 40 {
            IF radar < 25000 { SET f["show_radar"] TO TRUE. }
        }
    }
    IF SHIP:STATUS = "LANDED" { SET f["show_radar"] TO TRUE. }
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
        LOCAL do_bt IS TRUE.
        IF DEFINED AOSO_CPU_LEVEL {
            IF AOSO_CPU_LEVEL >= 2 { SET do_bt TO FALSE. }
        }
        IF do_bt { SET o["burn_s"] TO aoso_perf_burn_time_for_dv(nd:DELTAV:MAG). }
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
    SET rsrc["unusable_dv"] TO 0.
    SET rsrc["reserve_dv"] TO 0.
    SET rsrc["return_dv"] TO 0.
    SET rsrc["abort_dv"] TO 0.
    IF DEFINED AOSO_BUDGET {
        IF AOSO_BUDGET:HASKEY("unusable_dv") { SET rsrc["unusable_dv"] TO AOSO_BUDGET["unusable_dv"]. }
        IF AOSO_BUDGET:HASKEY("reserve_dv") { SET rsrc["reserve_dv"] TO AOSO_BUDGET["reserve_dv"]. }
        IF AOSO_BUDGET:HASKEY("return_dv") { SET rsrc["return_dv"] TO AOSO_BUDGET["return_dv"]. }
        IF AOSO_BUDGET:HASKEY("abort_dv") { SET rsrc["abort_dv"] TO AOSO_BUDGET["abort_dv"]. }
    }
    SET rsrc["twr_now"] TO 0.
    SET rsrc["twr_next"] TO 0.
    SET rsrc["role_next"] TO "".
    LOCAL want_pred IS TRUE.
    IF DEFINED AOSO_CPU_LEVEL {
        IF AOSO_CPU_LEVEL >= 1 { SET want_pred TO FALSE. }
    }
    IF want_pred {
        LOCAL pred IS aoso_capabilities_predict_next().
        SET rsrc["twr_now"] TO pred["twr_now"].
        SET rsrc["twr_next"] TO pred["twr_next"].
        SET rsrc["role_next"] TO pred["role_next"].
    }
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
    SET m["cert"] TO "".
    SET m["health"] TO "".
    SET m["weak"] TO "".
    IF DEFINED AOSO_CERT_LAST {
        IF AOSO_CERT_LAST:HASKEY("status") { SET m["cert"] TO AOSO_CERT_LAST["status"]. }
    }
    IF DEFINED AOSO_ASSURE_LAST {
        IF AOSO_ASSURE_LAST:HASKEY("health") { SET m["health"] TO AOSO_ASSURE_LAST["health"]. }
        IF AOSO_ASSURE_LAST:HASKEY("weak_body") { SET m["weak"] TO AOSO_ASSURE_LAST["weak_body"]. }
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
                    LOCAL tag IS "".
                    IF i < idx { SET tag TO " (done)". }
                    IF i = idx { SET tag TO " (now)". }
                    IF out <> "" { SET out TO out + " > ". }
                    SET out TO out + targets[i] + tag.
                    SET i TO i + 1.
                    IF i >= 10 {
                        SET out TO out + " > ...".
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
    SET l["has_site"] TO FALSE.
    SET l["site_lat"] TO 0.
    SET l["site_lng"] TO 0.
    SET l["site_alt"] TO 0.
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
                SET l["site_lat"] TO AOSO_TOUR["data"]["site_lat"].
                SET l["site_lng"] TO AOSO_TOUR["data"]["site_lng"].
                IF AOSO_TOUR["data"]:HASKEY("site_alt") { SET l["site_alt"] TO AOSO_TOUR["data"]["site_alt"]. }
                SET l["site"] TO ROUND(l["site_lat"], 2) + " / " + ROUND(l["site_lng"], 2).
                LOCAL site_picked IS FALSE.
                IF AOSO_TOUR["data"]:HASKEY("site_score") {
                    IF AOSO_TOUR["data"]["site_score"] > -1 { SET site_picked TO TRUE. }
                }
                IF ABS(l["site_lat"]) + ABS(l["site_lng"]) > 0.02 { SET site_picked TO TRUE. }
                SET l["has_site"] TO site_picked.
            }
        }
    }
}

FUNCTION aoso_hud_gc_m {
    PARAMETER lat1.
    PARAMETER lng1.
    PARAMETER lat2.
    PARAMETER lng2.
    LOCAL body_r IS SHIP:BODY:RADIUS.
    LOCAL deg IS CONSTANT:PI / 180.
    LOCAL la1 IS lat1 * deg.
    LOCAL la2 IS lat2 * deg.
    LOCAL dla IS (lat2 - lat1) * deg.
    LOCAL dlo IS (lng2 - lng1) * deg.
    LOCAL hav IS SIN(dla / 2) * SIN(dla / 2) + COS(la1) * COS(la2) * SIN(dlo / 2) * SIN(dlo / 2).
    IF hav < 0 { SET hav TO 0. }
    IF hav > 1 { SET hav TO 1. }
    LOCAL ang IS 2 * ARCTAN2(SQRT(hav), SQRT(1 - hav)).
    RETURN body_r * ang.
}

FUNCTION aoso_hud_collect_traj {
    LOCAL tr IS AOSO_HUD_DATA["traj"].
    LOCAL geo IS SHIP:GEOPOSITION.
    LOCAL st IS SHIP:STATUS.
    IF st = "PRELAUNCH" {
        SET AOSO_HUD_ASC_LAT TO geo:LAT.
        SET AOSO_HUD_ASC_LNG TO geo:LNG.
        SET AOSO_HUD_ASC_SEEN_PRE TO TRUE.
        SET AOSO_HUD_ASC_LOCK TO FALSE.
        SET AOSO_HUD_ASC_X TO LIST().
        SET AOSO_HUD_ASC_Y TO LIST().
        SET AOSO_HUD_ASC_SAMPLE_UT TO -1.
    } ELSE {
        IF AOSO_HUD_ASC_SEEN_PRE {
            IF NOT AOSO_HUD_ASC_LOCK { SET AOSO_HUD_ASC_LOCK TO TRUE. }
        }
    }
    SET tr["locked"] TO AOSO_HUD_ASC_LOCK.
    SET tr["has_origin"] TO AOSO_HUD_ASC_SEEN_PRE.
    LOCAL down_m IS 0.
    IF AOSO_HUD_ASC_SEEN_PRE {
        SET down_m TO aoso_hud_gc_m(AOSO_HUD_ASC_LAT, AOSO_HUD_ASC_LNG, geo:LAT, geo:LNG).
    }
    LOCAL alt_km IS ALTITUDE / 1000.
    LOCAL down_km IS down_m / 1000.
    SET tr["down_km"] TO down_km.
    SET tr["alt_km"] TO alt_km.
    SET tr["in_atm"] TO FALSE.
    SET tr["atm_km"] TO 0.
    IF SHIP:BODY:ATM:EXISTS {
        SET tr["atm_km"] TO SHIP:BODY:ATM:HEIGHT / 1000.
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT { SET tr["in_atm"] TO TRUE. }
    }
    LOCAL ap_km IS APOAPSIS / 1000.
    IF ap_km < 0 { SET ap_km TO 0. }
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT:HASKEY("data") {
            IF AOSO_ASCENT["data"]:HASKEY("target_apo") {
                LOCAL want_ap IS AOSO_ASCENT["data"]["target_apo"] / 1000.
                IF want_ap > ap_km { SET ap_km TO want_ap. }
            }
        }
    }
    SET tr["ap_km"] TO ap_km.
    LOCAL x_max IS MAX(down_km * 1.25, 10).
    LOCAL y_max IS MAX(MAX(alt_km, ap_km), tr["atm_km"]) * 1.08.
    IF y_max < 5 { SET y_max TO 5. }
    LOCAL ti IS 0.
    UNTIL ti >= AOSO_HUD_ASC_X:LENGTH {
        IF AOSO_HUD_ASC_X[ti] > x_max { SET x_max TO AOSO_HUD_ASC_X[ti] * 1.05. }
        IF AOSO_HUD_ASC_Y[ti] > y_max { SET y_max TO AOSO_HUD_ASC_Y[ti] * 1.05. }
        SET ti TO ti + 1.
    }
    SET tr["xmax_km"] TO x_max.
    SET tr["ymax_km"] TO y_max.

    SET tr["has_cmd"] TO FALSE.
    SET tr["pitch_cmd"] TO 0.
    IF DEFINED AOSO_ASCENT {
        IF AOSO_ASCENT["current"] <> "" {
            IF AOSO_ASCENT["current"] <> "DONE" {
                IF AOSO_ASCENT["current"] <> "ABORTED" {
                    IF AOSO_ASCENT:HASKEY("data") {
                        SET tr["pitch_cmd"] TO aoso_ascent_program_pitch(AOSO_ASCENT["data"]).
                        SET tr["has_cmd"] TO TRUE.
                    }
                }
            }
        }
    }
    SET tr["lf"] TO aoso_resource_amount("LiquidFuel").
    SET tr["lf_best"] TO -1.
    IF DEFINED AOSO_LEARN_LAST {
        IF AOSO_LEARN_LAST:HASKEY("best_orbit_lf") {
            SET tr["lf_best"] TO AOSO_LEARN_LAST["best_orbit_lf"].
        }
    }

    LOCAL sample_ok IS AOSO_HUD_ASC_LOCK.
    IF st = "PRELAUNCH" { SET sample_ok TO FALSE. }
    IF st = "LANDED" { SET sample_ok TO FALSE. }
    IF st = "SPLASHED" { SET sample_ok TO FALSE. }
    IF st = "ORBITING" { SET sample_ok TO FALSE. }
    IF st = "DOCKED" { SET sample_ok TO FALSE. }
    IF sample_ok {
        LOCAL gap IS 1.5.
        IF DEFINED AOSO_CPU_LEVEL {
            IF AOSO_CPU_LEVEL >= 2 { SET gap TO 3. }
            IF AOSO_CPU_LEVEL >= 3 { SET sample_ok TO FALSE. }
        }
        IF sample_ok {
            IF AOSO_HUD_ASC_SAMPLE_UT < 0 OR TIME:SECONDS - AOSO_HUD_ASC_SAMPLE_UT >= gap {
                SET AOSO_HUD_ASC_SAMPLE_UT TO TIME:SECONDS.
                AOSO_HUD_ASC_X:ADD(down_km).
                AOSO_HUD_ASC_Y:ADD(alt_km).
                IF AOSO_HUD_ASC_X:LENGTH > 12 {
                    AOSO_HUD_ASC_X:REMOVE(0).
                    AOSO_HUD_ASC_Y:REMOVE(0).
                }
            }
        }
    }

    SET tr["site_ok"] TO FALSE.
    SET tr["site_km"] TO 0.
    LOCAL lnd IS AOSO_HUD_DATA["landing"].
    IF lnd:HASKEY("has_site") {
        IF lnd["has_site"] {
            SET tr["site_km"] TO aoso_hud_gc_m(geo:LAT, geo:LNG, lnd["site_lat"], lnd["site_lng"]) / 1000.
            SET tr["site_ok"] TO TRUE.
        }
    }
    LOCAL have_dv IS 0.
    LOCAL need_dv IS 0.
    IF AOSO_HUD_DATA["res"]:HASKEY("mission_dv") { SET have_dv TO AOSO_HUD_DATA["res"]["mission_dv"]. }
    IF AOSO_HUD_DATA["res"]:HASKEY("land_dv") { SET need_dv TO AOSO_HUD_DATA["res"]["land_dv"]. }
    SET tr["dv_margin"] TO have_dv - need_dv.
}

FUNCTION aoso_hud_collect_systems {
    LOCAL s IS AOSO_HUD_DATA["systems"].
    LOCAL cpu_st IS "NOM".
    LOCAL cpu_name IS "NORMAL".
    IF DEFINED AOSO_CPU_NAME { SET cpu_name TO AOSO_CPU_NAME. }
    SET s["cpu"] TO cpu_st.
    SET s["cpu_name"] TO cpu_name.
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
    SET s["com_why"] TO "".
    IF NOT net["has_antenna"] {
        SET com_st TO "DEG".
        SET s["com_why"] TO "no antenna".
    }
    IF net["blackout_risk"] {
        SET com_st TO "DEG".
        SET s["com_why"] TO "plasma blackout risk".
    }
    SET s["com"] TO com_st.
    SET s["com_home"] TO net["in_home_soi"].
    SET s["guid"] TO "NOM".
    LOCAL worst IS "NOM".
    LOCAL fail_n IS 0.
    LOCAL deg_n IS 0.
    LOCAL why IS "".
    LOCAL keys IS LIST("pwr", "wd", "stg", "steer", "nav", "msn", "lnd", "com", "guid").
    FOR k IN keys {
        LOCAL st IS s[k].
        IF st = "FAIL" {
            SET worst TO "FAIL".
            SET fail_n TO fail_n + 1.
            IF why <> "" { SET why TO why + " · ". }
            SET why TO why + k:TOUPPER + " " + aoso_hud_sys_reason(k, s).
        } ELSE {
            IF st = "DEG" {
                IF worst <> "FAIL" { SET worst TO "DEG". }
                SET deg_n TO deg_n + 1.
                IF why <> "" { SET why TO why + " · ". }
                SET why TO why + k:TOUPPER + " " + aoso_hud_sys_reason(k, s).
            }
        }
    }
    SET s["worst"] TO worst.
    SET s["fail_n"] TO fail_n.
    SET s["deg_n"] TO deg_n.
    SET s["why"] TO why.
    IF worst = "FAIL" { SET s["rollup"] TO "FAIL". }
    ELSE {
        IF worst = "DEG" { SET s["rollup"] TO "DEGRADED". }
        ELSE { SET s["rollup"] TO "NOMINAL". }
    }
}

FUNCTION aoso_hud_sys_reason {
    PARAMETER key.
    PARAMETER s.
    IF key = "cpu" {
        RETURN "kOS busy (" + s["cpu_name"] + ") - HUD still painting".
    }
    IF key = "pwr" {
        RETURN "EC " + ROUND(AOSO_HUD_DATA["res"]["ec"], 0) + "%".
    }
    IF key = "wd" { RETURN "tripped". }
    IF key = "stg" { RETURN "no thrust". }
    IF key = "steer" { RETURN "OFF during burn". }
    IF key = "nav" { RETURN "GOTO aborted". }
    IF key = "msn" { RETURN "mission aborted". }
    IF key = "lnd" { RETURN "landing aborted". }
    IF key = "com" {
        IF s:HASKEY("com_why") { RETURN s["com_why"]. }
        RETURN "link".
    }
    RETURN "fault".
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
    IF DEFINED AOSO_CPU_LEFT { SET d["left"] TO AOSO_CPU_LEFT. }
    LOCAL used IS 0.
    LOCAL frac IS 0.
    LOCAL cname IS "NORMAL".
    IF DEFINED AOSO_CPU_USED { SET used TO AOSO_CPU_USED. }
    IF DEFINED AOSO_CPU_FRAC { SET frac TO AOSO_CPU_FRAC. }
    IF DEFINED AOSO_CPU_NAME { SET cname TO AOSO_CPU_NAME. }
    SET d["used"] TO used.
    SET d["frac"] TO frac.
    SET d["cpu"] TO cname.
    SET d["band"] TO aoso_cpu_band().
    SET d["spills"] TO 0.
    IF DEFINED AOSO_CPU_SPILLS { SET d["spills"] TO AOSO_CPU_SPILLS. }
    SET d["deferred"] TO 0.
    SET d["shed"] TO 0.
    IF DEFINED AOSO_TASKS {
        SET d["deferred"] TO aoso_sched_stat_sum("deferred_n").
        SET d["shed"] TO aoso_sched_stat_sum("shed_n").
    }
    SET d["cert"] TO "UNKNOWN".
    IF DEFINED AOSO_CERT_LAST {
        IF AOSO_CERT_LAST:HASKEY("status") { SET d["cert"] TO AOSO_CERT_LAST["status"]. }
    }
    SET d["weak"] TO "".
    SET d["health"] TO "".
    IF DEFINED AOSO_ASSURE_LAST {
        IF AOSO_ASSURE_LAST:HASKEY("weak_body") { SET d["weak"] TO AOSO_ASSURE_LAST["weak_body"]. }
        IF AOSO_ASSURE_LAST:HASKEY("health") { SET d["health"] TO AOSO_ASSURE_LAST["health"]. }
    }
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
        aoso_hud_collect_traj().
        aoso_hud_collect_systems().
        aoso_hud_collect_vehicle().
        aoso_hud_collect_debug().
        aoso_hud_refresh_context().
        SET AOSO_HUD_LAST_HI TO now.
        SET AOSO_HUD_LAST_MD TO now.
        SET AOSO_HUD_LAST_LO TO now.
        RETURN rates.
    }
    IF now <> AOSO_HUD_FAST_UT { aoso_hud_collect_flight(). }
    LOCAL pg IS AOSO_HUD_PAGE.
    IF pg = "FLT" OR pg = "NAV" OR pg = "DBG" {
        aoso_hud_collect_orbit().
        aoso_hud_refresh_context().
        SET AOSO_HUD_LAST_HI TO now.
    } ELSE {
        IF (now - AOSO_HUD_LAST_HI) >= rates["hi"] {
            aoso_hud_collect_orbit().
            aoso_hud_refresh_context().
            SET AOSO_HUD_LAST_HI TO now.
        }
    }
    IF pg = "DBG" OR pg = "SYS" { aoso_hud_collect_debug(). }
    IF pg = "SYS" OR pg = "DBG" { aoso_hud_collect_systems(). }
    IF pg = "NAV" OR pg = "RNDZ" { aoso_hud_collect_target(). }
    IF pg = "MSN" OR pg = "RTE" OR pg = "BDG" { aoso_hud_collect_mission(). }
    IF pg = "PRP" OR pg = "STG" OR pg = "BDG" OR pg = "RTE" OR pg = "VSIT" { aoso_hud_collect_res(). }
    IF pg = "LND" OR pg = "VSIT" { aoso_hud_collect_landing(). }
    IF pg = "ASC" OR pg = "VSIT" OR pg = "RNDZ" { aoso_hud_collect_traj(). }
    IF pg = "VEH" { aoso_hud_collect_vehicle(). }
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
