// AOSO/landing/descent.ks
// Suicide-burn (hoverslam) + final-approach descent guidance.
//
// Airless landing follows an actual suicide-burn profile:
//   1. lower periapsis below the selected terrain (an impact trajectory),
//   2. numerically simulate a full-thrust surface-retrograde burn,
//   3. coast until that burn's predicted vertical drop equals clearance,
//   4. commit to 100% throttle until terminal velocity is reached near ground.
// A scalar v^2/2a is distance along the velocity vector and is not a radar
// altitude on a shallow orbital approach. The local integrator below tracks
// horizontal and vertical velocity separately, so the burn does not ignite
// kilometres early and settle into a high-altitude hover. Throttle modulation
// is reserved for the final touchdown flare only.

GLOBAL AOSO_DESCENT IS aoso_state_new_machine().
GLOBAL AOSO_DESCENT_RADAR_OFFSET IS 8.
GLOBAL AOSO_DESCENT_BOTTOM_ALT IS -1.
GLOBAL AOSO_DESCENT_BOTTOM_SRC IS "none".
GLOBAL AOSO_DESCENT_BOUNDS_AT IS 0.
GLOBAL AOSO_DESCENT_PARTS_AT IS 0.
GLOBAL AOSO_DESCENT_BOTTOM_LOG_AT IS 0.
GLOBAL AOSO_DESCENT_LEGS_ON IS FALSE.
GLOBAL AOSO_DESCENT_LEGS_AT IS 0.
GLOBAL AOSO_DESCENT_OFFSET_PENDING IS -1.
GLOBAL AOSO_DESCENT_OFFSET_HITS IS 0.
GLOBAL AOSO_DESCENT_LOGGED_OFF IS -999.
GLOBAL AOSO_DESCENT_OFFSET_REV IS -999.
GLOBAL AOSO_DESCENT_COAST_ETA IS -1.
GLOBAL AOSO_DESCENT_COAST_AT IS -1.
GLOBAL AOSO_DESCENT_COAST_ASL IS -1.
GLOBAL AOSO_DESCENT_PRED_AT IS -1.
GLOBAL AOSO_DESCENT_PRED IS LEXICON().

FUNCTION aoso_descent_local_gravity {
    RETURN SHIP:BODY:MU / (SHIP:BODY:RADIUS + ALTITUDE) ^ 2.
}

// Fallback when SHIP:BOUNDS is missing: distance (m) from the radar/root
// reference down to the lowest part origin along UP, plus 2 m of skin.
// This is not the collider, and it does not see legs until they move.
// Prefer aoso_descent_refresh_bounds(), which uses the vessel bounding box
// and is called again while the gear is extending.
FUNCTION aoso_descent_geom_rev {
    IF DEFINED AOSO_TOPO {
        IF AOSO_TOPO:HASKEY("rev") { RETURN AOSO_TOPO["rev"]. }
    }
    RETURN -1.
}

FUNCTION aoso_descent_measure_radar_offset {
    LOCAL configured IS aoso_config_get("DESCENT_RADAR_OFFSET", 0).
    IF configured > 0 { RETURN configured. }

    LOCAL rev_now IS aoso_descent_geom_rev().
    IF rev_now >= 0 {
        IF rev_now = AOSO_DESCENT_OFFSET_REV {
            IF AOSO_DESCENT_BOTTOM_SRC = "parts" {
                aoso_cache_log("parts", "hit", "radar|" + rev_now).
                RETURN AOSO_DESCENT_RADAR_OFFSET.
            }
        }
    }

    LOCAL plist IS aoso_parts_list().
    LOCAL axis IS SHIP:UP:VECTOR.
    LOCAL min_along IS 0.
    LOCAL seen IS FALSE.
    FOR p IN plist {
        LOCAL along IS VDOT(p:POSITION, axis).
        IF NOT seen {
            SET min_along TO along.
            SET seen TO TRUE.
        } ELSE {
            IF along < min_along { SET min_along TO along. }
        }
    }
    LOCAL offset_m IS 0 - min_along.
    IF offset_m < 2 { SET offset_m TO 2. }
    IF offset_m > 80 { SET offset_m TO 80. }
    SET AOSO_DESCENT_OFFSET_REV TO rev_now.
    aoso_cache_log("parts", "miss", "radar|" + rev_now).
    RETURN offset_m + 2.
}

// ALT:RADAR is the root part (Mk1 Lander Can on Acacius), not the belly.
// SHIP:BOUNDS:BOTTOMALTRADAR is the lowest collider, including legs once
// they finish deploying. A zero reading while the root is still high is a
// failed raycast, not touchdown.
FUNCTION aoso_descent_refresh_bounds {
    LOCAL now IS TIME:SECONDS.
    LOCAL configured IS aoso_config_get("DESCENT_RADAR_OFFSET", 0).
    IF configured > 0 {
        SET AOSO_DESCENT_RADAR_OFFSET TO configured.
        SET AOSO_DESCENT_BOTTOM_ALT TO -1.
        SET AOSO_DESCENT_BOTTOM_SRC TO "config".
        RETURN.
    }

    LOCAL rev_now IS aoso_descent_geom_rev().
    LOCAL leg_live IS FALSE.
    IF AOSO_DESCENT_LEGS_ON {
        IF now - AOSO_DESCENT_LEGS_AT < 6 { SET leg_live TO TRUE. }
    }
    IF NOT leg_live {
        IF rev_now >= 0 {
            IF rev_now = AOSO_DESCENT_OFFSET_REV {
                IF AOSO_DESCENT_BOTTOM_SRC = "bounds" OR AOSO_DESCENT_BOTTOM_SRC = "parts" {
                    IF AOSO_DESCENT_BOTTOM_SRC = "bounds" {
                        LOCAL raw_now IS ALT:RADAR.
                        SET AOSO_DESCENT_BOTTOM_ALT TO raw_now - AOSO_DESCENT_RADAR_OFFSET.
                        IF AOSO_DESCENT_BOTTOM_ALT < 0 { SET AOSO_DESCENT_BOTTOM_ALT TO 0. }
                    }
                    RETURN.
                }
            }
        }
    }
    IF now - AOSO_DESCENT_BOUNDS_AT < 0.2 { RETURN. }
    SET AOSO_DESCENT_BOUNDS_AT TO now.

    LOCAL raw IS ALT:RADAR.
    LOCAL got IS FALSE.
    IF SHIP:HASSUFFIX("BOUNDS") {
        LOCAL b IS SHIP:BOUNDS.
        IF b:HASSUFFIX("BOTTOMALTRADAR") {
            LOCAL bottom IS b:BOTTOMALTRADAR.
            LOCAL sane IS FALSE.
            IF bottom >= 0 AND bottom <= raw + 2 {
                IF bottom > 1 OR raw < 40 { SET sane TO TRUE. }
            }
            IF sane {
                LOCAL off IS raw - bottom.
                IF off < 0 { SET off TO 0. }
                IF off > 80 { SET off TO 80. }
                // SHIP:BOUNDS on Acacius flickered 0-14 m every tick and
                // both moved the suicide trigger and flooded the log.
                // Accept a small drift immediately; a jump has to repeat.
                IF AOSO_DESCENT_BOTTOM_SRC <> "bounds" {
                    SET AOSO_DESCENT_RADAR_OFFSET TO off.
                    SET AOSO_DESCENT_OFFSET_HITS TO 0.
                    SET AOSO_DESCENT_OFFSET_PENDING TO off.
                } ELSE {
                    LOCAL delta_off IS off - AOSO_DESCENT_RADAR_OFFSET.
                    IF ABS(delta_off) <= 2.5 {
                        SET AOSO_DESCENT_RADAR_OFFSET TO AOSO_DESCENT_RADAR_OFFSET * 0.5 + off * 0.5.
                        SET AOSO_DESCENT_OFFSET_HITS TO 0.
                    } ELSE {
                        IF ABS(off - AOSO_DESCENT_OFFSET_PENDING) <= 1.5 {
                            SET AOSO_DESCENT_OFFSET_HITS TO AOSO_DESCENT_OFFSET_HITS + 1.
                        } ELSE {
                            SET AOSO_DESCENT_OFFSET_PENDING TO off.
                            SET AOSO_DESCENT_OFFSET_HITS TO 1.
                        }
                        IF AOSO_DESCENT_OFFSET_HITS >= 3 {
                            SET AOSO_DESCENT_RADAR_OFFSET TO off.
                            SET AOSO_DESCENT_OFFSET_HITS TO 0.
                        }
                    }
                }
                IF ABS(AOSO_DESCENT_RADAR_OFFSET - AOSO_DESCENT_LOGGED_OFF) >= 3 {
                    IF now - AOSO_DESCENT_BOTTOM_LOG_AT > 8 {
                        SET AOSO_DESCENT_BOTTOM_LOG_AT TO now.
                        SET AOSO_DESCENT_LOGGED_OFF TO AOSO_DESCENT_RADAR_OFFSET.
                        aoso_log_info("DESCENT", "Vessel bottom " + ROUND(AOSO_DESCENT_RADAR_OFFSET, 1) +
                            " m below radar (bounds). legs=" + AOSO_DESCENT_LEGS_ON + ".").
                    }
                }
                SET AOSO_DESCENT_BOTTOM_ALT TO raw - AOSO_DESCENT_RADAR_OFFSET.
                IF AOSO_DESCENT_BOTTOM_ALT < 0 { SET AOSO_DESCENT_BOTTOM_ALT TO 0. }
                SET AOSO_DESCENT_BOTTOM_SRC TO "bounds".
                SET AOSO_DESCENT_OFFSET_REV TO aoso_descent_geom_rev().
                SET got TO TRUE.
            }
        }
    }
    IF got { RETURN. }

    IF AOSO_DESCENT_BOTTOM_SRC = "parts" {
        IF now - AOSO_DESCENT_PARTS_AT < 2 { RETURN. }
    }
    LOCAL offp IS aoso_descent_measure_radar_offset().
    IF ABS(offp - AOSO_DESCENT_RADAR_OFFSET) >= 3 OR AOSO_DESCENT_BOTTOM_SRC <> "parts" {
        IF now - AOSO_DESCENT_BOTTOM_LOG_AT > 1.5 {
            SET AOSO_DESCENT_BOTTOM_LOG_AT TO now.
            aoso_log_info("DESCENT", "Vessel bottom " + ROUND(offp, 1) + " m below radar (part walk). bounds unavailable.").
        }
    }
    SET AOSO_DESCENT_RADAR_OFFSET TO offp.
    SET AOSO_DESCENT_BOTTOM_ALT TO -1.
    SET AOSO_DESCENT_BOTTOM_SRC TO "parts".
    SET AOSO_DESCENT_PARTS_AT TO now.
}

FUNCTION aoso_descent_true_radar {
    aoso_descent_refresh_bounds().
    IF AOSO_DESCENT_BOTTOM_SRC = "bounds" {
        IF AOSO_DESCENT_BOTTOM_ALT >= 0 {
            IF AOSO_DESCENT_BOTTOM_ALT < 1 { RETURN 1. }
            RETURN AOSO_DESCENT_BOTTOM_ALT.
        }
    }
    LOCAL radar_m IS ALT:RADAR - AOSO_DESCENT_RADAR_OFFSET.
    IF radar_m < 1 { RETURN 1. }
    RETURN radar_m.
}

// Gear changes the bottom of the ship. Deploy before the hoverslam gets
// low, then keep sampling bounds while the animation extends the feet.
FUNCTION aoso_descent_maintain_legs {
    PARAMETER radar.
    PARAMETER force IS FALSE.
    LOCAL cur IS "".
    IF DEFINED AOSO_DESCENT { SET cur TO AOSO_DESCENT["current"]. }
    LOCAL want IS force.
    IF cur = "BURN" { SET want TO TRUE. }
    IF cur = "FINAL_APPROACH" { SET want TO TRUE. }
    IF radar < 400 { SET want TO TRUE. }
    IF radar < AOSO_DESCENT_RADAR_OFFSET + 350 { SET want TO TRUE. }
    IF NOT want { RETURN. }

    IF NOT AOSO_DESCENT_LEGS_ON {
        LEGS ON.
        SET AOSO_DESCENT_LEGS_ON TO TRUE.
        SET AOSO_DESCENT_LEGS_AT TO TIME:SECONDS.
        SET AOSO_DESCENT_BOUNDS_AT TO 0.
        aoso_descent_refresh_bounds().
        aoso_log_info("DESCENT", "Legs commanded on. Remeasuring the bottom as the gear extends. offset=" +
            ROUND(AOSO_DESCENT_RADAR_OFFSET, 1) + " m (" + AOSO_DESCENT_BOTTOM_SRC + ") radar=" + ROUND(radar, 0) + " m.").
        RETURN.
    }
    IF TIME:SECONDS - AOSO_DESCENT_LEGS_AT < 6 {
        LEGS ON.
        SET AOSO_DESCENT_BOUNDS_AT TO 0.
        aoso_descent_refresh_bounds().
    }
}

// Maximum net deceleration (m/s^2) available against gravity at full
// throttle. 0 when the current stage cannot hover, so callers can burn
// immediately instead of computing a negative stopping distance.
FUNCTION aoso_descent_max_deceleration {
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL accel IS SHIP:AVAILABLETHRUST / SHIP:MASS.
    RETURN MAX(0, accel - aoso_descent_local_gravity()).
}

// Kinematic stopping distance (m) to kill the full surface-velocity vector
// (not just vertical speed) at constant net deceleration.
FUNCTION aoso_descent_stopping_distance {
    PARAMETER speed_ms.
    PARAMETER decel.
    IF decel <= 0 { RETURN -1. }
    RETURN (speed_ms ^ 2) / (2 * decel).
}

// Seconds until a ballistic vertical arc reaches the surface. Kept for
// the freefall breadcrumb. It is not the ignition clock: a shallow pass
// has a long time-to-impact even when surface speed is high.
FUNCTION aoso_descent_ballistic_tti {
    LOCAL y0 IS aoso_descent_true_radar().
    LOCAL g_loc IS aoso_descent_local_gravity().
    IF g_loc < 0.05 { SET g_loc TO 0.05. }
    LOCAL vy IS VERTICALSPEED.
    LOCAL disc IS vy * vy + 2 * g_loc * y0.
    IF disc < 0 { RETURN 999999. }
    LOCAL t_hit IS (vy + SQRT(disc)) / g_loc.
    IF t_hit < 0.05 { RETURN 0.05. }
    RETURN t_hit.
}

FUNCTION aoso_descent_time_to_stop {
    LOCAL decel IS aoso_descent_max_deceleration().
    IF decel <= 0.05 { RETURN 999999. }
    RETURN SHIP:VELOCITY:SURFACE:MAG / decel.
}

// Rate-limited diagnostic of the live unpowered conic after deorbit.
// It measures actual surface impact against the selected body-fixed site;
// the full-thrust burn remains pure surface-retrograde and does not chase it.
FUNCTION aoso_descent_log_impact {
    PARAMETER data.
    IF SHIP:BODY:ATM:EXISTS { RETURN. }
    IF HASNODE { RETURN. }
    LOCAL now IS TIME:SECONDS.
    IF data:HASKEY("impact_log_next") {
        IF now < data["impact_log_next"] { RETURN. }
    }
    SET data["impact_log_next"] TO now + 20.

    LOCAL have_target IS FALSE.
    LOCAL target_lat IS 0.
    LOCAL target_lng IS 0.
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("site_lat") {
                SET target_lat TO AOSO_TOUR["data"]["site_lat"].
                SET target_lng TO AOSO_TOUR["data"]["site_lng"].
                SET have_target TO TRUE.
            }
        }
    }
    IF NOT have_target { RETURN. }

    LOCAL pred IS aoso_landing_impact_predict(target_lat, target_lng).
    IF pred:ISTYPE("Lexicon") {
        IF pred["ok"] {
            SET data["impact_miss"] TO pred["miss_distance"].
            SET data["impact_lat"] TO pred["lat"].
            SET data["impact_lng"] TO pred["lng"].
            SET data["impact_ut"] TO pred["impact_ut"].
            aoso_log_info("LAND_PREDICT", "radar=" + ROUND(aoso_descent_true_radar(), 0) +
                "m terrainClr=" + ROUND(pred["radial_alt"] - pred["terrain_alt"], 0) +
                "m v=" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) +
                "m/s vVert=" + ROUND(VERTICALSPEED, 1) + "m/s vHoriz=" +
                ROUND(GROUNDSPEED, 1) + "m/s impact=" + ROUND(pred["lat"], 3) + "/" +
                ROUND(pred["lng"], 3) + " target=" + ROUND(target_lat, 3) + "/" +
                ROUND(target_lng, 3) + " miss=" + ROUND(pred["miss_distance"], 0) +
                "m confidence=" + pred["confidence"] + " tImpact=" + ROUND(pred["time_to_impact"], 1) +
                "s stop=" + ROUND(aoso_descent_stopping_distance(SHIP:VELOCITY:SURFACE:MAG,
                aoso_descent_max_deceleration()), 0) + "m burnAt~" +
                ROUND(aoso_descent_burn_trigger_alt(), 0) + "m rotation=" +
                ROUND(pred["rotation_period"], 1) + "s model=unpowered-conic.").
            RETURN.
        }
        aoso_log_every(60, "LAND_PREDICT", "prediction unavailable reason=" + pred["reason"] +
            " radar=" + ROUND(aoso_descent_true_radar(), 0) + "m AP=" +
            ROUND(APOAPSIS, 0) + "m PE=" + ROUND(PERIAPSIS, 0) + "m.").
    }
}

// Simulate an immediate, maximum-thrust surface-retrograde burn in the local
// vertical/horizontal plane. A scalar v^2/2a is distance ALONG the velocity
// vector; comparing it to radar altitude ignites far too early on a shallow
// orbital approach. This integrator returns the maximum VERTICAL clearance
// consumed while the ideal retrograde burn kills both velocity components.
FUNCTION aoso_descent_full_burn_prediction {
    LOCAL now_ut IS TIME:SECONDS.
    IF AOSO_DESCENT_PRED_AT >= 0 {
        IF now_ut - AOSO_DESCENT_PRED_AT < 0.08 {
            IF AOSO_DESCENT_PRED:LENGTH > 0 { RETURN AOSO_DESCENT_PRED. }
        }
    }

    LOCAL max_accel IS 0.
    IF SHIP:MASS > 0 { SET max_accel TO SHIP:AVAILABLETHRUST / SHIP:MASS. }
    LOCAL g_loc IS aoso_descent_local_gravity().
    IF max_accel <= g_loc + 0.05 {
        SET AOSO_DESCENT_PRED_AT TO now_ut.
        SET AOSO_DESCENT_PRED TO LEXICON("ok", FALSE, "trigger", 999999,
            "drop", 999999, "burn_time", 999999, "end_vs", VERTICALSPEED,
            "end_hs", GROUNDSPEED, "max_accel", max_accel).
        RETURN AOSO_DESCENT_PRED.
    }

    LOCAL steps_n IS aoso_config_get("DESCENT_PREDICT_STEPS", 36).
    IF steps_n < 16 { SET steps_n TO 16. }
    IF steps_n > 64 { SET steps_n TO 64. }
    LOCAL target_vs IS aoso_config_get("DESCENT_FINAL_SPEED", -2).
    IF target_vs > -0.2 { SET target_vs TO -0.2. }
    LOCAL target_hs IS aoso_config_get("DESCENT_TERMINAL_HS", 1.5).
    IF target_hs < 0.2 { SET target_hs TO 0.2. }

    LOCAL sim_vs IS VERTICALSPEED.
    LOCAL sim_hs IS GROUNDSPEED.
    LOCAL speed_ms IS SQRT(sim_vs ^ 2 + sim_hs ^ 2).
    LOCAL net_accel IS max_accel - g_loc.
    // Retrograde thrust initially spends most of its authority cancelling
    // lateral velocity. Give the simulation enough time for low-TWR landers
    // without increasing its configured step count.
    LOCAL estimate_s IS speed_ms / net_accel * 1.35.
    LOCAL step_s IS estimate_s / steps_n.
    IF step_s < 0.02 { SET step_s TO 0.02. }
    IF step_s > 1.5 { SET step_s TO 1.5. }

    LOCAL drop_m IS 0.
    LOCAL max_drop IS 0.
    LOCAL elapsed_s IS 0.
    LOCAL idx IS 0.
    LOCAL done IS FALSE.
    UNTIL idx >= steps_n OR done {
        IF sim_hs <= target_hs AND sim_vs >= target_vs {
            SET done TO TRUE.
        } ELSE {
            SET speed_ms TO SQRT(sim_vs ^ 2 + sim_hs ^ 2).
            IF speed_ms < 0.05 {
                SET done TO TRUE.
            } ELSE {
                LOCAL previous_vs IS sim_vs.
                LOCAL horizontal_accel IS 0 - max_accel * sim_hs / speed_ms.
                // Tangential speed curves away from the surface. Its h^2/r
                // radial term is why a shallow Minmus pass does not fall as
                // though it were hovering motionless over flat ground.
                LOCAL radial_m IS SHIP:BODY:RADIUS + ALTITUDE - drop_m.
                IF radial_m < SHIP:BODY:RADIUS { SET radial_m TO SHIP:BODY:RADIUS. }
                LOCAL curve_accel IS sim_hs ^ 2 / radial_m.
                LOCAL vertical_accel IS max_accel * (0 - sim_vs) / speed_ms - g_loc + curve_accel.
                SET sim_hs TO sim_hs + horizontal_accel * step_s.
                IF sim_hs < 0 { SET sim_hs TO 0. }
                SET sim_vs TO sim_vs + vertical_accel * step_s.
                SET drop_m TO drop_m - (previous_vs + sim_vs) * 0.5 * step_s.
                IF drop_m > max_drop { SET max_drop TO drop_m. }
                SET elapsed_s TO elapsed_s + step_s.
            }
        }
        SET idx TO idx + 1.
    }
    IF sim_hs <= target_hs AND sim_vs >= target_vs { SET done TO TRUE. }

    LOCAL terminal_h IS aoso_config_get("DESCENT_TERMINAL_ALT", 12).
    IF terminal_h < 3 { SET terminal_h TO 3. }
    LOCAL margin_mult IS aoso_config_get("DESCENT_SUICIDE_MARGIN", 1.02).
    IF margin_mult < 1 { SET margin_mult TO 1. }
    IF margin_mult > 1.15 { SET margin_mult TO 1.15. }
    LOCAL reaction_s IS aoso_config_get("DESCENT_IGNITION_MARGIN_S", 0.15).
    IF reaction_s < 0 { SET reaction_s TO 0. }
    IF reaction_s > 1 { SET reaction_s TO 1. }
    LOCAL reaction_m IS MAX(0, 0 - VERTICALSPEED) * reaction_s.
    LOCAL trigger_m IS max_drop * margin_mult + reaction_m + terminal_h.
    IF trigger_m < terminal_h + 2 { SET trigger_m TO terminal_h + 2. }
    IF NOT done { SET trigger_m TO 999999. }

    SET AOSO_DESCENT_PRED_AT TO now_ut.
    SET AOSO_DESCENT_PRED TO LEXICON("ok", done, "trigger", trigger_m,
        "drop", max_drop, "burn_time", elapsed_s, "end_vs", sim_vs,
        "end_hs", sim_hs, "max_accel", max_accel).
    RETURN AOSO_DESCENT_PRED.
}

FUNCTION aoso_descent_burn_trigger_alt {
    LOCAL burn_pred IS aoso_descent_full_burn_prediction().
    RETURN burn_pred["trigger"].
}

// Geo under a point `dist_m` ahead of the ship along surface velocity,
// walking the sphere so the sample is on the ground track rather than
// a chord above it. Returns 0 when the direction is meaningless.
// SHIP-RAW origin is the vessel: vector from body to ship is
// SHIP:POSITION - BODY:POSITION, and GEOPOSITIONOF wants ship-raw.
FUNCTION aoso_descent_ahead_geo {
    PARAMETER dist_m.
    LOCAL body_ref IS SHIP:BODY.
    LOCAL radius_vec IS SHIP:POSITION - body_ref:POSITION.
    LOCAL rmag IS radius_vec:MAG.
    IF rmag < 1 { RETURN 0. }
    LOCAL horizontal IS VXCL(radius_vec, SHIP:VELOCITY:SURFACE).
    IF horizontal:MAG < 1 { RETURN 0. }
    LOCAL ang_deg IS (dist_m / rmag) * AOSO_CONST["RAD2DEG"].
    // Farther than this, LATLNG terrain is the unloaded sea-level sentinel.
    IF ang_deg > 5 { RETURN 0. }
    IF ang_deg < 0.05 { RETURN SHIP:GEOPOSITION. }
    LOCAL rhat IS radius_vec:NORMALIZED.
    LOCAL hhat IS horizontal:NORMALIZED.
    LOCAL ahead_from_body IS rhat * (rmag * COS(ang_deg)) + hhat * (rmag * SIN(ang_deg)).
    RETURN body_ref:GEOPOSITIONOF(ahead_from_body - radius_vec).
}

// Lowest of true radar and altitude-above-terrain out along the ground
// track. Look-ahead is about one slew lead at the current groundspeed:
// the Minmus crash climbed a highland ~700 m ahead while still in rails.
// Samples that increase clearance are ignored: an unloaded query returns
// terrain 0, which would otherwise open the pad while a highland is under
// the ship. Points more than ~5 deg off the ship never enter.
FUNCTION aoso_descent_clearance {
    LOCAL clear IS aoso_descent_true_radar().
    IF GROUNDSPEED < 5 { RETURN clear. }
    LOCAL lead_s IS aoso_config_get("DESCENT_ALIGN_LEAD_S", 30).
    IF lead_s < 8 { SET lead_s TO 8. }
    LOCAL reach IS GROUNDSPEED * lead_s.
    IF reach < 1500 { SET reach TO 1500. }
    LOCAL dist_i IS 0.
    UNTIL dist_i >= 3 {
        LOCAL dist_m IS reach * (dist_i + 1) / 3.
        LOCAL geo IS aoso_descent_ahead_geo(dist_m).
        IF geo:ISTYPE("GeoCoordinates") {
            LOCAL ahead_clear IS ALTITUDE - geo:TERRAINHEIGHT - AOSO_DESCENT_RADAR_OFFSET.
            LOCAL drop IS (dist_m / GROUNDSPEED) * MAX(0, -VERTICALSPEED).
            SET ahead_clear TO ahead_clear - drop.
            IF ahead_clear < clear { SET clear TO ahead_clear. }
        }
        SET dist_i TO dist_i + 1.
    }
    IF clear < 0 { SET clear TO 0. }
    RETURN clear.
}

// Throttle modulation is deliberately confined to the last few metres. The
// actual suicide burn is always full throttle and surface-retrograde; this
// controller merely holds a soft sink and damps the small residual lateral
// velocity after the max-thrust burn has reached its predicted terminal state.
FUNCTION aoso_descent_terminal_guidance {
    PARAMETER data.
    LOCAL clear_m IS aoso_descent_true_radar().
    LOCAL target_vs IS aoso_config_get("DESCENT_FINAL_SPEED", -2).
    IF target_vs > -0.2 { SET target_vs TO -0.2. }
    LOCAL max_accel IS 0.
    IF SHIP:MASS > 0 { SET max_accel TO SHIP:AVAILABLETHRUST / SHIP:MASS. }
    LOCAL miss_m IS -1.
    IF data:HASKEY("impact_miss") { SET miss_m TO data["impact_miss"]. }
    IF max_accel <= 0 {
        RETURN LEXICON("mode", "NO_THRUST", "direction", SHIP:UP:VECTOR,
            "throttle", 0, "target_sink", target_vs, "clearance", clear_m,
            "stop", 0, "miss", miss_m).
    }

    LOCAL g_loc IS aoso_descent_local_gravity().
    LOCAL up_accel IS g_loc + 0.8 * (target_vs - VERTICALSPEED).
    IF up_accel < 0 { SET up_accel TO 0. }
    IF up_accel > max_accel { SET up_accel TO max_accel. }
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL horizontal_vel IS VXCL(up_vec, SHIP:VELOCITY:SURFACE).
    LOCAL horizontal_accel IS horizontal_vel * -0.6.
    LOCAL horizontal_cap IS up_accel.
    IF horizontal_cap > max_accel * 0.5 { SET horizontal_cap TO max_accel * 0.5. }
    IF horizontal_accel:MAG > horizontal_cap {
        SET horizontal_accel TO horizontal_accel:NORMALIZED * horizontal_cap.
    }
    LOCAL command_vec IS up_vec * up_accel + horizontal_accel.
    LOCAL command_mag IS command_vec:MAG.
    IF command_mag < 0.01 { SET command_vec TO up_vec. }
    LOCAL throttle_cmd IS command_mag / max_accel.
    IF throttle_cmd > 1 { SET throttle_cmd TO 1. }
    IF throttle_cmd < 0 { SET throttle_cmd TO 0. }
    RETURN LEXICON("mode", "TERMINAL", "direction", command_vec,
        "throttle", throttle_cmd, "target_sink", target_vs,
        "clearance", clear_m, "stop", 0, "miss", miss_m).
}

FUNCTION aoso_descent_should_terminal {
    LOCAL terminal_h IS aoso_config_get("DESCENT_TERMINAL_ALT", 12).
    LOCAL flare_ceiling IS terminal_h + 25.
    IF aoso_descent_true_radar() > flare_ceiling { RETURN FALSE. }
    LOCAL max_speed IS aoso_config_get("DESCENT_FINAL_SPEED_MAX", 25).
    IF SHIP:VELOCITY:SURFACE:MAG > max_speed { RETURN FALSE. }
    LOCAL target_hs IS aoso_config_get("DESCENT_TERMINAL_HS", 1.5).
    IF GROUNDSPEED > MAX(3, target_hs * 2) { RETURN FALSE. }
    LOCAL target_vs IS aoso_config_get("DESCENT_FINAL_SPEED", -2).
    IF VERTICALSPEED < target_vs - 2 { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_descent_on_abort {
    PARAMETER data.
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_auth_release_all("descent").
    aoso_auth_use("").
    aoso_state_transition(AOSO_DESCENT, "ABORTED").
}

// TRUE if the planned orbit intersects terrain or passes inside the live
// numerical burn trigger. A normal airless deorbit now has PE below the
// selected terrain, so it takes the impact-path branch immediately.
FUNCTION aoso_descent_pe_reaches_suicide {
    IF aoso_orbit_is_hyperbolic() { RETURN TRUE. }
    IF PERIAPSIS < 0 { RETURN TRUE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT { RETURN TRUE. }
        RETURN FALSE.
    }
    LOCAL burn_pred IS aoso_descent_full_burn_prediction().
    LOCAL trigger IS burn_pred["trigger"].
    LOCAL site_alt IS aoso_deorbit_site_alt().
    LOCAL radar_pe IS PERIAPSIS - site_alt.
    IF radar_pe < 80 { RETURN TRUE. }
    IF radar_pe <= trigger + 500 { RETURN TRUE. }
    RETURN FALSE.
}

// Seconds until ASL falls to asl_m, from the predicted orbit rather than a
// ballistic clock. Ballistic time ignores orbital support and drops warp
// while the ship is still near apoapsis; periapsis ETA is the opposite
// mistake (the burn is due before PE). Cached a few seconds so the
// freefall tick is not eight POSITIONAT calls.
// Altitude is |POSITIONAT(ship) - POSITIONAT(body)|, the same body-centred
// vector nav/orbit.ks uses. POSITIONAT(ship) - BODY:POSITION leaves the
// moon's travel around its parent in the vector (Minmus ~274 m/s). Over a
// few minutes that is tens of kilometres, the search never sees the ship
// descend, and coastEta sticks at periapsis — rails until the cliff.
FUNCTION aoso_descent_eta_to_asl {
    PARAMETER asl_m.
    IF ALTITUDE <= asl_m { RETURN 0. }
    LOCAL pe_eta IS 0.
    IF NOT aoso_orbit_is_hyperbolic() { SET pe_eta TO ETA:PERIAPSIS. }
    IF pe_eta < 1 { RETURN 0. }
    IF PERIAPSIS >= asl_m { RETURN pe_eta. }
    LOCAL now_ut IS TIME:SECONDS.
    IF AOSO_DESCENT_COAST_AT > 0 AND AOSO_DESCENT_COAST_ETA >= 0 {
        IF ABS(asl_m - AOSO_DESCENT_COAST_ASL) < 300 {
            IF now_ut - AOSO_DESCENT_COAST_AT < 5 {
                LOCAL left IS AOSO_DESCENT_COAST_ETA - (now_ut - AOSO_DESCENT_COAST_AT).
                IF left < 0 { SET left TO 0. }
                RETURN left.
            }
        }
    }
    LOCAL lo IS 0.
    LOCAL hi IS pe_eta.
    LOCAL body_ref IS SHIP:BODY.
    LOCAL i IS 0.
    UNTIL i >= 8 {
        LOCAL mid IS (lo + hi) / 2.
        LOCAL rel IS aoso_orbit_position_at(SHIP, now_ut + mid).
        LOCAL alt_at IS rel:MAG - body_ref:RADIUS.
        IF alt_at > asl_m { SET lo TO mid. }
        ELSE { SET hi TO mid. }
        SET i TO i + 1.
    }
    SET AOSO_DESCENT_COAST_ETA TO hi.
    SET AOSO_DESCENT_COAST_AT TO now_ut.
    SET AOSO_DESCENT_COAST_ASL TO asl_m.
    RETURN hi.
}

FUNCTION aoso_descent_freefall_entry {
    PARAMETER data.
    aoso_throttle_set(0).
    SET AOSO_DESCENT_LEGS_ON TO FALSE.
    SET AOSO_DESCENT_LEGS_AT TO 0.
    SET AOSO_DESCENT_BOUNDS_AT TO 0.
    SET AOSO_DESCENT_BOTTOM_SRC TO "none".
    SET AOSO_DESCENT_COAST_ETA TO -1.
    SET AOSO_DESCENT_COAST_AT TO -1.
    SET AOSO_DESCENT_PRED_AT TO -1.
    aoso_descent_refresh_bounds().
    aoso_log_info("DESCENT", "Radar offset=" + ROUND(AOSO_DESCENT_RADAR_OFFSET, 1) + " m via " + AOSO_DESCENT_BOTTOM_SRC +
        ". AP=" + ROUND(APOAPSIS, 0) +
        " PE=" + ROUND(PERIAPSIS, 0) + " alt=" + ROUND(ALTITUDE, 0) + " vs=" + ROUND(VERTICALSPEED, 1) +
        " " + aoso_warp_diag_txt() + ".").
}

FUNCTION aoso_descent_freefall_execute {
    PARAMETER data.
    aoso_parachute_auto_check().
    aoso_descent_log_impact(data).

    // Fly a PE-lowering node if we already decided this ellipse cannot land.
    // Descent holds STEERING and THROTTLE at prio 4, and maneuver acquires
    // them at prio 3, so equal-or-lower cannot preempt. Without a yield the
    // node sits forever (Minmus -1.2 m/s, auth denied, throttle 0).
    IF HASNODE {
        IF NOT data:HASKEY("descent_yielded") {
            aoso_auth_release("descent", "STEERING").
            aoso_auth_release("descent", "THROTTLE").
            SET data["descent_yielded"] TO TRUE.
            aoso_log_info("DESCENT", "Yielding steering and throttle so the PE-lowering node can burn.").
        }
        IF aoso_maneuver_execute_next() {
            aoso_auth_acquire("descent", "STEERING", 4).
            aoso_auth_acquire("descent", "THROTTLE", 4).
            aoso_auth_use("descent").
            SET data["descent_yielded"] TO FALSE.
            aoso_log_info("DESCENT", "PE-lowering burn complete. AP=" + ROUND(APOAPSIS, 0) +
                " PE=" + ROUND(PERIAPSIS, 0) + " alt=" + ROUND(ALTITUDE, 0) + ".").
        }
        RETURN.
    }
    IF data:HASKEY("descent_yielded") {
        IF data["descent_yielded"] {
            aoso_auth_acquire("descent", "STEERING", 4).
            aoso_auth_acquire("descent", "THROTTLE", 4).
            aoso_auth_use("descent").
            SET data["descent_yielded"] TO FALSE.
        }
    }

    IF NOT aoso_descent_pe_reaches_suicide() {
        LOCAL tgt IS aoso_deorbit_target_periapsis_alt().
        LOCAL eta_s IS aoso_orbit_eta_apoapsis().
        IF eta_s < 20 { SET eta_s TO 25. }
        aoso_log_warn("DESCENT", "PE " + ROUND(PERIAPSIS, 0) + "m is above suicide range (trig~" +
            ROUND(aoso_descent_burn_trigger_alt(), 0) + "m) - lowering periapsis to " + ROUND(tgt, 0) +
            "m instead of looping this ellipse.").
        aoso_decide("DESCENT", "drop_pe", ROUND(tgt, 0), "pe_high", "pe=" + ROUND(PERIAPSIS, 0) + " tgt=" + ROUND(tgt, 0)).
        LOCAL nd IS aoso_deorbit_add_node(tgt, TRUE, eta_s).
        IF nd = 0 {
            aoso_log_warn("DESCENT", "Could not add PE-lowering node - suicide will try from this PE anyway.").
        }
        RETURN.
    }

    // After a deorbit the ship is still at apoapsis with VS≈0 for minutes
    // (Minmus 16x8 km). Using radar/speed as TTI then LOCK SRFRETROGRADE
    // makes WARPTO a no-op, so warp starts and dies every tick and the
    // suicide burn never arrives. Warp to periapsis on rails first;
    // only point surface-retro when we are actually falling onto the PE.
    LOCAL pe_eta IS 0.
    IF NOT aoso_orbit_is_hyperbolic() {
        SET pe_eta TO ETA:PERIAPSIS.
    }
    IF VERTICALSPEED >= 0 {
        aoso_log_every(30, "DESCENT", "Freefall climbing/apo alt=" + ROUND(ALTITUDE, 0) + " AP=" + ROUND(APOAPSIS, 0) +
            " PE=" + ROUND(PERIAPSIS, 0) + " vs=" + ROUND(VERTICALSPEED, 1) + " peEta=" + ROUND(pe_eta, 0) +
            "s " + aoso_warp_diag_txt() + ".").
        IF pe_eta > 25 {
            aoso_steer_release().
            aoso_warp_request(pe_eta, 25, 12).
        }
        RETURN.
    }

    // Atmospheric bodies: wait for air/chutes to do the first half. A
    // TWR~1 stack cannot hoverslam from 70 km on Kerbin.
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE > 8000 {
            IF aoso_descent_max_deceleration() < 3 { RETURN. }
        }
    }

    LOCAL burn_pred IS aoso_descent_full_burn_prediction().
    LOCAL trigger IS burn_pred["trigger"].
    LOCAL radar IS aoso_descent_true_radar().
    LOCAL clear IS aoso_descent_clearance().
    LOCAL speed_ms IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL tti IS aoso_descent_ballistic_tti().
    LOCAL t_stop IS aoso_descent_time_to_stop().
    LOCAL decel IS aoso_descent_max_deceleration().
    aoso_descent_maintain_legs(radar).

    // Align pad is distance, not a clock that gets overwritten by periapsis
    // ETA. The Minmus crash restored coastEta to peEta (314 s) while the
    // burn was already due, so rails 10x ran until radar fell 2959 -> 240
    // in one tick and ignition happened unpointed.
    LOCAL align_pad IS 1500.
    LOCAL lead_s IS aoso_config_get("DESCENT_ALIGN_LEAD_S", 30).
    IF lead_s < 8 { SET lead_s TO 8. }
    IF VERTICALSPEED < 0 {
        LOCAL fall_pad IS -VERTICALSPEED * lead_s.
        IF fall_pad > align_pad { SET align_pad TO fall_pad. }
    }
    LOCAL align_h IS trigger + align_pad.
    LOCAL stop_m IS burn_pred["drop"].
    LOCAL terminal_h IS aoso_config_get("DESCENT_TERMINAL_ALT", 12).
    LOCAL no_margin_h IS stop_m + terminal_h.
    LOCAL critical IS FALSE.
    IF clear <= no_margin_h { SET critical TO TRUE. }

    LOCAL coast_eta IS aoso_descent_eta_to_asl(align_h + MAX(aoso_deorbit_site_alt(), SHIP:GEOPOSITION:TERRAINHEIGHT)).
    IF coast_eta > pe_eta AND pe_eta > 0 { SET coast_eta TO pe_eta. }

    aoso_log_every(30, "DESCENT", "Freefall alt=" + ROUND(ALTITUDE, 0) + " AP=" + ROUND(APOAPSIS, 0) +
        " PE=" + ROUND(PERIAPSIS, 0) + " vs=" + ROUND(VERTICALSPEED, 1) + " radar=" + ROUND(radar, 0) +
        " clr=" + ROUND(clear, 0) + " trig=" + ROUND(trigger, 0) + " align=" + ROUND(align_h, 0) +
        " peEta=" + ROUND(pe_eta, 0) + "s tti=" + ROUND(tti, 1) +
        "s burnT=" + ROUND(burn_pred["burn_time"], 1) + "s burnDrop=" + ROUND(stop_m, 1) +
        "m coastEta=" + ROUND(coast_eta, 0) + "s " + aoso_warp_diag_txt() + ".").

    IF clear > align_h {
        IF data:HASKEY("align_since") { data:REMOVE("align_since"). }
        aoso_steer_release().
        aoso_warp_request(coast_eta, 25, 12).
        RETURN.
    }

    // Inside the align band: kill warp and point surface-retrograde BEFORE
    // any throttle. A rails drop can flush several seconds; do not light
    // the engine on that same tick unless the ground is already inside the
    // no-margin stop distance.
    IF WARP > 0 OR KUNIVERSE:TIMEWARP:RATE > 1.01 OR NOT SHIP:UNPACKED {
        aoso_warp_hard_stop().
        aoso_steer_release().
        IF data:HASKEY("align_since") { data:REMOVE("align_since"). }
        RETURN.
    }

    aoso_steer_srf_retrograde().
    IF NOT data:HASKEY("align_since") { SET data["align_since"] TO TIME:SECONDS. }
    LOCAL held IS TIME:SECONDS - data["align_since"].
    IF held < 0 { SET held TO 0. }

    LOCAL facing_err IS 90.
    IF speed_ms > 5 {
        SET facing_err TO VANG(SHIP:FACING:VECTOR, SHIP:SRFRETROGRADE:VECTOR).
    }
    LOCAL aligned IS FALSE.
    IF facing_err < 20 { SET aligned TO TRUE. }
    LOCAL timed_out IS FALSE.
    IF held >= lead_s { SET timed_out TO TRUE. }

    LOCAL arm IS FALSE.
    IF clear <= trigger {
        IF aligned OR timed_out OR critical { SET arm TO TRUE. }
    }
    IF critical { SET arm TO TRUE. }
    IF NOT arm { RETURN. }

    LOCAL grav_commit IS aoso_descent_local_gravity().
    LOCAL twr_commit IS 0.
    IF grav_commit > 0 AND SHIP:MASS > 0 {
        SET twr_commit TO SHIP:AVAILABLETHRUST / (SHIP:MASS * grav_commit).
    }
    LOCAL miss_commit IS -1.
    IF data:HASKEY("impact_miss") { SET miss_commit TO data["impact_miss"]. }
    aoso_log_info("SUICIDE_COMMIT", "radar=" + ROUND(radar, 1) +
        "m clearance=" + ROUND(clear, 1) + "m speed=" + ROUND(speed_ms, 1) +
        "m/s vertical=" + ROUND(VERTICALSPEED, 1) + "m/s horizontal=" +
        ROUND(GROUNDSPEED, 1) + "m/s thrust=" + ROUND(SHIP:AVAILABLETHRUST, 0) +
        "kN mass=" + ROUND(SHIP:MASS, 1) + "twr=" + ROUND(twr_commit, 2) +
        "g=" + ROUND(grav_commit, 3) + "m/s2 netDecel=" + ROUND(decel, 3) +
        "m/s2 burnDrop=" + ROUND(stop_m, 1) + "m burnTime=" +
        ROUND(burn_pred["burn_time"], 2) + "s endVS=" + ROUND(burn_pred["end_vs"], 2) +
        "m/s endHS=" + ROUND(burn_pred["end_hs"], 2) + "m/s targetMiss=" + ROUND(miss_commit, 0) +
        "m " + aoso_warp_diag_txt() + ".").
    aoso_log_info("DESCENT", "Suicide burn now: radar=" + ROUND(radar, 0) + " m clr=" + ROUND(clear, 0) +
        " m trigger=" + ROUND(trigger, 0) + " m vSrf=" + ROUND(speed_ms, 1) + " m/s vVert=" +
        ROUND(VERTICALSPEED, 1) + " m/s face=" + ROUND(facing_err, 0) + " deg held=" + ROUND(held, 1) +
        "s burnTime=" + ROUND(burn_pred["burn_time"], 1) + "s verticalDrop=" +
        ROUND(stop_m, 1) + "m decel=" + ROUND(decel, 2) + " m/s^2 FULL THROTTLE " + aoso_warp_diag_txt() + ".").
    SET AOSO_LAND_SUICIDE_ALT TO radar.
    aoso_observe_event("LAND", "INFO", "BURN", "suicide radar=" + ROUND(radar, 0) + " clr=" + ROUND(clear, 0) +
        " vSrf=" + ROUND(speed_ms, 1) + " vs=" + ROUND(VERTICALSPEED, 1) +
        " hs=" + ROUND(GROUNDSPEED, 1) + " twr=" + ROUND(twr_commit, 2) +
        " face=" + ROUND(facing_err, 0) + " tStop=" + ROUND(t_stop, 1) +
        " suic=" + ROUND(radar, 0)).
    aoso_decide("DESCENT", "suicide", "BURN", "trigger", "radar=" + ROUND(radar, 0) + " clr=" + ROUND(clear, 0) +
        " trig=" + ROUND(trigger, 0) + " face=" + ROUND(facing_err, 0)).
    aoso_state_transition(AOSO_DESCENT, "BURN").
}

FUNCTION aoso_descent_measure_dv {
    PARAMETER data.
    LOCAL now IS TIME:SECONDS.
    IF NOT data:HASKEY("actual_dv") { SET data["actual_dv"] TO 0. }
    IF NOT data:HASKEY("dv_last_ut") {
        SET data["dv_last_ut"] TO now.
        RETURN.
    }
    LOCAL dt IS now - data["dv_last_ut"].
    SET data["dv_last_ut"] TO now.
    IF dt <= 0 { RETURN. }
    IF dt > 2 { RETURN. }
    IF SHIP:MASS <= 0 { RETURN. }
    IF SHIP:THRUST <= 0 { RETURN. }
    SET data["actual_dv"] TO data["actual_dv"] + (SHIP:THRUST / SHIP:MASS) * dt.
}

FUNCTION aoso_descent_suicide_command {
    PARAMETER data.
    LOCAL burn_pred IS aoso_descent_full_burn_prediction().
    LOCAL miss_m IS -1.
    IF data:HASKEY("impact_miss") { SET miss_m TO data["impact_miss"]. }
    aoso_steer_srf_retrograde().
    aoso_throttle_set(1).
    RETURN LEXICON("mode", "SUICIDE", "direction", SHIP:SRFRETROGRADE:VECTOR,
        "throttle", 1, "target_sink", aoso_config_get("DESCENT_FINAL_SPEED", -2),
        "clearance", aoso_descent_clearance(), "stop", burn_pred["trigger"],
        "miss", miss_m).
}

FUNCTION aoso_descent_terminal_command {
    PARAMETER data.
    LOCAL cmd IS aoso_descent_terminal_guidance(data).
    aoso_steer_to_vector(cmd["direction"]).
    aoso_throttle_set(cmd["throttle"]).
    RETURN cmd.
}

FUNCTION aoso_descent_operator_status {
    PARAMETER data.
    PARAMETER cmd.
    LOCAL now_ut IS TIME:SECONDS.
    IF data:HASKEY("status_next_ut") {
        IF now_ut < data["status_next_ut"] { RETURN. }
    }
    LOCAL gap_s IS aoso_config_get("DESCENT_STATUS_S", 2).
    IF gap_s < 1 { SET gap_s TO 1. }
    SET data["status_next_ut"] TO now_ut + gap_s.
    LOCAL cpu_txt IS "?".
    IF DEFINED AOSO_CPU_LEVEL { SET cpu_txt TO AOSO_CPU_LEVEL. }
    LOCAL fuel_pct IS aoso_stage_propellant_pct().
    aoso_log_operator("LAND", cmd["mode"] +
        " r=" + ROUND(aoso_descent_true_radar(), 0) +
        " vs=" + ROUND(VERTICALSPEED, 1) +
        " hs=" + ROUND(GROUNDSPEED, 1) +
        " tgt=" + ROUND(cmd["target_sink"], 1) +
        " thr=" + ROUND(cmd["throttle"] * 100, 0) + "%" +
        " margin=" + ROUND(cmd["clearance"] - cmd["stop"], 0) +
        " miss=" + ROUND(cmd["miss"], 0) +
        " fuel=" + ROUND(fuel_pct, 0) + "% cpu=" + cpu_txt).
}

FUNCTION aoso_descent_burn_entry {
    PARAMETER data.
    aoso_warp_hard_stop().
    SET AOSO_DESCENT_PRED_AT TO -1.
    IF data:HASKEY("burn_rearm") { data:REMOVE("burn_rearm"). }
    aoso_descent_maintain_legs(aoso_descent_true_radar(), TRUE).
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }
    LOCAL cmd IS aoso_descent_suicide_command(data).
    aoso_descent_operator_status(data, cmd).
}

FUNCTION aoso_descent_burn_execute {
    PARAMETER data.
    aoso_descent_measure_dv(data).
    aoso_parachute_auto_check().
    aoso_warp_hard_stop().

    aoso_staging_auto_check().
    IF aoso_fuel_abort_check() {
        aoso_state_abort(AOSO_DESCENT).
        RETURN.
    }

    LOCAL radar IS aoso_descent_true_radar().
    aoso_descent_maintain_legs(radar).

    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
        RETURN.
    }

    // Nominal path: stay at 100% throttle and surface retrograde for the
    // entire suicide burn. The only planned handoff is the low terminal flare.
    LOCAL cmd IS aoso_descent_suicide_command(data).
    aoso_descent_operator_status(data, cmd).

    IF aoso_descent_should_terminal() {
        aoso_log_info("DESCENT", "Full-thrust suicide burn complete; terminal flare at radar=" + ROUND(radar, 1) +
            "m vs=" + ROUND(VERTICALSPEED, 1) + "m/s hs=" + ROUND(GROUNDSPEED, 1) + "m/s.").
        aoso_state_transition(AOSO_DESCENT, "FINAL_APPROACH").
    }
}

FUNCTION aoso_descent_final_approach_entry {
    PARAMETER data.
    aoso_descent_maintain_legs(aoso_descent_true_radar(), TRUE).
    LOCAL cmd IS aoso_descent_terminal_command(data).
    aoso_descent_operator_status(data, cmd).
}

FUNCTION aoso_descent_final_approach_execute {
    PARAMETER data.
    aoso_descent_measure_dv(data).
    aoso_descent_maintain_legs(aoso_descent_true_radar()).
    // A disturbance above the terminal envelope re-enters maximum-thrust
    // braking. This is a safety recovery, not a scheduled powered descent.
    LOCAL resume_speed IS aoso_config_get("DESCENT_FINAL_SPEED_MAX", 25) * 1.4.
    LOCAL target_hs IS aoso_config_get("DESCENT_TERMINAL_HS", 1.5).
    IF SHIP:STATUS <> "LANDED" {
        IF GROUNDSPEED > MAX(6, target_hs * 4) OR SHIP:VELOCITY:SURFACE:MAG > resume_speed {
            aoso_log_warn("DESCENT", "Terminal flare disturbed (vSrf=" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) +
                "m/s hs=" + ROUND(GROUNDSPEED, 1) + "m/s) - resuming full-thrust braking.").
            aoso_observe_event("LAND", "WARN", "BOUNCE",
                "radar=" + ROUND(aoso_descent_true_radar(), 1) +
                " vs=" + ROUND(VERTICALSPEED, 2) +
                " hs=" + ROUND(GROUNDSPEED, 2) +
                " thr=" + ROUND(THROTTLE, 3) +
                " spd=" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1)).
            aoso_state_transition(AOSO_DESCENT, "BURN").
            RETURN.
        }
    }

    LOCAL cmd IS aoso_descent_terminal_command(data).
    aoso_descent_operator_status(data, cmd).

    aoso_staging_auto_check().

    IF SHIP:STATUS = "LANDED" {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
        RETURN.
    }
    IF aoso_descent_true_radar() <= aoso_config_get("DESCENT_TOUCHDOWN_ALT", 0.5) {
        aoso_state_transition(AOSO_DESCENT, "TOUCHDOWN").
    }
}

FUNCTION aoso_descent_touchdown_entry {
    PARAMETER data.
    aoso_descent_measure_dv(data).
    IF data:HASKEY("actual_dv") { aoso_action_add_actual_dv(data["actual_dv"]). }
    LOCAL thr_cut IS THROTTLE.
    aoso_throttle_set(0).
    aoso_steer_release().
    LOCAL touchdown_geo IS SHIP:GEOPOSITION.
    LOCAL touchdown_target_lat IS touchdown_geo:LAT.
    LOCAL touchdown_target_lng IS touchdown_geo:LNG.
    LOCAL touchdown_site_slope IS aoso_landing_site_slope_deg(touchdown_geo).
    LOCAL touchdown_miss IS -1.
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("site_lat") {
                SET touchdown_target_lat TO AOSO_TOUR["data"]["site_lat"].
                SET touchdown_target_lng TO AOSO_TOUR["data"]["site_lng"].
                SET touchdown_miss TO aoso_landing_target_miss_m(touchdown_geo:LAT,
                    touchdown_geo:LNG, touchdown_target_lat, touchdown_target_lng).
            }
        }
    }
    LOCAL elapsed_land IS 0.
    IF data:HASKEY("land_start_ut") {
        SET elapsed_land TO TIME:SECONDS - data["land_start_ut"].
    }
    aoso_log_info("LAND_TOUCHDOWN", "actual=" + ROUND(touchdown_geo:LAT, 4) + "/" +
        ROUND(touchdown_geo:LNG, 4) + " target=" + ROUND(touchdown_target_lat, 4) +
        "/" + ROUND(touchdown_target_lng, 4) + " miss=" + ROUND(touchdown_miss, 1) +
        "m vertical=" + ROUND(VERTICALSPEED, 2) + "m/s horizontal=" +
        ROUND(GROUNDSPEED, 2) + "m/s total=" +
        ROUND(SHIP:VELOCITY:SURFACE:MAG, 2) + "m/s dv=" +
        ROUND(data["actual_dv"], 1) + "m/s slope=" +
        ROUND(touchdown_site_slope, 2) + "deg elapsed=" + ROUND(elapsed_land, 1) + "s.").
    aoso_log_info("DESCENT", "Touchdown, throttle cut.").
    LOCAL land_pitch IS 90 - VANG(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR).
    LOCAL land_twr IS 0.
    IF SHIP:MASS > 0 {
        LOCAL g_touch IS SHIP:BODY:MU / ((SHIP:BODY:RADIUS + ALTITUDE) * (SHIP:BODY:RADIUS + ALTITUDE)).
        IF g_touch > 0 { SET land_twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * g_touch). }
    }
    LOCAL suic_alt IS -1.
    IF DEFINED AOSO_LAND_SUICIDE_ALT { SET suic_alt TO AOSO_LAND_SUICIDE_ALT. }
    aoso_observe_event("TOUCHDOWN", "INFO", "TOUCHDOWN",
        "lat=" + ROUND(touchdown_geo:LAT, 4) +
        " lng=" + ROUND(touchdown_geo:LNG, 4) +
        " site=" + ROUND(touchdown_target_lat, 4) + "/" + ROUND(touchdown_target_lng, 4) +
        " slope=" + ROUND(touchdown_site_slope, 2) +
        " radar=" + ROUND(aoso_descent_true_radar(), 1) +
        " vs=" + ROUND(VERTICALSPEED, 2) +
        " hs=" + ROUND(GROUNDSPEED, 2) +
        " thr=" + ROUND(thr_cut, 3) +
        " pitch=" + ROUND(land_pitch, 1) +
        " twr=" + ROUND(land_twr, 2) +
        " suic=" + ROUND(suic_alt, 0) +
        " miss=" + ROUND(touchdown_miss, 1)).
    LOCAL ver_l IS aoso_verify_landing().
    LOCAL res_l IS aoso_result_make("LANDING", "SUCCESS", "touchdown").
    IF data:HASKEY("pred_land") { SET res_l["predicted_dv"] TO data["pred_land"]. }
    SET res_l TO aoso_verify_apply_result(res_l, ver_l).
    aoso_result_emit(res_l).
    aoso_auth_release_all("descent").
    aoso_auth_use("").
}

FUNCTION aoso_descent_aborted_entry {
    PARAMETER data.
    aoso_observe_event("ABORT", "ERROR", "DESCENT",
        "radar=" + ROUND(aoso_descent_true_radar(), 1) +
        " vs=" + ROUND(VERTICALSPEED, 2) +
        " hs=" + ROUND(GROUNDSPEED, 2) +
        " thr=" + ROUND(THROTTLE, 3) +
        " alt_m=" + ROUND(ALTITUDE, 0) +
        " suic=" + ROUND(AOSO_LAND_SUICIDE_ALT, 0)).
    aoso_descent_measure_dv(data).
    IF AOSO_ACTION_CUR:ISTYPE("Lexicon") {
        IF AOSO_ACTION_CUR["type"] = "LANDING" {
            IF data:HASKEY("actual_dv") { aoso_action_add_actual_dv(data["actual_dv"]). }
            LOCAL res_a IS aoso_action_finish("ABORTED", "descent aborted").
            aoso_result_emit(res_a).
        }
    }
}

FUNCTION aoso_descent_poll {
    RETURN.
}

FUNCTION aoso_descent_is_landed {
    RETURN AOSO_DESCENT["current"] = "TOUCHDOWN".
}

FUNCTION aoso_descent_is_aborted {
    RETURN AOSO_DESCENT["current"] = "ABORTED".
}

FUNCTION aoso_descent_start {
    aoso_state_define(AOSO_DESCENT, "FREEFALL", aoso_descent_freefall_entry@, aoso_descent_freefall_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "BURN", aoso_descent_burn_entry@, aoso_descent_burn_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "FINAL_APPROACH", aoso_descent_final_approach_entry@, aoso_descent_final_approach_execute@, 0, 0, 0, aoso_descent_on_abort@).
    aoso_state_define(AOSO_DESCENT, "TOUCHDOWN", aoso_descent_touchdown_entry@, 0, 0).
    aoso_state_define(AOSO_DESCENT, "ABORTED", aoso_descent_aborted_entry@, 0, 0).

    SET AOSO_DESCENT["data"] TO LEXICON("actual_dv", 0, "dv_last_ut", TIME:SECONDS,
        "land_start_ut", TIME:SECONDS).
    aoso_state_queue(AOSO_DESCENT, "FREEFALL").
    aoso_sched_add("descent", 0, aoso_descent_tick@).
    aoso_auth_acquire("descent", "STEERING", 4).
    aoso_auth_acquire("descent", "THROTTLE", 4).
    aoso_auth_acquire("descent", "WARP", 4).
    aoso_auth_acquire("descent", "STAGING", 4).
    aoso_auth_use("descent").
    LOCAL pred_l IS aoso_feas_land_cost(SHIP:BODY:NAME).
    LOCAL did_l IS aoso_decide("DESCENT", "start", SHIP:BODY:NAME, "landing", "pred=" + ROUND(pred_l, 0), pred_l).
    LOCAL act_l IS aoso_action_create(did_l, "LANDING", SHIP:BODY:NAME, pred_l).
    aoso_action_begin(act_l).
    SET AOSO_DESCENT["data"]["pred_land"] TO pred_l.
    aoso_log_info("DESCENT", "Descent guidance started in FREEFALL. AP=" + ROUND(aoso_orbit_apoapsis_alt(), 0) +
        " PE=" + ROUND(PERIAPSIS, 0) + " alt=" + ROUND(ALTITUDE, 0) + " vs=" + ROUND(VERTICALSPEED, 1) +
        " " + aoso_warp_diag_txt() + ".").
}

FUNCTION aoso_descent_tick {
    IF AOSO_DESCENT["current"] = "" { RETURN. }
    aoso_auth_use("descent").
    LOCAL cur IS AOSO_DESCENT["current"].
    LOCAL pending IS FALSE.
    IF AOSO_DESCENT:HASKEY("need_entry") {
        IF AOSO_DESCENT["need_entry"] { SET pending TO TRUE. }
    }
    IF NOT pending {
        IF cur = "TOUCHDOWN" {
            aoso_sched_remove("descent").
            RETURN.
        }
        IF cur = "ABORTED" {
            aoso_sched_remove("descent").
            RETURN.
        }
    }
    aoso_state_update(AOSO_DESCENT).
    SET cur TO AOSO_DESCENT["current"].
    LOCAL p_d IS 0.2.
    IF cur = "FREEFALL" { SET p_d TO 0.3. }
    IF cur = "BURN" { SET p_d TO 0.7. }
    IF cur = "FINAL_APPROACH" { SET p_d TO 0.9. }
    IF cur = "TOUCHDOWN" { SET p_d TO 1. }
    LOCAL rad IS aoso_descent_true_radar().
    IF rad > 0 {
        IF rad < 50000 { SET p_d TO p_d + (1 - rad / 50000) * 0.05. }
    }
    aoso_hb_set("descent", cur, p_d).
    SET pending TO FALSE.
    IF AOSO_DESCENT:HASKEY("need_entry") {
        IF AOSO_DESCENT["need_entry"] { SET pending TO TRUE. }
    }
    IF NOT pending {
        IF cur = "TOUCHDOWN" { aoso_sched_remove("descent"). }
        IF cur = "ABORTED" { aoso_sched_remove("descent"). }
    }
}
