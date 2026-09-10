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
// parachutes still have room to work. Airless bodies used to target PE=0
// (sea level), which on Mun put Acacius on a lithobrake ellipse (PE=-1923 m)
// and the suicide burn never had a circular-ish approach to work from.
// Airless PE is now a floor above the highlands (DESCENT_SAFE_PE_ALT) so
// descent.ks's hoverslam starts from a finite radar altitude, not a crater.
FUNCTION aoso_deorbit_target_periapsis_alt {
    IF SHIP:BODY:ATM:EXISTS {
        RETURN aoso_config_get("DEORBIT_PE_ALT", 30000).
    }
    LOCAL floor_alt IS aoso_config_get("DESCENT_SAFE_PE_ALT", 8000).
    LOCAL body_cap IS SHIP:BODY:RADIUS * 0.2.
    IF floor_alt > body_cap {
        SET floor_alt TO MAX(2000, SHIP:BODY:RADIUS * 0.1).
    }
    IF floor_alt < 2000 { SET floor_alt TO 2000. }
    RETURN floor_alt.
}

// Adds a deorbit node. Accepts an explicit target_pe_alt for callers with a
// specific landing site/altitude in mind; otherwise falls back to
// aoso_deorbit_target_periapsis_alt(). eta_s > 0 places the burn that many
// seconds from now instead of at apoapsis -- used when the tour has a
// scanned site and wants to burn while opposite it so PE is over the site.
// Returns 0 (no node) if the current periapsis is already at/below the target.
FUNCTION aoso_deorbit_add_node {
    PARAMETER target_pe_alt IS 0.
    PARAMETER has_target IS FALSE.
    PARAMETER eta_s IS -1.

    IF NOT has_target { SET target_pe_alt TO aoso_deorbit_target_periapsis_alt(). }

    IF PERIAPSIS <= target_pe_alt {
        aoso_log_info("DEORBIT", "Periapsis already at/below target; no deorbit burn needed.").
        RETURN 0.
    }

    LOCAL dv IS aoso_hohmann_dv_at_apoapsis_for_periapsis(target_pe_alt).
    LOCAL burn_eta IS ETA:APOAPSIS.
    IF eta_s >= 0 { SET burn_eta TO eta_s. }
    LOCAL nd IS NODE(TIME:SECONDS + burn_eta, 0, 0, dv).
    ADD nd.
    aoso_log_info("DEORBIT", "Deorbit node added: target periapsis=" + ROUND(target_pe_alt, 0) + "m, dv=" + ROUND(dv, 1) + " m/s, in " + ROUND(burn_eta, 0) + "s.").
    RETURN nd.
}

// Non-blocking burn executor, kept as its own named wrapper (rather than
// having callers hit flight/maneuver.ks directly) so a later phase can
// insert deorbit-specific bookkeeping (e.g. mission-state transitions)
// without touching every call site.
FUNCTION aoso_deorbit_execute {
    RETURN aoso_maneuver_execute_next().
}