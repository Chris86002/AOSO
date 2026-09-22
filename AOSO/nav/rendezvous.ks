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

// Extra physics ticks after a node edit so KSP rebuilt NEXTPATCH before we
// score PE. Rushing this is how a 503 km Minmus graze got burned.
FUNCTION aoso_rendezvous_settle {
    WAIT 0.
    WAIT 0.
    IF DEFINED AOSO_HUD_READY {
        IF AOSO_HUD_READY {
            IF OPCODESLEFT > 240 {
                aoso_hud_fast_tick().
            }
        }
    }
}

// Do not burn a guess. Hill-climb patched PE (B-plane / aiming radius)
// until it is a capture altitude. Returns FALSE if it is still a graze.
FUNCTION aoso_rendezvous_finalize_node {
    PARAMETER nd.
    PARAMETER hop.
    aoso_rendezvous_settle().
    LOCAL pe0 IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL want IS aoso_rendezvous_desired_pe(hop).
    IF aoso_rendezvous_pe_ok_value(pe0, hop) {
        aoso_log_info("RENDEZVOUS", hop:NAME + " intercept PE " + ROUND(pe0, 0) + "m already a capture (want " + ROUND(want, 0) + "m).").
        RETURN TRUE.
    }
    aoso_log_info("RENDEZVOUS", hop:NAME + " intercept PE " + ROUND(pe0, 0) + "m is not a capture (want " + ROUND(want, 0) + "m) - hill-climbing patched conics before the burn.").
    aoso_ui_pulse("Aiming " + hop:NAME + " intercept", "PE " + ROUND(pe0, 0) + "m  want " + ROUND(want, 0) + "m").
    aoso_rendezvous_refine_intercept(nd, hop, nd:PROGRADE).
    aoso_rendezvous_tune_pe(nd, hop).
    aoso_rendezvous_settle().
    LOCAL pe1 IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    IF aoso_rendezvous_pe_ok_value(pe1, hop) {
        aoso_log_info("RENDEZVOUS", "Aimed " + hop:NAME + " intercept PE " + ROUND(pe0, 0) + " -> " + ROUND(pe1, 0) + "m (want " + ROUND(want, 0) + "m).").
        RETURN TRUE.
    }
    aoso_log_warn("RENDEZVOUS", "Still a graze after aiming: PE " + ROUND(pe1, 0) + "m want " + ROUND(want, 0) + "m - will not burn this window.").
    RETURN FALSE.
}

FUNCTION aoso_rendezvous_porkchop_tof_hoh {
    PARAMETER hop.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL radius1 IS SHIP:BODY:RADIUS + (APOAPSIS + PERIAPSIS) / 2.
    IF radius1 < SHIP:BODY:RADIUS + 1000 { SET radius1 TO SHIP:BODY:RADIUS + ALTITUDE. }
    LOCAL radius2 IS hop:ORBIT:SEMIMAJORAXIS.
    LOCAL sma_t IS (radius1 + radius2) / 2.
    LOCAL tof_h IS CONSTANT:PI * SQRT((sma_t ^ 3) / mu).
    IF tof_h < 600 { SET tof_h TO 600. }
    RETURN tof_h.
}

FUNCTION aoso_rendezvous_apply_lambert {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER t_dep.
    PARAMETER tof_s.
    IF t_dep <= TIME:SECONDS + 25 { RETURN FALSE. }
    LOCAL parent_body IS SHIP:BODY.
    LOCAL pos1 IS aoso_lambert_rel_pos(SHIP, t_dep, parent_body).
    LOCAL pos2 IS aoso_lambert_rel_pos(hop, t_dep + tof_s, parent_body).
    LOCAL vel_now IS VELOCITYAT(SHIP, t_dep):ORBIT.
    LOCAL mu IS parent_body:MU.

    // Aim beside the body, not through its center. Lambert-to-center is a
    // lithobrake; the patched PE we want is parking altitude.
    LOCAL aim_off IS hop:RADIUS + aoso_rendezvous_desired_pe(hop).
    LOCAL nrm_aim IS VCRS(pos1, pos2).
    IF nrm_aim:MAG < 0.001 { SET nrm_aim TO VCRS(pos2, V(0, 1, 0)). }
    IF nrm_aim:MAG > 0.001 {
        LOCAL miss_dir IS VCRS(pos2, nrm_aim):NORMALIZED.
        SET pos2 TO pos2 + miss_dir * aim_off.
    }

    LOCAL sol IS aoso_lambert_solve(pos1, pos2, tof_s, mu, FALSE).
    IF NOT sol["ok"] {
        SET sol TO aoso_lambert_solve(pos1, pos2, tof_s, mu, TRUE).
    }
    IF sol["ok"] {
    } ELSE {
        RETURN FALSE.
    }
    LOCAL dv_vec IS sol["vel1"] - vel_now.
    LOCAL dv_max IS aoso_rendezvous_dv_max(pos1:MAG).
    IF dv_vec:MAG > dv_max * 1.15 { RETURN FALSE. }
    LOCAL xyz IS aoso_lambert_dv_to_node_xyz(dv_vec, pos1, vel_now).
    SET nd:ETA TO t_dep - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
    SET nd:RADIALOUT TO xyz["radial"].
    SET nd:NORMAL TO xyz["normal"].
    SET nd:PROGRADE TO xyz["prograde"].
    aoso_rendezvous_clamp_prograde(nd).
    RETURN TRUE.
}

FUNCTION aoso_rendezvous_apply_dv {
    PARAMETER nd.
    PARAMETER t_dep.
    PARAMETER dv_pg.
    PARAMETER dv_nml.
    PARAMETER dv_rad IS 0.
    IF t_dep <= TIME:SECONDS + 25 { RETURN FALSE. }
    SET nd:ETA TO t_dep - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
    SET nd:RADIALOUT TO dv_rad.
    SET nd:NORMAL TO dv_nml.
    SET nd:PROGRADE TO dv_pg.
    aoso_rendezvous_clamp_prograde(nd).
    RETURN TRUE.
}

FUNCTION aoso_rendezvous_porkchop_keep {
    PARAMETER cands.
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER desired.
    PARAMETER n_max.
    LOCAL pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL sc IS aoso_rendezvous_porkchop_score(nd, hop, desired).
    IF sc < 0 { RETURN. }
    LOCAL item IS LEXICON("ut", TIME:SECONDS + nd:ETA, "pg", nd:PROGRADE, "rad", nd:RADIALOUT, "nml", nd:NORMAL, "sc", sc, "dv", nd:DELTAV:MAG, "pe", pe).
    IF cands:LENGTH < n_max {
        cands:ADD(item).
        RETURN.
    }
    LOCAL wi IS 0.
    LOCAL wsc IS cands[0]["sc"].
    LOCAL i IS 1.
    UNTIL i >= cands:LENGTH {
        IF cands[i]["sc"] > wsc {
            SET wsc TO cands[i]["sc"].
            SET wi TO i.
        }
        SET i TO i + 1.
    }
    IF sc < wsc { SET cands[wi] TO item. }
}

FUNCTION aoso_rendezvous_porkchop_best_txt {
    PARAMETER cands.
    IF cands:LENGTH = 0 { RETURN "none". }
    LOCAL bi IS 0.
    LOCAL bsc IS cands[0]["sc"].
    LOCAL i IS 1.
    UNTIL i >= cands:LENGTH {
        IF cands[i]["sc"] < bsc {
            SET bsc TO cands[i]["sc"].
            SET bi TO i.
        }
        SET i TO i + 1.
    }
    RETURN ROUND(cands[bi]["pe"], 0) + "m dv=" + ROUND(cands[bi]["dv"], 0).
}

FUNCTION aoso_rendezvous_settle_long {
    WAIT 0.
    WAIT 0.
    WAIT 0.
    IF DEFINED AOSO_HUD_READY {
        IF AOSO_HUD_READY {
            IF OPCODESLEFT > 200 {
                aoso_hud_fast_tick().
            }
        }
    }
}

FUNCTION aoso_rendezvous_native_candidates_to_node {
    PARAMETER native_res.
    PARAMETER hop.
    PARAMETER t_soon.

    IF native_res:ISTYPE("Lexicon") {
    } ELSE {
        RETURN 0.
    }
    IF NOT native_res:HASKEY("ok") { RETURN 0. }
    IF NOT native_res["ok"] { RETURN 0. }
    IF NOT native_res:HASKEY("cands") { RETURN 0. }

    LOCAL cands IS native_res["cands"].
    IF NOT cands:ISTYPE("List") { RETURN 0. }
    IF cands:LENGTH = 0 { RETURN 0. }

    LOCAL nd_native IS NODE(t_soon, 0, 0, 10).
    ADD nd_native.

    LOCAL win_dv IS 1e99.
    LOCAL win_ut IS 0.
    LOCAL win_pg IS 0.
    LOCAL win_rad IS 0.
    LOCAL win_nml IS 0.
    LOCAL win_pe IS -1.
    LOCAL n_tried IS 0.
    LOCAL n_cap IS 0.
    LOCAL ci IS 0.

    UNTIL ci >= cands:LENGTH {
        IF n_tried >= 8 { SET ci TO cands:LENGTH. }
        IF ci < cands:LENGTH {
            LOCAL cand IS cands[ci].
            SET nd_native:ETA TO cand["ut"] - TIME:SECONDS.
            IF nd_native:ETA < 25 { SET nd_native:ETA TO 25. }
            SET nd_native:PROGRADE TO cand["pg"].
            SET nd_native:RADIALOUT TO cand["rad"].
            SET nd_native:NORMAL TO cand["nml"].
            aoso_rendezvous_clamp_prograde(nd_native).

            aoso_ui_pulse("Native intercept check",
                (n_tried + 1) + "/" + MIN(8, cands:LENGTH) +
                "  dv=" + ROUND(cand["dv"], 0) +
                " PE=" + ROUND(cand["pe"], 0) + "m").

            IF aoso_rendezvous_finalize_node(nd_native, hop) {
                SET n_cap TO n_cap + 1.
                LOCAL pe_f IS aoso_rendezvous_orbit_pe(nd_native:ORBIT, hop).
                LOCAL dv_f IS nd_native:DELTAV:MAG.
                IF dv_f < win_dv {
                    SET win_dv TO dv_f.
                    SET win_ut TO TIME:SECONDS + nd_native:ETA.
                    SET win_pg TO nd_native:PROGRADE.
                    SET win_rad TO nd_native:RADIALOUT.
                    SET win_nml TO nd_native:NORMAL.
                    SET win_pe TO pe_f.
                }
            }
            SET n_tried TO n_tried + 1.
        }
        SET ci TO ci + 1.
    }

    IF win_pe < 0 {
        aoso_log_warn("RENDEZVOUS", "Native porkchop returned " + cands:LENGTH +
            " candidates but none passed finalize_node; running KerboScript grid.").
        REMOVE nd_native.
        RETURN 0.
    }

    SET nd_native:ETA TO win_ut - TIME:SECONDS.
    IF nd_native:ETA < 25 { SET nd_native:ETA TO 25. }
    SET nd_native:PROGRADE TO win_pg.
    SET nd_native:RADIALOUT TO win_rad.
    SET nd_native:NORMAL TO win_nml.
    aoso_rendezvous_settle_long().

    LOCAL final_pe IS aoso_rendezvous_orbit_pe(nd_native:ORBIT, hop).
    IF NOT aoso_rendezvous_pe_ok_value(final_pe, hop) {
        aoso_log_warn("RENDEZVOUS", "Native winner lost capture PE after re-apply; using KerboScript grid.").
        REMOVE nd_native.
        RETURN 0.
    }

    aoso_log_info("RENDEZVOUS", "Native porkchop accepted: PE " + ROUND(final_pe, 0) +
        "m dv=" + ROUND(nd_native:DELTAV:MAG, 1) + " m/s in " +
        ROUND(nd_native:ETA, 0) + "s (checked " + n_tried +
        ", capture " + n_cap + ").").
    aoso_ui_set("Aiming " + hop:NAME + " intercept",
        "native PE " + ROUND(final_pe, 0) + "m  dv " + ROUND(nd_native:DELTAV:MAG, 0)).
    RETURN nd_native.
}

FUNCTION aoso_rendezvous_try_native_porkchop {
    PARAMETER hop.
    PARAMETER n_dep.
    PARAMETER n_dv.
    PARAMETER n_nml.
    PARAMETER dv_hoh.
    PARAMETER dv_max.
    PARAMETER t_soon.
    PARAMETER t_hoh.
    PARAMETER p_ship.
    PARAMETER desired.

    IF NOT aoso_addon_native_porkchop_available() { RETURN 0. }

    LOCAL think_ok IS TRUE.
    IF DEFINED AOSO_BRAIN {
        SET think_ok TO aoso_brain_think_ok().
    }
    IF NOT think_ok {
        aoso_log_info("RENDEZVOUS", "Native porkchop deferred: not in a brain quiet window.").
        RETURN 0.
    }

    LOCAL max_mult IS aoso_config_get("INTERCEPT_PE_MAX_MULT", 2.2).
    IF max_mult < 1.3 { SET max_mult TO 1.3. }
    LOCAL pe_max IS desired * max_mult.
    IF pe_max < desired + 8000 { SET pe_max TO desired + 8000. }
    LOCAL soi_alt IS aoso_rendezvous_soi_alt(hop).
    LOCAL soi_cap IS soi_alt * 0.06.
    IF pe_max > soi_cap { SET pe_max TO soi_cap. }

    LOCAL opts IS LEXICON(
        "dep_samples", n_dep,
        "dv_samples", n_dv,
        "nml_samples", n_nml,
        "tof_samples", aoso_config_get("PORKCHOP_TOF_SAMPLES", 8),
        "dv_hoh", dv_hoh,
        "dv_max", dv_max,
        "t_soon", t_soon,
        "t_hoh", t_hoh,
        "period_s", p_ship,
        "step_win", aoso_rendezvous_search_step_s(hop),
        "desired_pe", desired,
        "pe_min", aoso_rendezvous_pe_min(hop, desired),
        "pe_max", pe_max,
        "soi_alt", soi_alt,
        "tof_min", aoso_config_get("PORKCHOP_TOF_MIN", 0.06),
        "tof_max", aoso_config_get("PORKCHOP_TOF_MAX", 1.7)
    ).

    LOCAL started IS aoso_addon_native_porkchop_start(hop, opts).
    IF started:ISTYPE("Scalar") { RETURN 0. }
    IF NOT started:HASKEY("ok") { RETURN 0. }
    IF NOT started["ok"] {
        LOCAL start_err IS "".
        IF started:HASKEY("err") { SET start_err TO started["err"]. }
        aoso_log_warn("RENDEZVOUS", "Native porkchop start failed (" + start_err + "); using KerboScript grid.").
        RETURN 0.
    }

    aoso_log_info("RENDEZVOUS", "Native porkchop search started for " + hop:NAME +
        " (" + n_dep + " dep, " + n_dv + " dv, " + n_nml + " normal).").

    LOCAL done IS FALSE.
    LOCAL failed IS FALSE.
    LOCAL polls IS 0.
    UNTIL done OR failed OR polls >= 500 {
        LOCAL status IS aoso_addon_native_porkchop_poll().
        IF status:ISTYPE("Scalar") {
            SET failed TO TRUE.
        } ELSE {
            IF NOT status:HASKEY("ok") {
                SET failed TO TRUE.
            } ELSE {
                IF NOT status["ok"] {
                    SET failed TO TRUE.
                } ELSE {
                    IF status:HASKEY("done") { SET done TO status["done"]. }
                    IF status:HASKEY("progress") {
                        aoso_ui_pulse("Native porkchop " + hop:NAME,
                            ROUND(status["progress"] * 100, 0) + "%  hits " +
                            status["n_hit"] + " capture " + status["n_ok"]).
                    }
                }
            }
        }
        SET polls TO polls + 1.
        IF NOT done AND NOT failed { WAIT 0. }
    }

    IF NOT done {
        aoso_log_warn("RENDEZVOUS", "Native porkchop did not finish cleanly after " +
            polls + " polls; using KerboScript grid.").
        RETURN 0.
    }

    LOCAL native_res IS aoso_addon_native_porkchop_result().
    IF native_res:ISTYPE("Scalar") { RETURN 0. }
    IF NOT native_res:HASKEY("ok") { RETURN 0. }
    IF NOT native_res["ok"] {
        LOCAL res_err IS "".
        IF native_res:HASKEY("err") { SET res_err TO native_res["err"]. }
        aoso_log_warn("RENDEZVOUS", "Native porkchop result failed (" + res_err + "); using KerboScript grid.").
        RETURN 0.
    }

    LOCAL n_cands IS 0.
    IF native_res:HASKEY("cands") { SET n_cands TO native_res["cands"]:LENGTH. }
    aoso_log_info("RENDEZVOUS", "Native porkchop finished: cells=" + native_res["n_done"] +
        " hits=" + native_res["n_hit"] + " capture=" + native_res["n_ok"] +
        " candidates=" + n_cands + ".").

    RETURN aoso_rendezvous_native_candidates_to_node(native_res, hop, t_soon).
}

// NASA-style porkchop for stock KSP: scan departure × prograde Δv ×
// small normal (plane) on patched conics. Lambert seeds aim beside the
// body (parking offset); this grid still owns SOI hits. Slow on purpose.
FUNCTION aoso_rendezvous_porkchop_search {
    PARAMETER hop.

    IF hop:BODY:NAME <> SHIP:BODY:NAME { RETURN 0. }
    IF NOT aoso_config_get("PORKCHOP_ENABLED", TRUE) { RETURN 0. }

    aoso_warp_hard_stop().
    aoso_steer_release().
    aoso_maneuver_clear_all().
    IF DEFINED AOSO_BRAIN {
        aoso_brain_wait_think("porkchop intercept").
    }

    LOCAL tof_h IS aoso_rendezvous_porkchop_tof_hoh(hop).
    LOCAL n_dep IS aoso_config_get("PORKCHOP_DEP_SAMPLES", 24).
    IF n_dep < 10 { SET n_dep TO 10. }
    IF n_dep > 40 { SET n_dep TO 40. }
    LOCAL n_dv IS aoso_config_get("PORKCHOP_DV_SAMPLES", 18).
    IF n_dv < 8 { SET n_dv TO 8. }
    IF n_dv > 28 { SET n_dv TO 28. }
    LOCAL n_nml IS aoso_config_get("PORKCHOP_NML_SAMPLES", 5).
    IF n_nml < 1 { SET n_nml TO 1. }
    IF n_nml > 7 { SET n_nml TO 7. }

    LOCAL p_ship IS aoso_orbit_period_s().
    IF p_ship < 80 { SET p_ship TO 600. }
    LOCAL wait_hoh IS aoso_rendezvous_wait_time_to_transfer_s(hop).
    IF wait_hoh < 0 { SET wait_hoh TO p_ship. }
    LOCAL t_soon IS TIME:SECONDS + 90.
    LOCAL t_hoh IS TIME:SECONDS + wait_hoh.
    IF t_hoh < t_soon { SET t_hoh TO t_soon. }

    // Coarse orbit scan + SOI-sized samples around the Hohmann window.
    // Old code stepped ~period/24 (minutes). Minmus's departure window is
    // ~15-30 s, so the grid walked right past every intercept.
    LOCAL deps IS LIST().
    LOCAL n_coarse IS 8.
    LOCAL ci_dep IS 0.
    UNTIL ci_dep >= n_coarse {
        deps:ADD(t_soon + ci_dep * (p_ship * 1.2 / MAX(1, n_coarse - 1))).
        SET ci_dep TO ci_dep + 1.
    }
    LOCAL step_win IS aoso_rendezvous_search_step_s(hop).
    LOCAL n_fine IS n_dep.
    IF n_fine < 12 { SET n_fine TO 12. }
    LOCAL half_f IS (n_fine - 1) / 2.
    LOCAL fi_dep IS 0.
    UNTIL fi_dep >= n_fine {
        LOCAL t_d IS t_hoh + (fi_dep - half_f) * step_win.
        IF t_d > TIME:SECONDS + 50 { deps:ADD(t_d). }
        SET fi_dep TO fi_dep + 1.
    }

    LOCAL target_alt IS hop:ORBIT:SEMIMAJORAXIS - SHIP:BODY:RADIUS.
    LOCAL dv_hoh IS aoso_hohmann_dv_at_periapsis_for_apoapsis(target_alt).
    IF dv_hoh < 80 { SET dv_hoh TO 80. }
    LOCAL dv_max IS aoso_rendezvous_dv_max(SHIP:BODY:RADIUS + ALTITUDE).
    LOCAL dv_lo IS dv_hoh * 0.35.
    IF dv_lo < 80 { SET dv_lo TO 80. }
    IF dv_lo > dv_max * 0.4 { SET dv_lo TO dv_max * 0.4. }
    LOCAL nml_span IS MIN(90, dv_hoh * 0.12).
    IF nml_span < 20 { SET nml_span TO 20. }

    LOCAL n_tot IS deps:LENGTH * n_dv * n_nml.
    LOCAL t_start IS TIME:SECONDS.
    aoso_log_info("RENDEZVOUS", "Patched porkchop for " + hop:NAME + ": " + deps:LENGTH + " departures × " + n_dv +
        " Δv × " + n_nml + " normal = " + n_tot + " cells. Hohmann dv=" + ROUND(dv_hoh, 0) + " m/s TOF=" + ROUND(tof_h, 0) +
        "s window in " + ROUND(wait_hoh, 0) + "s. Slow on purpose - waiting for a capture PE.").
    aoso_ui_set("Porkchop " + hop:NAME, n_tot + " patched cells  Hohmann " + ROUND(dv_hoh, 0) + " m/s").

    LOCAL desired IS aoso_rendezvous_desired_pe(hop).

    LOCAL native_nd IS aoso_rendezvous_try_native_porkchop(
        hop, n_dep, n_dv, n_nml, dv_hoh, dv_max,
        t_soon, t_hoh, p_ship, desired).
    IF native_nd:ISTYPE("Node") {
        RETURN native_nd.
    }

    // Native unavailable / failed / rejected: run the unchanged KerboScript
    // patched-conic grid as the behavioral oracle and fallback.
    LOCAL nd IS NODE(t_soon, 0, 0, 10).
    ADD nd.

    LOCAL cands IS LIST().
    LOCAL n_hit IS 0.
    LOCAL n_ok IS 0.
    LOCAL n_done IS 0.

    // Lambert is only a candidate seed. Patched conics still decide whether
    // the candidate actually enters the target SOI, and finalize_node still
    // owns capture-PE acceptance before any node can be returned.
    LOCAL seed_allowed IS aoso_config_get("LAMBERT_SEED_PORKCHOP", TRUE).
    IF seed_allowed {
        IF OPCODESLEFT < aoso_cpu_headroom() + 160 { SET seed_allowed TO FALSE. }
    }
    IF seed_allowed {
        LOCAL seed_stride IS 1.
        IF deps:LENGTH > 32 {
            SET seed_stride TO 3.
        } ELSE {
            IF deps:LENGTH > 16 { SET seed_stride TO 2. }
        }
        LOCAL seed_tofs IS LIST().
        LOCAL n_tof IS aoso_config_get("PORKCHOP_TOF_SAMPLES", 8).
        IF n_tof < 3 { SET n_tof TO 3. }
        IF n_tof > 6 { SET n_tof TO 6. }
        LOCAL tof_lo IS tof_h * aoso_config_get("PORKCHOP_TOF_MIN", 0.06).
        LOCAL tof_hi IS tof_h * aoso_config_get("PORKCHOP_TOF_MAX", 1.7).
        IF tof_lo < 600 { SET tof_lo TO 600. }
        IF tof_hi < tof_lo + 60 { SET tof_hi TO tof_lo + 60. }
        LOCAL ti_s IS 0.
        UNTIL ti_s >= n_tof {
            LOCAL frac_t IS 0.
            IF n_tof > 1 { SET frac_t TO ti_s / (n_tof - 1). }
            seed_tofs:ADD(tof_lo + (tof_hi - tof_lo) * frac_t).
            SET ti_s TO ti_s + 1.
        }
        seed_tofs:ADD(tof_h).
        LOCAL seed_hits IS 0.
        LOCAL seed_di IS 0.
        UNTIL seed_di >= deps:LENGTH {
            LOCAL t_seed IS deps[seed_di].
            LOCAL near_win IS FALSE.
            IF ABS(t_seed - t_hoh) < p_ship * 0.2 { SET near_win TO TRUE. }
            IF near_win {
                LOCAL seed_ti IS 0.
                UNTIL seed_ti >= seed_tofs:LENGTH {
                    LOCAL tof_try IS seed_tofs[seed_ti].
                    IF aoso_rendezvous_apply_lambert(nd, hop, t_seed, tof_try) {
                        aoso_rendezvous_settle_long().
                        IF aoso_rendezvous_node_hits_body(nd, hop) {
                            SET seed_hits TO seed_hits + 1.
                            aoso_rendezvous_porkchop_keep(cands, nd, hop, desired, 20).
                        }
                    }
                    SET seed_ti TO seed_ti + 1.
                }
            }
            SET seed_di TO seed_di + seed_stride.
        }
        aoso_log_info("RENDEZVOUS", "Lambert seeded porkchop with " + seed_hits +
            " patched hit(s); full patched grid still runs.").
    } ELSE {
        aoso_log_info("RENDEZVOUS", "Lambert porkchop seeds skipped for opcode headroom; full patched grid still runs.").
    }

    LOCAL di2 IS 0.
    UNTIL di2 >= deps:LENGTH {
        LOCAL dvi IS 0.
        UNTIL dvi >= n_dv {
            LOCAL dv_pg IS dv_lo + (dv_max - dv_lo) * dvi / MAX(1, n_dv - 1).
            LOCAL nmi IS 0.
            UNTIL nmi >= n_nml {
                LOCAL dv_nml IS 0.
                IF n_nml > 1 {
                    SET dv_nml TO (0 - nml_span) + (2 * nml_span) * nmi / (n_nml - 1).
                }
                SET n_done TO n_done + 1.
                IF aoso_rendezvous_apply_dv(nd, deps[di2], dv_pg, dv_nml) {
                    aoso_rendezvous_settle_long().
                    IF aoso_rendezvous_node_hits_body(nd, hop) {
                        SET n_hit TO n_hit + 1.
                        LOCAL pe_try IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
                        IF aoso_rendezvous_pe_ok_value(pe_try, hop) { SET n_ok TO n_ok + 1. }
                        aoso_rendezvous_porkchop_keep(cands, nd, hop, desired, 20).
                    }
                }
                IF FLOOR(n_done / 8) * 8 = n_done {
                    aoso_ui_pulse("Porkchop " + hop:NAME, n_done + "/" + n_tot + "  hits " + n_hit + "  capture " + n_ok + "  keep " + cands:LENGTH + "  best " + aoso_rendezvous_porkchop_best_txt(cands)).
                }
                SET nmi TO nmi + 1.
            }
            SET dvi TO dvi + 1.
        }
        SET di2 TO di2 + 1.
    }

    LOCAL dt_s IS TIME:SECONDS - t_start.
    aoso_log_info("RENDEZVOUS", "Porkchop grid done in " + ROUND(dt_s, 0) + "s: hits=" + n_hit + " capture=" + n_ok + "/" + n_tot + " kept " + cands:LENGTH + "  best " + aoso_rendezvous_porkchop_best_txt(cands) + ".").

    IF cands:LENGTH > 0 {
        aoso_log_info("RENDEZVOUS", "Densifying around " + MIN(3, cands:LENGTH) + " hit(s) - looking for cheaper capture PEs.").
        LOCAL hi IS 0.
        UNTIL hi >= cands:LENGTH {
            IF hi >= 3 { SET hi TO cands:LENGTH. }
            IF hi < cands:LENGTH {
                LOCAL seed IS cands[hi].
                LOCAL step_den IS aoso_rendezvous_search_step_s(hop).
                LOCAL tj IS 0.
                UNTIL tj >= 7 {
                    LOCAL t_r IS seed["ut"] + (tj - 3) * step_den.
                    LOCAL dj IS 0.
                    UNTIL dj >= 7 {
                        LOCAL dv_r IS seed["pg"] + (dj - 3) * 8.
                        LOCAL nj IS 0.
                        UNTIL nj >= 3 {
                            LOCAL nml_r IS seed["nml"] + (nj - 1) * 8.
                            SET n_done TO n_done + 1.
                            IF aoso_rendezvous_apply_dv(nd, t_r, dv_r, nml_r, seed["rad"]) {
                                aoso_rendezvous_settle_long().
                                IF aoso_rendezvous_node_hits_body(nd, hop) {
                                    SET n_hit TO n_hit + 1.
                                    LOCAL pe_r IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
                                    IF aoso_rendezvous_pe_ok_value(pe_r, hop) { SET n_ok TO n_ok + 1. }
                                    aoso_rendezvous_porkchop_keep(cands, nd, hop, desired, 20).
                                }
                            }
                            SET nj TO nj + 1.
                        }
                        SET dj TO dj + 1.
                    }
                    SET tj TO tj + 1.
                }
            }
            SET hi TO hi + 1.
        }
        aoso_log_info("RENDEZVOUS", "After densify: hits=" + n_hit + " capture=" + n_ok + " kept " + cands:LENGTH + "  best " + aoso_rendezvous_porkchop_best_txt(cands) + ".").
    }

    IF cands:LENGTH = 0 {
        aoso_log_warn("RENDEZVOUS", "NAV_FALLBACK porkchop hits=0 for " + hop:NAME + " after " + n_tot + " cells.").
        aoso_observe_event("NAV_FALLBACK", "WARN", "porkchop", "hits=0 body=" + hop:NAME).
        IF DEFINED AOSO_EVENTS { aoso_event_publish("NAV_FALLBACK", "rendezvous", "porkchop 0 " + hop:NAME). }
        REMOVE nd.
        RETURN 0.
    }

    LOCAL a IS 0.
    UNTIL a >= cands:LENGTH {
        LOCAL b IS a + 1.
        UNTIL b >= cands:LENGTH {
            IF cands[b]["dv"] < cands[a]["dv"] {
                LOCAL tmp IS cands[a].
                SET cands[a] TO cands[b].
                SET cands[b] TO tmp.
            }
            SET b TO b + 1.
        }
        SET a TO a + 1.
    }

    LOCAL win_dv IS 1e99.
    LOCAL win_ut IS 0.
    LOCAL win_pg IS 0.
    LOCAL win_rad IS 0.
    LOCAL win_nml IS 0.
    LOCAL win_pe IS -1.
    LOCAL n_tried IS 0.
    LOCAL n_cap IS 0.
    LOCAL ci IS 0.
    UNTIL ci >= cands:LENGTH {
        IF n_tried >= 8 { SET ci TO cands:LENGTH. }
        IF ci < cands:LENGTH {
            LOCAL c IS cands[ci].
            SET nd:ETA TO c["ut"] - TIME:SECONDS.
            IF nd:ETA < 25 { SET nd:ETA TO 25. }
            SET nd:PROGRADE TO c["pg"].
            SET nd:RADIALOUT TO c["rad"].
            SET nd:NORMAL TO c["nml"].
            aoso_ui_pulse("Comparing intercepts", (n_tried + 1) + "/" + MIN(8, cands:LENGTH) + "  dv=" + ROUND(c["dv"], 0) + " PE=" + ROUND(c["pe"], 0) + "m").
            IF aoso_rendezvous_finalize_node(nd, hop) {
                SET n_cap TO n_cap + 1.
                LOCAL pe_f IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
                LOCAL dv_f IS nd:DELTAV:MAG.
                aoso_log_info("RENDEZVOUS", "Candidate " + (n_tried + 1) + " capture PE=" + ROUND(pe_f, 0) + "m dv=" + ROUND(dv_f, 1) + " m/s in " + ROUND(nd:ETA, 0) + "s.").
                IF dv_f < win_dv {
                    SET win_dv TO dv_f.
                    SET win_ut TO TIME:SECONDS + nd:ETA.
                    SET win_pg TO nd:PROGRADE.
                    SET win_rad TO nd:RADIALOUT.
                    SET win_nml TO nd:NORMAL.
                    SET win_pe TO pe_f.
                }
            }
            SET n_tried TO n_tried + 1.
        }
        SET ci TO ci + 1.
    }

    IF win_pe < 0 {
        aoso_log_warn("RENDEZVOUS", "Porkchop had " + cands:LENGTH + " seeds but none trimmed to a capture PE - dropping them.").
        REMOVE nd.
        RETURN 0.
    }

    SET nd:ETA TO win_ut - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
    SET nd:PROGRADE TO win_pg.
    SET nd:RADIALOUT TO win_rad.
    SET nd:NORMAL TO win_nml.
    aoso_rendezvous_settle_long().
    aoso_log_info("RENDEZVOUS", "Porkchop picked cheapest capture: PE " + ROUND(win_pe, 0) + "m dv=" + ROUND(nd:DELTAV:MAG, 1) +
        " m/s in " + ROUND(nd:ETA, 0) + "s (compared " + n_tried + ", capture " + n_cap + ").").
    aoso_ui_set("Aiming " + hop:NAME + " intercept", "cheapest PE " + ROUND(win_pe, 0) + "m  dv " + ROUND(nd:DELTAV:MAG, 0)).
    RETURN nd.
}

FUNCTION aoso_rendezvous_porkchop_score {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER desired.
    LOCAL pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL dv_m IS nd:DELTAV:MAG.
    IF pe < -0.5 { RETURN -1. }
    IF aoso_rendezvous_pe_ok_value(pe, hop) {
        RETURN dv_m + ABS(pe - desired) * 0.002.
    }
    RETURN 100000000 + aoso_rendezvous_pe_score(nd, hop, desired) + dv_m.
}

FUNCTION aoso_rendezvous_sample_hit {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER t_ut.
    IF t_ut <= TIME:SECONDS + 25 { RETURN -1. }
    SET nd:ETA TO t_ut - TIME:SECONDS.
    aoso_rendezvous_settle().
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

    IF target_orbitable:ISTYPE("Vessel") OR target_orbitable:ISTYPE("DockingPort") {
        LOCAL tgt_ves IS target_orbitable.
        IF target_orbitable:ISTYPE("DockingPort") { SET tgt_ves TO target_orbitable:SHIP. }
        LOCAL stcw IS aoso_cw_state_now(tgt_ves).
        IF stcw["ok"] {
            IF stcw["range"] <= aoso_config_get("CW_MAX_RANGE_M", 50000) {
                IF stcw["range"] >= aoso_config_get("CW_MIN_RANGE_M", 500) {
                    LOCAL nd_cw IS aoso_cw_add_intercept_node(tgt_ves, 0).
                    IF nd_cw <> 0 {
                        aoso_log_info("RENDEZVOUS", "CW intercept to " + tgt_ves:NAME + " range=" + ROUND(stcw["range"], 0) + "m dv=" + ROUND(nd_cw:DELTAV:MAG, 1) + " m/s.").
                        RETURN nd_cw.
                    }
                }
            }
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

    // NASA porkchop (Lambert × TOF grid + patched-conic PE) is the
    // intercept. Slow on purpose. Hohmann is the fallback.
    LOCAL nd_pc IS aoso_rendezvous_porkchop_search(target_orbitable).
    IF nd_pc <> 0 {
        aoso_ui_clear().
        RETURN nd_pc.
    }
    aoso_log_warn("RENDEZVOUS", "NAV_FALLBACK porkchop miss -> Hohmann for " + target_orbitable:NAME + ".").
    aoso_observe_event("NAV_FALLBACK", "WARN", "hohmann", target_orbitable:NAME).
    IF DEFINED AOSO_EVENTS { aoso_event_publish("NAV_FALLBACK", "rendezvous", "hohmann " + target_orbitable:NAME). }
    aoso_log_info("RENDEZVOUS", "Searching Hohmann intercept windows for " + target_orbitable:NAME + ".").

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
        IF aoso_rendezvous_pe_ok_value(pe_now, target_orbitable) {
            aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").
            aoso_ui_clear().
            RETURN nd.
        }
        aoso_log_warn("RENDEZVOUS", "Hohmann window still a graze after aiming " + pe_txt + " - not burning. Will retry next orbit.").
        aoso_ui_clear().
        REMOVE nd.
        RETURN 0.
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
    LOCAL min_pe IS desired_pe * 0.6.
    IF hop:ATM:EXISTS {
        LOCAL floor_pe IS hop:ATM:HEIGHT + 8000.
        IF min_pe < floor_pe { SET min_pe TO floor_pe. }
    } ELSE {
        IF min_pe < 5000 { SET min_pe TO 5000. }
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
    LOCAL max_mult IS aoso_config_get("INTERCEPT_PE_MAX_MULT", 2.2).
    IF max_mult < 1.3 { SET max_mult TO 1.3. }
    LOCAL max_pe IS desired * max_mult.
    IF max_pe < desired + 8000 { SET max_pe TO desired + 8000. }
    LOCAL soi_cap IS aoso_rendezvous_soi_alt(hop) * 0.06.
    IF max_pe > soi_cap { SET max_pe TO soi_cap. }
    IF pe > max_pe { RETURN FALSE. }
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
    IF aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), hop) {
        IF best < desired * 0.12 { RETURN TRUE. }
    }

    LOCAL step_t IS aoso_rendezvous_search_step_s(hop).
    IF step_t > 20 { SET step_t TO 20. }
    IF step_t < 4 { SET step_t TO 4. }
    LOCAL step_dv IS 5.
    LOCAL rounds IS 0.
    UNTIL rounds >= 22 {
        LOCAL improved IS FALSE.

        LOCAL orig_eta IS nd:ETA.
        SET nd:ETA TO orig_eta + step_t.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_rendezvous_settle().
        LOCAL s IS aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:ETA TO orig_eta - step_t.
            IF nd:ETA < 25 {
                SET nd:ETA TO orig_eta.
            } ELSE {
                aoso_rendezvous_settle().
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
                aoso_rendezvous_settle().
                SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
                IF s < best {
                    SET best TO s.
                    SET improved TO TRUE.
                } ELSE {
                    SET nd:NORMAL TO orig_n.
                }
            }
        }

        IF aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), hop) {
            IF best < desired * 0.12 { RETURN TRUE. }
        }
        IF NOT improved {
            SET step_t TO step_t * 0.5.
            SET step_dv TO step_dv * 0.5.
            IF step_dv < 0.15 { RETURN aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), hop). }
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
    IF DEFINED AOSO_BRAIN {
        IF eta_p > aoso_config_get("BRAIN_THINK_LEAD_S", 600) {
            aoso_brain_wait_think("mid-course correction").
        }
    }
    // Place the burn soon: hours-out nodes overshoot on rails (Acacius
    // 11 h / 0.3 placement, ETA -360, never aligned). A few minutes is
    // still early enough for a few m/s to move PE.
    LOCAL t_corr IS eta_p * 0.15.
    IF t_corr > 720 { SET t_corr TO 720. }
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
    IF nd:DELTAV:MAG > aoso_config_get("MIDCOURSE_MAX_DV", 40) {
        aoso_log_warn("RENDEZVOUS", "Mid-course dv=" + ROUND(nd:DELTAV:MAG, 1) + " exceeds cap - leaving coast, replan later.").
        REMOVE nd.
        RETURN 0.
    }
    aoso_log_info("RENDEZVOUS", "Mid-course correction dv=" + ROUND(nd:DELTAV:MAG, 1) + " m/s, PE " + ROUND(pe_now, 0) + " -> " + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), 0) + "m.").
    RETURN nd.
}
