// AOSO/interplanetary/transfer.ks
// Heliocentric transfer-window math between two bodies that share the same
// parent (i.e. both orbit the same star directly, e.g. Kerbin -> Duna),
// generalizing nav/rendezvous.ks's phase-angle/wait-time approach from
// vessel-vs-target to body-vs-body. Assumes both bodies' orbits are
// near-circular and mutually coplanar for the transfer-time/dv estimates --
// the same simplification rendezvous.ks makes for target-radius/transfer
// time, and accurate enough for stock-system patched-conic planning. Full
// eccentric/inclined Lambert solving is out of scope here (see
// core/addons.ks's note on why Astrogator isn't driven directly). Builds
// only on nav/orbit.ks helpers -- no new stock suffixes.

// Sun-relative ("heliocentric") position of a body right now. Reuses
// nav/orbit.ks's parent-relative helper; valid for dep_body/arr_body only
// when both orbit the same star directly (checked by callers via
// aoso_interplanetary_share_parent).
FUNCTION aoso_interplanetary_heliocentric_position {
    PARAMETER body_ref.
    RETURN aoso_interplanetary_heliocentric_position_at(body_ref, TIME:SECONDS).
}

// Same geometry at an arbitrary universal time. This is the planner-facing
// equivalent of an ephemeris query: stock KSP's own Kepler propagation is
// authoritative, so AOSO does not carry a separate SPICE/n-body model.
FUNCTION aoso_interplanetary_heliocentric_position_at {
    PARAMETER body_ref.
    PARAMETER at_ut.
    RETURN aoso_orbit_position_at(body_ref, at_ut).
}

FUNCTION aoso_interplanetary_share_parent {
    PARAMETER dep_body.
    PARAMETER arr_body.
    RETURN dep_body:BODY:NAME = arr_body:BODY:NAME.
}

// Semi-major axis (m) of the Hohmann transfer ellipse between dep_body's and
// arr_body's (assumed near-circular) heliocentric orbits.
FUNCTION aoso_interplanetary_transfer_sma {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL r1 IS dep_body:ORBIT:SEMIMAJORAXIS.
    LOCAL r2 IS arr_body:ORBIT:SEMIMAJORAXIS.
    RETURN (r1 + r2) / 2.
}

// One-way transfer time (s): half the transfer ellipse's period.
FUNCTION aoso_interplanetary_transfer_time_s {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL mu IS dep_body:BODY:MU.
    LOCAL sma_t IS aoso_interplanetary_transfer_sma(dep_body, arr_body).
    RETURN CONSTANT:PI * SQRT(sma_t ^ 3 / mu).
}

// Signed heliocentric delta-v (m/s) needed at departure: positive means
// speed up (prograde, for an outer target), negative means slow down
// (retrograde, for an inner target). This is dep_body's own required
// velocity change, i.e. the hyperbolic-excess speed the ship must add on
// top of dep_body's orbital velocity once it leaves dep_body's SOI.
FUNCTION aoso_interplanetary_v_infinity_signed {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL mu IS dep_body:BODY:MU.
    LOCAL r1 IS dep_body:ORBIT:SEMIMAJORAXIS.
    LOCAL sma_t IS aoso_interplanetary_transfer_sma(dep_body, arr_body).
    LOCAL v_circ IS SQRT(mu / r1).
    LOCAL v_transfer IS SQRT(MAX(0, mu * (2 / r1 - 1 / sma_t))).
    RETURN v_transfer - v_circ.
}

// Signed phase angle (deg) from dep_body to arr_body around their shared
// parent, positive when arr_body is ahead of dep_body in the direction of
// dep_body's orbital motion. Mirrors nav/rendezvous.ks's
// aoso_rendezvous_phase_angle_deg, generalized to body-vs-body.
FUNCTION aoso_interplanetary_phase_angle_deg {
    PARAMETER dep_body.
    PARAMETER arr_body.
    RETURN aoso_interplanetary_phase_angle_deg_at(dep_body, arr_body, TIME:SECONDS).
}

FUNCTION aoso_interplanetary_phase_angle_deg_at {
    PARAMETER dep_body.
    PARAMETER arr_body.
    PARAMETER at_ut.
    LOCAL pos_dep IS aoso_interplanetary_heliocentric_position_at(dep_body, at_ut).
    LOCAL pos_arr IS aoso_interplanetary_heliocentric_position_at(arr_body, at_ut).
    LOCAL ang IS VANG(pos_dep, pos_arr).
    LOCAL na IS aoso_orbit_normal_at(dep_body, at_ut).
    IF VDOT(VCRS(pos_dep, pos_arr), na) < 0 { SET ang TO -ang. }
    RETURN ang.
}

// Phase angle (deg) arr_body must lead dep_body by, right now, for a
// departure today to arrive where arr_body will have coasted to.
FUNCTION aoso_interplanetary_required_phase_angle_deg {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL transfer_time IS aoso_interplanetary_transfer_time_s(dep_body, arr_body).
    LOCAL arr_travel_deg IS 360 * transfer_time / arr_body:ORBIT:PERIOD.
    RETURN 180 - arr_travel_deg.
}

// Seconds to wait until the current dep_body/arr_body phase angle reaches
// the required transfer-window phase angle. Returns -1 if the two bodies'
// periods are equal (phase angle never changes).
FUNCTION aoso_interplanetary_wait_time_to_window_s {
    PARAMETER dep_body.
    PARAMETER arr_body.
    RETURN aoso_interplanetary_wait_time_to_window_s_at(dep_body, arr_body, TIME:SECONDS).
}

FUNCTION aoso_interplanetary_synodic_s {
    PARAMETER dep_body.
    PARAMETER arr_body.
    LOCAL dep_rate IS 1 / dep_body:ORBIT:PERIOD.
    LOCAL arr_rate IS 1 / arr_body:ORBIT:PERIOD.
    LOCAL rel IS ABS(dep_rate - arr_rate).
    IF rel <= 0 { RETURN 0. }
    RETURN 1 / rel.
}

FUNCTION aoso_interplanetary_wait_time_to_window_s_at {
    PARAMETER dep_body.
    PARAMETER arr_body.
    PARAMETER at_ut.
    LOCAL current_phase IS aoso_interplanetary_phase_angle_deg_at(dep_body, arr_body, at_ut).
    LOCAL required_phase IS aoso_interplanetary_required_phase_angle_deg(dep_body, arr_body).

    LOCAL dep_rate IS 360 / dep_body:ORBIT:PERIOD.
    LOCAL arr_rate IS 360 / arr_body:ORBIT:PERIOD.
    LOCAL relative_rate IS dep_rate - arr_rate.
    IF relative_rate = 0 { RETURN -1. }

    LOCAL wait_s IS -(current_phase - required_phase) / relative_rate.
    LOCAL syn_s IS 360 / ABS(relative_rate).
    UNTIL wait_s >= 0 {
        SET wait_s TO wait_s + syn_s.
    }
    UNTIL wait_s < syn_s {
        SET wait_s TO wait_s - syn_s.
    }
    RETURN wait_s.
}

// ---------------------------------------------------------------------
// Native planetary Lambert porkchop
// ---------------------------------------------------------------------
// Real interplanetary planning in stock KSP does not need n-body/SPICE.
// Search KSP's own future body ephemerides for departure UT x flight time,
// then let ejection.ks validate the winning candidates with stock patched
// conics before any burn is accepted.

FUNCTION aoso_interplanetary_desired_pe {
    PARAMETER target_body.
    IF target_body:ATM:EXISTS {
        RETURN MAX(aoso_config_get("PARKING_ORBIT_ALT", 100000), target_body:ATM:HEIGHT + 15000).
    }
    RETURN MAX(15000, target_body:RADIUS * 0.08).
}

FUNCTION aoso_interplanetary_time_cost_day {
    LOCAL mode IS aoso_config_get("OPTIMIZATION_MODE", "BALANCED").
    IF mode = "TIME" { RETURN aoso_config_get("INTERPLANETARY_TIME_COST_DAY_TIME", 80). }
    IF mode = "MINIMUM_DV" OR mode = "FUEL" {
        RETURN aoso_config_get("INTERPLANETARY_TIME_COST_DAY_DV", 5).
    }
    IF mode = "SAFETY" { RETURN aoso_config_get("INTERPLANETARY_TIME_COST_DAY_SAFETY", 20). }
    RETURN aoso_config_get("INTERPLANETARY_TIME_COST_DAY", 20).
}

FUNCTION aoso_interplanetary_native_search {
    PARAMETER target_body.
    IF NOT aoso_addon_native_interplanetary_available() { RETURN 0. }
    IF NOT aoso_interplanetary_share_parent(SHIP:BODY, target_body) { RETURN 0. }

    LOCAL now_ut IS TIME:SECONDS.
    LOCAL syn_s IS aoso_interplanetary_synodic_s(SHIP:BODY, target_body).
    IF syn_s <= 0 { SET syn_s TO aoso_config_get("INTERPLANETARY_SEARCH_FALLBACK_S", 5000000). }
    LOCAL horizon_cap IS aoso_config_get("INTERPLANETARY_SEARCH_HORIZON_S", 0).
    IF horizon_cap > 0 {
        IF syn_s > horizon_cap { SET syn_s TO horizon_cap. }
    }

    LOCAL tof_h IS aoso_interplanetary_transfer_time_s(SHIP:BODY, target_body).
    LOCAL tof_min IS tof_h * aoso_config_get("INTERPLANETARY_TOF_MIN", 0.55).
    LOCAL tof_max IS tof_h * aoso_config_get("INTERPLANETARY_TOF_MAX", 1.8).
    IF tof_min < 600 { SET tof_min TO 600. }
    IF tof_max < tof_min + 600 { SET tof_max TO tof_min + 600. }

    LOCAL opts IS LEXICON(
        "dep_samples", aoso_config_get("INTERPLANETARY_DEP_SAMPLES", 48),
        "tof_samples", aoso_config_get("INTERPLANETARY_TOF_SAMPLES", 28),
        "refine_seeds", aoso_config_get("INTERPLANETARY_REFINE_SEEDS", 6),
        "start_ut", now_ut + 120,
        "end_ut", now_ut + syn_s,
        "tof_min_s", tof_min,
        "tof_max_s", tof_max,
        "desired_pe", aoso_interplanetary_desired_pe(target_body),
        "parking_radius", SHIP:ORBIT:SEMIMAJORAXIS,
        "time_cost_day", aoso_interplanetary_time_cost_day()
    ).

    aoso_log_info("TRANSFER", "Native planetary porkchop " + SHIP:BODY:NAME + " -> " +
        target_body:NAME + " searching one practical window: " +
        ROUND((opts["end_ut"] - opts["start_ut"]) / 21600, 1) + "d departure span, TOF " +
        ROUND(tof_min / 21600, 1) + ".." + ROUND(tof_max / 21600, 1) + "d.").

    LOCAL st IS aoso_addon_native_interplanetary_start(target_body, opts).
    IF NOT st:ISTYPE("Lexicon") { RETURN 0. }
    IF NOT st["ok"] {
        aoso_log_warn("TRANSFER", "Native planetary porkchop start failed: " + st["err"] + ".").
        RETURN 0.
    }

    LOCAL polls IS 0.
    LOCAL pulse_at IS 12.
    LOCAL max_polls IS aoso_config_get("INTERPLANETARY_MAX_POLLS", 600).
    UNTIL st["done"] OR polls >= max_polls {
        WAIT 0.
        SET st TO aoso_addon_native_interplanetary_poll().
        IF NOT st:ISTYPE("Lexicon") { RETURN 0. }
        IF NOT st["ok"] {
            aoso_log_warn("TRANSFER", "Native planetary porkchop poll failed: " + st["err"] + ".").
            RETURN 0.
        }
        SET polls TO polls + 1.
        IF polls >= pulse_at {

            SET pulse_at TO pulse_at + 12.
        }
    }

    IF NOT st["done"] {
        aoso_log_warn("TRANSFER", "Native planetary porkchop timed out after " + polls + " polls.").
        RETURN 0.
    }

    LOCAL res IS aoso_addon_native_interplanetary_result().
    IF NOT res:ISTYPE("Lexicon") { RETURN 0. }
    IF NOT res["ok"] {
        aoso_log_warn("TRANSFER", "Native planetary porkchop result failed: " + res["err"] + ".").
        RETURN 0.
    }

    aoso_log_info("TRANSFER", "Native planetary porkchop finished: " + res["n_done"] +
        " cells, " + res["n_valid"] + " Lambert solutions, " + res["cands"]:LENGTH + " finalists.").
    RETURN res.
}

FUNCTION aoso_interplanetary_candidate_vinf {
    PARAMETER dep_body.
    PARAMETER arr_body.
    PARAMETER cand.

    LOCAL dep_ut IS cand["dep_ut"].
    LOCAL arr_ut IS cand["arr_ut"].
    LOCAL tof_s IS arr_ut - dep_ut.
    IF tof_s <= 30 { RETURN LEXICON("ok", FALSE). }

    LOCAL parent IS dep_body:BODY.
    LOCAL pos1 IS aoso_orbit_position_at(dep_body, dep_ut).
    LOCAL pos2 IS aoso_orbit_position_at(arr_body, arr_ut).
    LOCAL sol IS aoso_lambert_solve(pos1, pos2, tof_s, parent:MU, cand["long_way"]).
    IF NOT sol["ok"] { RETURN LEXICON("ok", FALSE). }

    LOCAL dep_vel IS aoso_orbit_velocity_at(dep_body, dep_ut).
    LOCAL arr_vel IS aoso_orbit_velocity_at(arr_body, arr_ut).
    LOCAL vinf_out IS sol["vel1"] - dep_vel.
    LOCAL vinf_in IS sol["vel2"] - arr_vel.
    RETURN LEXICON(
        "ok", TRUE,
        "dep_ut", dep_ut,
        "arr_ut", arr_ut,
        "tof", tof_s,
        "vinf_out", vinf_out,
        "vinf_in", vinf_in,
        "vinf_out_mag", vinf_out:MAG,
        "vinf_in_mag", vinf_in:MAG,
        "long_way", cand["long_way"]
    ).
}

