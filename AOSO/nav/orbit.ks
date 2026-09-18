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
    PARAMETER orbitable_a.
    PARAMETER orbitable_b.
    RETURN VANG(aoso_orbit_normal_now(orbitable_a), aoso_orbit_normal_now(orbitable_b)).
}

// Angle (deg, 0-180) between two Orbit structures using inclination + LAN.
// NODE:ORBIT after a trial burn is the ground truth for "did this normal
// actually close the plane?" - VCRS vs kOS NODE:NORMAL disagree in sign
// (KSP's orbit normal is v cross r; VCRS(r,v) is r cross v), which is why
// the Minmus 6 deg burn went to 12 deg.
FUNCTION aoso_orbit_rel_inc_from_orbit {
    PARAMETER orb.
    PARAMETER other.
    LOCAL i1 IS orb:INCLINATION.
    LOCAL lan1 IS orb:LAN.
    LOCAL i2 IS other:ORBIT:INCLINATION.
    LOCAL lan2 IS other:ORBIT:LAN.
    LOCAL ci IS COS(i1) * COS(i2) + SIN(i1) * SIN(i2) * COS(lan1 - lan2).
    IF ci > 1 { SET ci TO 1. }
    IF ci < -1 { SET ci TO -1. }
    RETURN ARCCOS(ci).
}

// Circular orbital speed SQRT(mu/r). Separate from vis-viva so a circularize
// burn can ask for the target speed without inventing a new SMA.
FUNCTION aoso_orbit_circular_speed {
    PARAMETER mu.
    PARAMETER radius.
    IF radius <= 0 { RETURN 0. }
    RETURN SQRT(mu / radius).
}

// Vis-viva speed at body-centered radius for a given semi-major axis.
FUNCTION aoso_orbit_vis_viva {
    PARAMETER mu.
    PARAMETER radius.
    PARAMETER sma.
    RETURN SQRT(MAX(0, mu * (2 / radius - 1 / sma))).
}

// Vis-viva speed (m/s) an orbitable would have at body-centered radius r if
// it kept its current semi-major axis. Used by hohmann.ks/rendezvous.ks
// instead of duplicating the vis-viva formula per call site.
FUNCTION aoso_orbit_speed_at_radius {
    PARAMETER orbitable.
    PARAMETER radius.
    RETURN aoso_orbit_vis_viva(orbitable:BODY:MU, radius, orbitable:ORBIT:SEMIMAJORAXIS).
}

FUNCTION aoso_orbit_is_hyperbolic {
    PARAMETER orbitable IS SHIP.
    RETURN orbitable:ORBIT:ECCENTRICITY >= 1.
}

// kOS returns Infinity for PERIOD / APOAPSIS / ETA:APOAPSIS on a hyperbola
// (ESCAPING). Pushing Infinity onto the stack crashes the CPU. These
// helpers return 0 instead so a SOI capture can re-profile.
FUNCTION aoso_orbit_period_s {
    PARAMETER orbitable IS SHIP.
    IF orbitable:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    LOCAL p IS orbitable:ORBIT:PERIOD.
    IF p <= 0 { RETURN 0. }
    RETURN p.
}

FUNCTION aoso_orbit_apoapsis_alt {
    PARAMETER orbitable IS SHIP.
    IF orbitable:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    RETURN orbitable:ORBIT:APOAPSIS.
}

FUNCTION aoso_orbit_eta_apoapsis {
    IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN 0. }
    RETURN ETA:APOAPSIS.
}

// Finds up to two upcoming times (seconds from now) at which orbitable_a
// crosses the orbital plane of orbitable_b -- i.e. the relative ascending
// and descending nodes -- within two periods of orbitable_a. Rather than
// solving Kepler's equation for an analytic true-anomaly-of-node (fragile to
// get right without in-game verification), this samples the predicted
// position against the target plane's normal and bisects any sign change,
// which is robust for any (including highly eccentric) orbit shape.
FUNCTION aoso_orbit_relative_node_etas {
    PARAMETER orbitable_a.
    PARAMETER orbitable_b.
    PARAMETER samples IS 360.

    LOCAL nb IS aoso_orbit_normal_now(orbitable_b).
    LOCAL period IS aoso_orbit_period_s(orbitable_a).
    IF period <= 0 { RETURN LIST(). }
    LOCAL now IS TIME:SECONDS.
    LOCAL dt IS period / samples.
    LOCAL n_samples IS samples * 2.

    LOCAL etas IS LIST().
    LOCAL prev_t IS 0.
    LOCAL prev_val IS VDOT(aoso_orbit_position_at(orbitable_a, now), nb).

    LOCAL i IS 1.
    UNTIL i > n_samples OR etas:LENGTH >= 2 {
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

// Near-circular fallback when the sample bisection misses the relative
// node. Returns AN and DN from LAN difference as seconds-from-now.
FUNCTION aoso_orbit_lan_node_etas {
    PARAMETER target_orbitable.
    LOCAL period IS aoso_orbit_period_s().
    IF period <= 0 { RETURN LIST(). }
    LOCAL ta_an IS target_orbitable:ORBIT:LAN - SHIP:ORBIT:LAN - SHIP:ORBIT:ARGUMENTOFPERIAPSIS.
    LOCAL dta IS ta_an - SHIP:ORBIT:TRUEANOMALY.
    UNTIL dta >= 8 {
        SET dta TO dta + 360.
    }
    UNTIL dta < 368 {
        SET dta TO dta - 360.
    }
    LOCAL out IS LIST().
    LOCAL eta_an IS period * dta / 360.
    IF eta_an > 20 { out:ADD(eta_an). }
    LOCAL dta_dn IS dta + 180.
    UNTIL dta_dn >= 8 {
        SET dta_dn TO dta_dn + 360.
    }
    UNTIL dta_dn < 368 {
        SET dta_dn TO dta_dn - 360.
    }
    LOCAL eta_dn IS period * dta_dn / 360.
    IF eta_dn > 20 { out:ADD(eta_dn). }
    RETURN out.
}

// Upcoming times (seconds from now) at which orbitable crosses the body's
// equatorial plane -- the AN/DN used for polar or equatorial plane changes.
// Same bisection as aoso_orbit_relative_node_etas, but the reference normal
// is BODY:ANGULARVEL instead of another orbitable.
FUNCTION aoso_orbit_equatorial_node_etas {
    PARAMETER orbitable IS SHIP.
    PARAMETER samples IS 360.

    LOCAL nb IS orbitable:BODY:ANGULARVEL:NORMALIZED.
    LOCAL period IS aoso_orbit_period_s(orbitable).
    IF period <= 0 { RETURN LIST(). }
    LOCAL now IS TIME:SECONDS.
    LOCAL dt IS period / samples.

    LOCAL etas IS LIST().
    LOCAL prev_t IS 0.
    LOCAL prev_val IS VDOT(aoso_orbit_position_at(orbitable, now), nb).

    LOCAL i IS 1.
    UNTIL i > samples OR etas:LENGTH >= 2 {
        LOCAL t IS i * dt.
        LOCAL val IS VDOT(aoso_orbit_position_at(orbitable, now + t), nb).

        IF (val >= 0 AND prev_val < 0) OR (val < 0 AND prev_val >= 0) {
            LOCAL lo IS prev_t.
            LOCAL hi IS t.
            LOCAL lo_val IS prev_val.
            LOCAL iter IS 0.
            UNTIL iter >= 20 {
                LOCAL mid IS (lo + hi) / 2.
                LOCAL mid_val IS VDOT(aoso_orbit_position_at(orbitable, now + mid), nb).
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
