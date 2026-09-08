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

// TRUE if geo sits on/under this body's ocean (never a valid touchdown
// site for a lander). Bodies with no ocean always report FALSE here
// regardless of TERRAINHEIGHT sign.
FUNCTION aoso_landing_site_is_water {
    PARAMETER geo.
    IF NOT SHIP:BODY:HASOCEAN { RETURN FALSE. }
    RETURN geo:TERRAINHEIGHT < 0.
}

// Overall safety check combining the water check with the configured
// MAX_SLOPE_DEG cutoff (core/config.ks) -- the single predicate
// landing/descent.ks and any future site-selection logic should call
// instead of re-deriving the slope/water rules themselves.
FUNCTION aoso_landing_site_is_safe {
    PARAMETER geo.
    PARAMETER sample_dist_m IS 50.

    IF aoso_landing_site_is_water(geo) { RETURN FALSE. }
    RETURN aoso_landing_site_slope_deg(geo, sample_dist_m) <= aoso_config_get("MAX_SLOPE_DEG", 15).
}

// Lower-is-better score for comparing candidate sites: disqualifies water
// or over-slope sites outright (-1), otherwise combines slope with ground
// distance from an optional preferred target (e.g. a mission waypoint) so
// safe sites are ranked by how close they are to where the operator
// actually wanted to land.
FUNCTION aoso_landing_site_score {
    PARAMETER geo.
    PARAMETER target_geo IS 0.

    IF aoso_landing_site_is_water(geo) { RETURN -1. }

    LOCAL slope IS aoso_landing_site_slope_deg(geo).
    LOCAL max_slope IS aoso_config_get("MAX_SLOPE_DEG", 15).
    IF slope > max_slope { RETURN -1. }

    LOCAL score IS slope.
    IF target_geo:ISTYPE("GeoCoordinates") {
        SET score TO score + (geo:DISTANCE / 1000). // km, weighted lightly vs. slope degrees
    }
    RETURN score.
}
