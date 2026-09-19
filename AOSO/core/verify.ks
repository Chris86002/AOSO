// AOSO/core/verify.ks
// Postconditions. A controller finishing is not success. These helpers
// inspect the real ship after an action.

FUNCTION aoso_verify_ok {
    PARAMETER ok.
    PARAMETER reason.
    LOCAL st IS "SUCCESS".
    IF NOT ok { SET st TO "FAILED". }
    RETURN LEXICON("ok", ok, "reason", reason, "status", st).
}

FUNCTION aoso_verify_orbit {
    PARAMETER min_pe IS -1.
    IF SHIP:STATUS = "LANDED" { RETURN LEXICON("ok", FALSE, "reason", "landed", "status", "FAILED"). }
    IF SHIP:STATUS = "PRELAUNCH" { RETURN LEXICON("ok", FALSE, "reason", "pad", "status", "FAILED"). }
    IF SHIP:ORBIT:ECCENTRICITY >= 1 {
        RETURN LEXICON("ok", FALSE, "reason", "unbound e=" + ROUND(SHIP:ORBIT:ECCENTRICITY, 3), "status", "FAILED").
    }
    LOCAL floor_pe IS 2000.
    IF SHIP:BODY:ATM:EXISTS { SET floor_pe TO SHIP:BODY:ATM:HEIGHT + 1000. }
    IF min_pe > floor_pe { SET floor_pe TO min_pe. }
    IF PERIAPSIS < floor_pe {
        RETURN LEXICON("ok", FALSE, "reason", "pe " + ROUND(PERIAPSIS, 0) + " < " + ROUND(floor_pe, 0), "status", "PARTIAL").
    }
    RETURN LEXICON("ok", TRUE, "reason", "bound pe=" + ROUND(PERIAPSIS, 0), "status", "SUCCESS").
}

FUNCTION aoso_verify_ascent {
    LOCAL ver IS aoso_verify_orbit(-1).
    IF NOT ver["ok"] { RETURN ver. }
    IF SHIP:AVAILABLETHRUST <= 0 {
        IF STAGE:NUMBER <= 0 {
            RETURN LEXICON("ok", FALSE, "reason", "no thrust remaining", "status", "PARTIAL").
        }
    }
    RETURN ver.
}

FUNCTION aoso_verify_maneuver {
    PARAMETER burn_result.
    IF burn_result = "missed" {
        RETURN LEXICON("ok", FALSE, "reason", "missed node", "status", "FAILED").
    }
    IF burn_result = "incomplete" {
        RETURN LEXICON("ok", FALSE, "reason", "incomplete burn", "status", "FAILED").
    }
    IF burn_result = "no thrust" {
        RETURN LEXICON("ok", FALSE, "reason", "no thrust", "status", "FAILED").
    }
    RETURN LEXICON("ok", TRUE, "reason", burn_result, "status", "SUCCESS").
}

FUNCTION aoso_verify_transfer {
    PARAMETER goal_name.
    IF SHIP:BODY:NAME = goal_name {
        RETURN LEXICON("ok", TRUE, "reason", "in " + goal_name + " SOI", "status", "SUCCESS").
    }
    IF NOT SHIP:ORBIT:HASNEXTPATCH {
        RETURN LEXICON("ok", FALSE, "reason", "no encounter", "status", "FAILED").
    }
    LOCAL pb IS SHIP:ORBIT:NEXTPATCH:BODY:NAME.
    IF pb = goal_name {
        RETURN LEXICON("ok", TRUE, "reason", "patch to " + pb, "status", "SUCCESS").
    }
    RETURN LEXICON("ok", FALSE, "reason", "patch to " + pb + " not " + goal_name, "status", "PARTIAL").
}

FUNCTION aoso_verify_capture {
    LOCAL ver IS aoso_verify_orbit(-1).
    IF NOT ver["ok"] { RETURN ver. }
    IF SHIP:STATUS <> "ORBITING" {
        IF SHIP:ORBIT:ECCENTRICITY >= 0.95 {
            RETURN LEXICON("ok", FALSE, "reason", "not bound after capture", "status", "PARTIAL").
        }
    }
    RETURN ver.
}

FUNCTION aoso_verify_landing {
    IF SHIP:STATUS <> "LANDED" {
        IF SHIP:STATUS <> "SPLASHED" {
            RETURN LEXICON("ok", FALSE, "reason", "status " + SHIP:STATUS, "status", "FAILED").
        }
    }
    IF SHIP:VELOCITY:SURFACE:MAG > 1.5 {
        RETURN LEXICON("ok", FALSE, "reason", "sliding " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 2) + " m/s", "status", "PARTIAL").
    }
    IF VERTICALSPEED < -1 {
        RETURN LEXICON("ok", FALSE, "reason", "still falling", "status", "PARTIAL").
    }
    RETURN LEXICON("ok", TRUE, "reason", "stable surface", "status", "SUCCESS").
}

FUNCTION aoso_verify_takeoff {
    RETURN aoso_verify_ascent().
}

FUNCTION aoso_verify_apply_result {
    PARAMETER res.
    PARAMETER ver.
    SET res["status"] TO ver["status"].
    SET res["reason"] TO ver["reason"].
    IF NOT ver["ok"] {
        IF ver["status"] = "SUCCESS" { SET res["status"] TO "FAILED". }
    }
    RETURN res.
}
