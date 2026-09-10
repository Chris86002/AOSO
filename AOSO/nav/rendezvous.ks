// AOSO/nav/rendezvous.ks
// Phasing/transfer-window math for closing with a targeted vessel: current
// vs. required phase angle, wait time until the transfer window opens, and
// a prograde transfer node timed to that window. Assumes near-circular
// orbits for the target-radius/transfer-time estimates, consistent with the
// same simplification vehicle/capabilities.ks makes for single-stage dV
// (a full arbitrary-eccentricity solver is out of scope here). Precision
// final-approach/docking burns are handled by advanced/docking.ks (Phase
// 11) once this has closed the gap; this file only covers the "get into
// the same orbit, near the target" nav problem.

FUNCTION aoso_rendezvous_available {
    RETURN HASTARGET.
}

// TARGET:POSITION (and any orbitable's :POSITION) is already relative to the
// active vessel, so no subtraction is needed to get ship-relative position.
FUNCTION aoso_rendezvous_relative_position {
    PARAMETER target_orbitable IS TARGET.
    RETURN target_orbitable:POSITION.
}

FUNCTION aoso_rendezvous_distance {
    PARAMETER target_orbitable IS TARGET.
    RETURN aoso_rendezvous_relative_position(target_orbitable):MAG.
}

FUNCTION aoso_rendezvous_relative_speed {
    PARAMETER target_orbitable IS TARGET.
    RETURN (target_orbitable:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT):MAG.
}

// Signed phase angle (deg) from ship to target around the body, positive
// when the target is ahead of the ship in the direction of the ship's
// orbital motion.
FUNCTION aoso_rendezvous_phase_angle_deg {
    PARAMETER target_orbitable IS TARGET.
    LOCAL pos_ship IS aoso_orbit_position_now(SHIP).
    LOCAL pos_target IS aoso_orbit_position_now(target_orbitable).
    LOCAL ang IS VANG(pos_ship, pos_target).
    LOCAL na IS aoso_orbit_normal_now(SHIP).
    IF VDOT(VCRS(pos_ship, pos_target), na) < 0 { SET ang TO -ang. }
    RETURN ang.
}

// Classic Hohmann phase-angle-at-departure formula: how far ahead the
// target needs to be (deg) right now for a transfer burn today to arrive
// where the target will have coasted to.
FUNCTION aoso_rendezvous_required_phase_angle_deg {
    PARAMETER target_orbitable IS TARGET.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r1 IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL r2 IS target_orbitable:ORBIT:SEMIMAJORAXIS.
    LOCAL sma_t IS (r1 + r2) / 2.
    LOCAL transfer_time IS CONSTANT:PI * SQRT(sma_t ^ 3 / mu).
    LOCAL target_travel_deg IS 360 * transfer_time / target_orbitable:ORBIT:PERIOD.
    RETURN 180 - target_travel_deg.
}

// Seconds to wait until the current phase angle reaches the required
// transfer-window phase angle. Returns -1 if ship and target orbital periods
// are equal (phase angle never changes, so a transfer window never arrives
// without first changing altitude).
FUNCTION aoso_rendezvous_wait_time_to_transfer_s {
    PARAMETER target_orbitable IS TARGET.
    LOCAL current_phase IS aoso_rendezvous_phase_angle_deg(target_orbitable).
    LOCAL required_phase IS aoso_rendezvous_required_phase_angle_deg(target_orbitable).

    LOCAL ship_rate IS 360 / SHIP:ORBIT:PERIOD.
    LOCAL target_rate IS 360 / target_orbitable:ORBIT:PERIOD.
    LOCAL relative_rate IS ship_rate - target_rate.
    IF relative_rate = 0 { RETURN -1. }

    LOCAL wait_s IS -(current_phase - required_phase) / relative_rate.
    UNTIL wait_s >= 0 {
        SET wait_s TO wait_s + (360 / ABS(relative_rate)).
    }
    RETURN wait_s.
}

// Adds a prograde transfer node timed to the next transfer window, sized to
// raise/lower the ship onto a Hohmann transfer ellipse meeting the target's
// (assumed near-circular) altitude. Then walks the node time (and a small
// dv bump) until patched conics actually show an encounter with the hop
// body — the raw Hohmann phase is not enough once the burn is late or the
// ship is already on a steep ellipse (Acacius missed Mun and sat in
// 12061x100 km for 24 h). Returns 0 if no window can be computed.
FUNCTION aoso_rendezvous_node_hits_body {
    PARAMETER nd.
    PARAMETER hop.
    IF NOT nd:ORBIT:HASNEXTPATCH { RETURN FALSE. }
    RETURN nd:ORBIT:NEXTPATCH:BODY:NAME = hop:NAME.
}

FUNCTION aoso_rendezvous_seek_encounter {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER step_s IS 40.
    PARAMETER max_steps IS 48.

    IF aoso_rendezvous_node_hits_body(nd, hop) { RETURN TRUE. }

    LOCAL t0 IS TIME:SECONDS + nd:ETA.
    LOCAL i IS 0.
    UNTIL i >= max_steps {
        SET nd:ETA TO (t0 - TIME:SECONDS) + (i * step_s).
        IF aoso_rendezvous_node_hits_body(nd, hop) { RETURN TRUE. }
        SET i TO i + 1.
    }
    SET nd:ETA TO t0 - TIME:SECONDS.
    RETURN FALSE.
}

FUNCTION aoso_rendezvous_add_phasing_transfer_node {
    PARAMETER target_orbitable IS TARGET.

    SET TARGET TO target_orbitable.

    IF SHIP:ORBIT:HASNEXTPATCH {
        IF SHIP:ORBIT:NEXTPATCH:BODY:NAME = target_orbitable:NAME {
            aoso_log_info("RENDEZVOUS", "Already on a patch to " + target_orbitable:NAME + " - no burn.").
            RETURN 0.
        }
    }

    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r2 IS target_orbitable:ORBIT:SEMIMAJORAXIS.
    LOCAL target_alt IS r2 - SHIP:BODY:RADIUS.
    LOCAL r1 IS SHIP:BODY:RADIUS + ALTITUDE.
    LOCAL node_wait IS 0.
    LOCAL already IS FALSE.
    IF APOAPSIS > target_alt * 0.75 {
        IF APOAPSIS < target_alt * 1.5 { SET already TO TRUE. }
    }

    IF already {
        SET r1 TO SHIP:BODY:RADIUS + MAX(PERIAPSIS, 1000).
        SET node_wait TO ETA:PERIAPSIS.
        IF node_wait < 30 { SET node_wait TO node_wait + SHIP:ORBIT:PERIOD. }
        aoso_log_info("RENDEZVOUS", "Already near " + target_orbitable:NAME + " altitude (AP=" + ROUND(APOAPSIS, 0) + " m) - correcting at periapsis instead of a new Hohmann.").
    } ELSE {
        LOCAL wait_s IS aoso_rendezvous_wait_time_to_transfer_s(target_orbitable).
        IF wait_s < 0 {
            aoso_log_warn("RENDEZVOUS", "Ship and target periods match; no transfer window exists.").
            RETURN 0.
        }
        SET node_wait TO wait_s.
    }

    LOCAL sma_t IS (r1 + r2) / 2.
    LOCAL v_now IS aoso_orbit_speed_at_radius(SHIP, r1).
    LOCAL v_transfer IS SQRT(MAX(0, mu * (2 / r1 - 1 / sma_t))).
    LOCAL dv IS v_transfer - v_now.

    LOCAL align_s IS aoso_maneuver_align_s().
    LOCAL burn_time IS aoso_perf_burn_time_for_dv(ABS(dv)).
    LOCAL need_s IS (burn_time / 2) + align_s + 15.
    IF node_wait < need_s {
        LOCAL period IS SHIP:ORBIT:PERIOD.
        IF period < 60 { SET period TO 60. }
        UNTIL node_wait >= need_s {
            SET node_wait TO node_wait + period.
        }
    }

    LOCAL nd IS NODE(TIME:SECONDS + node_wait, 0, 0, dv).
    ADD nd.

    LOCAL hit IS aoso_rendezvous_seek_encounter(nd, target_orbitable, 40, 48).
    IF NOT hit {
        SET nd:PROGRADE TO nd:PROGRADE * 1.08.
        SET hit TO aoso_rendezvous_seek_encounter(nd, target_orbitable, 40, 48).
    }
    IF NOT hit {
        SET nd:PROGRADE TO dv.
        SET nd:ETA TO node_wait.
        SET nd:PROGRADE TO nd:PROGRADE * 1.15.
        SET hit TO aoso_rendezvous_seek_encounter(nd, target_orbitable, 30, 60).
    }
    IF already {
        IF NOT hit {
            LOCAL dv_try IS -80.
            UNTIL hit OR dv_try > 160 {
                SET nd:PROGRADE TO dv_try.
                SET nd:ETA TO node_wait.
                SET hit TO aoso_rendezvous_seek_encounter(nd, target_orbitable, 80, 24).
                SET dv_try TO dv_try + 40.
            }
        }
    }

    IF hit {
        LOCAL pe_txt IS "".
        IF nd:ORBIT:HASNEXTPATCH {
            SET pe_txt TO " patchPE=" + ROUND(nd:ORBIT:NEXTPATCH:PERIAPSIS, 0) + " m".
        }
        aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").
    } ELSE {
        aoso_log_warn("RENDEZVOUS", "No patched encounter found; flying Hohmann dv=" + ROUND(nd:PROGRADE, 1) + " m/s in " + ROUND(nd:ETA, 0) + "s anyway.").
    }
    RETURN nd.
}
