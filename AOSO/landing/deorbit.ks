// AOSO/landing/deorbit.ks
// Deorbit burn: lowers periapsis to bring the vessel down for landing.
// Reuses nav/hohmann.ks's generic periapsis-change math (the same relation
// interplanetary/ejection.ks has with nav/hohmann.ks) instead of duplicating
// vis-viva, and flight/maneuver.ks's aoso_maneuver_execute_next() as the
// burn executor, so this file is only concerned with picking/logging the
// target periapsis.

// Target periapsis altitude (m) for a deorbit burn. Atmospheric bodies use
// the configured DEORBIT_PE_ALT (core/config.ks) directly -- deep enough to
// guarantee entry, shallow enough that landing/descent.ks and any
// parachutes still have room to work. Airless bodies have no atmosphere to
// aerobrake into, so the configured altitude (tuned for atmospheric entry)
// would just leave the ship coasting in a low orbit; instead this targets
// a periapsis of 0 (sea level), which for a body with a solid surface
// guarantees the orbit intersects the terrain, so landing/descent.ks's
// suicide-burn logic is guaranteed to get a chance to take over once radar
// altitude gets low, the same convention most kOS landing scripts use.
FUNCTION aoso_deorbit_target_periapsis_alt {
    IF SHIP:BODY:ATM:EXISTS {
        RETURN aoso_config_get("DEORBIT_PE_ALT", 30000).
    }
    RETURN 0.
}

// Adds a deorbit node. Accepts an explicit target_pe_alt for callers with a
// specific landing site/altitude in mind; otherwise falls back to
// aoso_deorbit_target_periapsis_alt(). Returns 0 (no node) if the current
// periapsis is already at/below the target, since nav/hohmann.ks's
// apoapsis-side burn math assumes the target is a genuine lowering.
FUNCTION aoso_deorbit_add_node {
    PARAMETER target_pe_alt IS 0.
    PARAMETER has_target IS FALSE.

    IF NOT has_target { SET target_pe_alt TO aoso_deorbit_target_periapsis_alt(). }

    IF PERIAPSIS <= target_pe_alt {
        IF DEFINED aoso_log_info {
            aoso_log_info("DEORBIT", "Periapsis already at/below target; no deorbit burn needed.").
        }
        RETURN 0.
    }

    LOCAL nd IS aoso_hohmann_add_periapsis_change(target_pe_alt).
    IF DEFINED aoso_log_info {
        aoso_log_info("DEORBIT", "Deorbit node added: target periapsis=" + ROUND(target_pe_alt, 0) + "m.").
    }
    RETURN nd.
}

// Non-blocking burn executor, kept as its own named wrapper (rather than
// having callers hit flight/maneuver.ks directly) so a later phase can
// insert deorbit-specific bookkeeping (e.g. mission-state transitions)
// without touching every call site.
FUNCTION aoso_deorbit_execute {
    RETURN aoso_maneuver_execute_next().
}
