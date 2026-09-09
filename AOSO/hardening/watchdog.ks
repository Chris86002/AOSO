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
    "tripped", FALSE
).

// A cheap "did anything happen" fingerprint: AOSO_MISSION's own history
// length while the mission layer is active, or -1 (never stalled) if it
// isn't running at all.
FUNCTION aoso_watchdog_progress_marker {
    IF DEFINED AOSO_MISSION AND AOSO_MISSION["current"] <> "" {
        RETURN AOSO_MISSION["history"]:LENGTH.
    }
    RETURN -1.
}

FUNCTION aoso_watchdog_critical_condition {
    IF aoso_fuel_abort_check() { RETURN TRUE. }
    IF aoso_power_ec_pct() <= aoso_config_get("WATCHDOG_EC_CRITICAL_PCT", 5) {
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
FUNCTION aoso_watchdog_trip {
    IF AOSO_WATCHDOG["tripped"] { RETURN. }
    SET AOSO_WATCHDOG["tripped"] TO TRUE.

    aoso_log_fatal("WATCHDOG", "No mission progress for " + aoso_config_get("WATCHDOG_TIMEOUT", 120) +
        "s with a critical condition active; forcing safe abort.").
    LOCK THROTTLE TO 0.
    aoso_steer_release().
    IF DEFINED AOSO_MISSION AND AOSO_MISSION["current"] <> "" {
        aoso_state_abort(AOSO_MISSION).
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
    IF marker < 0 { RETURN. } // no mission layer running - nothing to watch

    LOCAL stalled_s IS TIME:SECONDS - AOSO_WATCHDOG["last_progress_at"].
    IF stalled_s < aoso_config_get("WATCHDOG_TIMEOUT", 120) { RETURN. }

    IF aoso_watchdog_critical_condition() {
        aoso_watchdog_trip().
    }
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
