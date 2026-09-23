// AOSO/landing/site.ks
// Phase 6 (Landing) foundation: pure-kOS landing-site safety scoring, built
// only on stock LATLNG/GeoCoordinates suffixes (no MechJeb/KER dependency --
// see core/addons.ks). landing/deorbit.ks and landing/descent.ks target a
// GeoCoordinates chosen/validated here rather than a raw lat/lng pair, so
// every landing module shares one definition of "safe".

// Offsets a GeoCoordinates by a small lat/lng delta (degrees). Kept
// separate from aoso_landing_site_slope_deg() so callers needing a single
// nearby sample (e.g. a custom scoring pass) don't have to re-derive it.
FUNCTION aoso_landing_site_offset_geo {
    PARAMETER geo.
    PARAMETER d_lat_deg.
    PARAMETER d_lng_deg.
    RETURN LATLNG(geo:LAT + d_lat_deg, geo:LNG + d_lng_deg).
}

// Converts a great-circle sample distance (m) at a geo's latitude into a
// latitude-degrees delta, via the body's mean radius plus the site's own
// terrain height (so mountain/canyon sites still get a locally-correct
// sample spacing instead of assuming sea level).
FUNCTION aoso_landing_site_sample_delta_deg {
    PARAMETER geo.
    PARAMETER sample_dist_m.
    LOCAL radius IS SHIP:BODY:RADIUS + geo:TERRAINHEIGHT.
    IF radius <= 0 { RETURN 0. }
    RETURN (sample_dist_m / radius) * AOSO_CONST["RAD2DEG"].
}

// Local terrain slope (deg, 0-90) at geo, estimated by sampling terrain
// height a short distance north/south/east/west and taking the steepest of
// the two finite-difference gradients. This avoids any single-axis bias
// (e.g. a site on a north-south ridge would look flat if only sampled
// east-west) without needing a full raycast/heightmap the stock game does
// not expose to kOS.
FUNCTION aoso_landing_site_slope_deg {
    PARAMETER geo.
    PARAMETER sample_dist_m IS 50.

    LOCAL d IS aoso_landing_site_sample_delta_deg(geo, sample_dist_m).
    IF d <= 0 { RETURN 0. }

    LOCAL h_north IS aoso_landing_site_offset_geo(geo, d, 0):TERRAINHEIGHT.
    LOCAL h_south IS aoso_landing_site_offset_geo(geo, -d, 0):TERRAINHEIGHT.
    LOCAL h_east IS aoso_landing_site_offset_geo(geo, 0, d):TERRAINHEIGHT.
    LOCAL h_west IS aoso_landing_site_offset_geo(geo, 0, -d):TERRAINHEIGHT.

    LOCAL grade_ns IS ABS(h_north - h_south) / (2 * sample_dist_m).
    LOCAL grade_ew IS ABS(h_east - h_west) / (2 * sample_dist_m).

    RETURN ARCTAN(MAX(grade_ns, grade_ew)).
}

// Local relief around the touchdown point. Slope alone can rate the center
// of a small crater/ridge as flat even when the surrounding footprint is
// rough. This measures max-min terrain across center + four cardinal samples.
FUNCTION aoso_landing_site_roughness_m {
    PARAMETER geo.
    PARAMETER sample_dist_m IS 0.
    IF sample_dist_m <= 0 {
        SET sample_dist_m TO aoso_config_get("LANDING_ROUGHNESS_SAMPLE_M", 200).
    }
    LOCAL d IS aoso_landing_site_sample_delta_deg(geo, sample_dist_m).
    IF d <= 0 { RETURN 0. }

    LOCAL h0 IS geo:TERRAINHEIGHT.
    LOCAL hn IS aoso_landing_site_offset_geo(geo, d, 0):TERRAINHEIGHT.
    LOCAL hs IS aoso_landing_site_offset_geo(geo, -d, 0):TERRAINHEIGHT.
    LOCAL he IS aoso_landing_site_offset_geo(geo, 0, d):TERRAINHEIGHT.
    LOCAL hw IS aoso_landing_site_offset_geo(geo, 0, -d):TERRAINHEIGHT.

    LOCAL lo IS h0.
    LOCAL hi IS h0.
    IF hn < lo { SET lo TO hn. }
    IF hs < lo { SET lo TO hs. }
    IF he < lo { SET lo TO he. }
    IF hw < lo { SET lo TO hw. }
    IF hn > hi { SET hi TO hn. }
    IF hs > hi { SET hi TO hs. }
    IF he > hi { SET hi TO he. }
    IF hw > hi { SET hi TO hw. }
    RETURN hi - lo.
}

// TRUE if geo sits on/under this body's ocean (never a valid touchdown
// site for a lander). Bodies with no ocean always report FALSE here
// regardless of TERRAINHEIGHT sign.
FUNCTION aoso_landing_site_is_water {
    PARAMETER geo.
    IF NOT SHIP:BODY:HASOCEAN { RETURN FALSE. }
    RETURN geo:TERRAINHEIGHT < 0.
}

// Lower-is-better score for comparing candidate sites: disqualifies water
// or over-slope sites outright (-1). Remaining terms: slope (safety),
// latitude (solar / equatorial departure), terrain altitude (takeoff dV
// on atmo worlds, peak penalty on airless), optional distance to a
// preferred waypoint. A slightly steeper highland that is cheaper to
// leave can beat a dead-flat basin.
FUNCTION aoso_landing_site_score {
    PARAMETER geo.
    PARAMETER target_geo IS 0.

    IF aoso_landing_site_is_water(geo) { RETURN -1. }

    LOCAL slope IS aoso_landing_site_slope_deg(geo).
    LOCAL max_slope IS aoso_config_get("MAX_SLOPE_DEG", 15).
    IF slope > max_slope { RETURN -1. }

    LOCAL roughness IS aoso_landing_site_roughness_m(geo).
    LOCAL rough_w IS aoso_config_get("LANDING_ROUGHNESS_WEIGHT", 0.08).
    IF rough_w < 0 { SET rough_w TO 0. }

    LOCAL score IS slope * 2.5 + roughness * rough_w.
    LOCAL alt_m IS geo:TERRAINHEIGHT.
    LOCAL lat_abs IS ABS(geo:LAT).

    LOCAL solar_pref IS FALSE.
    IF DEFINED AOSO_PROFILE {
        IF AOSO_PROFILE:HASKEY("power") {
            IF AOSO_PROFILE["power"]["solar_count"] > 0 { SET solar_pref TO TRUE. }
        }
    }
    IF solar_pref {
        SET score TO score + lat_abs * 0.08.
    } ELSE {
        SET score TO score + lat_abs * 0.03.
    }

    IF SHIP:BODY:ATM:EXISTS {
        LOCAL high_bonus IS alt_m / 1500.
        IF high_bonus > 10 { SET high_bonus TO 10. }
        IF high_bonus < 0 { SET high_bonus TO 0. }
        SET score TO score - high_bonus.
        IF alt_m < 0 { SET score TO score + 12. }
    } ELSE {
        IF alt_m > 5000 { SET score TO score + 4. }
        IF alt_m < -200 { SET score TO score + 1. }
    }

    IF target_geo:ISTYPE("GeoCoordinates") {
        SET score TO score + (geo:DISTANCE / 2000).
    }
    RETURN score.
}

FUNCTION aoso_landing_site_quality {
    PARAMETER geo.
    PARAMETER target_geo IS 0.
    LOCAL sc IS aoso_landing_site_score(geo, target_geo).
    LOCAL slope IS 0.
    LOCAL roughness IS 0.
    LOCAL alt_m IS 0.
    LOCAL water IS FALSE.
    LOCAL lat_n IS 0.
    LOCAL lng_n IS 0.
    IF geo:ISTYPE("GeoCoordinates") {
        SET slope TO aoso_landing_site_slope_deg(geo).
        SET roughness TO aoso_landing_site_roughness_m(geo).
        SET alt_m TO geo:TERRAINHEIGHT.
        SET water TO aoso_landing_site_is_water(geo).
        SET lat_n TO geo:LAT.
        SET lng_n TO geo:LNG.
    }
    LOCAL max_slope IS aoso_config_get("MAX_SLOPE_DEG", 15).
    LOCAL slope_score IS 0.
    IF max_slope > 0 { SET slope_score TO 1 - (slope / max_slope). }
    IF slope_score < 0 { SET slope_score TO 0. }
    LOCAL sun_score IS 1 - (ABS(lat_n) / 90).
    IF sun_score < 0 { SET sun_score TO 0. }
    LOCAL takeoff_score IS 0.6.
    IF SHIP:BODY:ATM:EXISTS {
        LOCAL bonus IS alt_m / 8000.
        IF bonus > 0.5 { SET bonus TO 0.5. }
        IF bonus < 0 { SET bonus TO 0. }
        SET takeoff_score TO 0.4 + bonus.
    } ELSE {
        IF alt_m > 5000 { SET takeoff_score TO 0.4. }
        ELSE { SET takeoff_score TO 0.7. }
    }
    LOCAL roughness_score IS 1 - (roughness / 150).
    IF roughness_score < 0 { SET roughness_score TO 0. }
    IF roughness_score > 1 { SET roughness_score TO 1. }
    LOCAL safety_score IS slope_score * 0.7 + roughness_score * 0.3.
    IF water { SET safety_score TO 0. }
    LOCAL resource_score IS 0.5.
    IF DEFINED AOSO_PROFILE {
        IF aoso_profile_capable("can_isru") { SET resource_score TO 0.6. }
    }
    LOCAL overall IS 0.35 * safety_score + 0.2 * sun_score + 0.25 * takeoff_score + 0.2 * resource_score.
    LOCAL ok IS FALSE.
    IF sc >= 0 { SET ok TO TRUE. }
    LOCAL conf IS 0.55.
    RETURN LEXICON(
        "lat", lat_n,
        "lng", lng_n,
        "slope_score", ROUND(slope_score, 3),
        "roughness_score", ROUND(roughness_score, 3),
        "roughness_m", ROUND(roughness, 1),
        "elevation_score", ROUND(takeoff_score, 3),
        "resource_score", ROUND(resource_score, 3),
        "sun_score", ROUND(sun_score, 3),
        "takeoff_score", ROUND(takeoff_score, 3),
        "safety_score", ROUND(safety_score, 3),
        "overall_score", ROUND(overall, 3),
        "confidence", conf,
        "slope_deg", ROUND(slope, 2),
        "score", sc,
        "alt", alt_m,
        "water", water,
        "ok", ok
    ).
}

// Instant orbital scan: samples the ground track over the next N periods
// (kOS can query TERRAINHEIGHT of any lat/lng from anywhere, so this does
// not require actually flying over the sites). Tour still warps LANDING_SCAN_ORBITS
// so a live overflight can beat the prediction. Returns a lexicon with
// the lowest-score safe site, or 0 if none of the samples were landable.
FUNCTION aoso_landing_site_scan_orbit {
    PARAMETER samples IS 0.
    IF samples <= 0 { SET samples TO aoso_config_get("LANDING_SCAN_SAMPLES", 36). }
    IF samples < 4 { SET samples TO 4. }

    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { SET period TO 600. }
    LOCAL orbits IS aoso_config_get("LANDING_SCAN_ORBITS", 2).
    IF orbits < 1 { SET orbits TO 1. }
    IF orbits > 4 { SET orbits TO 4. }
    LOCAL span IS period * orbits.

    LOCAL best_geo IS 0.
    LOCAL best_score IS 0.
    LOCAL found IS FALSE.
    LOCAL i IS 0.
    UNTIL i >= samples {
        LOCAL frac IS (i + 0.5) / samples.
        LOCAL ut IS TIME:SECONDS + (frac * span).
        LOCAL geo IS SHIP:BODY:GEOPOSITIONOF(POSITIONAT(SHIP, ut)).
        LOCAL sc IS aoso_landing_site_score(geo).
        IF sc >= 0 {
            IF NOT found {
                SET best_geo TO geo.
                SET best_score TO sc.
                SET found TO TRUE.
            } ELSE {
                IF sc < best_score {
                    SET best_geo TO geo.
                    SET best_score TO sc.
                }
            }
        }
        SET i TO i + 1.
    }

    IF NOT found {
        aoso_log_warn("SITE", "Orbit scan found no safe landing site among " + samples + " samples.").
        RETURN 0.
    }

    LOCAL slope IS aoso_landing_site_slope_deg(best_geo).
    LOCAL roughness IS aoso_landing_site_roughness_m(best_geo).
    LOCAL quality IS aoso_landing_site_quality(best_geo).
    aoso_log_info("SITE", "Best landing site lat=" + ROUND(best_geo:LAT, 2) + " lng=" + ROUND(best_geo:LNG, 2) +
        " alt=" + ROUND(best_geo:TERRAINHEIGHT, 0) + "m slope=" + ROUND(slope, 1) +
        "deg rough=" + ROUND(roughness, 0) + "m score=" + ROUND(best_score, 2) +
        " quality=" + quality["overall_score"] + " sun=" + quality["sun_score"] +
        " takeoff=" + quality["takeoff_score"] +
        " (" + samples + " samples / " + orbits + " orbit horizon).").
    RETURN LEXICON(
        "lat", best_geo:LAT,
        "lng", best_geo:LNG,
        "score", best_score,
        "slope", slope,
        "roughness", roughness,
        "alt", best_geo:TERRAINHEIGHT,
        "quality", quality["overall_score"],
        "sun", quality["sun_score"],
        "takeoff", quality["takeoff_score"]
    ).
}
