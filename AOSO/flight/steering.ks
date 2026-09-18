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

GLOBAL AOSO_CMD_THROTTLE IS 0.
GLOBAL AOSO_CMD_STEERING IS SHIP:UP.
GLOBAL AOSO_THROTTLE_MODE IS "OFF".
GLOBAL AOSO_STEER_MODE IS "OFF".

FUNCTION aoso_throttle_set {
    PARAMETER t.
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
    UNLOCK THROTTLE.
    SET AOSO_THROTTLE_MODE TO "OFF".
}

FUNCTION aoso_steer_heading_pitch {
    PARAMETER hdg.
    PARAMETER pitch.
    SET AOSO_CMD_STEERING TO HEADING(hdg, pitch).
    IF AOSO_STEER_MODE <> "CMD" {
        LOCK STEERING TO AOSO_CMD_STEERING.
        SET AOSO_STEER_MODE TO "CMD".
    }
}

FUNCTION aoso_steer_to_vector {
    PARAMETER dir_vector.
    SET AOSO_CMD_STEERING TO dir_vector.
    IF AOSO_STEER_MODE <> "CMD" {
        LOCK STEERING TO AOSO_CMD_STEERING.
        SET AOSO_STEER_MODE TO "CMD".
    }
}

FUNCTION aoso_steer_prograde {
    IF AOSO_STEER_MODE = "PROGRADE" { RETURN. }
    LOCK STEERING TO SHIP:PROGRADE.
    SET AOSO_STEER_MODE TO "PROGRADE".
}

// Surface-relative retrograde: landing burns cancel velocity relative to
// the ground, not the body-centered orbital velocity vector.
FUNCTION aoso_steer_srf_retrograde {
    IF AOSO_STEER_MODE = "SRF_RETROGRADE" { RETURN. }
    LOCK STEERING TO SHIP:SRFRETROGRADE.
    SET AOSO_STEER_MODE TO "SRF_RETROGRADE".
}

// Radial-out ("straight up" from the local surface), used for the final
// vertical hold just before touchdown so the vessel settles upright rather
// than tipping toward whatever direction the last velocity vector pointed.
FUNCTION aoso_steer_up {
    IF AOSO_STEER_MODE = "UP" { RETURN. }
    LOCK STEERING TO SHIP:UP.
    SET AOSO_STEER_MODE TO "UP".
}

FUNCTION aoso_steer_release {
    UNLOCK STEERING.
    SET AOSO_STEER_MODE TO "OFF".
}

// Long stacks oscillate at the stock MAXSTOPPINGTIME of ~2 s and never
// settle inside a 5-8 deg align cone (Acacius: 44 m, two Mun windows missed).
FUNCTION aoso_steer_prepare_for_burn {
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO MAX(STEERINGMANAGER:MAXSTOPPINGTIME, 5).
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
