// AOSO/landing/descent.ks
// Suicide-burn (hoverslam) + final-approach descent guidance.
//
// Do not go back to a vertical-only time-to-impact ignition. That is what
// hit Minmus at 173 m/s: on a shallow arc centripetal support cancels
// gravity, so ballistic TTI stays ~90 s while the full-vector stop is
// ~16 s, throttle stays 0, and a cliff can collapse radar inside one
// rails tick. The law below is the usual community hoverslam
// (CheersKevin / amartyn1996 / HerrCraziDev / Garwel SBLAND):
//   decel = AVAILABLETHRUST/MASS - g
//   stop  = (v_srf^2)/(2*decel) * DESCENT_STOP_MARGIN + v_srf * DESCENT_BURN_MARGIN_S
//   ignite when clearance <= stop, after warp is already 0 and the nose
//   is on surface retrograde (or the pad has run out).
// Clearance is the minimum of true radar and altitude above terrain
// sampled ahead along the surface-velocity vector. After the survival burn,
// one vector controller damps horizontal motion and commands a continuous
// radar-dependent sink instead of allowing a high-altitude hover equilibrium.

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
 // powered guidance later consumes the stored error as a bounded bias.
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

// Radar-style clearance (m) at which the suicide burn must already be
// underway. Full surface speed, not vertical speed: a periapsis above
// the flats never makes VERTICALSPEED steep enough for a TTI trigger,
// and at PE itself vy≈0 used to return 0 so the burn never armed.
// DESCENT_STOP_MARGIN pads v^2/2a; DESCENT_BURN_MARGIN_S adds reaction
// distance at the current surface speed. Neither is capped — a 2.5 s
// clamp was eating the 4 s configured lead.
FUNCTION aoso_descent_burn_trigger_alt {
    LOCAL speed_ms IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL decel IS aoso_descent_max_deceleration().
    IF decel <= 0.05 { RETURN 999999. }
    LOCAL stop_m IS aoso_descent_stopping_distance(speed_ms, decel).
    IF stop_m < 0 { RETURN 999999. }
    LOCAL pad IS aoso_config_get("DESCENT_STOP_MARGIN", 1.2).
    IF pad < 1 { SET pad TO 1. }
    LOCAL margin_s IS aoso_config_get("DESCENT_BURN_MARGIN_S", 4).
    IF margin_s < 0 { SET margin_s TO 0. }
    LOCAL trig IS stop_m * pad + speed_ms * margin_s.
    IF trig < 8 { SET trig TO 8. }
    RETURN trig.
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

// Sink schedule after the full-vector braking phase. The old hoverslam
// throttle was stop/radar, so a high-TWR craft naturally settled at its
// hover throttle thousands of metres up. A negative target at every height
// makes altitude progress explicit while retaining a gentle final sink.
FUNCTION aoso_descent_target_sink {
    PARAMETER clearance_m.
    PARAMETER final_mode IS FALSE.
    LOCAL final_sink IS aoso_config_get("DESCENT_FINAL_SPEED", -3).
    IF final_sink > -0.5 { SET final_sink TO -0.5. }
    IF final_mode { RETURN final_sink. }
    LOCAL final_h IS aoso_config_get("DESCENT_FINAL_APPROACH_ALT", 150).
    LOCAL max_sink IS aoso_config_get("DESCENT_GUIDE_MAX_SINK", 20).
    IF max_sink < ABS(final_sink) { SET max_sink TO ABS(final_sink). }
    LOCAL sink_gain IS aoso_config_get("DESCENT_GUIDE_SINK_GAIN", 0.01).
    IF sink_gain < 0 { SET sink_gain TO 0. }
    LOCAL extra_h IS clearance_m - final_h.
    IF extra_h < 0 { SET extra_h TO 0. }
    LOCAL sink_mag IS ABS(final_sink) + extra_h * sink_gain.
    IF sink_mag > max_sink { SET sink_mag TO max_sink. }
    RETURN 0 - sink_mag.
}

// Direction of the stored unpowered impact error in the local tangent plane.
// This uses the predictor only as a bounded bias; survival braking always
// wins and large errors are explicitly ignored rather than chased.
FUNCTION aoso_descent_impact_error_vector {
    PARAMETER data.
    IF NOT data:HASKEY("impact_miss") { RETURN V(0, 0, 0). }
    IF NOT data:HASKEY("impact_lat") { RETURN V(0, 0, 0). }
    IF NOT data:HASKEY("impact_lng") { RETURN V(0, 0, 0). }
    LOCAL max_miss IS aoso_config_get("DESCENT_TARGET_MAX_MISS", 6000).
    IF data["impact_miss"] <= 0 { RETURN V(0, 0, 0). }
    IF data["impact_miss"] > max_miss { RETURN V(0, 0, 0). }

    LOCAL target_lat IS 0.
    LOCAL target_lng IS 0.
    LOCAL have_target IS FALSE.
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("site_lat") {
                SET target_lat TO AOSO_TOUR["data"]["site_lat"].
                SET target_lng TO AOSO_TOUR["data"]["site_lng"].
                SET have_target TO TRUE.
            }
        }
    }
    IF NOT have_target { RETURN V(0, 0, 0). }
    LOCAL body_pos IS SHIP:BODY:POSITION.
    LOCAL impact_vec IS LATLNG(data["impact_lat"], data["impact_lng"]):POSITION - body_pos.
    LOCAL target_vec IS LATLNG(target_lat, target_lng):POSITION - body_pos.
    LOCAL error_vec IS target_vec - impact_vec.
    RETURN VXCL(SHIP:UP:VECTOR, error_vec).
}

// One vector controller owns both axes after the initial surface-retrograde
// kill. Horizontal velocity is driven toward zero (plus a small predictor
// bias) while vertical velocity follows the radar-dependent sink schedule.
FUNCTION aoso_descent_guidance {
    PARAMETER data.
    PARAMETER final_mode IS FALSE.
    LOCAL clear_m IS aoso_descent_clearance().
    LOCAL speed_ms IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL decel IS aoso_descent_max_deceleration().
    LOCAL stop_m IS aoso_descent_stopping_distance(speed_ms, decel).
    IF stop_m < 0 { SET stop_m TO clear_m. }
    LOCAL pad IS aoso_config_get("DESCENT_STOP_MARGIN", 1.2).
    IF pad < 1 { SET pad TO 1. }

    LOCAL handoff_hs IS aoso_config_get("DESCENT_BRAKE_HANDOFF_HS", 2).
    LOCAL resume_hs IS aoso_config_get("DESCENT_BRAKE_RESUME_HS", 6).
    IF resume_hs < handoff_hs + 1 { SET resume_hs TO handoff_hs + 1. }
    LOCAL max_handoff IS aoso_config_get("DESCENT_FINAL_SPEED_MAX", 25).
    LOCAL guide_mode IS "SURVIVAL".
    IF data:HASKEY("guidance_mode") { SET guide_mode TO data["guidance_mode"]. }
    LOCAL reported_miss IS -1.
    IF data:HASKEY("impact_miss") { SET reported_miss TO data["impact_miss"]. }
    LOCAL must_brake IS FALSE.
    IF clear_m <= stop_m * pad { SET must_brake TO TRUE. }
    IF guide_mode = "SURVIVAL" {
        IF GROUNDSPEED > handoff_hs { SET must_brake TO TRUE. }
        IF speed_ms > max_handoff { SET must_brake TO TRUE. }
    } ELSE {
        IF GROUNDSPEED > resume_hs { SET must_brake TO TRUE. }
    }
    IF must_brake {
        SET data["guidance_mode"] TO "SURVIVAL".
        RETURN LEXICON("mode", "SURVIVAL", "direction", SHIP:SRFRETROGRADE:VECTOR,
            "throttle", 1, "target_sink", 0, "clearance", clear_m,
            "stop", stop_m, "miss", reported_miss).
    }

    LOCAL mode_txt IS "GUIDE".
    IF final_mode { SET mode_txt TO "FINAL". }
    SET data["guidance_mode"] TO mode_txt.
    LOCAL target_sink IS aoso_descent_target_sink(clear_m, final_mode).
    IF data:HASKEY("sink_recovery_until") {
        IF TIME:SECONDS < data["sink_recovery_until"] {
            IF target_sink > -6 { SET target_sink TO -6. }
        }
    }

    LOCAL max_accel IS 0.
    IF SHIP:MASS > 0 { SET max_accel TO SHIP:AVAILABLETHRUST / SHIP:MASS. }
    IF max_accel <= 0 {
        RETURN LEXICON("mode", "NO_THRUST", "direction", SHIP:UP:VECTOR,
            "throttle", 0, "target_sink", target_sink, "clearance", clear_m,
            "stop", stop_m, "miss", reported_miss).
    }

    LOCAL g_loc IS aoso_descent_local_gravity().
    LOCAL vertical_gain IS 0.6.
    LOCAL up_accel IS g_loc + vertical_gain * (target_sink - VERTICALSPEED).
    IF up_accel < 0 { SET up_accel TO 0. }
    IF up_accel > max_accel { SET up_accel TO max_accel. }

    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL horizontal_vel IS VXCL(up_vec, SHIP:VELOCITY:SURFACE).
    LOCAL horizontal_accel IS horizontal_vel * -0.45.
    LOCAL miss_m IS reported_miss.
    LOCAL target_bias IS V(0, 0, 0).
    LOCAL impact_error IS aoso_descent_impact_error_vector(data).
    IF impact_error:MAG > 1 {
        LOCAL target_speed IS MIN(aoso_config_get("DESCENT_TARGET_MAX_SPEED", 5), miss_m * 0.002).
        SET target_bias TO impact_error:NORMALIZED * target_speed * 0.35.
    }

    // Preserve a real vertical component whenever lateral thrust is needed;
    // then cap velocity cancellation and target correction independently.
    IF horizontal_accel:MAG > 0.01 OR target_bias:MAG > 0.01 {
        IF up_accel < g_loc * 0.5 { SET up_accel TO g_loc * 0.5. }
    }
    LOCAL guide_tilt IS aoso_config_get("DESCENT_GUIDE_MAX_TILT", 45).
    IF guide_tilt < 5 { SET guide_tilt TO 5. }
    IF guide_tilt > 70 { SET guide_tilt TO 70. }
    LOCAL horizontal_cap IS up_accel * TAN(guide_tilt).
    IF horizontal_cap > max_accel * 0.9 { SET horizontal_cap TO max_accel * 0.9. }
    IF horizontal_accel:MAG > horizontal_cap {
        SET horizontal_accel TO horizontal_accel:NORMALIZED * horizontal_cap.
    }
    LOCAL target_tilt IS aoso_config_get("DESCENT_TARGET_MAX_TILT", 10).
    IF target_tilt < 0 { SET target_tilt TO 0. }
    IF target_tilt > 25 { SET target_tilt TO 25. }
    LOCAL target_cap IS up_accel * TAN(target_tilt).
    IF target_bias:MAG > target_cap {
        SET target_bias TO target_bias:NORMALIZED * target_cap.
    }
    SET horizontal_accel TO horizontal_accel + target_bias.
    IF horizontal_accel:MAG > horizontal_cap {
        SET horizontal_accel TO horizontal_accel:NORMALIZED * horizontal_cap.
    }

    LOCAL command_vec IS up_vec * up_accel + horizontal_accel.
    LOCAL command_mag IS command_vec:MAG.
    IF command_mag < 0.01 { SET command_vec TO up_vec. }
    LOCAL throttle_cmd IS command_mag / max_accel.
    IF throttle_cmd > 1 { SET throttle_cmd TO 1. }
    IF throttle_cmd < 0 { SET throttle_cmd TO 0. }
    RETURN LEXICON("mode", mode_txt, "direction", command_vec,
        "throttle", throttle_cmd, "target_sink", target_sink,
        "clearance", clear_m, "stop", stop_m, "miss", miss_m).
}

FUNCTION aoso_descent_should_final_approach {
    LOCAL h IS aoso_descent_true_radar().
    LOCAL final_alt IS aoso_config_get("DESCENT_FINAL_APPROACH_ALT", 150).
    IF h > final_alt { RETURN FALSE. }
    LOCAL max_speed IS aoso_config_get("DESCENT_FINAL_SPEED_MAX", 25).
    IF SHIP:VELOCITY:SURFACE:MAG > max_speed { RETURN FALSE. }
    LOCAL handoff_hs IS aoso_config_get("DESCENT_BRAKE_HANDOFF_HS", 2).
    IF GROUNDSPEED > handoff_hs + 1 { RETURN FALSE. }
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

// TRUE if periapsis altitude actually reaches the kinematic suicide
// clearance. An 8 km PE on Minmus with a ~2 km stop distance never does.
// Do not treat "radar under 6 km" as success: that shortcut is why a
// 600 m PE over a 2.7 km highland was allowed to coast in rails.
FUNCTION aoso_descent_pe_reaches_suicide {
    IF aoso_orbit_is_hyperbolic() { RETURN TRUE. }
    IF PERIAPSIS < 0 { RETURN TRUE. }
    IF SHIP:BODY:ATM:EXISTS {
        IF PERIAPSIS < SHIP:BODY:ATM:HEIGHT { RETURN TRUE. }
        RETURN FALSE.
    }
    LOCAL trigger IS aoso_descent_burn_trigger_alt().
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
            aoso_warp_approach(pe_eta, 25, 12).
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

    LOCAL trigger IS aoso_descent_burn_trigger_alt().
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
    LOCAL stop_m IS aoso_descent_stopping_distance(speed_ms, decel).
    IF stop_m < 0 { SET stop_m TO trigger. }
    LOCAL critical IS FALSE.
    IF clear <= stop_m * 0.7 { SET critical TO TRUE. }

    LOCAL coast_eta IS aoso_descent_eta_to_asl(align_h + MAX(aoso_deorbit_site_alt(), SHIP:GEOPOSITION:TERRAINHEIGHT)).
    IF coast_eta > pe_eta AND pe_eta > 0 { SET coast_eta TO pe_eta. }

    aoso_log_every(30, "DESCENT", "Freefall alt=" + ROUND(ALTITUDE, 0) + " AP=" + ROUND(APOAPSIS, 0) +
        " PE=" + ROUND(PERIAPSIS, 0) + " vs=" + ROUND(VERTICALSPEED, 1) + " radar=" + ROUND(radar, 0) +
        " clr=" + ROUND(clear, 0) + " trig=" + ROUND(trigger, 0) + " align=" + ROUND(align_h, 0) +
        " peEta=" + ROUND(pe_eta, 0) + "s tti=" + ROUND(tti, 1) +
        "s tStop=" + ROUND(t_stop, 1) + "s coastEta=" + ROUND(coast_eta, 0) + "s " + aoso_warp_diag_txt() + ".").

    IF clear > align_h {
        IF data:HASKEY("align_since") { data:REMOVE("align_since"). }
        aoso_steer_release().
        aoso_warp_approach(coast_eta, 25, 12).
        RETURN.
    }

    // Inside the align band: kill warp and point surface-retrograde BEFORE
    // any throttle. A rails drop can flush several seconds; do not light
    // the engine on that same tick unless the ground is already inside the
    // no-margin stop distance.
    IF WARP > 0 OR KUNIVERSE:TIMEWARP:RATE > 1.01 OR NOT SHIP:UNPACKED {
        SET WARP TO 0.
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
        "m/s2 stop=" + ROUND(stop_m, 1) + "m targetMiss=" + ROUND(miss_commit, 0) +
        "m " + aoso_warp_diag_txt() + ".").
    aoso_log_info("DESCENT", "Suicide burn now: radar=" + ROUND(radar, 0) + " m clr=" + ROUND(clear, 0) +
        " m trigger=" + ROUND(trigger, 0) + " m vSrf=" + ROUND(speed_ms, 1) + " m/s vVert=" +
        ROUND(VERTICALSPEED, 1) + " m/s face=" + ROUND(facing_err, 0) + " deg held=" + ROUND(held, 1) +
        "s tStop=" + ROUND(t_stop, 1) + "s decel=" + ROUND(decel, 2) + " m/s^2 " + aoso_warp_diag_txt() + ".").
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

FUNCTION aoso_descent_apply_guidance {
    PARAMETER data.
    PARAMETER final_mode IS FALSE.
    LOCAL cmd IS aoso_descent_guidance(data, final_mode).
    IF cmd["mode"] = "SURVIVAL" {
        aoso_steer_srf_retrograde().
    } ELSE {
        aoso_steer_to_vector(cmd["direction"]).
    }
    aoso_throttle_set(cmd["throttle"]).
    RETURN cmd.
}

FUNCTION aoso_descent_watch_progress {
    PARAMETER data.
    PARAMETER radar_m.
    LOCAL now_ut IS TIME:SECONDS.
    IF NOT data:HASKEY("progress_ut") {
        SET data["progress_ut"] TO now_ut.
        SET data["progress_radar"] TO radar_m.
        RETURN.
    }
    IF radar_m <= data["progress_radar"] - 5 {
        SET data["progress_ut"] TO now_ut.
        SET data["progress_radar"] TO radar_m.
        RETURN.
    }
    IF radar_m > data["progress_radar"] + 25 {
        SET data["progress_ut"] TO now_ut.
        SET data["progress_radar"] TO radar_m.
        RETURN.
    }
    LOCAL stall_s IS aoso_config_get("DESCENT_STALL_S", 15).
    IF now_ut - data["progress_ut"] < stall_s { RETURN. }
    LOCAL final_h IS aoso_config_get("DESCENT_FINAL_APPROACH_ALT", 150).
    IF radar_m <= final_h + 50 { RETURN. }
    IF VERTICALSPEED < -1 { RETURN. }
    SET data["sink_recovery_until"] TO now_ut + 10.
    SET data["progress_ut"] TO now_ut.
    SET data["progress_radar"] TO radar_m.
    aoso_log_warn("DESCENT_STALL", "Powered descent stopped losing altitude at radar=" +
        ROUND(radar_m, 0) + "m vs=" + ROUND(VERTICALSPEED, 1) +
        "m/s hs=" + ROUND(GROUNDSPEED, 1) + "m/s; forcing the sink schedule.").
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
    SET WARP TO 0.
    SET data["guidance_mode"] TO "SURVIVAL".
    SET data["progress_ut"] TO TIME:SECONDS.
    SET data["progress_radar"] TO aoso_descent_true_radar().
    aoso_descent_maintain_legs(aoso_descent_true_radar(), TRUE).
    IF SHIP:AVAILABLETHRUST <= 0 { aoso_staging_ensure_thrust(). }
    LOCAL cmd IS aoso_descent_apply_guidance(data, FALSE).
    aoso_descent_operator_status(data, cmd).
}

FUNCTION aoso_descent_burn_execute {
    PARAMETER data.
    aoso_descent_measure_dv(data).
    aoso_parachute_auto_check().
    SET WARP TO 0.

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

    aoso_descent_watch_progress(data, radar).
    LOCAL cmd IS aoso_descent_apply_guidance(data, FALSE).
    aoso_descent_operator_status(data, cmd).

    IF aoso_descent_should_final_approach() {
        aoso_log_info("DESCENT", "Guidance handoff to FINAL at radar=" + ROUND(radar, 1) +
            "m vs=" + ROUND(VERTICALSPEED, 1) + "m/s hs=" + ROUND(GROUNDSPEED, 1) + "m/s.").
        aoso_state_transition(AOSO_DESCENT, "FINAL_APPROACH").
    }
}

FUNCTION aoso_descent_final_approach_entry {
    PARAMETER data.
    aoso_descent_maintain_legs(aoso_descent_true_radar(), TRUE).
    SET data["guidance_mode"] TO "FINAL".
    LOCAL cmd IS aoso_descent_apply_guidance(data, TRUE).
    aoso_descent_operator_status(data, cmd).
}

FUNCTION aoso_descent_final_approach_execute {
    PARAMETER data.
    aoso_descent_measure_dv(data).
    aoso_descent_maintain_legs(aoso_descent_true_radar()).
    // Hysteresis: do not bounce states at the entry thresholds, but return to
    // survival braking if a disturbance creates a clearly unsafe slide.
    IF NOT aoso_descent_should_final_approach() {
        IF SHIP:STATUS <> "LANDED" {
            LOCAL resume_hs IS aoso_config_get("DESCENT_BRAKE_RESUME_HS", 6).
            LOCAL resume_speed IS aoso_config_get("DESCENT_FINAL_SPEED_MAX", 25) * 1.4.
            IF GROUNDSPEED > resume_hs OR SHIP:VELOCITY:SURFACE:MAG > resume_speed {
                aoso_log_warn("DESCENT", "Final approach disturbed (vSrf=" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1) +
                    "m/s hs=" + ROUND(GROUNDSPEED, 1) + "m/s) - returning to survival braking.").
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
    }

    LOCAL cmd IS aoso_descent_apply_guidance(data, TRUE).
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
