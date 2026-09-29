// AOSO/landing/impact.ks
// Rotation-aware, unpowered conic surface-intersection prediction.
// The predictor is intentionally separate from the deorbit periapsis proxy:
// after a burn it evaluates the vessel's live patched-conic orbit, finds the
// first terrain crossing, then reports that point in the body's future-fixed
// latitude/longitude frame. Powered flight/atmospheric drag are not modeled.

FUNCTION aoso_landing_wrap_lng {
    PARAMETER longitude_deg.
    UNTIL longitude_deg <= 180 { SET longitude_deg TO longitude_deg - 360. }
    UNTIL longitude_deg > -180 { SET longitude_deg TO longitude_deg + 360. }
    RETURN longitude_deg.
}

// Convert an inertial, body-relative position at a future UT into the
// surface coordinates that will be under that inertial point at that UT.
// GEOPOSITIONOF uses the body's current rotation, so unwind future spin
// using the same sign convention as the established deorbit geometry code.
FUNCTION aoso_landing_future_lng {
    PARAMETER current_lng.
    PARAMETER dt_s.
    PARAMETER rotation_s.
    LOCAL future_lng IS current_lng.
    IF rotation_s > 1 {
        SET future_lng TO future_lng - 360 * dt_s / rotation_s.
    }
    RETURN aoso_landing_wrap_lng(future_lng).
}

FUNCTION aoso_landing_impact_geo_at {
    PARAMETER impact_ut.
    LOCAL body_ref IS SHIP:BODY.
    LOCAL dt_s IS impact_ut - TIME:SECONDS.
    LOCAL rel_pos IS aoso_orbit_position_at(SHIP, impact_ut).
    IF rel_pos:MAG < 1 { RETURN 0. }
    LOCAL current_frame_geo IS body_ref:GEOPOSITIONOF(rel_pos + body_ref:POSITION).
    LOCAL rotation_s IS body_ref:ROTATIONPERIOD.
    LOCAL future_lng IS aoso_landing_future_lng(current_frame_geo:LNG, dt_s, rotation_s).
    RETURN LATLNG(current_frame_geo:LAT, future_lng).
}

// Evaluate radial clearance against the terrain queried at the future-fixed
// surface point. position/velocity are from KSP's patched-conic coast model.
FUNCTION aoso_landing_impact_sample {
    PARAMETER impact_ut.
    LOCAL body_ref IS SHIP:BODY.
    LOCAL rel_pos IS aoso_orbit_position_at(SHIP, impact_ut).
    IF rel_pos:MAG < 1 { RETURN 0. }
    LOCAL geo IS aoso_landing_impact_geo_at(impact_ut).
    IF NOT geo:ISTYPE("GeoCoordinates") { RETURN 0. }
    LOCAL terrain_m IS geo:TERRAINHEIGHT.
    LOCAL radial_alt IS rel_pos:MAG - body_ref:RADIUS.
    LOCAL clearance_m IS radial_alt - terrain_m.
    LOCAL rel_vel IS aoso_orbit_velocity_at(SHIP, impact_ut).
    RETURN LEXICON(
        "ok", TRUE,
        "clearance", clearance_m,
        "radial_alt", radial_alt,
        "terrain", terrain_m,
        "lat", geo:LAT,
        "lng", geo:LNG,
        "speed", rel_vel:MAG
    ).
}

// Find the first descending terrain crossing of the live unpowered conic.
// Returns ok=FALSE for a non-intersecting orbit or an invalid state. This
// is not used for atmospheric entry, powered descent, or a trajectory with
// an active maneuver node that has not yet been executed.
FUNCTION aoso_landing_impact_predict {
    PARAMETER target_lat IS 0.
    PARAMETER target_lng IS 0.
    PARAMETER max_horizon_s IS 0.

    LOCAL now_ut IS TIME:SECONDS.
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
        RETURN LEXICON("ok", FALSE, "reason", "already_on_surface").
    }
    IF SHIP:BODY:ATM:EXISTS {
        RETURN LEXICON("ok", FALSE, "reason", "atmosphere_not_modeled").
    }

    LOCAL period_s IS aoso_orbit_period_s().
    IF max_horizon_s <= 0 {
        IF period_s > 30 {
            SET max_horizon_s TO period_s * 1.25.
        } ELSE {
            SET max_horizon_s TO 21600.
        }
    }
    IF max_horizon_s < 120 { SET max_horizon_s TO 120. }
    IF max_horizon_s > 86400 { SET max_horizon_s TO 86400. }

    LOCAL samples_n IS 96.
    LOCAL step_s IS max_horizon_s / samples_n.
    LOCAL prev_t IS 0.
    LOCAL prev IS aoso_landing_impact_sample(now_ut).
    IF NOT prev:ISTYPE("Lexicon") {
        RETURN LEXICON("ok", FALSE, "reason", "invalid_initial_state").
    }

    LOCAL found IS FALSE.
    LOCAL lo_s IS 0.
    LOCAL hi_s IS 0.
    LOCAL best IS 0.
    LOCAL i IS 1.
    UNTIL i > samples_n {
        LOCAL t_s IS i * step_s.
        LOCAL cur IS aoso_landing_impact_sample(now_ut + t_s).
        IF cur:ISTYPE("Lexicon") {
            // Require a descending crossing. A terrain query that briefly
            // reports an unloaded zero-height sentinel must not count as an
            // impact while the vessel is still moving outward.
            IF cur["clearance"] <= 0 AND prev["clearance"] > 0 {
                SET lo_s TO prev_t.
                SET hi_s TO t_s.
                SET best TO cur.
                SET found TO TRUE.
                BREAK.
            }
            SET prev_t TO t_s.
            SET prev TO cur.
        }
        SET i TO i + 1.
    }

    IF NOT found {
        RETURN LEXICON("ok", FALSE, "reason", "no_surface_intersection",
            "horizon_s", max_horizon_s).
    }

    LOCAL iter IS 0.
    UNTIL iter >= 18 {
        LOCAL mid_s IS (lo_s + hi_s) / 2.
        LOCAL mid IS aoso_landing_impact_sample(now_ut + mid_s).
        IF NOT mid:ISTYPE("Lexicon") {
            SET lo_s TO mid_s.
        } ELSE {
            SET best TO mid.
            IF mid["clearance"] > 0 {
                SET lo_s TO mid_s.
            } ELSE {
                SET hi_s TO mid_s.
            }
        }
        SET iter TO iter + 1.
    }

    LOCAL impact_dt IS (lo_s + hi_s) / 2.
    LOCAL impact_ut IS now_ut + impact_dt.
    SET best TO aoso_landing_impact_sample(impact_ut).
    LOCAL miss_m IS -1.
    IF target_lat >= -90 AND target_lat <= 90 {
        LOCAL target_vec IS LATLNG(target_lat, target_lng):POSITION - SHIP:BODY:POSITION.
        LOCAL impact_vec IS LATLNG(best["lat"], best["lng"]):POSITION - SHIP:BODY:POSITION.
        IF target_vec:MAG > 1 AND impact_vec:MAG > 1 {
            SET miss_m TO VANG(target_vec, impact_vec) * AOSO_CONST["DEG2RAD"] * SHIP:BODY:RADIUS.
        }
    }
    RETURN LEXICON(
        "ok", TRUE,
        "reason", "conic_terrain_crossing",
        "time_to_impact", impact_dt,
        "impact_ut", impact_ut,
        "lat", best["lat"],
        "lng", best["lng"],
        "terrain_alt", best["terrain"],
        "radial_alt", best["radial_alt"],
        "impact_speed_inertial", best["speed"],
        "miss_distance", miss_m,
        "iterations", iter,
        "rotation_period", SHIP:BODY:ROTATIONPERIOD
    ).
}
