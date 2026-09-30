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

GLOBAL AOSO_POLAR_MIDCOURSE_TUNING IS FALSE.
GLOBAL AOSO_INTERCEPT_LAST IS LEXICON().
GLOBAL AOSO_INTERCEPT_EPOCH IS 0.

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
// A direct transfer from a parent body to one of its moons must enter that
// moon FIRST. The old validator searched four patches deep, so a trajectory
// Kerbin -> Mun -> Kerbin -> Minmus was accepted as a "Minmus encounter".
FUNCTION aoso_rendezvous_requires_direct_child_patch {
    PARAMETER hop.
    IF NOT hop:ISTYPE("Body") { RETURN FALSE. }
    IF hop:NAME = SHIP:BODY:NAME { RETURN FALSE. }
    RETURN hop:BODY:NAME = SHIP:BODY:NAME.
}

FUNCTION aoso_rendezvous_node_hits_body {
    PARAMETER nd.
    PARAMETER hop.
    LOCAL cur IS nd:ORBIT.

    IF aoso_rendezvous_requires_direct_child_patch(hop) {
        // A moon patch can hide a later impact with the parent. Never commit
        // a phasing orbit whose parent periapsis is inside the atmosphere.
        LOCAL parent_floor IS 5000.
        IF SHIP:BODY:ATM:EXISTS {
            SET parent_floor TO SHIP:BODY:ATM:HEIGHT + 10000.
        }
        IF cur:PERIAPSIS < parent_floor { RETURN FALSE. }
        IF NOT cur:HASNEXTPATCH { RETURN FALSE. }
        RETURN cur:NEXTPATCH:BODY:NAME = hop:NAME.
    }

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

    IF aoso_rendezvous_requires_direct_child_patch(hop) {
        IF NOT cur:HASNEXTPATCH { RETURN FALSE. }
        RETURN cur:NEXTPATCH:BODY:NAME = hop:NAME.
    }

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

// Burn duration the maneuver executor will actually center on the node.
// aoso_perf_burn_time_for_dv is zero while engines are shut down, which is
// the usual state when a transfer node is being planned.
FUNCTION aoso_rendezvous_burn_seconds {
    PARAMETER dv.

    LOCAL dv_abs IS ABS(dv).
    LOCAL t_lit IS aoso_perf_burn_time_for_dv(dv_abs).
    IF t_lit > 1 { RETURN t_lit. }

    LOCAL elist IS aoso_parts_engines().
    LOCAL best_d IS -999.
    FOR e IN elist {
        IF NOT e:FLAMEOUT {
            IF e:DECOUPLEDIN > best_d { SET best_d TO e:DECOUPLEDIN. }
        }
    }
    LOCAL pressure_atm IS 0.
    IF SHIP:BODY:ATM:EXISTS { SET pressure_atm TO SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE). }
    LOCAL thrust_sum IS 0.
    LOCAL isp_weighted IS 0.
    FOR e IN elist {
        IF NOT e:FLAMEOUT {
            IF e:DECOUPLEDIN = best_d {
                LOCAL th IS aoso_capabilities_engine_thrust(e, pressure_atm).
                IF th > 0 {
                    SET thrust_sum TO thrust_sum + th.
                    LOCAL isp_e IS e:VACUUMISP.
                    IF pressure_atm > 0.01 { SET isp_e TO e:ISP. }
                    SET isp_weighted TO isp_weighted + (isp_e * th).
                }
            }
        }
    }
    IF thrust_sum <= 0 { RETURN 0. }
    IF SHIP:MASS <= 0 { RETURN 0. }
    LOCAL ve IS (isp_weighted / thrust_sum) * AOSO_CONST["G0"].
    IF ve <= 1 { RETURN 0. }
    LOCAL analytical IS (SHIP:MASS * ve / thrust_sum) * (1 - CONSTANT:E ^ (-dv_abs / ve)).
    IF DEFINED AOSO_XP {
        RETURN aoso_xp_metric_apply("MANEUVER", SHIP:BODY:NAME, "BURN_TIME", analytical).
    }
    RETURN analytical.
}

// A ~2 min Kerbin->Minmus burn is not the impulsive node the conic scored.
// Acacius accepted a 102 km Minmus shoulder, burned 117 s, and the patch
// was gone. Short burns can still commit a rough encounter immediately.
FUNCTION aoso_rendezvous_burn_is_long {
    PARAMETER dv.
    RETURN aoso_rendezvous_burn_seconds(dv) > 35.
}

// Extra physics ticks after a node edit so KSP rebuilt NEXTPATCH before we
// score PE. Rushing this is how a 503 km Minmus graze got burned.
FUNCTION aoso_rendezvous_settle {
    WAIT 0.
    WAIT 0.

}

// Do not burn a guess. Hill-climb patched PE (B-plane / aiming radius)
// until it is a capture altitude. Returns FALSE if it is still a graze.
FUNCTION aoso_rendezvous_finalize_node {
    PARAMETER nd.
    PARAMETER hop.
    aoso_rendezvous_settle().
    IF NOT aoso_rendezvous_node_hits_body(nd, hop) {
        aoso_log_warn("RENDEZVOUS", "Rejected " + hop:NAME + " intercept: another SOI occurs before the target.").
        RETURN FALSE.
    }
    LOCAL pe0 IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL want IS aoso_rendezvous_desired_pe(hop).
    IF aoso_rendezvous_pe_ok_value(pe0, hop) {
        aoso_log_info("RENDEZVOUS", hop:NAME + " intercept PE " + ROUND(pe0, 0) + "m already a capture (want " + ROUND(want, 0) + "m).").
        RETURN TRUE.
    }
    IF NOT aoso_rendezvous_burn_is_long(nd:DELTAV:MAG) {
        IF aoso_rendezvous_pe_rough_ok_value(pe0, hop) {
            aoso_log_info("RENDEZVOUS", "SAFE ROUGH " + hop:NAME + " intercept PE=" +
                ROUND(pe0, 0) + "m (final want " + ROUND(want, 0) +
                "m). No departure-side polishing; mid-course owns final PE.").
            RETURN TRUE.
        }
    }
    aoso_log_info("RENDEZVOUS", hop:NAME + " intercept PE " + ROUND(pe0, 0) +
        "m is outside the safe rough corridor (want " + ROUND(want, 0) +
        "m) - refining only enough to obtain a usable encounter.").

    aoso_rendezvous_refine_intercept(nd, hop, nd:PROGRADE).
    aoso_rendezvous_tune_pe_keep(nd, hop).
    aoso_rendezvous_settle().
    LOCAL pe1 IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    IF aoso_rendezvous_pe_ok_value(pe1, hop) {
        aoso_log_info("RENDEZVOUS", "Aimed " + hop:NAME + " intercept PE " + ROUND(pe0, 0) + " -> " + ROUND(pe1, 0) + "m (want " + ROUND(want, 0) + "m).").
        RETURN TRUE.
    }
    IF aoso_rendezvous_pe_rough_ok_value(pe1, hop) {
        aoso_log_info("RENDEZVOUS", "SAFE ROUGH " + hop:NAME + " intercept PE=" +
            ROUND(pe1, 0) + "m (final want " + ROUND(want, 0) +
            "m). Committing departure; mid-course will refine the capture PE.").
        RETURN TRUE.
    }
    aoso_log_warn("RENDEZVOUS", "Still outside the safe rough encounter corridor: PE " +
        ROUND(pe1, 0) + "m want " + ROUND(want, 0) + "m - will not burn this window.").
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

    // r/Kos (Farsyte): near-180 Lambert with even a little relative
    // inclination invents a polar transfer. Project the aim point into
    // the ship's plane; plane-change is a later mid-course, not this seed.
    LOCAL nrm_ship IS VCRS(pos1, vel_now).
    IF nrm_ship:MAG > 0.001 {
        IF VANG(pos1, pos2) > 150 {
            LOCAL n_hat IS nrm_ship:NORMALIZED.
            LOCAL pos2_p IS pos2 - n_hat * VDOT(pos2, n_hat).
            IF pos2_p:MAG > 1 { SET pos2 TO pos2_p. }
        }
    }

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

    // Native v0.3 searches the full practical departure window and performs
    // its own fine time/dV/normal/radial refinement. If it found no actual
    // capture PE, do not spend tens of seconds asking KerboScript to
    // hill-climb eight known grazes one by one.
    LOCAL native_caps IS 0.
    IF native_res:HASKEY("n_ok") { SET native_caps TO native_res["n_ok"]. }
    IF native_caps <= 0 {
        aoso_log_warn("RENDEZVOUS", "Native porkchop found " + cands:LENGTH +
            " encounter candidates but no capture PE; skipping slow graze finalization.").
        RETURN 0.
    }

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
            " candidates but none passed finalize_node; returning to fallback navigation.").
        REMOVE nd_native.
        RETURN 0.
    }

    SET nd_native:ETA TO win_ut - TIME:SECONDS.
    IF nd_native:ETA < 25 { SET nd_native:ETA TO 25. }
    SET nd_native:PROGRADE TO win_pg.
    SET nd_native:RADIALOUT TO win_rad.
    SET nd_native:NORMAL TO win_nml.
    aoso_rendezvous_settle_long().

    aoso_rendezvous_aim_prograde_departure(nd_native, hop).
    LOCAL final_pe IS aoso_rendezvous_orbit_pe(nd_native:ORBIT, hop).
    IF NOT aoso_rendezvous_pe_ok_value(final_pe, hop) {
        aoso_log_warn("RENDEZVOUS", "Native winner lost capture PE after re-apply; returning to fallback navigation.").
        REMOVE nd_native.
        RETURN 0.
    }

    aoso_log_info("RENDEZVOUS", "Native porkchop accepted: PE " + ROUND(final_pe, 0) +
        "m dv=" + ROUND(nd_native:DELTAV:MAG, 1) + " m/s in " +
        ROUND(nd_native:ETA, 0) + "s (checked " + n_tried +
        ", capture " + n_cap + ").").

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

    // Native Phase 2 is already chunked into bounded main-thread slices and
    // yields between polls. Do not throw it away merely because the CPU band
    // is HIGH; that was forcing the 2,880-cell KerboScript fallback exactly
    // when the addon was supposed to save VM work.
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
        aoso_log_warn("RENDEZVOUS", "Native porkchop start failed (" + start_err + "); returning to fallback navigation.").
        RETURN 0.
    }

    aoso_log_info("RENDEZVOUS", "NATIVE PORKCHOP ACTIVE: " + hop:NAME +
        " search started (" + n_dep + " dep, " + n_dv + " dv, " + n_nml + " normal).").

    LOCAL done IS FALSE.
    LOCAL failed IS FALSE.
    LOCAL polls IS 0.
    LOCAL last_progress IS 0.
    LOCAL last_cells IS 0.
    LOCAL last_hits IS 0.
    LOCAL last_capture IS 0.
    UNTIL done OR failed OR polls >= 500 {
        LOCAL poll_status IS aoso_addon_native_porkchop_poll().
        IF poll_status:ISTYPE("Scalar") {
            SET failed TO TRUE.
        } ELSE {
            IF NOT poll_status:HASKEY("ok") {
                SET failed TO TRUE.
            } ELSE {
                IF NOT poll_status["ok"] {
                    SET failed TO TRUE.
                } ELSE {
                    IF poll_status:HASKEY("done") { SET done TO poll_status["done"]. }
                    IF poll_status:HASKEY("progress") { SET last_progress TO poll_status["progress"]. }
                    IF poll_status:HASKEY("n_done") { SET last_cells TO poll_status["n_done"]. }
                    IF poll_status:HASKEY("n_hit") { SET last_hits TO poll_status["n_hit"]. }
                    IF poll_status:HASKEY("n_ok") { SET last_capture TO poll_status["n_ok"]. }

                }
            }
        }
        SET polls TO polls + 1.
        IF NOT done AND NOT failed { WAIT 0. }
    }

    IF NOT done {
        aoso_log_warn("RENDEZVOUS", "Native porkchop timeout after " + polls +
            " polls: progress=" + ROUND(last_progress * 100, 1) + "% cells=" +
            last_cells + " hits=" + last_hits + " capture=" + last_capture +
            ". Falling back to the rough-transfer planner.").
        RETURN 0.
    }

    LOCAL native_res IS aoso_addon_native_porkchop_result().
    IF native_res:ISTYPE("Scalar") { RETURN 0. }
    IF NOT native_res:HASKEY("ok") { RETURN 0. }
    IF NOT native_res["ok"] {
        LOCAL res_err IS "".
        IF native_res:HASKEY("err") { SET res_err TO native_res["err"]. }
        aoso_log_warn("RENDEZVOUS", "Native porkchop result failed (" + res_err + "); returning to fallback navigation.").
        RETURN 0.
    }

    LOCAL n_cands IS 0.
    IF native_res:HASKEY("cands") { SET n_cands TO native_res["cands"]:LENGTH. }
    aoso_log_info("RENDEZVOUS", "NATIVE PORKCHOP DONE: cells=" + native_res["n_done"] +
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

    aoso_steer_release().
    IF NOT aoso_warp_ensure_physics_idle() {
        RETURN 0.
    }
    aoso_maneuver_clear_all().
    LOCAL native_ready IS aoso_addon_native_porkchop_available().
    IF DEFINED AOSO_BRAIN {
        IF NOT native_ready {
            aoso_brain_wait_think("KerboScript porkchop fallback").
        }
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

    LOCAL desired IS aoso_rendezvous_desired_pe(hop).

    LOCAL native_nd IS aoso_rendezvous_try_native_porkchop(
        hop, n_dep, n_dv, n_nml, dv_hoh, dv_max,
        t_soon, t_hoh, p_ship, desired).
    IF native_nd:ISTYPE("Node") {
        RETURN native_nd.
    }

    // With the addon installed, its bounded full-window search supersedes the
    // duplicate 2,880-cell KerboScript grid. If native still finds no
    // capture, return immediately so the existing Hohmann window search can
    // take over. The slow KerboScript porkchop remains the no-addon fallback.
    IF native_ready {
        aoso_log_warn("RENDEZVOUS", "Native porkchop exhausted without a valid final node; skipping duplicate KerboScript grid.").
        RETURN 0.
    }

    IF DEFINED AOSO_LAMBERT_MEMO { SET AOSO_LAMBERT_MEMO TO LEXICON(). }
    LOCAL reused IS aoso_intercept_reuse(hop).
    IF reused:ISTYPE("Node") { RETURN reused. }

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
    aoso_rendezvous_aim_prograde_departure(nd, hop).
    aoso_log_info("RENDEZVOUS", "Porkchop picked cheapest capture: PE " + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), 0) + "m dv=" + ROUND(nd:DELTAV:MAG, 1) +
        " m/s in " + ROUND(nd:ETA, 0) + "s (compared " + n_tried + ", capture " + n_cap + ").").
    aoso_intercept_store(hop, nd, win_pe).
    RETURN nd.
}

// Last KS-fallback intercept. Reuse only for the same hop and epoch bucket,
// and only if no SOI / maneuver-fail / vehicle event has bumped the epoch.
// Finalize still owns the PE gate; a cache hit cannot approve a burn.
FUNCTION aoso_intercept_reuse {
    PARAMETER hop.
    IF NOT AOSO_INTERCEPT_LAST:HASKEY("to") { RETURN 0. }
    IF AOSO_INTERCEPT_LAST["to"] <> hop:NAME { RETURN 0. }
    IF AOSO_INTERCEPT_LAST["from"] <> SHIP:BODY:NAME { RETURN 0. }
    IF AOSO_INTERCEPT_LAST["epoch"] <> AOSO_INTERCEPT_EPOCH { RETURN 0. }
    LOCAL bucket IS FLOOR(TIME:SECONDS / 120).
    IF AOSO_INTERCEPT_LAST["epoch_bucket"] <> bucket { RETURN 0. }
    LOCAL ut_re IS AOSO_INTERCEPT_LAST["ut"].
    IF ut_re < TIME:SECONDS + 30 { RETURN 0. }
    LOCAL nd_re IS NODE(ut_re, AOSO_INTERCEPT_LAST["rad"], AOSO_INTERCEPT_LAST["nml"], AOSO_INTERCEPT_LAST["pg"]).
    ADD nd_re.
    IF aoso_rendezvous_finalize_node(nd_re, hop) {
        aoso_cache_log("lambert", "hit", hop:NAME + "|" + bucket).
        RETURN nd_re.
    }
    REMOVE nd_re.
    aoso_cache_log("lambert", "miss", hop:NAME + "|pe").
    RETURN 0.
}

FUNCTION aoso_intercept_store {
    PARAMETER hop.
    PARAMETER nd_ok.
    PARAMETER pe_ok.
    LOCAL park_m IS PERIAPSIS.
    IF park_m < 0 { SET park_m TO ALTITUDE. }
    SET AOSO_INTERCEPT_LAST TO LEXICON(
        "from", SHIP:BODY:NAME,
        "to", hop:NAME,
        "epoch_bucket", FLOOR(TIME:SECONDS / 120),
        "epoch", AOSO_INTERCEPT_EPOCH,
        "park_alt", park_m,
        "pe", pe_ok,
        "dv", nd_ok:DELTAV:MAG,
        "ut", TIME:SECONDS + nd_ok:ETA,
        "pg", nd_ok:PROGRADE,
        "rad", nd_ok:RADIALOUT,
        "nml", nd_ok:NORMAL
    ).
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

    LOCAL best_sc IS 1000000000000.
    LOCAL best_ut IS t_center.
    LOCAL best_pg IS dv_use.
    LOCAL found IS FALSE.
    LOCAL n_chk IS 0.
    // A long finite burn smears a shoulder encounter off the SOI. Keep
    // walking the rest of the parking orbit until the PE is actually tight.
    LOCAL long_burn IS aoso_rendezvous_burn_is_long(dv_use).

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
                    IF found {
                        IF NOT long_burn { SET pass TO 2. }
                        ELSE {
                            IF best_sc < desired * 1.5 { SET pass TO 2. }
                        }
                    }
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
        aoso_yield().

        LOCAL coarse_pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
        IF aoso_rendezvous_pe_ok_value(coarse_pe, hop) {
            RETURN TRUE.
        }
        // Short burns may commit a rough encounter and let mid-course
        // finish PE. A multi-minute burn has to be centered first; the
        // 102 km Minmus shoulder did not survive 117 s of finite burn.
        IF NOT long_burn {
            IF aoso_rendezvous_pe_rough_ok_value(coarse_pe, hop) {
                RETURN TRUE.
            }
        }

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
            aoso_yield().
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
        aoso_yield().
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
        aoso_yield().
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
    aoso_yield().
}

// The ship is still down low, but apoapsis is already out near the moon, so
// the "already near altitude" path used to wait until apoapsis and poke
// ±40 m/s. That is the wrong place: near escape, a few m/s of prograde at
// periapsis moves apo by tens of Mm, and the apoapsis burn is hours later.
// Search a small near-term node first. Mostly normal/radial; prograde stays
// inside the few m/s that still reach the moon without escaping.
FUNCTION aoso_rendezvous_search_low_repair {
    PARAMETER nd.
    PARAMETER hop.

    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL period IS aoso_orbit_period_s().
    IF period < 80 { SET period TO 600. }
    LOCAL horizon IS period * 0.15.
    IF horizon > 900 { SET horizon TO 900. }
    IF horizon < 180 { SET horizon TO 180. }

    LOCAL raw_t IS LIST(90, 180, 400, 800).
    LOCAL times IS LIST().
    LOCAL ri IS 0.
    UNTIL ri >= raw_t:LENGTH {
        IF raw_t[ri] <= horizon + 20 { times:ADD(raw_t[ri]). }
        SET ri TO ri + 1.
    }
    IF times:LENGTH = 0 { times:ADD(90). }

    LOCAL dvs IS LIST(0, -3, -6, -10, -16, 3).
    LOCAL normals IS LIST(0, 30, -30, 70, -70).
    LOCAL radials IS LIST(0, 25, -25).

    LOCAL best_sc IS 1000000000000.
    LOCAL best_ut IS TIME:SECONDS + times[0].
    LOCAL best_pg IS 0.
    LOCAL best_nml IS 0.
    LOCAL best_rad IS 0.
    LOCAL found IS FALSE.
    LOCAL n_chk IS 0.
    LOCAL stop IS FALSE.

    LOCAL ti IS 0.
    UNTIL stop OR ti >= times:LENGTH {
        LOCAL di IS 0.
        UNTIL stop OR di >= dvs:LENGTH {
            LOCAL ni IS 0.
            UNTIL stop OR ni >= normals:LENGTH {
                LOCAL ai IS 0.
                UNTIL stop OR ai >= radials:LENGTH {
                    IF n_chk >= 180 { SET stop TO TRUE. }
                    IF NOT stop {
                        SET nd:PROGRADE TO dvs[di].
                        SET nd:NORMAL TO normals[ni].
                        SET nd:RADIALOUT TO radials[ai].
                        SET nd:ETA TO times[ti].
                        IF nd:ETA < 25 { SET nd:ETA TO 25. }
                        aoso_rendezvous_settle().
                        SET n_chk TO n_chk + 1.
                        IF nd:ORBIT:ECCENTRICITY < 1 {
                            IF aoso_rendezvous_node_hits_body(nd, hop) {
                                LOCAL sc IS aoso_rendezvous_pe_score(nd, hop, desired).
                                IF sc < best_sc {
                                    SET best_sc TO sc.
                                    SET best_ut TO TIME:SECONDS + nd:ETA.
                                    SET best_pg TO nd:PROGRADE.
                                    SET best_nml TO nd:NORMAL.
                                    SET best_rad TO nd:RADIALOUT.
                                    SET found TO TRUE.
                                }
                                LOCAL pe_try IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
                                IF aoso_rendezvous_pe_ok_value(pe_try, hop) { SET stop TO TRUE. }
                            }
                        }
                    }
                    SET ai TO ai + 1.
                }
                SET ni TO ni + 1.
            }
            SET di TO di + 1.
        }
        SET ti TO ti + 1.
    }

    IF NOT found {
        aoso_log_info("RENDEZVOUS", "Low repair found no " + hop:NAME + " patch in " + n_chk + " near-term samples.").
        RETURN FALSE.
    }

    SET nd:PROGRADE TO best_pg.
    SET nd:NORMAL TO best_nml.
    SET nd:RADIALOUT TO best_rad.
    SET nd:ETA TO best_ut - TIME:SECONDS.
    IF nd:ETA < 25 { SET nd:ETA TO 25. }
    aoso_yield().
    aoso_log_info("RENDEZVOUS", "Low repair hit " + hop:NAME + " dv=" + ROUND(nd:DELTAV:MAG, 1) + " m/s in " + ROUND(nd:ETA, 0) + "s after " + n_chk + " samples.").
    RETURN TRUE.
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
            aoso_yield().
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

                    RETURN TRUE.
                }
            }
            SET di TO di + 1.
        }

        SET k TO k + 1.
    }
    IF found {
        SET nd:PROGRADE TO best_pg.
        SET nd:ETA TO best_ut - TIME:SECONDS.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_yield().
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
        IF ALTITUDE < target_alt * 0.4 {
            aoso_log_info("RENDEZVOUS", "Still low (" + ROUND(ALTITUDE, 0) + " m) under " + target_orbitable:NAME + " - searching a near-term repair before apoapsis phasing.").
            LOCAL nd_low IS NODE(TIME:SECONDS + 120, 0, 0, 0).
            ADD nd_low.
            LOCAL hit_low IS aoso_rendezvous_search_low_repair(nd_low, target_orbitable).
            IF hit_low {
                aoso_rendezvous_tune_pe_keep(nd_low, target_orbitable).
                aoso_rendezvous_settle().
                IF aoso_rendezvous_node_hits_body(nd_low, target_orbitable) {
                    LOCAL pe_low IS aoso_rendezvous_orbit_pe(nd_low:ORBIT, target_orbitable).
                    IF aoso_rendezvous_pe_rough_ok_value(pe_low, target_orbitable) {
                        aoso_log_info("RENDEZVOUS", "Low repair encounter with " + target_orbitable:NAME + " in " + ROUND(nd_low:ETA, 0) + "s dv=" + ROUND(nd_low:DELTAV:MAG, 1) + " m/s patchPE=" + ROUND(pe_low, 0) + " m.").
                        RETURN nd_low.
                    }
                }
                aoso_log_warn("RENDEZVOUS", "Low repair tune lost the " + target_orbitable:NAME + " patch.").
            }
            REMOVE nd_low.
        }
        LOCAL nd_a IS NODE(TIME:SECONDS + MAX(40, ETA:APOAPSIS), 0, 0, 0).
        ADD nd_a.
        LOCAL hit_a IS aoso_rendezvous_search_apo_passages(nd_a, target_orbitable).
        IF hit_a {
            aoso_rendezvous_tune_pe_keep(nd_a, target_orbitable).
            aoso_rendezvous_settle().
            IF aoso_rendezvous_node_hits_body(nd_a, target_orbitable) {
                LOCAL pe_a IS aoso_rendezvous_orbit_pe(nd_a:ORBIT, target_orbitable).
                IF aoso_rendezvous_pe_rough_ok_value(pe_a, target_orbitable) {
                    aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd_a:ETA, 0) + "s dv=" + ROUND(nd_a:PROGRADE, 1) + " m/s patchPE=" + ROUND(pe_a, 0) + " m.").
                    RETURN nd_a.
                }
            }
            aoso_log_warn("RENDEZVOUS", "Phasing tune lost a safe direct encounter - waiting for another window.").
        }
        aoso_log_warn("RENDEZVOUS", "No " + target_orbitable:NAME + " patch on this ellipse this synodic - not burning a second Hohmann. Will wait.").
        REMOVE nd_a.
        RETURN 0.
    }

    // NASA porkchop (Lambert × TOF grid + patched-conic PE) is the
    // intercept. Slow on purpose. Hohmann is the fallback.
    LOCAL nd_pc IS aoso_rendezvous_porkchop_search(target_orbitable).
    IF nd_pc <> 0 {

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
            aoso_yield().
        }
    }
    aoso_log_info("RENDEZVOUS", "Searching " + target_orbitable:NAME + " intercept at Hohmann dv=" + ROUND(dv, 1) + " m/s (escape " + ROUND(dv_esc, 1) + ") in " + ROUND(node_wait, 0) + "s rel_inc=" + ROUND(rel_now, 1) + "deg.").

    LOCAL hit IS aoso_rendezvous_search_intercept(nd, target_orbitable, dv).

    IF hit {
        // A tight capture PE can be burned as planned. A rough shoulder on a
        // long burn cannot: mid-course never runs if the finite burn erases
        // the patch. Fall through and hill-climb that case. After tune, the
        // rough-ok accept below still commits the only window.
        LOCAL burn_s IS aoso_rendezvous_burn_seconds(nd:DELTAV:MAG).
        LOCAL rough_pe0 IS aoso_rendezvous_orbit_pe(nd:ORBIT, target_orbitable).
        IF aoso_rendezvous_node_hits_body(nd, target_orbitable) {
            IF aoso_rendezvous_pe_rough_ok_value(rough_pe0, target_orbitable) {
                IF aoso_rendezvous_pe_ok_value(rough_pe0, target_orbitable) OR burn_s <= 35 {
                    aoso_rendezvous_aim_prograde_departure(nd, target_orbitable).
                    LOCAL rough_pe1 IS aoso_rendezvous_orbit_pe(nd:ORBIT, target_orbitable).
                    LOCAL rough_inc1 IS aoso_rendezvous_orbit_inc(nd:ORBIT, target_orbitable).
                    LOCAL accept_why IS "Capture PE is already in band; polar is an in-SOI plane change, not a mid-course.".
                    IF NOT aoso_rendezvous_pe_ok_value(rough_pe1, target_orbitable) {
                        SET accept_why TO "One PE-only mid-course if the live patch leaves the capture band.".
                    }
                    aoso_log_info("RENDEZVOUS", "Rough " + target_orbitable:NAME +
                        " departure accepted: PE=" + ROUND(rough_pe1, 0) +
                        "m inc=" + ROUND(rough_inc1, 1) + "deg dv=" +
                        ROUND(nd:DELTAV:MAG, 1) + " m/s. " + accept_why).

                    RETURN nd.
                }
                aoso_log_info("RENDEZVOUS", "Long burn " + ROUND(burn_s, 0) +
                    "s would smear rough " + target_orbitable:NAME + " PE=" +
                    ROUND(rough_pe0, 0) + "m - tuning before commit.").
            }
        }

        SET rel_now TO aoso_orbit_rel_inc_from_orbit(nd:ORBIT, target_orbitable).
        IF rel_now >= 0.15 {
            IF NOT polar_hop {
                LOCAL sc_before IS aoso_rendezvous_pe_score(nd, target_orbitable, aoso_rendezvous_desired_pe(target_orbitable)).
                LOCAL pg_keep IS nd:PROGRADE.
                LOCAL nml_keep IS nd:NORMAL.
                LOCAL rad_keep IS nd:RADIALOUT.
                aoso_planechange_apply_to_node(nd, target_orbitable).
                aoso_yield().
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
                    aoso_yield().
                }
            }
        }
        aoso_rendezvous_tune_pe_keep(nd, target_orbitable).
        aoso_rendezvous_aim_prograde_departure(nd, target_orbitable).
        LOCAL pe_now IS aoso_rendezvous_orbit_pe(nd:ORBIT, target_orbitable).
        LOCAL want_pe IS aoso_rendezvous_desired_pe(target_orbitable).
        LOCAL pe_txt IS "".
        IF pe_now >= 0 { SET pe_txt TO " patchPE=" + ROUND(pe_now, 0) + " m want=" + ROUND(want_pe, 0) + "m". }
        LOCAL inc_p IS aoso_rendezvous_orbit_inc(nd:ORBIT, target_orbitable).
        IF inc_p >= 0 { SET pe_txt TO pe_txt + " patchInc=" + ROUND(inc_p, 1) + "deg". }
        IF aoso_rendezvous_pe_ok_value(pe_now, target_orbitable) {
            aoso_log_info("RENDEZVOUS", "Encounter with " + target_orbitable:NAME + " in " + ROUND(nd:ETA, 0) + "s dv=" + ROUND(nd:PROGRADE, 1) + " m/s" + pe_txt + ".").

            RETURN nd.
        }
        IF aoso_rendezvous_pe_rough_ok_value(pe_now, target_orbitable) {
            aoso_log_info("RENDEZVOUS", "Rough encounter with " + target_orbitable:NAME +
                " accepted for departure in " + ROUND(nd:ETA, 0) + "s dv=" +
                ROUND(nd:DELTAV:MAG, 1) + " m/s" + pe_txt +
                "; one PE-only mid-course if the live patch leaves the capture band.").

            RETURN nd.
        }
        aoso_log_warn("RENDEZVOUS", "Hohmann window is outside the safe rough encounter corridor " + pe_txt + " - retrying.").

        REMOVE nd.
        RETURN 0.
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

// Polar survey is an in-SOI plane change after a raised apoapsis (tour
// POLAR). It is not a coast objective. Chasing 90 deg from Kerbin burned
// a chain of mid-course corrections at transfer speed; plane change is
// 2*v*sin(theta/2) and that v is the expensive one. Callers that still
// ask get "not a coast error" so a capture-band PE is left alone.
FUNCTION aoso_rendezvous_polar_approach_error {
    PARAMETER orb.
    PARAMETER hop.
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

// Departure does not need to solve the final capture orbit. A direct,
// non-impacting target-body encounter is enough; the coast controller keeps
// the strict PE test above and retunes it later when the target geometry is
// much better conditioned. This is the normal rough-transfer -> mid-course
// -> capture workflow rather than orbit-after-orbit perfection hunting.
FUNCTION aoso_rendezvous_pe_rough_ok_value {
    PARAMETER pe.
    PARAMETER hop.
    IF pe < -0.5 { RETURN FALSE. }
    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL min_pe IS aoso_rendezvous_pe_min(hop, desired).
    IF pe < min_pe { RETURN FALSE. }

    LOCAL rough_mult IS aoso_config_get("INTERCEPT_ROUGH_PE_MAX_MULT", 8).
    IF rough_mult < 2.5 { SET rough_mult TO 2.5. }
    LOCAL max_pe IS desired * rough_mult.
    IF max_pe < desired + 40000 { SET max_pe TO desired + 40000. }

    LOCAL soi_frac IS aoso_config_get("INTERCEPT_ROUGH_SOI_FRAC", 0.18).
    IF soi_frac < 0.08 { SET soi_frac TO 0.08. }
    IF soi_frac > 0.35 { SET soi_frac TO 0.35. }
    LOCAL soi_cap IS aoso_rendezvous_soi_alt(hop) * soi_frac.
    IF max_pe > soi_cap { SET max_pe TO soi_cap. }

    IF pe > max_pe { RETURN FALSE. }
    RETURN TRUE.
}

FUNCTION aoso_rendezvous_orbit_needs_correct {
    PARAMETER orb.
    PARAMETER hop.
    // PE only. Inclination at the moon is whatever the prograde B-plane
    // produced; tour POLAR rotates it once, slow, after capture.
    RETURN NOT aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(orb, hop), hop).
}

FUNCTION aoso_rendezvous_clamp_prograde {
    PARAMETER nd.
    LOCAL radius IS SHIP:BODY:RADIUS + (APOAPSIS + PERIAPSIS) / 2.
    IF radius < SHIP:BODY:RADIUS + 1000 { SET radius TO SHIP:BODY:RADIUS + ALTITUDE. }
    LOCAL dv_max IS aoso_rendezvous_dv_max(radius).
    IF nd:PROGRADE > dv_max { SET nd:PROGRADE TO dv_max. }
}

// tune_pe scores an impact (~5e9) as worse than a 1 Mm graze (~1e8), so a
// hill climb can walk off a real encounter and the caller then deletes it.
// Put the node back when the score gets worse. Mid-course still calls
// tune_pe directly: that path needs the "reached a capture PE" boolean.
FUNCTION aoso_rendezvous_tune_pe_keep {
    PARAMETER nd.
    PARAMETER hop.
    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL pre_pg IS nd:PROGRADE.
    LOCAL pre_nml IS nd:NORMAL.
    LOCAL pre_rad IS nd:RADIALOUT.
    LOCAL pre_ut IS TIME:SECONDS + nd:ETA.
    LOCAL pre_pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL pre_sc IS aoso_rendezvous_pe_score(nd, hop, desired).
    aoso_rendezvous_tune_pe(nd, hop).
    aoso_rendezvous_settle().
    LOCAL post_pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL post_sc IS aoso_rendezvous_pe_score(nd, hop, desired).
    IF post_sc > pre_sc {
        SET nd:PROGRADE TO pre_pg.
        SET nd:NORMAL TO pre_nml.
        SET nd:RADIALOUT TO pre_rad.
        SET nd:ETA TO pre_ut - TIME:SECONDS.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_rendezvous_settle().
        aoso_log_warn("RENDEZVOUS", "PE tune worsened " + hop:NAME + " (PE " + ROUND(pre_pe, 0) + "m -> " + ROUND(post_pe, 0) + "m) - restored the pre-tune intercept.").
        RETURN FALSE.
    }
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
                    aoso_rendezvous_settle().
                }
            }
        }

        LOCAL orig_pg IS nd:PROGRADE.
        SET nd:PROGRADE TO orig_pg + step_dv.
        aoso_rendezvous_clamp_prograde(nd).
        aoso_rendezvous_settle().
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:PROGRADE TO orig_pg - step_dv.
            aoso_rendezvous_settle().
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
        aoso_rendezvous_settle().
        SET s TO aoso_rendezvous_pe_score(nd, hop, desired).
        IF s < best {
            SET best TO s.
            SET improved TO TRUE.
        } ELSE {
            SET nd:RADIALOUT TO orig_rad - step_dv.
            aoso_rendezvous_settle().
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
        IF rel_left >= 0.4 {
            SET nd:NORMAL TO orig_n + step_dv.
            aoso_rendezvous_settle().
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

// Build a polar SOI-edge aim point from the incoming hyperbolic velocity.
// The body's angular velocity gives its pole in the same raw frame as the
// Lambert vectors. Both polar directions are tried against KSP conics.
FUNCTION aoso_rendezvous_polar_soi_offset {
    PARAMETER hop.
    PARAMETER incoming.
    PARAMETER direction.
    LOCAL speed2 IS VDOT(incoming, incoming).
    LOCAL soi_radius IS hop:SOIRADIUS.
    LOCAL peri_radius IS hop:RADIUS + aoso_rendezvous_desired_pe(hop).
    LOCAL spin IS hop:ANGULARVEL.
    IF speed2 < 1 OR soi_radius <= peri_radius OR spin:MAG < 0.000001 { RETURN V(0, 0, 0). }
    LOCAL outward IS incoming * -1.
    LOCAL pole_normal IS VCRS(outward, spin).
    IF pole_normal:MAG < 0.000001 { RETURN V(0, 0, 0). }
    LOCAL entry_speed IS SQRT(speed2 + 2 * hop:MU * (1 / peri_radius - 1 / soi_radius)).
    LOCAL angular_momentum IS entry_speed * peri_radius.
    LOCAL reach2 IS speed2 * soi_radius * soi_radius - angular_momentum * angular_momentum.
    IF reach2 <= 0 { RETURN V(0, 0, 0). }
    LOCAL hvec IS pole_normal:NORMALIZED * angular_momentum * direction.
    RETURN (outward * SQRT(reach2) + VCRS(outward, hvec)) / speed2.
}

// Seed the mid-course node with a body-pole-aware SOI aim. The Lambert
// arrival velocity changes as the aim point moves, so refine it three times.
// Only a candidate with a real, safer KSP patched encounter is retained.
FUNCTION aoso_rendezvous_seed_polar_correction {
    PARAMETER nd.
    PARAMETER hop.
    PARAMETER arrival_ut.
    LOCAL departure_ut IS TIME:SECONDS + nd:ETA.
    LOCAL transit_s IS arrival_ut - departure_ut.
    IF transit_s < 120 { RETURN FALSE. }
    LOCAL parent_body IS SHIP:BODY.
    IF hop:BODY:NAME <> parent_body:NAME { RETURN FALSE. }
    LOCAL pos1 IS aoso_lambert_rel_pos(SHIP, departure_ut, parent_body).
    LOCAL body_pos IS aoso_lambert_rel_pos(hop, arrival_ut, parent_body).
    LOCAL vel_ship IS VELOCITYAT(SHIP, departure_ut):ORBIT.
    LOCAL vel_hop IS VELOCITYAT(hop, arrival_ut):ORBIT.
    LOCAL desired IS aoso_rendezvous_desired_pe(hop).
    LOCAL best_score IS aoso_rendezvous_pe_score(nd, hop, desired).
    LOCAL best_radial IS nd:RADIALOUT.
    LOCAL best_normal IS nd:NORMAL.
    LOCAL best_prograde IS nd:PROGRADE.
    LOCAL improved IS FALSE.
    LOCAL variant IS 0.
    UNTIL variant >= 4 {
        LOCAL long_way IS variant >= 2.
        LOCAL direction IS 1.
        IF variant = 1 OR variant = 3 { SET direction TO -1. }
        LOCAL aim_pos IS body_pos.
        LOCAL valid IS TRUE.
        LOCAL iter IS 0.
        LOCAL solution IS LEXICON("ok", FALSE).
        UNTIL iter >= 3 {
            SET solution TO aoso_lambert_solve(pos1, aim_pos, transit_s, parent_body:MU, long_way).
            IF NOT solution["ok"] {
                SET valid TO FALSE.
                BREAK.
            }
            LOCAL incoming IS solution["vel2"] - vel_hop.
            LOCAL offset IS aoso_rendezvous_polar_soi_offset(hop, incoming, direction).
            IF offset:MAG < 1 {
                SET valid TO FALSE.
                BREAK.
            }
            SET aim_pos TO body_pos + offset.
            SET iter TO iter + 1.
        }
        IF valid {
            SET solution TO aoso_lambert_solve(pos1, aim_pos, transit_s, parent_body:MU, long_way).
            IF solution["ok"] {
                LOCAL delta_v IS solution["vel1"] - vel_ship.
                IF delta_v:MAG <= aoso_config_get("MIDCOURSE_MAX_DV", 40) {
                    LOCAL xyz IS aoso_lambert_dv_to_node_xyz(delta_v, pos1, vel_ship).
                    SET nd:RADIALOUT TO xyz["radial"].
                    SET nd:NORMAL TO xyz["normal"].
                    SET nd:PROGRADE TO xyz["prograde"].
                    aoso_rendezvous_settle().
                    IF aoso_rendezvous_node_hits_body(nd, hop) {
                        LOCAL candidate_score IS aoso_rendezvous_pe_score(nd, hop, desired).
                        IF candidate_score < best_score {
                            SET best_score TO candidate_score.
                            SET best_radial TO nd:RADIALOUT.
                            SET best_normal TO nd:NORMAL.
                            SET best_prograde TO nd:PROGRADE.
                            SET improved TO TRUE.
                        }
                    }
                }
            }
        }
        SET variant TO variant + 1.
    }
    SET nd:RADIALOUT TO best_radial.
    SET nd:NORMAL TO best_normal.
    SET nd:PROGRADE TO best_prograde.
    aoso_rendezvous_settle().
    RETURN improved.
}

// Mid-course while on a live patch, or while its saved SOI clock is still
// available. A missing live patch never authorizes an unverified burn.
// Prograde SOI-edge aim (Jin Li patched conic, minimum inclination).
// The position is an offset from the body center in the same frame as the
// incoming Lambert velocity. Polar is intentionally not an option here:
// a polar B-plane at Mun/Minmus distance is a large plane change.
FUNCTION aoso_rendezvous_prograde_soi_offset {
    PARAMETER hop.
    PARAMETER incoming.
    PARAMETER peri_alt.
    LOCAL speed2 IS VDOT(incoming, incoming).
    IF speed2 < 1 { RETURN V(0, 0, 0). }
    LOCAL peri_r IS hop:RADIUS + peri_alt.
    LOCAL soi_r IS hop:SOIRADIUS.
    IF soi_r <= peri_r + 50 { RETURN V(0, 0, 0). }
    LOCAL mu_b IS hop:MU.
    LOCAL ve2 IS speed2 + mu_b * (2 / peri_r - 2 / soi_r).
    IF ve2 <= 0 { RETURN V(0, 0, 0). }
    LOCAL ve IS SQRT(ve2).
    LOCAL h_mag IS ve * peri_r.
    LOCAL n_plane IS incoming:X * incoming:X + incoming:Z * incoming:Z.
    IF n_plane < speed2 * 0.002 { RETURN V(0, 0, 0). }
    LOCAL cos_i IS SQRT(n_plane / speed2).
    LOCAL hscale IS h_mag * cos_i.
    LOCAL hx IS (-incoming:X * incoming:Y / n_plane) * hscale.
    LOCAL hy IS hscale.
    LOCAL hz IS (-incoming:Y * incoming:Z / n_plane) * hscale.
    LOCAL hvec IS V(hx, hy, hz).
    LOCAL reach2 IS speed2 * soi_r * soi_r - h_mag * h_mag.
    IF reach2 <= 1 { RETURN V(0, 0, 0). }
    LOCAL along IS SQRT(reach2).
    LOCAL cross_h IS VCRS(incoming, hvec).
    RETURN (incoming * along + cross_h) / speed2.
}

// One departure-side prograde aim. Kept only when KSP's own conic stays a
// direct hit, PE is at least as close to the capture altitude, and the
// burn does not grow by a plane-change. Otherwise the rough node is restored.
FUNCTION aoso_rendezvous_aim_prograde_departure {
    PARAMETER nd.
    PARAMETER hop.
    IF NOT aoso_rendezvous_node_hits_body(nd, hop) { RETURN FALSE. }
    IF hop:BODY:NAME <> SHIP:BODY:NAME { RETURN FALSE. }
    LOCAL parent_body IS SHIP:BODY.
    LOCAL t_dep IS TIME:SECONDS + nd:ETA.
    IF t_dep <= TIME:SECONDS + 30 { RETURN FALSE. }
    LOCAL t_arr IS 0.
    IF nd:ORBIT:HASNEXTPATCH {
        IF nd:ORBIT:NEXTPATCH:BODY:NAME = hop:NAME {
            IF nd:ORBIT:NEXTPATCH:HASSUFFIX("EPOCH") {
                SET t_arr TO nd:ORBIT:NEXTPATCH:EPOCH.
            }
        }
    }
    IF t_arr <= t_dep + 60 {
        SET t_arr TO t_dep + aoso_rendezvous_porkchop_tof_hoh(hop).
    }
    IF t_arr <= t_dep + 60 { RETURN FALSE. }
    LOCAL tof_s IS t_arr - t_dep.
    LOCAL keep_pg IS nd:PROGRADE.
    LOCAL keep_nml IS nd:NORMAL.
    LOCAL keep_rad IS nd:RADIALOUT.
    LOCAL keep_eta IS nd:ETA.
    LOCAL keep_pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL keep_dv IS nd:DELTAV:MAG.
    LOCAL pos1 IS aoso_lambert_rel_pos(SHIP, t_dep, parent_body).
    LOCAL body_pos IS aoso_lambert_rel_pos(hop, t_arr, parent_body).
    LOCAL vel_ship IS VELOCITYAT(SHIP, t_dep):ORBIT.
    LOCAL vel_hop IS VELOCITYAT(hop, t_arr):ORBIT.
    LOCAL peri_alt IS aoso_rendezvous_desired_pe(hop).
    LOCAL aim_pos IS body_pos.
    LOCAL sol IS LEXICON("ok", FALSE).
    LOCAL incoming IS V(0, 0, 0).
    LOCAL offset IS V(0, 0, 0).
    LOCAL use_long IS FALSE.
    LOCAL iter IS 0.
    UNTIL iter >= 6 {
        SET sol TO aoso_lambert_solve(pos1, aim_pos, tof_s, parent_body:MU, use_long).
        IF NOT sol["ok"] {
            IF iter = 0 {
                SET use_long TO TRUE.
                SET sol TO aoso_lambert_solve(pos1, aim_pos, tof_s, parent_body:MU, use_long).
            }
        }
        IF NOT sol["ok"] { RETURN FALSE. }
        SET incoming TO sol["vel2"] - vel_hop.
        SET offset TO aoso_rendezvous_prograde_soi_offset(hop, incoming, peri_alt).
        IF offset:MAG < 1 { RETURN FALSE. }
        SET aim_pos TO body_pos + offset.
        SET iter TO iter + 1.
    }
    SET sol TO aoso_lambert_solve(pos1, aim_pos, tof_s, parent_body:MU, use_long).
    IF NOT sol["ok"] { RETURN FALSE. }
    LOCAL dv_vec IS sol["vel1"] - vel_ship.
    LOCAL extra_cap IS aoso_config_get("DEPARTURE_AIM_MAX_EXTRA_DV", 40).
    IF extra_cap < 15 { SET extra_cap TO 15. }
    IF extra_cap > 80 { SET extra_cap TO 80. }
    IF dv_vec:MAG > keep_dv + extra_cap {
        aoso_log_info("RENDEZVOUS", "Prograde SOI aim for " + hop:NAME + " costs +" +
            ROUND(dv_vec:MAG - keep_dv, 1) + " m/s - keeping the rough intercept.").
        RETURN FALSE.
    }
    LOCAL xyz IS aoso_lambert_dv_to_node_xyz(dv_vec, pos1, vel_ship).
    SET nd:RADIALOUT TO xyz["radial"].
    SET nd:NORMAL TO xyz["normal"].
    SET nd:PROGRADE TO xyz["prograde"].
    aoso_rendezvous_clamp_prograde(nd).
    aoso_rendezvous_settle().
    LOCAL new_pe IS aoso_rendezvous_orbit_pe(nd:ORBIT, hop).
    LOCAL hit_ok IS aoso_rendezvous_node_hits_body(nd, hop).
    LOCAL keep_err IS ABS(keep_pe - peri_alt).
    LOCAL new_err IS ABS(new_pe - peri_alt).
    LOCAL aim_ok IS FALSE.
    IF hit_ok {
        IF aoso_rendezvous_pe_rough_ok_value(new_pe, hop) {
            IF new_err <= keep_err + 500 { SET aim_ok TO TRUE. }
        }
    }
    // Native porkchop deletes the winner if PE leaves the capture band
    // after this aim. A node that was already inside the band must stay
    // there; otherwise restore the rough intercept.
    IF aim_ok {
        IF aoso_rendezvous_pe_ok_value(keep_pe, hop) {
            IF NOT aoso_rendezvous_pe_ok_value(new_pe, hop) { SET aim_ok TO FALSE. }
        }
    }
    IF NOT aim_ok {
        SET nd:PROGRADE TO keep_pg.
        SET nd:NORMAL TO keep_nml.
        SET nd:RADIALOUT TO keep_rad.
        SET nd:ETA TO keep_eta.
        IF nd:ETA < 25 { SET nd:ETA TO 25. }
        aoso_rendezvous_settle().
        aoso_log_info("RENDEZVOUS", "Prograde SOI aim did not improve " + hop:NAME +
            " (PE " + ROUND(keep_pe, 0) + "m -> " + ROUND(new_pe, 0) + "m) - keeping the rough intercept.").
        RETURN FALSE.
    }
    LOCAL inc_p IS aoso_rendezvous_orbit_inc(nd:ORBIT, hop).
    aoso_log_info("RENDEZVOUS", "Departure aim prograde " + hop:NAME +
        " PE=" + ROUND(new_pe, 0) + "m inc=" + ROUND(inc_p, 1) + "deg dv=" +
        ROUND(nd:DELTAV:MAG, 1) + " m/s (was PE=" + ROUND(keep_pe, 0) + "m dv=" +
        ROUND(keep_dv, 1) + ").").
    RETURN TRUE.
}

// Mid-course while on a live patch. A missing live patch never authorizes
// an unverified burn. Polar inclination is not a reason to correct.
FUNCTION aoso_rendezvous_add_correction_node {
    PARAMETER hop.
    PARAMETER arrival_ut IS 0.
    LOCAL live_patch IS SHIP:ORBIT:HASNEXTPATCH.
    IF NOT live_patch { RETURN 0. }

    // tune_pe() deliberately yields so patched conics can settle. Never enter
    // it while packed/rails/unpacking. The 17.6-day Minmus run spent most of
    // its bad recovery loop here because WAIT 0 was executed before 1x physics
    // had actually settled.
    IF NOT aoso_warp_ensure_physics_idle() { RETURN 0. }

    LOCAL pe_now IS aoso_rendezvous_orbit_pe(SHIP:ORBIT, hop).
    // A capture-band PE on a direct patch is finished. Another moon as the
    // first SOI still needs a repair; that fails ship_hits_body.
    IF aoso_rendezvous_pe_ok_value(pe_now, hop) {
        IF aoso_rendezvous_ship_hits_body(hop) { RETURN 0. }
    }

    LOCAL eta_p IS SHIP:ORBIT:NEXTPATCHETA.
    IF eta_p < 150 { RETURN 0. }
    // Place the burn soon: hours-out nodes overshoot on rails (Acacius
    // 11 h / 0.3 placement, ETA -360, never aligned). A few minutes is
    // still early enough for a few m/s to move PE.
    LOCAL t_corr IS eta_p * 0.15.
    IF t_corr > 720 { SET t_corr TO 720. }
    IF t_corr > eta_p - 180 { SET t_corr TO eta_p - 180. }
    IF t_corr < 45 { SET t_corr TO 45. }

    LOCAL nd IS NODE(TIME:SECONDS + t_corr, 0, 0, 0).
    ADD nd.
    SET AOSO_POLAR_MIDCOURSE_TUNING TO FALSE.
    LOCAL tuned IS aoso_rendezvous_tune_pe(nd, hop).
    IF NOT tuned {
        aoso_log_warn("RENDEZVOUS", "Mid-course tune did not reach a safe capture PE - leaving the coast as-is.").
        REMOVE nd.
        RETURN 0.
    }
    IF NOT aoso_rendezvous_node_hits_body(nd, hop) {
        aoso_log_warn("RENDEZVOUS", "Mid-course tune lost the " + hop:NAME + " patch - leaving the coast as-is.").
        REMOVE nd.
        RETURN 0.
    }
    LOCAL dv_cap IS aoso_config_get("MIDCOURSE_MAX_DV", 40).
    IF nd:DELTAV:MAG > dv_cap {
        LOCAL shrink IS dv_cap / nd:DELTAV:MAG.
        SET nd:PROGRADE TO nd:PROGRADE * shrink.
        SET nd:RADIALOUT TO nd:RADIALOUT * shrink.
        SET nd:NORMAL TO nd:NORMAL * shrink.
        aoso_rendezvous_settle().
        IF NOT aoso_rendezvous_node_hits_body(nd, hop) {
            aoso_log_warn("RENDEZVOUS", "Capped correction lost the " + hop:NAME + " patch - leaving coast as-is.").
            REMOVE nd.
            RETURN 0.
        }
        IF NOT aoso_rendezvous_pe_ok_value(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), hop) {
            aoso_log_warn("RENDEZVOUS", "Capped correction lost the safe capture PE - leaving coast as-is.").
            REMOVE nd.
            RETURN 0.
        }
    }
    IF nd:DELTAV:MAG < 0.8 {
        REMOVE nd.
        RETURN 0.
    }
    IF nd:DELTAV:MAG > dv_cap + 0.01 {
        aoso_log_warn("RENDEZVOUS", "Mid-course dv=" + ROUND(nd:DELTAV:MAG, 1) + " exceeds cap - leaving coast, replan later.").
        REMOVE nd.
        RETURN 0.
    }
    aoso_log_info("RENDEZVOUS", "Mid-course PE correction dv=" + ROUND(nd:DELTAV:MAG, 1) +
        " m/s, PE " + ROUND(pe_now, 0) + " -> " + ROUND(aoso_rendezvous_orbit_pe(nd:ORBIT, hop), 0) + "m.").
    RETURN nd.
}
