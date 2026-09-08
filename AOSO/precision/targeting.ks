// AOSO/precision/targeting.ks
// Phase 9 (Precision KSC return) foundation: pure-kOS ground-track
// prediction and target-site geometry, built only on stock GEOPOSITIONOF/
// ALTITUDEOF/POSITIONAT/GEOPOSITIONLATLNG suffixes (no MechJeb/Trajectories
// dependency -- see core/addons.ks). POSITIONAT (and therefore every
// helper below) already accounts for the CPU vessel's currently planned
// maneuver nodes, per kOS's own "Predictions of Flight Path" docs -- so a
// candidate deorbit node only has to be ADDed for these helpers to see its
// post-burn ground track, with no separate simulation needed.
//
// Every prediction here is a ballistic (vacuum, no-drag) coast projection,
// the same "unpowered coasting prediction only" scope nav/orbit.ks
// documents for its own POSITIONAT-based helpers. That is exact right up
// until the real trajectory starts feeling atmospheric drag, so
// precision/kscreturn.ks only ever trusts these predictions down to
// aoso_targeting_interface_alt() (the atmosphere's edge, or sea level on an
// airless body) -- everything below that interface is landing/deorbit.ks +
// landing/descent.ks's job, same handoff point return/return.ks already
// uses for the exo-atmospheric portion of a return trip.

// Target landing site (KSC by default -- core/config.ks's KSC_LAT/KSC_LNG),
// as a GeoCoordinates on SHIP:BODY. Every miss-distance check below compares
// a predicted ground-track point against this.
FUNCTION aoso_targeting_site {
    RETURN SHIP:BODY:GEOPOSITIONLATLNG(
        aoso_config_get("KSC_LAT", -0.0972),
        aoso_config_get("KSC_LNG", -74.5577)
    ).
}

// Body-centered surface position vector for a GeoCoordinates. GeoCoordinates
// :POSITION is Ship-Raw (relative to the CPU vessel's center of mass, per
// kOS docs), so subtracting the body's own :POSITION (measured "now", the
// same convention nav/orbit.ks's aoso_orbit_position_now uses) cancels that
// shared origin and leaves a body-centered vector.
FUNCTION aoso_targeting_geo_position_now {
    PARAMETER geo.
    RETURN geo:POSITION - geo:BODY:POSITION.
}

// Great-circle ground distance (m) between two GeoCoordinates on the same
// body, via the angle between their body-centered position vectors --
// correct across long distances, unlike a flat lat/lng delta (which
// landing/site.ks's small local slope samples can get away with, but a
// deorbit-to-KSC miss routinely cannot).
FUNCTION aoso_targeting_ground_distance {
    PARAMETER geo_a.
    PARAMETER geo_b.
    LOCAL ang IS VANG(aoso_targeting_geo_position_now(geo_a), aoso_targeting_geo_position_now(geo_b)).
    RETURN ang * AOSO_CONST["DEG2RAD"] * geo_a:BODY:RADIUS.
}

// The altitude (m) this module treats as the "atmosphere interface" --
// above it every prediction here is exact (no drag yet); below it, control
// passes to landing/deorbit.ks + landing/descent.ks. Airless bodies have no
// such interface, so sea level (0) is used directly, mirroring
// landing/deorbit.ks's own atmospheric-vs-airless target periapsis split.
FUNCTION aoso_targeting_interface_alt {
    IF SHIP:BODY:ATM:EXISTS { RETURN SHIP:BODY:ATM:HEIGHT. }
    RETURN 0.
}

// Ballistic ground-track point at time ut: the GeoCoordinates directly
// beneath orbitable's coasting position, ignoring any atmosphere. Reflects
// any currently planned maneuver nodes for ut past their burn time (see
// file header) when orbitable is SHIP.
FUNCTION aoso_targeting_ground_track_at {
    PARAMETER ut.
    PARAMETER orbitable IS SHIP.
    RETURN orbitable:BODY:GEOPOSITIONOF(POSITIONAT(orbitable, ut)).
}

// Sea-level-relative altitude (m) of the coasting position at time ut, used
// to find when the ballistic trajectory crosses a given altitude (the
// atmosphere interface, or 0 for an airless body).
FUNCTION aoso_targeting_altitude_at {
    PARAMETER ut.
    PARAMETER orbitable IS SHIP.
    RETURN orbitable:BODY:ALTITUDEOF(POSITIONAT(orbitable, ut)).
}

// Seconds from now until the ballistic trajectory first crosses target_alt,
// bisecting the same way nav/orbit.ks's aoso_orbit_relative_node_etas does.
// Samples out to search_horizon_s (falling back to orbitable's *current*
// patch ETA:PERIAPSIS when no explicit horizon is given -- pass a post-node
// Orbit's own ETA:PERIAPSIS as search_horizon_s instead when checking a
// candidate deorbit node, since an orbit patch's plain ETA:PERIAPSIS
// ignores any pending nodes beyond it). Returns 0 if already below
// target_alt right now, or -1 if no crossing is found within the horizon.
FUNCTION aoso_targeting_time_to_altitude {
    PARAMETER target_alt.
    PARAMETER search_horizon_s IS 0.
    PARAMETER orbitable IS SHIP.

    IF search_horizon_s <= 0 { SET search_horizon_s TO MAX(60, orbitable:ORBIT:ETA:PERIAPSIS). }

    LOCAL now IS TIME:SECONDS.
    LOCAL samples IS 60.
    LOCAL dt IS search_horizon_s / samples.

    LOCAL prev_t IS 0.
    LOCAL prev_val IS aoso_targeting_altitude_at(now, orbitable) - target_alt.
    IF prev_val <= 0 { RETURN 0. }

    LOCAL i IS 1.
    UNTIL i > samples {
        LOCAL t IS i * dt.
        LOCAL val IS aoso_targeting_altitude_at(now + t, orbitable) - target_alt.

        IF val <= 0 {
            LOCAL lo IS prev_t.
            LOCAL hi IS t.
            LOCAL iter IS 0.
            UNTIL iter >= 20 {
                LOCAL mid IS (lo + hi) / 2.
                LOCAL mid_val IS aoso_targeting_altitude_at(now + mid, orbitable) - target_alt.
                IF mid_val <= 0 { SET hi TO mid. } ELSE { SET lo TO mid. }
                SET iter TO iter + 1.
            }
            RETURN (lo + hi) / 2.
        }

        SET prev_t TO t.
        SET prev_val TO val.
        SET i TO i + 1.
    }
    RETURN -1.
}

// Predicted ground-track miss distance (m) from target_geo at the moment
// the ballistic trajectory reaches target_alt (see
// aoso_targeting_time_to_altitude). Returns -1 if no crossing was found
// within search_horizon_s, so callers can treat that candidate as invalid
// rather than mistaking it for a real (possibly zero) miss distance.
FUNCTION aoso_targeting_predicted_miss_m {
    PARAMETER target_alt.
    PARAMETER search_horizon_s IS 0.
    PARAMETER target_geo IS 0.
    PARAMETER orbitable IS SHIP.

    IF NOT target_geo:ISTYPE("GeoCoordinates") { SET target_geo TO aoso_targeting_site(). }

    LOCAL eta_s IS aoso_targeting_time_to_altitude(target_alt, search_horizon_s, orbitable).
    IF eta_s < 0 { RETURN -1. }

    LOCAL track IS aoso_targeting_ground_track_at(TIME:SECONDS + eta_s, orbitable).
    RETURN aoso_targeting_ground_distance(track, target_geo).
}
