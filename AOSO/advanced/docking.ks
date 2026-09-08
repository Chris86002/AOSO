// AOSO/advanced/docking.ks
// Phase 11 (Advanced): final-approach and docking autopilot, the piece
// nav/rendezvous.ks and interplanetary/ejection.ks both explicitly deferred
// ("precision timing/final-approach refinement belongs to a later phase")
// once a ship is already in the target's neighborhood. Assumes
// nav/rendezvous.ks (or an equivalent manual/MechJeb rendezvous) has
// already closed the gross orbital gap and TARGET is set to a docking port
// on the vessel to dock with.
//
// Built on core/state.ks as its own machine (AOSO_DOCKING), the same
// pattern every other autonomous subsystem in this repo uses. Two states
// only: APPROACH (close from wherever the ship currently is onto a
// stand-off waypoint offset out along the target port's own facing axis)
// and FINAL (slow, direct closing from that waypoint onto the port itself).
// Steering and translation are always computed relative to the ship's own
// docking port -- selected once at start and locked in as the control
// reference via PART:CONTROLFROM(), the documented kOS way to make
// SHIP:FACING and the SHIP:CONTROL:FORE/TOP/STARBOARD translation axes mean
// "this part's nose/top/starboard" instead of the root part's -- so the
// autopilot works regardless of where the docking port is mounted on the
// vessel. Translation is a simple proportional controller on the ship's
// velocity relative to the target vessel (not a full 6-DOF/PID solution;
// consistent with nav/rendezvous.ks's own near-circular-orbit
// simplification, this assumes a slow, already-close final approach, not
// an arbitrary high-speed intercept).

GLOBAL AOSO_DOCKING IS aoso_state_new_machine().

// --- Own-vessel docking port selection ------------------------------------

// First docking port on the active vessel that is actually free to dock
// with (STATE "Ready"; anything else -- "Docked (...)"/"PreAttached"/
// "Disabled" -- is skipped). Returns 0 if none is available.
FUNCTION aoso_docking_own_port {
    LOCAL doclist IS LIST().
    LIST DOCKINGPORTS IN doclist.
    FOR p IN doclist {
        IF p:STATE = "Ready" { RETURN p. }
    }
    RETURN 0.
}

// TRUE once both a target docking port and a free own port exist, i.e. it
// is safe to call aoso_docking_start().
FUNCTION aoso_docking_available {
    IF NOT HASTARGET { RETURN FALSE. }
    IF NOT TARGET:ISTYPE("DockingPort") { RETURN FALSE. }
    RETURN aoso_docking_own_port() <> 0.
}

// TRUE while TARGET is still a valid docking port to fly toward (lost if
// the operator clears TARGET or the target vessel is destroyed/undocked
// mid-approach).
FUNCTION aoso_docking_target_ok {
    RETURN HASTARGET AND TARGET:ISTYPE("DockingPort").
}

// % of MonoPropellant remaining across the whole vessel, mirroring
// vehicle/resources.ks's stage-propellant reserve check but for the whole
// ship (RCS draws from every connected tank, not just the current stage).
// Returns 100 (never a limiting factor) if the vessel carries no
// MonoPropellant at all, e.g. an all-cold-gas or ModuleRCSFX vehicle.
FUNCTION aoso_docking_monoprop_pct {
    FOR r IN SHIP:RESOURCES {
        IF r:NAME = "MonoPropellant" {
            IF r:CAPACITY <= 0 { RETURN 100. }
            RETURN 100 * r:AMOUNT / r:CAPACITY.
        }
    }
    RETURN 100.
}

// TRUE once own_port's STATE shows it has actually mated with the target,
// the only reliable "we are docked" signal kOS exposes (there is no
// separate "on docked" event/suffix).
FUNCTION aoso_docking_is_docked {
    PARAMETER own_port.
    IF own_port = 0 { RETURN FALSE. }
    RETURN own_port:STATE:CONTAINS("Docked").
}

// --- Translation control ---------------------------------------------------

FUNCTION aoso_docking_clamp {
    PARAMETER value.
    PARAMETER lo.
    PARAMETER hi.
    RETURN MIN(MAX(value, lo), hi).
}

// Drives SHIP:CONTROL:FORE/TOP/STARBOARD toward zero, used whenever the
// autopilot should stop translating (still turning to face the port,
// docked, done, or aborted).
FUNCTION aoso_docking_zero_translation {
    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:TOP TO 0.
    SET SHIP:CONTROL:STARBOARD TO 0.
}

// Proportional translation controller: closes on rel_pos (a point relative
// to the ship, e.g. TARGET:POSITION with an optional stand-off offset
// added) at a speed proportional to the remaining distance, capped at
// max_speed_mps, by comparing the ship's velocity relative to the target
// vessel against the desired closing velocity and commanding RCS
// translation proportional to the difference along the (now port-relative,
// thanks to CONTROLFROM) SHIP:FACING axes.
FUNCTION aoso_docking_translate_toward {
    PARAMETER rel_pos.
    PARAMETER target_port.
    PARAMETER max_speed_mps.

    LOCAL dist IS rel_pos:MAG.
    IF dist <= 0.01 {
        aoso_docking_zero_translation().
        RETURN.
    }

    LOCAL closing_gain IS aoso_config_get("DOCKING_CLOSING_GAIN", 0.3).
    LOCAL desired_speed IS MIN(max_speed_mps, dist * closing_gain).
    LOCAL desired_vel IS rel_pos:NORMALIZED * desired_speed.

    LOCAL target_vel IS target_port:SHIP:VELOCITY:ORBIT.
    LOCAL current_rel_vel IS SHIP:VELOCITY:ORBIT - target_vel.
    LOCAL vel_error IS desired_vel - current_rel_vel.

    LOCAL rcs_gain IS aoso_config_get("DOCKING_RCS_GAIN", 0.5).
    LOCAL fore_cmd IS aoso_docking_clamp(VDOT(vel_error, SHIP:FACING:FOREVECTOR) * rcs_gain, -1, 1).
    LOCAL top_cmd IS aoso_docking_clamp(VDOT(vel_error, SHIP:FACING:TOPVECTOR) * rcs_gain, -1, 1).
    LOCAL star_cmd IS aoso_docking_clamp(VDOT(vel_error, SHIP:FACING:STARVECTOR) * rcs_gain, -1, 1).

    SET SHIP:CONTROL:FORE TO fore_cmd.
    SET SHIP:CONTROL:TOP TO top_cmd.
    SET SHIP:CONTROL:STARBOARD TO star_cmd.
}

// --- State machine ----------------------------------------------------------

FUNCTION aoso_docking_on_abort {
    PARAMETER data.
    aoso_docking_zero_translation().
    aoso_steer_release().
    aoso_state_transition(AOSO_DOCKING, "ABORTED").
}

// Shared guard used by both APPROACH and FINAL: bails out to ABORTED if the
// target port has been lost or RCS propellant is critically low. Returns
// TRUE if the caller should stop (an abort was triggered).
FUNCTION aoso_docking_check_abort {
    IF NOT aoso_docking_target_ok() {
        IF DEFINED aoso_log_error { aoso_log_error("DOCKING", "Target docking port lost."). }
        aoso_state_abort(AOSO_DOCKING).
        RETURN TRUE.
    }
    IF aoso_docking_monoprop_pct() <= aoso_config_get("ABORT_FUEL_PCT", 3) {
        IF DEFINED aoso_log_warn { aoso_log_warn("DOCKING", "MonoPropellant at/below abort threshold."). }
        aoso_state_abort(AOSO_DOCKING).
        RETURN TRUE.
    }
    RETURN FALSE.
}

FUNCTION aoso_docking_approach_entry {
    PARAMETER data.
    RCS ON.
    data["own_port"]:CONTROLFROM().
    IF DEFINED aoso_log_info { aoso_log_info("DOCKING", "Approach started toward " + TARGET:NAME + "."). }
}

FUNCTION aoso_docking_approach_execute {
    PARAMETER data.
    IF aoso_docking_check_abort() { RETURN. }

    LOCAL tport IS TARGET.
    LOCAL standoff IS tport:PORTFACING:VECTOR * aoso_config_get("DOCKING_STANDOFF_DIST", 30).
    LOCAL hold_point IS tport:POSITION + standoff.
    LOCAL face_target IS -tport:PORTFACING:VECTOR.

    aoso_steer_to_vector(face_target).
    IF aoso_steer_is_aligned(face_target, aoso_config_get("DOCKING_ALIGN_TOLERANCE_DEG", 5)) {
        aoso_docking_translate_toward(hold_point, tport, aoso_config_get("DOCKING_MAX_APPROACH_SPEED", 2)).
    } ELSE {
        aoso_docking_zero_translation().
    }

    IF hold_point:MAG <= aoso_config_get("DOCKING_WAYPOINT_TOLERANCE_M", 2) {
        aoso_state_transition(AOSO_DOCKING, "FINAL").
    }
}

FUNCTION aoso_docking_final_execute {
    PARAMETER data.
    IF aoso_docking_check_abort() { RETURN. }

    IF aoso_docking_is_docked(data["own_port"]) {
        aoso_state_transition(AOSO_DOCKING, "DONE").
        RETURN.
    }

    LOCAL tport IS TARGET.
    LOCAL face_target IS -tport:PORTFACING:VECTOR.
    aoso_steer_to_vector(face_target).
    aoso_docking_translate_toward(tport:POSITION, tport, aoso_config_get("DOCKING_MAX_FINAL_SPEED", 0.3)).
}

FUNCTION aoso_docking_done_entry {
    PARAMETER data.
    aoso_docking_zero_translation().
    aoso_steer_release().
    IF DEFINED aoso_log_info { aoso_log_info("DOCKING", "Docked."). }
}

FUNCTION aoso_docking_aborted_entry {
    PARAMETER data.
    aoso_docking_zero_translation().
    aoso_steer_release().
    IF DEFINED aoso_log_error { aoso_log_error("DOCKING", "Docking aborted."). }
}

FUNCTION aoso_docking_define_states {
    aoso_state_define(AOSO_DOCKING, "APPROACH", aoso_docking_approach_entry@, aoso_docking_approach_execute@, 0, 0, 0, aoso_docking_on_abort@).
    aoso_state_define(AOSO_DOCKING, "FINAL", 0, aoso_docking_final_execute@, 0, 0, 0, aoso_docking_on_abort@).
    aoso_state_define(AOSO_DOCKING, "DONE", aoso_docking_done_entry@, 0, 0).
    aoso_state_define(AOSO_DOCKING, "ABORTED", aoso_docking_aborted_entry@, 0, 0).
}

// Entry point: TARGET must already be set to the docking port to approach
// (aoso_docking_available() checks this plus a free own port) before
// calling. Drive the machine every tick with aoso_docking_update()
// (directly, or via aoso_docking_register_task()).
FUNCTION aoso_docking_start {
    aoso_docking_define_states().

    LOCAL own_port IS aoso_docking_own_port().
    IF own_port = 0 OR NOT aoso_docking_target_ok() {
        IF DEFINED aoso_log_error { aoso_log_error("DOCKING", "No free own docking port or no target docking port set."). }
        SET AOSO_DOCKING["data"] TO LEXICON("own_port", 0).
        aoso_state_transition(AOSO_DOCKING, "ABORTED").
        RETURN.
    }

    SET AOSO_DOCKING["data"] TO LEXICON("own_port", own_port).
    aoso_state_transition(AOSO_DOCKING, "APPROACH").
}

FUNCTION aoso_docking_update {
    aoso_state_update(AOSO_DOCKING).
}

FUNCTION aoso_docking_register_task {
    PARAMETER interval_s IS 0.05.
    IF DEFINED aoso_sched_add {
        aoso_sched_add("docking", interval_s, aoso_docking_update@).
    }
}

FUNCTION aoso_docking_is_done {
    RETURN AOSO_DOCKING["current"] = "DONE".
}

FUNCTION aoso_docking_is_aborted {
    RETURN AOSO_DOCKING["current"] = "ABORTED".
}
