// AOSO/flight/launch.ks
// Countdown + ignition sequence, isolated from ascent guidance (flight/ascent.ks)
// so a caller can re-use just the ignition logic (e.g. relighting an upper
// stage) without re-running a full countdown.

FUNCTION aoso_launch_countdown {
    PARAMETER seconds IS 5.
    IF DEFINED aoso_log_info { aoso_log_info("LAUNCH", "T-minus " + seconds + "s"). }
    FROM { LOCAL t IS seconds. } UNTIL t <= 0 STEP { SET t TO t - 1. } DO {
        PRINT "T-" + t + "  ".
        WAIT 1.
    }
}

// Throttles up and stages until thrust is actually flowing. Handles vessels
// that need one STAGE for engine ignition and a second for launch clamps/
// fairing-style holds, without assuming a fixed part layout.
FUNCTION aoso_launch_ignite {
    LOCK THROTTLE TO 1.0.

    LOCAL attempts IS 0.
    UNTIL SHIP:AVAILABLETHRUST > 0 OR STAGE:NUMBER <= 0 OR attempts >= 4 {
        STAGE.
        WAIT UNTIL STAGE:READY.
        WAIT 0.5. // let engines spool up before re-checking AVAILABLETHRUST
        SET attempts TO attempts + 1.
    }

    IF DEFINED aoso_log_info {
        aoso_log_info("LAUNCH", "Ignition: AvailableThrust=" + ROUND(SHIP:AVAILABLETHRUST, 1) +
            " after " + attempts + " stage event(s).").
    }

    RETURN SHIP:AVAILABLETHRUST > 0.
}

FUNCTION aoso_launch_wait_for_liftoff {
    WAIT UNTIL SHIP:VERTICALSPEED > 0.5 OR ALTITUDE > 50.
}

// Full pad sequence: point at the launch heading, count down, ignite, and
// confirm liftoff. Does not itself fly the gravity turn -- hand off to
// flight/ascent.ks (aoso_ascent_start) once this returns TRUE.
FUNCTION aoso_launch_sequence {
    PARAMETER launch_heading IS 90.
    PARAMETER countdown_s IS 5.

    aoso_steer_heading_pitch(launch_heading, 90).
    aoso_launch_countdown(countdown_s).
    LOCAL ignited IS aoso_launch_ignite().
    IF NOT ignited {
        IF DEFINED aoso_log_error { aoso_log_error("LAUNCH", "No thrust after ignition attempts - aborting sequence."). }
        RETURN FALSE.
    }

    aoso_launch_wait_for_liftoff().
    IF DEFINED aoso_log_info { aoso_log_info("LAUNCH", "Liftoff."). }
    RETURN TRUE.
}
