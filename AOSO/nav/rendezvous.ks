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
    LOCAL cur IS nd:ORBIT.
    LOCAL n IS 0.
    UNTIL n >= 4 {
        IF NOT cur:HASNEXTPATCH { RETURN FALSE. }
        SET cur TO cur:NEXTPATCH.
        IF cur:BODY:NAME = hop:NAME { RETURN TRUE. }
        SET n TO n + 1.
    }
    RETURN FALSE.
}

FUNCTION aoso_rendezvous_ship_hits_body {
    PARAMETER hop.
    LOCAL cur IS SHIP:ORBIT.
    LOCAL n IS 0.
    UNTIL n >= 4 {
        IF NOT cur:HASNEXTPATCH { RETURN FALSE. }
        SET cur TO cur:NEXTPATCH.
        IF cur:BODY:NAME = hop:NAME { RETURN TRUE. }
        SET n TO n + 1.
    }
    RETURN FALSE.
}

FUNCTION aoso_rendezvous_escape_dv {
    PARAMETER radius.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL v_now IS aoso_orbit_speed_at_radius(SHIP, radius).
    LOCAL v_esc IS SQRT(MAX(1, 2 * mu / radius)).
    RETURN v_esc - v_now.
}

FUNCTION aoso_rendezvous_dv_max {
    PARAMETER radius.
    LOCAL dv_esc IS aoso_rendezvous_escape_dv(radius).
    LOCAL dv_max IS dv_esc * 0.98.
    IF dv_max < 10 { SET dv_max TO 10. }
    RETURN dv_max.
}

// Walk departure time around the Hohmann window. kOS patched conics on a
// NODE do not update until the next physics tick, so every trial does
// WAIT 0. Never bump dV past 98% of escape - Acacius's 1.15x Minmus
// Hohmann was 1045 m/s vs Kerbin escape ~941 and dumped the ship on a
// solar hyperbola. A real Minmus Hohmann is ~920, just under escape, so
// 0.90 was too tight.
FUNCTION aoso_rendezvous_search_intercept {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER dv0.

    LOCAL radius IS SHIP:BODY:RADIUS + (APOAPSIS + PERIAPSIS) / 2.
    IF radius < SHIP:BODY:RADIUS + 1000 { SET radius TO SHIP:BODY:RADIUS + ALTITUDE. }
    LOCAL dv_max IS aoso_rendezvous_dv_max(radius).
    LOCAL dv_use IS dv0.
    IF dv_use > dv_max { SET dv_use TO dv_max. }

    WAIT 0.
    IF aoso_rendezvous_node_hits_body(nd, hop) { RETURN TRUE. }

    LOCAL period IS aoso_orbit_period_s().
    IF period < 80 { SET period TO 600. }
    LOCAL t_center IS TIME:SECONDS + nd:ETA.
    LOCAL t_lo IS t_center - period.
    IF t_lo < TIME:SECONDS + 40 { SET t_lo TO TIME:SECONDS + 40. }
    LOCAL t_hi IS t_center + period.

    LOCAL scales IS LIST(1, 0.99, 1.01).
    LOCAL si IS 0.
    UNTIL si >= scales:LENGTH {
        LOCAL dv_try IS dv_use * scales[si].
        IF dv_try > dv_max { SET dv_try TO dv_max. }
        SET nd:PROGRADE TO dv_try.
        LOCAL t_ut IS t_lo.
        LOCAL step_s IS 20.
        IF si > 0 { SET step_s TO 35. }
        UNTIL t_ut > t_hi {
            SET nd:ETA TO t_ut - TIME:SECONDS.
            IF nd:ETA < 25 { SET nd:ETA TO 25. }
            WAIT 0.
            IF aoso_rendezvous_node_hits_body(nd, hop) { RETURN TRUE. }
            SET t_ut TO t_ut + step_s.
        }
        SET si TO si + 1.
    }
    SET nd:PROGRADE TO dv_use.
    SET nd:ETA TO t_center - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
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
    LOCAL r1 IS SHIP:BODY:RADIUS + (APOAPSIS + PERIAPSIS) / 2.
    IF r1 < SHIP:BODY:RADIUS + 1000 { SET r1 TO SHIP:BODY:RADIUS + ALTITUDE. }
    LOCAL node_wait IS 0.
    LOCAL already IS FALSE.
    IF SHIP:ORBIT:ECCENTRICITY < 1 {
        IF APOAPSIS > target_alt * 0.75 {
            IF APOAPSIS < target_alt * 1.5 { SET already TO TRUE. }
        }
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

    LOCAL dv_max IS aoso_rendezvous_dv_max(r1).
    LOCAL dv_esc IS aoso_rendezvous_escape_dv(r1).
    IF dv > dv_max {
        aoso_log_warn("RENDEZVOUS", "Hohmann dv " + ROUND(dv, 1) + " m/s exceeds 98% of escape " + ROUND(dv_esc, 1) + " - clamping to " + ROUND(dv_max, 1) + ".").
        SET dv TO dv_max.
    }
    IF dv < 5 { SET dv TO 5. }

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
    aoso_log_info("RENDEZVOUS", "Searching " + target_orbitable:NAME + " intercept at Hohmann dv=" + ROUND(dv, 1) + " m/s (escape " + ROUND(dv_esc, 1) + ") in " + ROUND(node_wait, 0) + "s.").

    LOCAL hit IS aoso_rendezvous_search_intercept(nd, target_orbitable, dv).
    IF already {
        IF NOT hit {
            LOCAL dv_try IS -80.
            UNTIL hit OR dv_try > 160 {
                SET nd:PROGRADE TO dv_try.
                SET nd:ETA TO node_wait.
                SET hit TO aoso_rendezvous_search_intercept(nd, target_orbitable, dv_try).
                SET dv_try TO dv_try + 40.
            }
        }
    }

    IF hit {
        aoso_planechange_apply_to_node(nd, target_orbitable).
        WAIT 0.
        IF NOT aoso_rendezvous_node_hits_body(nd, target_orbitable) {
            aoso_log_warn("RENDEZVOUS", "Plane-change fold lost the " + target_orbitable:NAME + " patch - restoring prograde-only intercept.").
            SET nd:NORMAL TO 0.
            SET nd:RADIALOUT TO 0.
            WAIT 0.
        }
        aoso_rendezvous_tune_pe(nd, target_orbitable).
        LOCAL pe_txt IS "".
        IF nd:ORBIT:HASNEXTPATCH {
            SET pe_txt TO " patchPE=" + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, target_orbitable), 0) + " m".
        }
        aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").
        RETURN nd.
    }

    aoso_log_warn("RENDEZVOUS", "No patched encounter this window - not burning a blind Hohmann (that escaped Kerbin last time). Will retry next orbit.").
    REMOVE nd.
    RETURN 0.
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

FUNCTION aoso_rendezvous_clamp_prograde {
    PARAMETER nd.
    LOCAL radius IS SHIP:BODY:RADIUS + (APOAPSIS + PERIAPSIS) / 2.
    IF radius < SHIP:BODY:RADIUS + 1000 { SET radius TO SHIP:BODY:RADIUS + ALTITUDE. }
    LOCAL dv_max IS aoso_rendezvous_dv_max(radius).
    IF nd:PROGRADE > dv_max { SET nd:PROGRADE TO dv_max. }
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
        WAIT 0.
        LOCAL s IS aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:ETA TO orig_eta - step_t.
            IF nd:ETA < 25 {
                SET nd:ETA TO orig_eta.
            } ELSE {
                WAIT 0.
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
        aoso_rendezvous_clamp_prograde(nd).
        WAIT 0.
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:PROGRADE TO orig_pg - step_dv.
            WAIT 0.
            SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
            IF s < best {
                SET best TO s.
                SET improved TO TRUE.
            } ELSE {
                SET nd:PROGRADE TO orig_pg.
            }
        }
        aoso_rendezvous_clamp_prograde(nd).

        LOCAL orig_rad IS nd:RADIALOUT.
        SET nd:RADIALOUT TO orig_rad + step_dv.
        WAIT 0.
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:RADIALOUT TO orig_rad - step_dv.
            WAIT 0.
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
        WAIT 0.
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:NORMAL TO orig_n - step_dv.
            WAIT 0.
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
