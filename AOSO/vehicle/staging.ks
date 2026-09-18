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
// Empty current-stage tanks still drop while other engines push (asparagus /
// boosters) ONLY if the engine group that would fall off has MASSFLOW ~ 0.
// Staging while that group is still thrusting is a hot-sep: the booster
// flies into the core (Acacius MET 62, stage 7, TWR 1.48 after the drop).
// Disabled outright when AOSO_CONFIG["SAFE_MODE"] is set.
//
// aoso_staging_sense() fills one snapshot per check (STAGE:RESOURCES +
// cached engines). aoso_staging_auto_check() refuses to run twice in the
// same physics tick so ascent 0.1s + auto_staging 0.1s do not double-work.
// Spool is a timestamp, not WAIT, so the main loop keeps steering.

GLOBAL AOSO_STAGING_RELIGHT_ATTEMPTS IS 0.
GLOBAL AOSO_STAGING_DEAD_SINCE IS 0.
GLOBAL AOSO_STAGING_LAST_REASON IS "".
GLOBAL AOSO_STAGING_TICK_UT IS -1.
GLOBAL AOSO_STAGING_COOLDOWN_UNTIL IS 0.
GLOBAL AOSO_STAGING_SPOOL_UNTIL IS 0.
GLOBAL AOSO_STAGING_PENDING_RELIGHT IS FALSE.
GLOBAL AOSO_STAGING_EXTRA_THIS IS 0.
GLOBAL AOSO_STG_DROP_FLOWING IS FALSE.
GLOBAL AOSO_STAGING_HOTSEP_LOG IS 0.
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

FUNCTION aoso_staging_ship_lf {
    FOR r IN SHIP:RESOURCES {
        IF r:NAME = "LiquidFuel" { RETURN r:AMOUNT. }
    }
    RETURN 0.
}

FUNCTION aoso_staging_after_stage {
    aoso_parts_cache_invalidate().
    LOCAL cool IS aoso_config_get("STAGING_COOLDOWN_S", 1.2).
    LOCAL spool IS aoso_config_get("STAGING_SPOOL_S", 0.8).
    LOCAL now IS TIME:SECONDS.
    SET AOSO_STAGING_COOLDOWN_UNTIL TO now + cool.
    SET AOSO_STAGING_SPOOL_UNTIL TO now + spool.
}

FUNCTION aoso_staging_emit {
    PARAMETER prev.
    PARAMETER reason.
    PARAMETER pred.
    LOCAL twr_now IS ROUND(pred["twr_now"], 2).
    LOCAL twr_next IS ROUND(pred["twr_next"], 2).
    LOCAL actual_twr IS aoso_perf_twr().
    aoso_observe_event("STAGE", "INFO", reason, "stg=" + prev + " twr=" + ROUND(actual_twr, 2)).
    LOCAL cat IS reason.
    IF reason = "empty fuel" { SET cat TO "fuel_gone". }
    IF reason = "flameout" { SET cat TO "flameout". }
    IF reason = "relight" { SET cat TO "relight". }
    IF reason = "thrust collapse" { SET cat TO "relight". }
    IF reason = "drop boosters" { SET cat TO "boosters". }
    aoso_decide("STAGING", "stage", reason, cat, "stg=" + prev + " twr_now=" + twr_now + " twr_next=" + twr_next).
    IF pred["twr_next"] > 1.2 {
        IF actual_twr < 0.5 {
            aoso_observe_anomaly("THRUST_MISMATCH", "HIGH", pred["twr_next"], actual_twr).
        }
    }
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

    LOCAL lf_gone IS aoso_staging_resource_gone(fuel["lf"], fuel["lf_cap"], thresh, pct).
    LOCAL ox_gone IS aoso_staging_resource_gone(fuel["ox"], fuel["ox_cap"], thresh, pct).
    LOCAL sf_gone IS aoso_staging_resource_gone(fuel["sf"], fuel["sf_cap"], thresh, pct).
    LOCAL xe_gone IS aoso_staging_resource_gone(fuel["xe"], fuel["xe_cap"], thresh, pct).

    // Mixed solid + LFO in the same KSP stage: only empty when EVERY present
    // type is gone. Staging because SF hit 0 while LF tanks are still full
    // is what dropped Acacius's booster early.
    LOCAL lfo_dead IS TRUE.
    IF fuel["lf"] >= 0 {
        SET lfo_dead TO lf_gone.
        IF fuel["ox"] >= 0 {
            IF ox_gone { SET lfo_dead TO TRUE. }
        }
    } ELSE {
        IF fuel["ox"] >= 0 { SET lfo_dead TO ox_gone. }
    }
    LOCAL sf_dead IS TRUE.
    IF fuel["sf"] >= 0 { SET sf_dead TO sf_gone. }
    LOCAL xe_dead IS TRUE.
    IF fuel["xe"] >= 0 { SET xe_dead TO xe_gone. }
    IF lfo_dead {
        IF sf_dead {
            IF xe_dead { RETURN TRUE. }
        }
    }
    RETURN FALSE.
}

FUNCTION aoso_staging_stage_has_fuel {
    LOCAL fuel IS aoso_staging_stage_fuel().
    IF fuel["lf"] > 10 { RETURN TRUE. }
    IF fuel["ox"] > 10 { RETURN TRUE. }
    IF fuel["sf"] > 10 { RETURN TRUE. }
    IF fuel["xe"] > 10 { RETURN TRUE. }
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

    // Highest DECOUPLEDIN group falls off on the next STAGE(). If any of
    // those engines still have MASSFLOW, staging is a hot-sep and the
    // booster flies into the core (Acacius MET 62, stage 7, TWR 1.48).
    LOCAL max_d IS -1.
    FOR e IN elist {
        IF e:DECOUPLEDIN > max_d { SET max_d TO e:DECOUPLEDIN. }
    }
    LOCAL drop_flowing IS FALSE.
    IF max_d >= 0 {
        FOR e IN elist {
            IF e:DECOUPLEDIN = max_d {
                IF e:IGNITION {
                    IF NOT e:FLAMEOUT {
                        IF e:MASSFLOW > 0.0001 { SET drop_flowing TO TRUE. }
                    }
                }
            }
        }
    } ELSE {
        IF flowing > 0 { SET drop_flowing TO TRUE. }
    }
    SET AOSO_STG_DROP_FLOWING TO drop_flowing.
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

    IF AOSO_STG_DROP_FLOWING {
        IF TIME:SECONDS - AOSO_STAGING_HOTSEP_LOG > 5 {
            aoso_log_info("STAGING", "Holding stage " + STAGE:NUMBER + " - next drop group still thrusting (hot-sep).").
            SET AOSO_STAGING_HOTSEP_LOG TO TIME:SECONDS.
        }
        RETURN FALSE.
    }

    IF TIME:SECONDS < AOSO_STAGING_COOLDOWN_UNTIL {
        LOCAL all_flamed IS FALSE.
        IF AOSO_STG_LIT > 0 {
            IF AOSO_STG_FLAMED = AOSO_STG_LIT { SET all_flamed TO TRUE. }
        }
        IF NOT all_flamed { RETURN FALSE. }
    }

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
            // Current-stage tanks are empty. If something is still making
            // thrust (asparagus / boosters + live core), drop the empties --
            // that is the whole reason empty-fuel exists (flameout lags).
            // If nothing is making thrust, this is a relight: cap extras so
            // unignited lander engines cannot walk the stack (Acacius 7->2).
            LOCAL still_pushing IS FALSE.
            IF AOSO_STG_THRUST > 0.05 {
                IF AOSO_STG_LIT > 0 {
                    IF AOSO_STG_FLAMED < AOSO_STG_LIT { SET still_pushing TO TRUE. }
                }
            }
            IF still_pushing {
                SET AOSO_STAGING_LAST_REASON TO "empty fuel".
                RETURN TRUE.
            }
            LOCAL ship_lf IS aoso_staging_ship_lf().
            IF ship_lf > 10 {
                LOCAL max_relight IS aoso_config_get("STAGING_MAX_EXTRA", 1).
                IF AOSO_STAGING_RELIGHT_ATTEMPTS < max_relight {
                    SET AOSO_STAGING_LAST_REASON TO "relight".
                    RETURN TRUE.
                }
            } ELSE {
                SET AOSO_STAGING_LAST_REASON TO "empty fuel".
                RETURN TRUE.
            }
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
                LOCAL max_relight IS aoso_config_get("STAGING_MAX_EXTRA", 1).
                IF AOSO_STAGING_RELIGHT_ATTEMPTS < max_relight {
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
            LOCAL max_relight IS aoso_config_get("STAGING_MAX_EXTRA", 1).
            IF AOSO_STAGING_RELIGHT_ATTEMPTS < max_relight {
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

FUNCTION aoso_staging_light_unlit {
    LOCAL lit_n IS 0.
    LOCAL engs IS LIST().
    LIST ENGINES IN engs.
    FOR e IN engs {
        IF e:MAXTHRUST > 0.05 {
            IF NOT e:FLAMEOUT {
                IF NOT e:IGNITION {
                    e:ACTIVATE.
                    SET lit_n TO lit_n + 1.
                }
            }
        }
    }
    IF lit_n > 0 {
        aoso_log_info("STAGING", "Activated " + lit_n + " unlit engine(s) without staging.").
    }
    RETURN lit_n.
}

// After dropping a spent stage, one extra STAGE is allowed only if the
// NEW current stage is also empty (jettison-then-ignite serial). Never
// dump a stage that still has fuel -- that is how Acacius lost the booster.
FUNCTION aoso_staging_finish_relight {
    SET AOSO_STAGING_PENDING_RELIGHT TO FALSE.
    IF SHIP:AVAILABLETHRUST > 0.05 {
        SET AOSO_STAGING_RELIGHT_ATTEMPTS TO 0.
        SET AOSO_STAGING_DEAD_SINCE TO 0.
        SET AOSO_STAGING_EXTRA_THIS TO 0.
        RETURN.
    }
    aoso_staging_sense(1).
    IF AOSO_STG_DROP_FLOWING {
        aoso_log_warn("STAGING", "No thrust after staging but next drop group still thrusting - not dumping it.").
        SET AOSO_STAGING_EXTRA_THIS TO 0.
        RETURN.
    }
    IF aoso_staging_stage_has_fuel() {
        LOCAL nlit IS aoso_staging_light_unlit().
        IF nlit > 0 { RETURN. }
        aoso_log_warn("STAGING", "No thrust after staging but current stage still has fuel - not dumping it.").
        SET AOSO_STAGING_EXTRA_THIS TO 0.
        RETURN.
    }
    LOCAL max_extra IS aoso_config_get("STAGING_MAX_EXTRA", 1).
    IF max_extra < 0 { SET max_extra TO 0. }
    IF AOSO_STAGING_EXTRA_THIS >= max_extra {
        LOCAL nlit2 IS aoso_staging_light_unlit().
        IF nlit2 > 0 { RETURN. }
        aoso_log_warn("STAGING", "Relight: still no thrust after " + AOSO_STAGING_EXTRA_THIS + " extra stage event(s) with LF remaining; not walking the stack.").
        SET AOSO_STAGING_EXTRA_THIS TO 0.
        RETURN.
    }
    IF STAGE:NUMBER <= 0 { RETURN. }
    IF NOT STAGE:READY {
        SET AOSO_STAGING_PENDING_RELIGHT TO TRUE.
        RETURN.
    }
    LOCAL prev IS STAGE:NUMBER.
    aoso_log_info("STAGING", "Relight: no thrust after staging, lighting next empty stage (" + prev + ").").
    aoso_observe_event("RELIGHT", "INFO", "relight", "stg=" + prev).
    STAGE.
    aoso_staging_after_stage().
    SET AOSO_STAGING_EXTRA_THIS TO AOSO_STAGING_EXTRA_THIS + 1.
    SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
    SET AOSO_STAGING_PENDING_RELIGHT TO TRUE.
}

FUNCTION aoso_staging_auto_check {
    LOCAL now IS TIME:SECONDS.
    IF now = AOSO_STAGING_TICK_UT { RETURN. }
    SET AOSO_STAGING_TICK_UT TO now.

    IF now < AOSO_STAGING_SPOOL_UNTIL { RETURN. }

    IF AOSO_STAGING_PENDING_RELIGHT {
        aoso_staging_finish_relight().
        RETURN.
    }

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
        aoso_staging_after_stage().
        SET AOSO_STAGING_EXTRA_THIS TO 0.
        SET AOSO_STAGING_PENDING_RELIGHT TO TRUE.

        aoso_staging_emit(prev, reason, pred).
        SET AOSO_PROFILE_PENDING TO "staging".
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
    LOCAL nlit0 IS aoso_staging_light_unlit().
    IF nlit0 > 0 {
        IF SHIP:AVAILABLETHRUST > 0.05 { RETURN TRUE. }
    }
    IF NOT AOSO_STG_AIRBORNE { RETURN FALSE. }
    IF AOSO_CONFIG["SAFE_MODE"] { RETURN FALSE. }
    IF STAGE:NUMBER <= 0 { RETURN FALSE. }
    IF NOT STAGE:READY { RETURN FALSE. }
    IF TIME:SECONDS < AOSO_STAGING_COOLDOWN_UNTIL { RETURN FALSE. }
    IF AOSO_STG_DROP_FLOWING { RETURN FALSE. }
    LOCAL max_relight IS aoso_config_get("STAGING_MAX_EXTRA", 1).
    IF AOSO_STAGING_RELIGHT_ATTEMPTS >= max_relight { RETURN FALSE. }

    LOCAL can_drop IS FALSE.
    IF AOSO_STG_FUEL_GONE { SET can_drop TO TRUE. }
    IF AOSO_STG_LIT > 0 {
        IF AOSO_STG_FLAMED = AOSO_STG_LIT {
            SET can_drop TO TRUE.
        } ELSE {
            IF AOSO_STG_FLOWING <= 0 { SET can_drop TO TRUE. }
        }
    }
    IF AOSO_STG_LIT = 0 { SET can_drop TO TRUE. }
    IF NOT can_drop { RETURN FALSE. }

    aoso_log_info("STAGING", "Ensuring thrust for upcoming burn, staging (" + STAGE:NUMBER + ").").
    SET AOSO_STAGING_RELIGHT_ATTEMPTS TO AOSO_STAGING_RELIGHT_ATTEMPTS + 1.
    LOCAL prev IS STAGE:NUMBER.
    LOCAL pred IS aoso_capabilities_predict_next().
    STAGE.
    aoso_staging_after_stage().
    SET AOSO_STAGING_EXTRA_THIS TO 0.
    SET AOSO_STAGING_PENDING_RELIGHT TO TRUE.
    aoso_staging_emit(prev, "relight", pred).
    SET AOSO_PROFILE_PENDING TO "ensure_thrust".
    RETURN SHIP:AVAILABLETHRUST > 0.05.
}
