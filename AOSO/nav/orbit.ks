// AOSO/nav/orbit.ks
// Phase 4 (Orbital nav) foundation: pure-kOS orbital-plane geometry and
// future-state prediction, built only on stock POSITIONAT/VELOCITYAT/VCRS
// suffixes (no MechJeb/Astrogator dependency -- see core/addons.ks). Every
// other nav/*.ks module (hohmann, planechange, rendezvous) builds on the
// helpers here instead of re-deriving orbital vectors.

// Body-centered position vector "now" for any orbitable (ship, other vessel,
// or body). ORBITABLE:POSITION is relative to the active vessel's current
// coordinate origin, so subtracting the body's own :POSITION (measured at
// the same instant) cancels that origin and leaves a body-centered vector.
FUNCTION aoso_orbit_position_now {
    PARAMETER orbitable IS SHIP.
    RETURN orbitable:POSITION - orbitable:BODY:POSITION.
}

// Body-centered position at an arbitrary (past or future) universal time,
// via kOS's builtin POSITIONAT -- valid for unpowered coasting prediction
// only, which is what every nav module here uses it for (finding future
// relative nodes / phase windows, not powered-flight trajectories).
FUNCTION aoso_orbit_position_at {
    PARAMETER orbitable.
    PARAMETER ut.
    RETURN POSITIONAT(orbitable, ut) - POSITIONAT(orbitable:BODY, ut).
}

// Body-relative orbital velocity at an arbitrary time. VELOCITYAT(...):ORBIT
// is already expressed relative to the orbited body's non-rotating frame
// (mirroring SHIP:VELOCITY:ORBIT), so no further subtraction is needed.
FUNCTION aoso_orbit_velocity_at {
    PARAMETER orbitable.
    PARAMETER ut.
    RETURN VELOCITYAT(orbitable, ut):ORBIT.
}

// Unit vector perpendicular to an orbit's plane "now", matching the
// long-standing kOS community convention (VCRS(position, velocity)) used for
// aligning with a maneuver node's NORMAL direction.
FUNCTION aoso_orbit_normal_now {
    PARAMETER orbitable IS SHIP.
    RETURN VCRS(aoso_orbit_position_now(orbitable), orbitable:VELOCITY:ORBIT):NORMALIZED.
}

FUNCTION aoso_orbit_normal_at {
    PARAMETER orbitable.
    PARAMETER ut.
    RETURN VCRS(aoso_orbit_position_at(orbitable, ut), aoso_orbit_velocity_at(orbitable, ut)):NORMALIZED.
}

// Angle (deg, 0-180) between two orbital planes "now". Unlike comparing
// ORBIT:INCLINATION values directly (only valid when both orbits share the
// same longitude of ascending node), this is correct for any two orbits.
FUNCTION aoso_orbit_relative_inclination_deg {
    PARAMETER orbitable_a IS SHIP.
    PARAMETER orbitable_b.
    RETURN VANG(aoso_orbit_normal_now(orbitable_a), aoso_orbit_normal_now(orbitable_b)).
}

// Vis-viva speed (m/s) an orbitable would have at body-centered radius r if
// it kept its current semi-major axis. Used by hohmann.ks/rendezvous.ks
// instead of duplicating the vis-viva formula per call site.
FUNCTION aoso_orbit_speed_at_radius {
    PARAMETER orbitable IS SHIP.
    PARAMETER r.
    LOCAL mu IS orbitable:BODY:MU.
    LOCAL sma IS orbitable:ORBIT:SEMIMAJORAXIS.
    RETURN SQRT(MAX(0, mu * (2 / r - 1 / sma))).
}

FUNCTION aoso_orbit_is_hyperbolic {
    PARAMETER orbitable IS SHIP.
    RETURN orbitable:ORBIT:ECCENTRICITY >= 1.
}

// Seconds until this orbit's next SOI transition, or -1 if none is patched.
FUNCTION aoso_orbit_time_to_soi_change {
    PARAMETER orbitable IS SHIP.
    IF orbitable:ORBIT:HASNEXTPATCH { RETURN orbitable:ORBIT:NEXTPATCHETA. }
    RETURN -1.
}

// Finds up to two upcoming times (seconds from now) at which orbitable_a
// crosses the orbital plane of orbitable_b -- i.e. the relative ascending
// and descending nodes -- within one period of orbitable_a. Rather than
// solving Kepler's equation for an analytic true-anomaly-of-node (fragile to
// get right without in-game verification), this samples the predicted
// position against the target plane's normal and bisects any sign change,
// which is robust for any (including highly eccentric) orbit shape.
FUNCTION aoso_orbit_relative_node_etas {
    PARAMETER orbitable_a IS SHIP.
    PARAMETER orbitable_b.
    PARAMETER samples IS 360.

    LOCAL nb IS aoso_orbit_normal_now(orbitable_b).
    LOCAL period IS orbitable_a:ORBIT:PERIOD.
    LOCAL now IS TIME:SECONDS.
    LOCAL dt IS period / samples.

    LOCAL etas IS LIST().
    LOCAL prev_t IS 0.
    LOCAL prev_val IS VDOT(aoso_orbit_position_at(orbitable_a, now), nb).

    LOCAL i IS 1.
    UNTIL i > samples OR etas:LENGTH >= 2 {
        LOCAL t IS i * dt.
        LOCAL val IS VDOT(aoso_orbit_position_at(orbitable_a, now + t), nb).

        IF (val >= 0 AND prev_val < 0) OR (val < 0 AND prev_val >= 0) {
            LOCAL lo IS prev_t.
            LOCAL hi IS t.
            LOCAL lo_val IS prev_val.
            LOCAL iter IS 0.
            UNTIL iter >= 20 {
                LOCAL mid IS (lo + hi) / 2.
                LOCAL mid_val IS VDOT(aoso_orbit_position_at(orbitable_a, now + mid), nb).
                IF (mid_val >= 0 AND lo_val < 0) OR (mid_val < 0 AND lo_val >= 0) {
                    SET hi TO mid.
                } ELSE {
                    SET lo TO mid.
                    SET lo_val TO mid_val.
                }
                SET iter TO iter + 1.
            }
            etas:ADD((lo + hi) / 2).
        }

        SET prev_t TO t.
        SET prev_val TO val.
        SET i TO i + 1.
    }
    RETURN etas.
}
