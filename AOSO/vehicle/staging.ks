// AOSO/vehicle/staging.ks
// Auto-staging that fires on empty tanks and thrust collapse, not only
// after kOS's FLAMEOUT flag. Flameout lags 1-6 s after the tanks actually
// run dry (Acacius: engine-failure at UT 17502, TWR=0 at 17506, STAGE at
// 17508) which is dead weight, lost TWR, and the reason circularization /
// transfer burns were missed -- aoso_staging_should_stage() used to refuse
// to fire at throttle 0, so an empty core sat dark through the coast and
// the node.
//
// Triggers, in order:
//   1. Current-stage LiquidFuel / Oxidizer / SolidFuel is empty (the kOS
//      docs / forum pattern: STAGE:RESOURCES amount ~ 0, don't wait for
//      flameout). LFO is starved if EITHER fuel or ox is gone.
//   2. Every currently-ignited engine has flamed out, or they are ignited
//      with throttle open but MASSFLOW ~ 0 (starved, flag not set yet).
//   3. AVAILABLETHRUST has been ~0 for STAGING_DEAD_S while airborne,
//      with an un-ignited engine still on the stack -- serial-stack relight.
//   4. Spent BOOSTER subset can drop while the core keeps burning
//      (vehicle/parts.ks aoso_parts_boosters_ready_to_jettison).
// Empty stages are dropped even at throttle 0 so a coast / warp-to-node
// does not carry dry tanks into the burn. Pad ignition is still
// flight/ascent.ks LIFTOFF -- relight is gated on SHIP:STATUS.
// Disabled outright when AOSO_CONFIG["SAFE_MODE"] is set.

GLOBAL AOSO_STAGING_RELIGHT_ATTEMPTS IS 0.
GLOBAL AOSO_STAGING_DEAD_SINCE IS 0.
GLOBAL AOSO_STAGING_LAST_REASON IS "".

FUNCTION aoso_staging_airborne {
    LOCAL st IS SHIP:STATUS.
    RETURN st <> "PRELAUNCH" AND st <> "LANDED" AND st <> "SPLASHED".
}

// Burnable propellant pooled to the current stage. Ore / EC / Ablator are
// not engine fuel and must not hide an empty LF tank.
FUNCTION aoso_staging_stage_fuel {
    LOCAL lf IS -1.
    LOCAL ox IS -1.
    LOCAL sf IS -1.
    LOCAL xe IS -1.
    FOR r IN STAGE:RESOURCES {
        IF r:CAPACITY > 0 {
            IF r:NAME = "LiquidFuel" { SET lf TO r:AMOUNT. }
            IF r:NAME = "Oxidizer" { SET ox TO r:AMOUNT. }
            IF r:NAME = "SolidFuel" { SET sf TO r:AMOUNT. }
            IF r:NAME = "XenonGas" { SET xe TO r:AMOUNT. }
        }
    }
    RETURN LEXICON("lf", lf, "ox", ox, "sf", sf, "xe", xe).
}

// TRUE when the active stage's engines can no longer draw propellant.
// Threshold is a few tenths of a unit: KSP leaves a residue in big tanks
// and solid boosters often never report a true 0.00.
FUNCTION aoso_staging_fuel_empty {
    LOCAL fuel IS aoso_staging_stage_fuel().
    LOCAL thresh IS aoso_config_get("STAGING_FUEL_EMPTY", 0.25).
    LOCAL any_tank IS FALSE.

    IF fuel["lf"] >= 0 { SET any_tank TO TRUE. }
    IF fuel["ox"] >= 0 { SET any_tank TO TRUE. }
    IF fuel["sf"] >= 0 { SET any_tank TO TRUE. }
    IF fuel["xe"] >= 0 { SET any_tank TO TRUE. }
    IF NOT any_tank { RETURN FALSE. }

    // LFO: starved if either resource in this stage is gone.
    IF fuel["lf"] >= 0 {
        IF fuel["lf"] <= thresh { RETURN TRUE. }
    }
    IF fuel["ox"] >= 0 {
        IF fuel["ox"] <= thresh { RETURN TRUE. }
    }
    IF fuel["sf"] >= 0 {
        IF fuel["lf"] < 0 {
            IF fuel["ox"] < 0 {
                IF fuel["sf"] <= thresh { RETURN TRUE. }
            }
        }
    }
    IF fuel["xe"] >= 0 {
        IF fuel["lf"] < 0 {
            IF fuel["ox"] < 0 {
                IF fuel["xe"] <= thresh { RETURN TRUE. }
            }
        }
    }
    RETURN FALSE.
}

FUNCTION aoso_staging_engine_counts {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    LOCAL lit IS 0.
    LOCAL flamed IS 0.
    LOCAL flowing IS 0.
    FOR e IN elist {
        IF e:IGNITION {
            SET lit TO lit + 1.
            IF e:FLAMEOUT {
                SET flamed TO flamed + 1.
            } ELSE {
                IF e:MASSFLOW > 0.0001 { SET flowing TO flowing + 1. }
            }
        }
    }
    RETURN LEXICON("lit", lit, "flamed", flamed, "flowing", flowing).
}

// Engines that were lit are now useless: all flamed out, or throttle is
// open and none of them are actually flowing mass. MASSFLOW is 0 at
// throttle 0 even with full tanks, so the flow check is gated on throttle.
FUNCTION aoso_staging_engines_spent {
    PARAMETER commanded_throttle IS THROTTLE.
    LOCAL counts IS aoso_staging_engine_counts().
    IF counts["lit"] <= 0 { RETURN FALSE. }
    IF counts["flamed"] = counts["lit"] { RETURN TRUE. }
    IF commanded_throttle > 0.12 {
        IF counts["flowing"] <= 0 { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_staging_thrust_dead {
    IF SHIP:AVAILABLETHRUST > 0.05 {
        SET AOSO_STAGING_DEAD_SINCE TO 0.
        RETURN FALSE.
    }
    IF NOT aoso_staging_airborne() {
        SET AOSO_STAGING_DEAD_SINCE TO 0.
        RETURN FALSE.
    }
    IF AOSO_STAGING_DEAD_SINCE <= 0 { SET AOSO_STAGING_DEAD_SINCE TO TIME:SECONDS. }
    LOCAL need IS aoso_config_get("STAGING_DEAD_S", 0.2).
    RETURN (TIME:SECONDS - AOSO_STAGING_DEAD_SINCE) >= need.
}

FUNCTION aoso_staging_should_stage {
    PARAMETER commanded_throttle IS THROTTLE.

    SET AOSO_STAGING_LAST_REASON TO "".
    IF STAGE:NUMBER <= 0 { RETURN FALSE. }
    IF aoso_config_get("SAFE_MODE", FALSE) { RETURN FALSE. }
    IF NOT STAGE:READY { RETURN FALSE. }

    LOCAL airborne IS aoso_staging_airborne().
    LOCAL fuel_gone IS aoso_staging_fuel_empty().
    LOCAL engines_spent IS aoso_staging_engines_spent(commanded_throttle).
    LOCAL thrust_dead IS aoso_staging_thrust_dead().
    LOCAL counts IS aoso_staging_engine_counts().

    // Drop a spent stage even with the throttle closed. The old
    // "commanded_throttle <= 0 -> FALSE" guard left Acacius coasting
    // at TWR 0 with a full unlit core (and missed the next burn).
    IF fuel_gone {
        IF airborne {
            SET AOSO_STAGING_LAST_REASON TO "empty fuel".
            RETURN TRUE.
        }
    }
    IF engines_spent {
        IF airborne {
            SET AOSO_STAGING_LAST_REASON TO "flameout".
            RETURN TRUE.
        }
        IF commanded_throttle > 0 {
            SET AOSO_STAGING_LAST_REASON TO "flameout".
            RETURN TRUE.
        }
    }

    IF airborne {
        IF thrust_dead {
            IF aoso_parts_has_unignited_engine() {
                IF AOSO_STAGING_RELIGHT_ATTEMPTS < 6 {
                    SET AOSO_STAGING_LAST_REASON TO "thrust collapse".
                    RETURN TRUE.
                }
            }
        }
    }

    IF counts["lit"] > 0 {
        IF aoso_parts_boosters_ready_to_jettison() {
            SET AOSO_STAGING_LAST_REASON TO "drop boosters".
            RETURN TRUE.
        }
    }

    // Serial-stack relight: nothing ignited, next engines exist.
    IF counts["lit"] = 0 {
        IF airborne {
            IF AOSO_STAGING_RELIGHT_ATTEMPTS < 6 {
                IF aoso_parts_has_unignited_engine() {
                    IF commanded_throttle > 0 {
                        SET AOSO_STAGING_LAST_REASON TO "relight".
                        RETURN TRUE.
                    }
                    IF HASNODE {
                        SET AOSO_STAGING_LAST_REASON TO "relight".
                        RETURN TRUE.
                    }
                    IF thrust_dead {
                        SET AOSO_STAGING_LAST_REASON TO "relight".
                        RETURN TRUE.
                    }
                }
            }
        }
    }

    RETURN FALSE.
}

// After dropping a spent stage, keep staging until something burns again.
// Serial stacks put "jettison empties" and "ignite next engines" in
// different KSP stages; one STAGE() is not enough. Bounded so we cannot
// dump the payload if the next engines refuse to light.
FUNCTION aoso_staging_relight_until_thrust {
    LOCAL extra IS 0.
    UNTIL SHIP:AVAILABLETHRUST > 0.05 OR STAGE:NUMBER <= 0 OR extra >= 4 OR AOSO_STAGING_RELIGHT_ATTEMPTS >= 6 OR NOT aoso_parts_has_unignited_engine() {
        IF NOT STAGE:READY { WAIT UNTIL STAGE:READY. }
        aoso_log_info("STAGING", "Relight: no thrust after staging, lighting next stage (" + STAGE:NUMBER + ").").
        STAGE.
        SET extra TO extra + 1.
        SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
        WAIT UNTIL STAGE:READY.
        WAIT 0.08.
    }
    IF SHIP:AVAILABLETHRUST > 0.05 {
        SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.
        SET AOSO_STAGING_DEAD_SINCE TO 0.
        IF extra > 0 {
            aoso_log_info("STAGING", "Relight: thrust restored after " + extra + " extra stage event(s).").
        }
    } ELSE IF extra > 0 {
        aoso_log_warn("STAGING", "Relight: still no thrust after " + AOSO_STAGING_RELIGHT_ATTEMPTS + " extra stage event(s).").
    }
}

FUNCTION aoso_staging_auto_check {
    IF aoso_staging_should_stage() {
        LOCAL prev IS STAGE:NUMBER.
        LOCAL reason IS AOSO_STAGING_LAST_REASON.
        IF reason = "" { SET reason TO "stage". }

        LOCAL pred IS aoso_capabilities_predict_next().
        aoso_log_info("STAGING", "Auto-staging: " + reason + ", stage " + prev + " -> " + (prev - 1) +
            "  TWR " + ROUND(pred["twr_now"], 2) + " -> " + ROUND(pred["twr_next"], 2) +
            "  dV after " + ROUND(pred["dv_after"], 0) + " m/s.").

        IF reason = "relight" OR reason = "thrust collapse" {
            SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
        }

        STAGE.
        WAIT UNTIL STAGE:READY.
        WAIT 0.08.

        IF SHIP:AVAILABLETHRUST <= 0.05 {
            aoso_staging_relight_until_thrust().
        } ELSE {
            SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.
            SET AOSO_STAGING_DEAD_SINCE TO 0.
        }

        aoso_profile_refresh("staging").
    }
}

FUNCTION aoso_staging_register_task {
    PARAMETER interval_s IS 0.1.
    aoso_sched_add("auto_staging", interval_s, aoso_staging_auto_check@).
}

// Light the next engine group even with throttle closed (coast / pre-burn).
// Uses AVAILABLETHRUST, not IGNITION: engines can still report IGNITION
// for seconds after the tanks are dry, which used to make this return
// TRUE and skip the drop.
FUNCTION aoso_staging_ensure_thrust {
    IF SHIP:AVAILABLETHRUST > 0.05 { RETURN TRUE. }
    IF NOT aoso_staging_airborne() { RETURN FALSE. }
    IF aoso_config_get("SAFE_MODE", FALSE) { RETURN FALSE. }
    IF STAGE:NUMBER <= 0 { RETURN FALSE. }
    IF NOT STAGE:READY { RETURN FALSE. }
    IF AOSO_STAGING_RELIGHT_ATTEMPTS >= 6 { RETURN FALSE. }

    LOCAL can_drop IS FALSE.
    IF aoso_staging_fuel_empty() { SET can_drop TO TRUE. }
    IF aoso_staging_engines_spent(1) { SET can_drop TO TRUE. }
    IF aoso_parts_has_unignited_engine() { SET can_drop TO TRUE. }
    IF NOT can_drop { RETURN FALSE. }

    aoso_log_info("STAGING", "Ensuring thrust for upcoming burn, staging (" + STAGE:NUMBER + ").").
    SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
    STAGE.
    WAIT UNTIL STAGE:READY.
    WAIT 0.08.
    IF SHIP:AVAILABLETHRUST <= 0.05 {
        aoso_staging_relight_until_thrust().
    } ELSE {
        SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.
        SET AOSO_STAGING_DEAD_SINCE TO 0.
    }
    aoso_profile_refresh("ensure_thrust").
    RETURN SHIP:AVAILABLETHRUST > 0.05.
}
