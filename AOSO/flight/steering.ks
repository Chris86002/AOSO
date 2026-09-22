// AOSO/flight/steering.ks
// Thin wrappers around native kOS STEERING locks so every flight/guidance
// module commands attitude the same way. MechJeb's SmartASS is deliberately
// not used here (see core/addons.ks reasoning on not guessing at its
// suffixes) -- native kOS STEERING is correct on every install.
//
// WHY lock-once: LOCK expressions re-eval every physics tick at trigger
// priority; locking to a user function burns IPU/EC at 25 Hz. Commanded
// throttle/steering therefore live in cheap globals. Callers SET the
// global each tick; the LOCK is issued once and just reads the global.
// Tracking modes (PROGRADE etc.) lock the native suffix once and return.
//
// Roll: HEADING() and LOCK STEERING TO a Vector both try to roll upright.
// A 44 m lander-can stack hunting that roll spun navball heading 345→270
// and oscillated through burns. Command LOOKDIRUP(look, current top) and
// keep ROLLCONTROLANGLERANGE tiny so the roll PID does not fight.

GLOBAL AOSO_CMD_THROTTLE IS 0.
GLOBAL AOSO_CMD_STEERING IS SHIP:UP.
GLOBAL AOSO_THROTTLE_MODE IS "OFF".
GLOBAL AOSO_STEER_MODE IS "OFF".

FUNCTION aoso_throttle_set {
    PARAMETER t.
    IF DEFINED AOSO_AUTH {
        IF NOT aoso_auth_can_cmd("THROTTLE") { RETURN. }
    }
    IF t < 0 { SET t TO 0. }
    IF t > 1 { SET t TO 1. }
    SET AOSO_CMD_THROTTLE TO t.
    IF AOSO_THROTTLE_MODE <> "CMD" {
        LOCK THROTTLE TO AOSO_CMD_THROTTLE.
        SET AOSO_THROTTLE_MODE TO "CMD".
    }
}

FUNCTION aoso_throttle_release {
    SET AOSO_CMD_THROTTLE TO 0.
    IF AOSO_THROTTLE_MODE = "OFF" { RETURN. }
    UNLOCK THROTTLE.
    SET AOSO_THROTTLE_MODE TO "OFF".
}

FUNCTION aoso_steer_heading_pitch {
    PARAMETER hdg.
    PARAMETER pitch.
    aoso_steer_heading_pitch_noroll(hdg, pitch).
}

// Compass pitch without HEADING()'s roll-to-upright. SIN/COS are degrees
// in kOS.
FUNCTION aoso_steer_heading_pitch_vector {
    PARAMETER hdg.
    PARAMETER pitch.
    LOCAL upv IS SHIP:UP:VECTOR.
    LOCAL east IS VXCL(upv, HEADING(hdg, 0):VECTOR).
    IF east:MAG < 0.01 { RETURN upv. }
    RETURN upv * SIN(pitch) + east:NORMALIZED * COS(pitch).
}

// Direction that points the nose at look and keeps the current roll.
// Parallel look/top is gimbal lock — swap in starboard as the up hint.
FUNCTION aoso_steer_facing_for_vector {
    PARAMETER dir_vector.
    IF dir_vector:MAG < 0.001 { RETURN SHIP:FACING. }
    LOCAL look IS dir_vector:NORMALIZED.
    LOCAL topv IS SHIP:FACING:TOPVECTOR.
    IF ABS(VDOT(look, topv)) > 0.97 {
        SET topv TO SHIP:FACING:STARVECTOR.
    }
    RETURN LOOKDIRUP(look, topv).
}

FUNCTION aoso_steer_quiet_roll {
    SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 1.
}

FUNCTION aoso_steer_heading_pitch_noroll {
    PARAMETER hdg.
    PARAMETER pitch.
    aoso_steer_to_vector(aoso_steer_heading_pitch_vector(hdg, pitch)).
}

FUNCTION aoso_steer_to_vector {
    PARAMETER dir_vector.
    IF DEFINED AOSO_AUTH {
        IF NOT aoso_auth_can_cmd("STEERING") { RETURN. }
    }
    SET AOSO_CMD_STEERING TO aoso_steer_facing_for_vector(dir_vector).
    aoso_steer_quiet_roll().
    IF AOSO_STEER_MODE <> "CMD" {
        LOCK STEERING TO AOSO_CMD_STEERING.
        SET AOSO_STEER_MODE TO "CMD".
    }
}

FUNCTION aoso_steer_prograde {
    IF DEFINED AOSO_AUTH {
        IF NOT aoso_auth_can_cmd("STEERING") { RETURN. }
    }
    IF AOSO_STEER_MODE = "PROGRADE" { RETURN. }
    LOCK STEERING TO SHIP:PROGRADE.
    SET AOSO_STEER_MODE TO "PROGRADE".
}

// Surface-relative retrograde: landing burns cancel velocity relative to
// the ground, not the body-centered orbital velocity vector.
FUNCTION aoso_steer_srf_retrograde {
    IF DEFINED AOSO_AUTH {
        IF NOT aoso_auth_can_cmd("STEERING") { RETURN. }
    }
    IF AOSO_STEER_MODE = "SRF_RETROGRADE" { RETURN. }
    LOCK STEERING TO SHIP:SRFRETROGRADE.
    SET AOSO_STEER_MODE TO "SRF_RETROGRADE".
}

// Radial-out ("straight up" from the local surface), used for the final
// vertical hold just before touchdown so the vessel settles upright rather
// than tipping toward whatever direction the last velocity vector pointed.
FUNCTION aoso_steer_up {
    IF DEFINED AOSO_AUTH {
        IF NOT aoso_auth_can_cmd("STEERING") { RETURN. }
    }
    IF AOSO_STEER_MODE = "UP" { RETURN. }
    LOCK STEERING TO SHIP:UP.
    SET AOSO_STEER_MODE TO "UP".
}

FUNCTION aoso_steer_release {
    // UNLOCK STEERING calls into kOS FlightControlManager and is not a cheap
    // no-op: kOS logs every toggle. Coast controllers call this defensively
    // each tick, so make release idempotent and avoid thousands of redundant
    // fly-by-wire disable operations during long/high-warp coasts.
    IF AOSO_STEER_MODE = "OFF" { RETURN. }
    UNLOCK STEERING.
    SET AOSO_STEER_MODE TO "OFF".
}

// Long stacks oscillate at the stock MAXSTOPPINGTIME of ~2 s. Quiet roll
// or the lander-can wheels hunt heading through the burn.
FUNCTION aoso_steer_prepare_for_burn {
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO MAX(STEERINGMANAGER:MAXSTOPPINGTIME, 5).
    SET STEERINGMANAGER:PITCHTS TO MAX(STEERINGMANAGER:PITCHTS, 6).
    SET STEERINGMANAGER:YAWTS TO MAX(STEERINGMANAGER:YAWTS, 6).
    SET STEERINGMANAGER:ROLLTS TO MAX(STEERINGMANAGER:ROLLTS, 14).
    aoso_steer_quiet_roll().
}

// Angle in degrees between the ship's current facing and a target direction
// vector. Used by guidance/maneuver code to decide when it is safe to throttle.
FUNCTION aoso_steer_error_deg {
    PARAMETER target_vector.
    RETURN VANG(SHIP:FACING:VECTOR, target_vector).
}

FUNCTION aoso_steer_is_aligned {
    PARAMETER target_vector.
    PARAMETER tolerance_deg IS 5.
    RETURN aoso_steer_error_deg(target_vector) <= tolerance_deg.
}
