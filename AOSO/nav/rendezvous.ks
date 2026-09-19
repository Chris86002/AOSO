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

FUNCTION aoso_rendezvous_search_step_s {
    PARAMETER hop.
    LOCAL r2 IS hop:ORBIT:SEMIMAJORAXIS.
    LOCAL soi IS hop:SOIRADIUS.
    LOCAL frac IS soi / MAX(1, r2).
    IF frac > 0.999 { SET frac TO 0.999. }
    LOCAL ang IS 2 * ARCSIN(frac).
    LOCAL p_ship IS aoso_orbit_period_s().
    IF p_ship < 80 { SET p_ship TO 600. }
    LOCAL p_hop IS hop:ORBIT:PERIOD.
    IF p_hop < 80 { SET p_hop TO p_ship. }
    LOCAL rel IS ABS((360 / p_ship) - (360 / p_hop)).
    IF rel < 0.002 { RETURN 12. }
    LOCAL win IS ang / rel.
    LOCAL step IS win / 5.
    IF step < 3 { SET step TO 3. }
    IF step > 18 { SET step TO 18. }
    RETURN step.
}

FUNCTION aoso_rendezvous_sample_hit {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER t_ut.
    IF t_ut <= TIME:SECONDS + 25 { RETURN -1. }
    SET nd:ETA TO t_ut - TIME:SECONDS.
    aoso_yield_hud().
    IF NOT aoso_rendezvous_node_hits_body(nd, hop) { RETURN -1. }
    RETURN aoso_rendezvous_pe_score(nd, hop, aoso_rendezvous_desired_pe(hop)).
}

// Keep the *best* patched PE, not the first clip. First-hit at T+219s
// was a 61 km Minmus graze; the Hohmann window (~15 km PE) was later.
// Step size tracks SOI angular width: Minmus's departure window is ~15 s,
// so a 25 s walk skipped the intercept entirely.
FUNCTION aoso_rendezvous_search_intercept {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER dv0.

    LOCAL radius IS SHIP:BODY:RADIUS + (APOAPSIS + PERIAPSIS) / 2.
    IF radius < SHIP:BODY:RADIUS + 1000 { SET radius TO SHIP:BODY:RADIUS + ALTITUDE. }
    LOCAL dv_max IS aoso_rendezvous_dv_max(radius).
    LOCAL dv_use IS dv0.
    IF dv_use > dv_max { SET dv_use TO dv_max. }
    IF dv_use < 0 { SET dv_use TO 0. }

    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL period IS aoso_orbit_period_s().
    IF period < 80 { SET period TO 600. }
    LOCAL t_center IS TIME:SECONDS + nd:ETA.
    LOCAL step_s IS aoso_rendezvous_search_step_s(hop).
    LOCAL fine_span IS 120.
    IF fine_span > period * 0.3 { SET fine_span TO period * 0.3. }
    IF fine_span < step_s * 8 { SET fine_span TO step_s * 8. }
    aoso_log_info("RENDEZVOUS", hop:NAME + " search step=" + ROUND(step_s, 1) + "s fine=±" + ROUND(fine_span, 0) + "s (SOI-sized; 25s used to miss Minmus).").
    aoso_ui_pulse("Searching " + hop:NAME + " intercept", "step " + ROUND(step_s, 0) + "s  Hohmann first").

    LOCAL best_sc IS 1000000000000.
    LOCAL best_ut IS t_center.
    LOCAL best_pg IS dv_use.
    LOCAL found IS FALSE.
    LOCAL n_chk IS 0.

    LOCAL scales IS LIST(1).
    IF ABS(dv_use) >= 8 {
        SET scales TO LIST(1, 0.99, 1.01).
    }
    LOCAL si IS 0.
    UNTIL si >= scales:LENGTH {
        IF found {
            IF best_sc < desired * 1.5 { SET si TO scales:LENGTH. }
        }
        IF si < scales:LENGTH {
            LOCAL dv_try IS dv_use * scales[si].
            IF dv_try > dv_max { SET dv_try TO dv_max. }
            SET nd:PROGRADE TO dv_try.
            LOCAL pass IS 0.
            UNTIL pass >= 2 {
                LOCAL span IS fine_span.
                LOCAL use_step IS step_s.
                IF pass = 1 {
                    SET span TO period.
                    SET use_step TO step_s * 2.
                    IF found { SET pass TO 2. }
                }
                IF pass < 2 {
                    LOCAL delta IS 0.
                    UNTIL delta > span {
                        LOCAL sc IS aoso_rendezvous_sample_hit(nd, hop, t_center + delta).
                        IF sc >= 0 {
                            IF sc < best_sc {
                                SET best_sc TO sc.
                                SET best_ut TO TIME:SECONDS + nd:ETA.
                                SET best_pg TO nd:PROGRADE.
                                SET found TO TRUE.
                            }
                        }
                        SET n_chk TO n_chk + 1.
                        IF delta > 0 {
                            LOCAL sc2 IS aoso_rendezvous_sample_hit(nd, hop, t_center - delta).
                            IF sc2 >= 0 {
                                IF sc2 < best_sc {
                                    SET best_sc TO sc2.
                                    SET best_ut TO TIME:SECONDS + nd:ETA.
                                    SET best_pg TO nd:PROGRADE.
                                    SET found TO TRUE.
                                }
                            }
                            SET n_chk TO n_chk + 1.
                        }
                        SET delta TO delta + use_step.
                        IF n_chk >= 8 {
                            LOCAL pe_txt IS "none yet".
                            IF found { SET pe_txt TO ROUND(best_sc, 0) + " score". }
                            aoso_ui_pulse("Searching " + hop:NAME + " intercept", "window ±" + ROUND(delta, 0) + "s  best " + pe_txt).
                            SET n_chk TO 0.
                        }
                    }
                    SET pass TO pass + 1.
                }
            }
            SET si TO si + 1.
        }
    }

    IF found {
        SET nd:PROGRADE TO best_pg.
        SET nd:ETA TO best_ut - TIME:SECONDS.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_yield_hud().
        aoso_rendezvous_refine_intercept(nd, hop, dv_use).
        RETURN TRUE.
    }
    SET nd:PROGRADE TO dv_use.
    SET nd:ETA TO t_center - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
    RETURN FALSE.
}

// 5 s time walk + small prograde/radial around the coarse hit so PE
// lands at parking (15 km Minmus) instead of the first SOI clip (61 km).
FUNCTION aoso_rendezvous_refine_intercept {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER dv0.

    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL best_sc IS aoso_rendezvous_pe_score(nd, hop, desired).
    LOCAL best_ut IS TIME:SECONDS + nd:ETA.
    LOCAL best_pg IS nd:PROGRADE.
    LOCAL best_rad IS nd:RADIALOUT.
    LOCAL n_ref IS 0.

    LOCAL dt IS -80.
    UNTIL dt > 80 {
        SET nd:ETA TO (best_ut + dt) - TIME:SECONDS.
        IF nd:ETA >= 25 {
            aoso_yield_hud().
            IF aoso_rendezvous_node_hits_body(nd, hop) {
                LOCAL sc IS aoso_rendezvous_pe_score(nd, hop, desired).
                IF sc < best_sc {
                    SET best_sc TO sc.
                    SET best_ut TO TIME:SECONDS + nd:ETA.
                    SET best_pg TO nd:PROGRADE.
                    SET best_rad TO nd:RADIALOUT.
                }
            }
            SET n_ref TO n_ref + 1.
            IF n_ref >= 8 {
                aoso_ui_pulse("Refining " + hop:NAME + " intercept", "PE score " + ROUND(best_sc, 0) + "  want " + ROUND(desired, 0) + "m").
                SET n_ref TO 0.
            }
        }
        SET dt TO dt + 5.
    }

    LOCAL extras IS LIST(-0.03 * ABS(dv0), 0.03 * ABS(dv0), -15, 15, -8, 8).
    LOCAL ei IS 0.
    UNTIL ei >= extras:LENGTH {
        SET nd:PROGRADE TO best_pg + extras[ei].
        aoso_rendezvous_clamp_prograde(nd).
        SET nd:RADIALOUT TO best_rad.
        SET nd:ETA TO best_ut - TIME:SECONDS.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_yield_hud().
        IF aoso_rendezvous_node_hits_body(nd, hop) {
            LOCAL sc2 IS aoso_rendezvous_pe_score(nd, hop, desired).
            IF sc2 < best_sc {
                SET best_sc TO sc2.
                SET best_ut TO TIME:SECONDS + nd:ETA.
                SET best_pg TO nd:PROGRADE.
                SET best_rad TO nd:RADIALOUT.
            }
        }
        SET nd:PROGRADE TO best_pg.
        SET nd:RADIALOUT TO best_rad + extras[ei] * 0.4.
        SET nd:ETA TO best_ut - TIME:SECONDS.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_yield_hud().
        IF aoso_rendezvous_node_hits_body(nd, hop) {
            LOCAL sc3 IS aoso_rendezvous_pe_score(nd, hop, desired).
            IF sc3 < best_sc {
                SET best_sc TO sc3.
                SET best_ut TO TIME:SECONDS + nd:ETA.
                SET best_pg TO nd:PROGRADE.
                SET best_rad TO nd:RADIALOUT.
            }
        }
        SET ei TO ei + 1.
    }

    SET nd:PROGRADE TO best_pg.
    SET nd:RADIALOUT TO best_rad.
    SET nd:ETA TO best_ut - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
    aoso_yield_hud().
}

// Already on a transfer-like ellipse (apo near the moon): wait at apoapsis
// passages with a *small* correction. Do not fire another full Hohmann at
// periapsis — that is how a 80×49 000 km miss becomes a solar escape.
FUNCTION aoso_rendezvous_search_apo_passages {
    PARAMETER nd.
    PARAMETER hop.

    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL period IS aoso_orbit_period_s().
    IF period < 80 { RETURN FALSE. }
    LOCAL apo_eta IS ETA:APOAPSIS.
    IF apo_eta < 40 { SET apo_eta TO apo_eta + period. }
    LOCAL t0 IS TIME:SECONDS + apo_eta.
    LOCAL dvs IS LIST(0, 20, -20, 40, -40).
    LOCAL best_sc IS 1000000000000.
    LOCAL best_ut IS t0.
    LOCAL best_pg IS 0.
    LOCAL found IS FALSE.
    LOCAL k IS 0.
    UNTIL k >= 10 {
        LOCAL di IS 0.
        UNTIL di >= dvs:LENGTH {
            SET nd:PROGRADE TO dvs[di].
            SET nd:ETA TO (t0 + k * period) - TIME:SECONDS.
            IF nd:ETA < 25 { SET nd:ETA TO 25. }
            aoso_yield_hud().
            IF aoso_rendezvous_node_hits_body(nd, hop) {
                LOCAL sc IS aoso_rendezvous_pe_score(nd, hop, desired).
                LOCAL pe_try IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
                IF sc < best_sc {
                    SET best_sc TO sc.
                    SET best_ut TO TIME:SECONDS + nd:ETA.
                    SET best_pg TO nd:PROGRADE.
                    SET found TO TRUE.
                }
                IF aoso_rendezvous_pe_ok_value(pe_try, hop) {
                    aoso_ui_pulse("Phasing to " + hop:NAME, "accepting pass " + (k + 1) + " PE " + ROUND(pe_try, 0) + "m").
                    RETURN TRUE.
                }
            }
            SET di TO di + 1.
        }
        aoso_ui_pulse("Phasing to " + hop:NAME, "apoapsis pass " + (k + 1) + "/10").
        SET k TO k + 1.
    }
    IF found {
        SET nd:PROGRADE TO best_pg.
        SET nd:ETA TO best_ut - TIME:SECONDS.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_yield_hud().
        RETURN TRUE.
    }
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
        aoso_log_info("RENDEZVOUS", "Already near " + target_orbitable:NAME + " altitude (AP=" + ROUND(APOAPSIS, 0) + " m) - phasing at apoapsis, not another Hohmann.").
        LOCAL nd_a IS NODE(TIME:SECONDS + MAX(40, ETA:APOAPSIS), 0, 0, 0).
        ADD nd_a.
        LOCAL hit_a IS aoso_rendezvous_search_apo_passages(nd_a, target_orbitable).
        IF hit_a {
            aoso_rendezvous_tune_pe(nd_a, target_orbitable).
            LOCAL pe_a IS aoso_rendezvous_orbit_pe(nd_a:ORBIT, target_orbitable).
            aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd_a:ETA, 0) + "s dv=" + ROUND(nd_a:PROGRADE, 1) + " m/s patchPE=" + ROUND(pe_a, 0) + " m.").
            RETURN nd_a.
        }
        aoso_log_warn("RENDEZVOUS", "No " + target_orbitable:NAME + " patch on this ellipse this synodic - not burning a second Hohmann. Will wait.").
        REMOVE nd_a.
        RETURN 0.
    }

    // Astrogator is the intercept planner when installed. AOSO Hohmann
    // phasing produced 400 km Minmus grazes; mid-course (goto COAST)
    // still retunes PE the regular way after the burn. Polar landing is a
    // Minmus-SOI plane-change after capture, not a graze from Kerbin.
    LOCAL nd_ag IS aoso_addon_astrogator_add_transfer(target_orbitable, TRUE).
    IF nd_ag <> 0 {
        aoso_yield_hud().
        LOCAL pe_ag IS aoso_rendezvous_orbit_pe(nd_ag:ORBIT, target_orbitable).
        LOCAL pe_txt IS "".
        IF pe_ag >= 0 { SET pe_txt TO " patchPE=" + ROUND(pe_ag, 0) + "m". }
        aoso_log_info("RENDEZVOUS", "Astrogator intercept with " + target_orbitable:NAME + " in " + ROUND(nd_ag:ETA, 0) + "s dv=" + ROUND(nd_ag:DELTAV:MAG, 1) + " m/s" + pe_txt + " (mid-course will retune PE).").
        aoso_ui_clear().
        RETURN nd_ag.
    }
    aoso_log_info("RENDEZVOUS", "Astrogator unavailable or returned no node - falling back to Hohmann search.").

    LOCAL wait_s IS aoso_rendezvous_wait_time_to_transfer_s(target_orbitable).
    IF wait_s < 0 {
        aoso_log_warn("RENDEZVOUS", "Ship and target periods match; no transfer window exists.").
        RETURN 0.
    }
    SET node_wait TO wait_s.

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
    LOCAL polar_hop IS FALSE.
    LOCAL rel_now IS aoso_orbit_relative_inclination_deg(SHIP, target_orbitable).
    IF rel_now >= 0.5 {
        IF NOT polar_hop {
            aoso_log_info("RENDEZVOUS", "Matching " + ROUND(rel_now, 1) + " deg plane to " + target_orbitable:NAME + " before intercept search (equatorial Hohmann misses Minmus SOI).").
            aoso_planechange_apply_to_node(nd, target_orbitable).
            aoso_yield_hud().
        }
    }
    aoso_log_info("RENDEZVOUS", "Searching " + target_orbitable:NAME + " intercept at Hohmann dv=" + ROUND(dv, 1) + " m/s (escape " + ROUND(dv_esc, 1) + ") in " + ROUND(node_wait, 0) + "s rel_inc=" + ROUND(rel_now, 1) + "deg.").
    aoso_ui_set("Searching " + target_orbitable:NAME + " intercept", "Hohmann " + ROUND(dv, 0) + " m/s  window " + ROUND(node_wait, 0) + "s").

    LOCAL hit IS aoso_rendezvous_search_intercept(nd, target_orbitable, dv).

    IF hit {
        SET rel_now TO aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).
        IF rel_now >= 0.15 {
            IF NOT polar_hop {
                LOCAL sc_before IS aoso_rendezvous_pe_score(nd, target_orbitable, aoso_rendezvous_desired_pe(target_orbitable)).
                LOCAL pg_keep IS nd:PROGRADE.
                LOCAL nml_keep IS nd:NORMAL.
                LOCAL rad_keep IS nd:RADIALOUT.
                aoso_planechange_apply_to_node(nd, target_orbitable).
                aoso_yield_hud().
                LOCAL fold_ok IS FALSE.
                IF aoso_rendezvous_node_hits_body(nd, target_orbitable) {
                    LOCAL sc_after IS aoso_rendezvous_pe_score(nd, target_orbitable, aoso_rendezvous_desired_pe(target_orbitable)).
                    IF sc_after <= sc_before * 1.15 { SET fold_ok TO TRUE. }
                }
                IF NOT fold_ok {
                    aoso_log_warn("RENDEZVOUS", "Plane-change fold lost or worsened the " + target_orbitable:NAME + " patch - restoring prograde-only intercept.").
                    SET nd:PROGRADE TO pg_keep.
                    SET nd:NORMAL TO nml_keep.
                    SET nd:RADIALOUT TO rad_keep.
                    aoso_yield_hud().
                }
            }
        }
        aoso_rendezvous_tune_pe(nd, target_orbitable).
        LOCAL pe_now IS aoso_rendezvous_orbit_pe(nd:ORBIT, target_orbitable).
        LOCAL want_pe IS aoso_rendezvous_desired_pe(target_orbitable).
        LOCAL pe_txt IS "".
        IF pe_now >= 0 { SET pe_txt TO " patchPE=" + ROUND(pe_now, 0) + " m want=" + ROUND(want_pe, 0) + "m". }
        LOCAL inc_p IS aoso_rendezvous_orbit_inc(nd:ORBIT, target_orbitable).
        IF inc_p >= 0 { SET pe_txt TO pe_txt + " patchInc=" + ROUND(inc_p, 1) + "deg". }
        IF pe_now >= 0 {
            IF ABS(pe_now - want_pe) > want_pe * 0.8 {
                aoso_log_warn("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + " - will mid-course if the PE stays a graze.").
            } ELSE {
                aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").
            }
        } ELSE {
            aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").
        }
        aoso_ui_clear().
        RETURN nd.
    }

    aoso_log_warn("RENDEZVOUS", "No patched encounter this window - not burning a blind Hohmann (that escaped Kerbin last time). Will retry next orbit.").
    aoso_ui_clear().
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

FUNCTION aoso_rendezvous_orbit_inc {
    PARAMETER orb.
    PARAMETER hop.
    LOCAL cur IS orb.
    LOCAL n IS 0.
    UNTIL n >= 5 {
        IF NOT cur:HASNEXTPATCH { RETURN -1. }
        SET cur TO cur:NEXTPATCH.
        IF cur:BODY:NAME = hop:NAME { RETURN cur:INCLINATION. }
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
    LOCAL sc IS ABS(pe - desired_pe).
    IF DEFINED AOSO_WANT_POLAR {
        IF AOSO_WANT_POLAR {
            IF SHIP:BODY:NAME = hop:NAME {
                LOCAL inc_p IS aoso_rendezvous_orbit_inc(nd:ORBIT, hop).
                IF inc_p >= 0 {
                    LOCAL tgt_i IS aoso_config_get("TOUR_POLAR_INCLINATION", 90).
                    SET sc TO sc + ABS(inc_p - tgt_i) * 400.
                }
            }
        }
    }
    RETURN sc.
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

    LOCAL step_t IS 40.
    LOCAL step_dv IS 8.
    LOCAL rounds IS 0.
    UNTIL rounds >= 10 {
        LOCAL improved IS FALSE.

        LOCAL orig_eta IS nd:ETA.
        SET nd:ETA TO orig_eta + step_t.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_yield_hud().
        LOCAL s IS aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:ETA TO orig_eta - step_t.
            IF nd:ETA < 25 {
                SET nd:ETA TO orig_eta.
            } ELSE {
                aoso_yield_hud().
                SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
                IF s < best {
                    SET best TO s.
                    SET improved TO TRUE.
                } ELSE {
                    SET nd:ETA TO orig_eta.
                    aoso_yield_hud().
                }
            }
        }

        LOCAL orig_pg IS nd:PROGRADE.
        SET nd:PROGRADE TO orig_pg + step_dv.
        aoso_rendezvous_clamp_prograde(nd).
        aoso_yield_hud().
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:PROGRADE TO orig_pg - step_dv.
            aoso_yield_hud().
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
        aoso_yield_hud().
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:RADIALOUT TO orig_rad - step_dv.
            aoso_yield_hud().
            SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
            IF s < best {
                SET best TO s.
                SET improved TO TRUE.
            } ELSE {
                SET nd:RADIALOUT TO orig_rad.
            }
        }

        LOCAL orig_n IS nd:NORMAL.
        LOCAL rel_left IS aoso_orbit_rel_inc_from_orbit(nd:ORBIT, hop).
        LOCAL walk_n IS FALSE.
        IF rel_left >= 0.4 { SET walk_n TO TRUE. }
        IF DEFINED AOSO_WANT_POLAR {
            IF AOSO_WANT_POLAR { SET walk_n TO TRUE. }
        }
        IF walk_n {
            SET nd:NORMAL TO orig_n + step_dv.
            aoso_yield_hud().
            SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
            IF s < best {
                SET best TO s.
                SET improved TO TRUE.
            } ELSE {
                SET nd:NORMAL TO orig_n - step_dv.
                aoso_yield_hud().
                SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
                IF s < best {
                    SET best TO s.
                    SET improved TO TRUE.
                } ELSE {
                    SET nd:NORMAL TO orig_n.
                }
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
    // ~30% of the remaining coast: early enough to turn a SOI-graze into
    // a real encounter before a long rails warp, late enough that a few
    // m/s still moves PE. (A 0.3 placement on Minmus was 18 h out; that
    // only looked idle because LOCK STEERING blocked rails WARPTO.)
    LOCAL t_corr IS eta_p * 0.3.
    IF t_corr > eta_p - 180 { SET t_corr TO eta_p - 180. }
    IF t_corr < 45 { SET t_corr TO 45. }

    LOCAL nd IS NODE(TIME:SECONDS + t_corr, 0, 0, 0).
    ADD nd.
    aoso_rendezvous_tune_pe(nd, hop).
    IF NOT aoso_rendezvous_node_hits_body(nd, hop) {
        aoso_log_warn("RENDEZVOUS", "Mid-course tune lost the " + hop:NAME + " patch - leaving the coast as-is.").
        REMOVE nd.
        RETURN 0.
    }
    IF nd:DELTAV:MAG < 0.8 {
        REMOVE nd.
        RETURN 0.
    }
    aoso_log_info("RENDEZVOUS", "Mid-course correction dv=" + ROUND(nd:DELTAV:MAG, 1) + " m/s, PE " + ROUND(pe_now, 0) + " -> " + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), 0) + "m.").
    RETURN nd.
}
