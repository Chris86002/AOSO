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
//
// aoso_staging_sense() fills one snapshot per check (STAGE:RESOURCES +
// cached engines). aoso_staging_auto_check() refuses to run twice in the
// same physics tick so ascent 0.1s + auto_staging 0.1s do not double-work.

GLOBAL AOSO_STAGING_RELIGHT_ATTEMPTS IS 0.
GLOBAL AOSO_STAGING_DEAD_SINCE IS 0.
GLOBAL AOSO_STAGING_LAST_REASON IS "".
GLOBAL AOSO_STAGING_TICK_UT IS -1.
GLOBAL AOSO_STG_LIT IS 0.
GLOBAL AOSO_STG_FLAMED IS 0.
GLOBAL AOSO_STG_FLOWING IS 0.
GLOBAL AOSO_STG_UNIGNITED IS FALSE.
GLOBAL AOSO_STG_BOOSTERS IS FALSE.
GLOBAL AOSO_STG_FUEL_GONE IS FALSE.
GLOBAL AOSO_STG_AIRBORNE IS FALSE.
GLOBAL AOSO_STG_THRUST IS 0.

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
    LOCAL lf_cap IS 0.
    LOCAL ox_cap IS 0.
    LOCAL sf_cap IS 0.
    LOCAL xe_cap IS 0.
    FOR r IN STAGE:RESOURCES {
        IF r:CAPACITY > 0 {
            IF r:NAME = "LiquidFuel" {
                SET lf TO r:AMOUNT.
                SET lf_cap TO r:CAPACITY.
            }
            IF r:NAME = "Oxidizer" {
                SET ox TO r:AMOUNT.
                SET ox_cap TO r:CAPACITY.
            }
            IF r:NAME = "SolidFuel" {
                SET sf TO r:AMOUNT.
                SET sf_cap TO r:CAPACITY.
            }
            IF r:NAME = "XenonGas" {
                SET xe TO r:AMOUNT.
                SET xe_cap TO r:CAPACITY.
            }
        }
    }
    RETURN LEXICON("lf", lf, "ox", ox, "sf", sf, "xe", xe, "lf_cap", lf_cap, "ox_cap", ox_cap, "sf_cap", sf_cap, "xe_cap", xe_cap).
}

// TRUE when the active stage's engines can no longer draw propellant.
// Absolute tenths-of-a-unit catch tiny residues; percent catch a 2000-unit
// tank that still reports 20 units (Acacius coasted with 11 m/s stage dV).
FUNCTION aoso_staging_resource_gone {
    PARAMETER amount.
    PARAMETER capacity.
    PARAMETER thresh.
    PARAMETER pct.
    IF amount < 0 { RETURN FALSE. }
    IF amount <= thresh { RETURN TRUE. }
    IF capacity > 1 {
        IF (amount / capacity) * 100 <= pct { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_staging_fuel_empty {
    LOCAL fuel IS aoso_staging_stage_fuel().
    LOCAL thresh IS AOSO_CONFIG["STAGING_FUEL_EMPTY"].
    LOCAL pct IS AOSO_CONFIG["STAGING_FUEL_EMPTY_PCT"].
    LOCAL any_tank IS FALSE.

    IF fuel["lf"] >= 0 { SET any_tank TO TRUE. }
    IF fuel["ox"] >= 0 { SET any_tank TO TRUE. }
    IF fuel["sf"] >= 0 { SET any_tank TO TRUE. }
    IF fuel["xe"] >= 0 { SET any_tank TO TRUE. }
    IF NOT any_tank { RETURN FALSE. }

    IF aoso_staging_resource_gone(fuel["lf"], fuel["lf_cap"], thresh, pct) { RETURN TRUE. }
    IF aoso_staging_resource_gone(fuel["ox"], fuel["ox_cap"], thresh, pct) { RETURN TRUE. }
    IF fuel["lf"] < 0 {
        IF fuel["ox"] < 0 {
            IF aoso_staging_resource_gone(fuel["sf"], fuel["sf_cap"], thresh, pct) { RETURN TRUE. }
            IF aoso_staging_resource_gone(fuel["xe"], fuel["xe_cap"], thresh, pct) { RETURN TRUE. }
        }
    }
    RETURN FALSE.
}

// One snapshot: current-stage fuel + one walk of cached engines for
// lit/flamed/flowing, unignited, and boosters-ready. Callers that need
// several of these must sense once instead of LIST ENGINES per helper.
FUNCTION aoso_staging_sense {
    PARAMETER commanded_throttle IS THROTTLE.

    SET AOSO_STG_AIRBORNE TO aoso_staging_airborne().
    SET AOSO_STG_THRUST TO SHIP:AVAILABLETHRUST.
    SET AOSO_STG_FUEL_GONE TO aoso_staging_fuel_empty().

    LOCAL elist IS aoso_parts_engines().
    LOCAL lit IS 0.
    LOCAL flamed IS 0.
    LOCAL flowing IS 0.
    LOCAL unignited IS FALSE.
    LOCAL have_spent IS FALSE.
    LOCAL have_burning IS FALSE.
    LOCAL spent_drop IS -1.
    LOCAL burn_drop IS -1.
    FOR e IN elist {
        IF e:IGNITION {
            SET lit TO lit + 1.
            LOCAL d IS e:DECOUPLEDIN.
            IF e:FLAMEOUT {
                SET flamed TO flamed + 1.
                SET have_spent TO TRUE.
                IF d > spent_drop { SET spent_drop TO d. }
            } ELSE {
                SET have_burning TO TRUE.
                IF d > burn_drop { SET burn_drop TO d. }
                IF e:MASSFLOW > 0.0001 { SET flowing TO flowing + 1. }
            }
        } ELSE {
            SET unignited TO TRUE.
        }
    }
    SET AOSO_STG_LIT TO lit.
    SET AOSO_STG_FLAMED TO flamed.
    SET AOSO_STG_FLOWING TO flowing.
    SET AOSO_STG_UNIGNITED TO unignited.

    LOCAL boosters IS FALSE.
    IF have_spent {
        IF have_burning {
            IF spent_drop >= 0 {
                IF spent_drop > burn_drop { SET boosters TO TRUE. }
            }
        }
    }
    SET AOSO_STG_BOOSTERS TO boosters.
}

FUNCTION aoso_staging_engine_counts {
    LOCAL elist IS aoso_parts_engines().
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
    IF AOSO_STG_LIT <= 0 {
        IF AOSO_STG_FLAMED <= 0 {
            aoso_staging_sense(commanded_throttle).
        }
    }
    IF AOSO_STG_LIT <= 0 { RETURN FALSE. }
    IF AOSO_STG_FLAMED = AOSO_STG_LIT { RETURN TRUE. }
    IF commanded_throttle > 0.12 {
        IF AOSO_STG_FLOWING <= 0 { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_staging_thrust_dead {
    IF AOSO_STG_THRUST > 0.05 {
        SET AOSO_STAGING_DEAD_SINCE TO 0.
        RETURN FALSE.
    }
    IF NOT AOSO_STG_AIRBORNE {
        SET AOSO_STAGING_DEAD_SINCE TO 0.
        RETURN FALSE.
    }
    IF AOSO_STAGING_DEAD_SINCE <= 0 { SET AOSO_STAGING_DEAD_SINCE TO TIME:SECONDS. }
    LOCAL need IS AOSO_CONFIG["STAGING_DEAD_S"].
    RETURN (TIME:SECONDS - AOSO_STAGING_DEAD_SINCE) >= need.
}

FUNCTION aoso_staging_should_stage {
    PARAMETER commanded_throttle IS THROTTLE.

    SET AOSO_STAGING_LAST_REASON TO "".
    IF STAGE:NUMBER <= 0 { RETURN FALSE. }
    IF AOSO_CONFIG["SAFE_MODE"] { RETURN FALSE. }
    IF NOT STAGE:READY { RETURN FALSE. }

    aoso_staging_sense(commanded_throttle).

    LOCAL airborne IS AOSO_STG_AIRBORNE.
    LOCAL fuel_gone IS AOSO_STG_FUEL_GONE.
    LOCAL engines_spent IS FALSE.
    IF AOSO_STG_LIT > 0 {
        IF AOSO_STG_FLAMED = AOSO_STG_LIT {
            SET engines_spent TO TRUE.
        } ELSE {
            IF commanded_throttle > 0.12 {
                IF AOSO_STG_FLOWING <= 0 { SET engines_spent TO TRUE. }
            }
        }
    }
    LOCAL thrust_dead IS aoso_staging_thrust_dead().

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
            IF AOSO_STG_UNIGNITED {
                IF AOSO_STAGING_RELIGHT_ATTEMPTS < 6 {
                    SET AOSO_STAGING_LAST_REASON TO "thrust collapse".
                    RETURN TRUE.
                }
            }
        }
    }

    IF AOSO_STG_LIT > 0 {
        IF AOSO_STG_BOOSTERS {
            SET AOSO_STAGING_LAST_REASON TO "drop boosters".
            RETURN TRUE.
        }
    }

    // Serial-stack relight: nothing ignited, next engines exist.
    IF AOSO_STG_LIT = 0 {
        IF airborne {
            IF AOSO_STAGING_RELIGHT_ATTEMPTS < 6 {
                IF AOSO_STG_UNIGNITED {
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
        aoso_parts_cache_invalidate().
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
    LOCAL now IS TIME:SECONDS.
    IF now = AOSO_STAGING_TICK_UT { RETURN. }
    SET AOSO_STAGING_TICK_UT TO now.

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
        aoso_parts_cache_invalidate().
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
    aoso_staging_sense(1).
    IF AOSO_STG_THRUST > 0.05 { RETURN TRUE. }
    IF NOT AOSO_STG_AIRBORNE { RETURN FALSE. }
    IF AOSO_CONFIG["SAFE_MODE"] { RETURN FALSE. }
    IF STAGE:NUMBER <= 0 { RETURN FALSE. }
    IF NOT STAGE:READY { RETURN FALSE. }
    IF AOSO_STAGING_RELIGHT_ATTEMPTS >= 6 { RETURN FALSE. }

    LOCAL can_drop IS FALSE.
    IF AOSO_STG_FUEL_GONE { SET can_drop TO TRUE. }
    IF AOSO_STG_LIT > 0 {
        IF AOSO_STG_FLAMED = AOSO_STG_LIT {
            SET can_drop TO TRUE.
        } ELSE {
            IF AOSO_STG_FLOWING <= 0 { SET can_drop TO TRUE. }
        }
    }
    IF AOSO_STG_UNIGNITED { SET can_drop TO TRUE. }
    IF NOT can_drop { RETURN FALSE. }

    aoso_log_info("STAGING", "Ensuring thrust for upcoming burn, staging (" + STAGE:NUMBER + ").").
    SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
    STAGE.
    aoso_parts_cache_invalidate().
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
