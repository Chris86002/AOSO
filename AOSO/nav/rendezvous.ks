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

    LOCAL ship_period IS aoso_orbit_period_s().
    LOCAL tgt_period IS aoso_orbit_period_s(target_orbitable).
    IF ship_period <= 0 { RETURN -1. }
    IF tgt_period <= 0 { RETURN -1. }
    LOCAL ship_rate IS 360 / ship_period.
    LOCAL target_rate IS 360 / tgt_period.
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
        IF node_wait < 30 { SET node_wait TO node_wait + MAX(60, aoso_orbit_period_s()). }
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
        LOCAL period IS aoso_orbit_period_s().
        IF period < 60 { SET period TO 60. }
        UNTIL node_wait >= need_s {
            SET node_wait TO node_wait + period.
        }
    }

    LOCAL nd IS NODE(TIME:SECONDS + node_wait, 0, 0, dv).
    ADD nd.
    aoso_planechange_apply_to_node(nd, target_orbitable).

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
        aoso_rendezvous_tune_pe(nd, target_orbitable).
        LOCAL pe_txt IS "".
        IF nd:ORBIT:HASNEXTPATCH {
            SET pe_txt TO " patchPE=" + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, target_orbitable), 0) + " m".
        }
        aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").
    } ELSE {
        aoso_log_warn("RENDEZVOUS", "No patched encounter found; flying Hohmann dv=" + ROUND(nd:PROGRADE, 1) + " m/s in " + ROUND(nd:ETA, 0) + "s anyway.").
    }
    RETURN nd.
}

// Parking-like periapsis we want at the hop body so capture is cheap
// (not a SOI-graze). Matches goto parking without calling goto at load.
FUNCTION aoso_rendezvous_desired_pe {
    PARAMETER hop.
    IF hop:ATM:EXISTS {
        LOCAL pe_atm IS hop:ATM:HEIGHT + 15000.
        IF pe_atm < 80000 { SET pe_atm TO 80000. }
        RETURN pe_atm.
    }
    LOCAL pe_air IS hop:RADIUS * 0.08.
    IF pe_air < 15000 { SET pe_air TO 15000. }
    RETURN pe_air.
}

FUNCTION aoso_rendezvous_soi_alt {
    PARAMETER hop.
    LOCAL soi_a IS hop:SOIRADIUS - hop:RADIUS.
    IF soi_a < 2000 { SET soi_a TO 2000. }
    RETURN soi_a.
}

// Walk patched conics from an orbit until hop, return that patch PE
// altitude, or -1 if no encounter.
FUNCTION aoso_rendezvous_orbit_pe {
    PARAMETER orb.
    PARAMETER hop.
    LOCAL cur IS orb.
    LOCAL n IS 0.
    UNTIL n >= 5 {
        IF NOT cur:HASNEXTPATCH { RETURN -1. }
        SET cur TO cur:NEXTPATCH.
        IF cur:BODY:NAME = hop:NAME { RETURN cur:PERIAPSIS. }
        SET n TO n + 1.
    }
    RETURN -1.
}

FUNCTION aoso_rendezvous_pe_min {
    PARAMETER hop.
    PARAMETER desired_pe.
    LOCAL min_pe IS desired_pe * 0.45.
    IF hop:ATM:EXISTS {
        LOCAL floor_pe IS hop:ATM:HEIGHT + 8000.
        IF min_pe < floor_pe { SET min_pe TO floor_pe. }
    } ELSE {
        IF min_pe < 3000 { SET min_pe TO 3000. }
    }
    RETURN min_pe.
}

// Lower is better. Miss / lithobrake / SOI-graze are huge.
FUNCTION aoso_rendezvous_pe_score {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER desired_pe.
    LOCAL pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    IF pe < -0.5 { RETURN 1000000000000. }
    LOCAL min_pe IS aoso_rendezvous_pe_min(hop, desired_pe).
    IF pe < min_pe { RETURN 5000000000 + (min_pe - pe). }
    LOCAL graze IS aoso_rendezvous_soi_alt(hop) * 0.35.
    IF pe > graze { RETURN 100000000 + (pe - desired_pe). }
    RETURN ABS(pe - desired_pe).
}

FUNCTION aoso_rendezvous_pe_ok_value {
    PARAMETER pe.
    PARAMETER hop.
    IF pe < -0.5 { RETURN FALSE. }
    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL min_pe IS aoso_rendezvous_pe_min(hop, desired).
    IF pe < min_pe { RETURN FALSE. }
    LOCAL graze IS aoso_rendezvous_soi_alt(hop) * 0.35.
    IF pe > graze { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_rendezvous_orbit_needs_correct {
    PARAMETER orb.
    PARAMETER hop.
    IF aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(orb, hop), hop) { RETURN FALSE. }
    RETURN TRUE.
}

// ElWanderer-style hill climb on ETA / prograde / radial / normal so the
// patched PE is a capture altitude, not a SOI clip. RSVP/MechJeb do this
// after the Hohmann guess; we stay on stock NODE suffixes.
FUNCTION aoso_rendezvous_tune_pe {
    PARAMETER nd.
    PARAMETER hop.
    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL best IS aoso_rendezvous_pe_score(nd, hop, desired).
    IF best < desired * 0.35 { RETURN TRUE. }

    LOCAL step_t IS 240.
    LOCAL step_dv IS 20.
    LOCAL rounds IS 0.
    UNTIL rounds >= 7 {
        LOCAL improved IS FALSE.

        LOCAL orig_eta IS nd:ETA.
        SET nd:ETA TO orig_eta + step_t.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        LOCAL s IS aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:ETA TO orig_eta - step_t.
            IF nd:ETA < 25 {
                SET nd:ETA TO orig_eta.
            } ELSE {
                SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
                IF s < best {
                    SET best TO s.
                    SET improved TO TRUE.
                } ELSE {
                    SET nd:ETA TO orig_eta.
                }
            }
        }

        LOCAL orig_pg IS nd:PROGRADE.
        SET nd:PROGRADE TO orig_pg + step_dv.
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:PROGRADE TO orig_pg - step_dv.
            SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
            IF s < best {
                SET best TO s.
                SET improved TO TRUE.
            } ELSE {
                SET nd:PROGRADE TO orig_pg.
            }
        }

        LOCAL orig_rad IS nd:RADIALOUT.
        SET nd:RADIALOUT TO orig_rad + step_dv.
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:RADIALOUT TO orig_rad - step_dv.
            SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
            IF s < best {
                SET best TO s.
                SET improved TO TRUE.
            } ELSE {
                SET nd:RADIALOUT TO orig_rad.
            }
        }

        LOCAL orig_n IS nd:NORMAL.
        SET nd:NORMAL TO orig_n + step_dv.
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:NORMAL TO orig_n - step_dv.
            SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
            IF s < best {
                SET best TO s.
                SET improved TO TRUE.
            } ELSE {
                SET nd:NORMAL TO orig_n.
            }
        }

        IF best < desired * 0.5 { RETURN TRUE. }
        IF NOT improved {
            SET step_t TO step_t * 0.5.
            SET step_dv TO step_dv * 0.5.
            IF step_dv < 0.3 { RETURN aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), hop). }
        }
        SET rounds TO rounds + 1.
    }
    LOCAL pe_now IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    aoso_log_info("RENDEZVOUS", "Tuned intercept PE to " + ROUND(pe_now, 0) + "m target=" + ROUND(desired, 0) + "m.").
    RETURN aoso_rendezvous_pe_ok_value(pe_now, hop).
}

// Mid-course while already on a patch whose PE is a graze / lithobrake.
FUNCTION aoso_rendezvous_add_correction_node {
    PARAMETER hop.
    IF NOT SHIP:ORBIT:HASNEXTPATCH { RETURN 0. }
    LOCAL pe_now IS aoso_rendezvous_orbit_pe(SHIP:ORBIT, hop).
    IF aoso_rendezvous_pe_ok_value(pe_now, hop) { RETURN 0. }

    LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
    IF eta_p < 150 { RETURN 0. }
    LOCAL t_corr IS eta_p * 0.3.
    IF t_corr > eta_p - 180 { SET t_corr TO eta_p - 180. }
    IF t_corr < 45 { SET t_corr TO 45. }

    LOCAL nd IS NODE(TIME:SECONDS + t_corr, 0, 0, 0).
    ADD nd.
    aoso_rendezvous_tune_pe(nd, hop).
    IF nd:DELTAV:MAG < 0.8 {
        REMOVE nd.
        RETURN 0.
    }
    aoso_log_info("RENDEZVOUS", "Mid-course correction dv=" + ROUND(nd:DELTAV:MAG, 1) + " m/s, PE " + ROUND(pe_now, 0) + " -> " + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), 0) + "m.").
    RETURN nd.
}
