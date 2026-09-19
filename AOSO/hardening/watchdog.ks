// AOSO/hardening/watchdog.ks
// Phase 12 (Hardening & UX): system-wide safety net for the WATCHDOG_TIMEOUT
// config key core/config.ks has reserved since Phase 1 but that no module
// actually consumed until now. core/state.ks's own per-state
// timeout_s/on_timeout only fires for states that opt into it; this
// watchdog instead watches whichever machine is actually driving the
// mission right now (mission/mission.ks's AOSO_MISSION) for *any* progress
// -- its own "history" list (one entry per transition) growing -- and,
// combined with a genuinely critical vehicle condition (stage propellant at
// vehicle/resources.ks's ABORT_FUEL_PCT, or ElectricCharge critical), forces
// a safe abort rather than letting a wedged step burn propellant/time
// indefinitely.
//
// A critical condition alone is not enough to trip the watchdog -- a short
// EC dip while panels are retracted during re-entry, or a fuel-critical
// stage that is about to separate anyway, is normal and should recover on
// its own -- so aoso_watchdog_tick() only acts once BOTH:
//   1. no mission-plan progress for WATCHDOG_TIMEOUT seconds, AND
//   2. a critical condition is still true at that moment.
// This mirrors return/return.ks's and precision/kscreturn.ks's own
// aoso_fuel_abort_check() consultation, just promoted to a system-wide
// last-resort rather than a per-module check. Without a mission layer
// running (AOSO_MISSION never started, e.g. manual flight with only
// hardening/UX tasks registered) there is nothing to consider "stalled",
// so the watchdog simply never trips.

GLOBAL AOSO_WATCHDOG IS LEXICON(
    "last_progress_marker", -1,
    "last_progress_at", 0,
    "tripped", FALSE,
    "recovery", "",
    "last_stall_action_at", 0
).

// Watchdog: no mission/tour history growth AND no controller heartbeat
// movement, plus a genuinely critical fuel/EC condition, forces abort.
// Heartbeats (`aoso_hb_set`) only advance progress_at when state or
// progress actually moved, so a stuck suicide burn is visible.
FUNCTION aoso_watchdog_progress_marker {
    LOCAL n IS 0.
    LOCAL live IS FALSE.
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "" {
            SET live TO TRUE.
            SET n TO n + AOSO_MISSION["history"]:LENGTH.
        }
    }
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR["current"] <> "" {
            SET live TO TRUE.
            SET n TO n + AOSO_TOUR["history"]:LENGTH * 1000.
            IF AOSO_TOUR:HASKEY("data") {
                IF AOSO_TOUR["data"]:HASKEY("index") {
                    SET n TO n + AOSO_TOUR["data"]["index"].
                }
            }
        }
    }
    IF live { RETURN n. }
    RETURN -1.
}

FUNCTION aoso_watchdog_critical_condition {
    IF aoso_fuel_abort_check() { RETURN TRUE. }
    IF aoso_power_ec_pct() <= AOSO_CONFIG["WATCHDOG_EC_CRITICAL_PCT"] {
        // Power is recoverable until the airstream shell is off and panels
        // are out. Aborting a suborbital coast because EC dipped while the
        // fairing was still on is how the last Acacius flight died.
        IF aoso_power_fairings_pending() { RETURN FALSE. }
        IF aoso_vessel_get("has_solar_panels", FALSE) {
            IF NOT AOSO_POWER_PANELS_DEPLOYED { RETURN FALSE. }
        }
        RETURN TRUE.
    }
    RETURN FALSE.
}

// Cuts throttle/steering and aborts the mission machine exactly once; safe
// to call repeatedly (subsequent calls are no-ops until aoso_watchdog_reset()).
FUNCTION aoso_watchdog_in_critical_flight {
    LOCAL phase IS "".
    IF DEFINED AOSO_OBS_PHASE { SET phase TO AOSO_OBS_PHASE. }
    LOCAL ctl IS "".
    IF DEFINED AOSO_CTX { SET ctl TO aoso_ctx_get("controller", ""). }
    IF phase = "ASCENT" { RETURN TRUE. }
    IF phase = "DESCENT" { RETURN TRUE. }
    IF phase = "LANDING" { RETURN TRUE. }
    IF ctl = "ascent" { RETURN TRUE. }
    IF ctl = "descent" { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION aoso_watchdog_recovery_kind {
    PARAMETER stalled.
    PARAMETER critical.
    PARAMETER flying.
    IF NOT stalled { RETURN "NONE". }
    IF critical { RETURN "ABORT". }
    IF flying { RETURN "NONE". }
    RETURN "REPLAN".
}

FUNCTION aoso_watchdog_recover {
    IF AOSO_WATCHDOG["tripped"] { RETURN. }
    LOCAL now IS TIME:SECONDS.
    IF now - AOSO_WATCHDOG["last_stall_action_at"] < aoso_config_get("WATCHDOG_PROGRESS_S", 90) {
        RETURN.
    }
    SET AOSO_WATCHDOG["last_stall_action_at"] TO now.
    LOCAL ctl IS "".
    IF DEFINED AOSO_CTX { SET ctl TO aoso_ctx_get("controller", ""). }
    aoso_throttle_set(0).
    IF HASNODE {
        REMOVE NEXTNODE.
    }
    IF ctl = "refuel" {
        IF DEFINED AOSO_REFUEL {
            SET DRILLS TO FALSE.
            SET ISRU TO FALSE.
        }
    }
    SET AOSO_WATCHDOG["recovery"] TO "REPLAN".
    aoso_event_publish("REPLAN_REQUESTED", "watchdog", "stall " + ctl).
    aoso_log_warn("WATCHDOG", "Stalled without critical resources; requesting replan (" + ctl + ").").
    IF AOSO_WATCHDOG["recovery"] = "REPLAN" {
        IF now - AOSO_WATCHDOG["last_progress_at"] > aoso_config_get("WATCHDOG_TIMEOUT", 120) * 2 {
            aoso_safe_hold("watchdog stall hold").
            SET AOSO_WATCHDOG["recovery"] TO "HOLD".
        }
    }
}

FUNCTION aoso_watchdog_trip {
    IF AOSO_WATCHDOG["tripped"] { RETURN. }
    SET AOSO_WATCHDOG["tripped"] TO TRUE.

    aoso_log_fatal("WATCHDOG", "No mission progress for " + AOSO_CONFIG["WATCHDOG_TIMEOUT"] +
        "s with a critical condition active; forcing safe abort.").
    aoso_throttle_set(0).
    aoso_steer_release().
    IF DEFINED AOSO_MISSION {
        IF AOSO_MISSION["current"] <> "" {
            aoso_state_abort(AOSO_MISSION).
        }
    }
}

FUNCTION aoso_watchdog_reset {
    SET AOSO_WATCHDOG["tripped"] TO FALSE.
    SET AOSO_WATCHDOG["last_progress_marker"] TO aoso_watchdog_progress_marker().
    SET AOSO_WATCHDOG["last_progress_at"] TO TIME:SECONDS.
}

FUNCTION aoso_watchdog_tick {
    IF AOSO_WATCHDOG["tripped"] { RETURN. }

    LOCAL marker IS aoso_watchdog_progress_marker().
    IF marker <> AOSO_WATCHDOG["last_progress_marker"] {
        SET AOSO_WATCHDOG["last_progress_marker"] TO marker.
        SET AOSO_WATCHDOG["last_progress_at"] TO TIME:SECONDS.
        RETURN.
    }

    LOCAL hb_at IS 0.
    IF DEFINED AOSO_HB {
        SET hb_at TO aoso_hb_any_progress_at().
    }
    LOCAL progress_at IS AOSO_WATCHDOG["last_progress_at"].
    IF hb_at > progress_at { SET progress_at TO hb_at. }

    IF marker < 0 {
        IF hb_at <= 0 { RETURN. }
    }

    LOCAL stalled_s IS TIME:SECONDS - progress_at.
    LOCAL hist_limit IS AOSO_CONFIG["WATCHDOG_TIMEOUT"].
    LOCAL hb_limit IS aoso_config_get("WATCHDOG_PROGRESS_S", 90).
    LOCAL stalled IS FALSE.
    IF stalled_s >= hist_limit { SET stalled TO TRUE. }
    IF hb_at > 0 {
        IF TIME:SECONDS - hb_at < hb_limit { SET stalled TO FALSE. }
    }
    IF NOT stalled { RETURN. }

    LOCAL flying IS aoso_watchdog_in_critical_flight().
    IF aoso_watchdog_critical_condition() {
        aoso_watchdog_trip().
        RETURN.
    }
    IF flying { RETURN. }
    aoso_watchdog_recover().
}

FUNCTION aoso_watchdog_is_tripped {
    RETURN AOSO_WATCHDOG["tripped"].
}

// Wires the watchdog into core/scheduler.ks, mirroring
// vehicle/staging.ks's aoso_staging_register_task().
FUNCTION aoso_watchdog_register_task {
    PARAMETER interval_s IS 1.
    aoso_watchdog_reset().
    aoso_sched_add("watchdog", interval_s, aoso_watchdog_tick@).
}
