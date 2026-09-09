// AOSO/flight/steering.ks
// Thin wrappers around native kOS STEERING locks so every flight/guidance
// module commands attitude the same way. MechJeb's SmartASS is deliberately
// not used here (see core/addons.ks reasoning on not guessing at its
// suffixes) -- native kOS STEERING is correct on every install.

FUNCTION aoso_steer_heading_pitch {
    PARAMETER hdg.
    PARAMETER pitch.
    LOCK STEERING TO HEADING(hdg, pitch).
}

FUNCTION aoso_steer_to_vector {
    PARAMETER dir_vector.
    LOCK STEERING TO dir_vector.
}

FUNCTION aoso_steer_prograde {
    LOCK STEERING TO SHIP:PROGRADE.
}

FUNCTION aoso_steer_retrograde {
    LOCK STEERING TO SHIP:RETROGRADE.
}

// Surface-relative counterparts. Orbital PROGRADE/RETROGRADE point along
// the body-centered velocity vector, which is wrong for a landing burn that
// needs to cancel velocity relative to the ground, and for the atmospheric
// half of a gravity turn (zero AoA means surface prograde, not orbital).
FUNCTION aoso_steer_srf_prograde {
    LOCK STEERING TO SHIP:SRFPROGRADE.
}

FUNCTION aoso_steer_srf_retrograde {
    LOCK STEERING TO SHIP:SRFRETROGRADE.
}

// Radial-out ("straight up" from the local surface), used for the final
// vertical hold just before touchdown so the vessel settles upright rather
// than tipping toward whatever direction the last velocity vector pointed.
FUNCTION aoso_steer_up {
    LOCK STEERING TO SHIP:UP.
}

// Actively damps angular velocity toward zero without commanding a facing,
// mirroring the stock "Kill Rotation" SAS mode.
FUNCTION aoso_steer_kill_rotation {
    LOCK STEERING TO "KILL".
}

FUNCTION aoso_steer_release {
    UNLOCK STEERING.
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
