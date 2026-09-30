// AOSO/landing/deorbit.ks
// Deorbit burn: lowers periapsis to bring the vessel down for landing.
// Reuses nav/hohmann.ks's generic periapsis-change math (the same relation
// interplanetary/ejection.ks has with nav/hohmann.ks) instead of duplicating
// vis-viva, and flight/maneuver.ks's aoso_maneuver_execute_next() as the
// burn executor, so this file is only concerned with picking/logging the
// target periapsis.

// Target periapsis altitude (m) for a deorbit burn. Atmospheric bodies use
// DEORBIT_PE_ALT so drag/chutes still have room. A true airless suicide burn
// must start from an IMPACT trajectory: a periapsis above the selected
// terrain can only be arrested high and then hovered down. Aim a bounded
// distance below the scanned terrain; landing/descent.ks waits until its
// full-thrust retrograde simulation says ignition is due.
FUNCTION aoso_deorbit_site_alt {
    IF DEFINED AOSO_TOUR {
        IF AOSO_TOUR:HASKEY("data") {
            IF AOSO_TOUR["data"]:HASKEY("site_alt") {
                RETURN AOSO_TOUR["data"]["site_alt"].
            }
        }
    }
    RETURN 0.
}

FUNCTION aoso_deorbit_target_periapsis_alt {
    IF SHIP:BODY:ATM:EXISTS {
        RETURN aoso_config_get("DEORBIT_PE_ALT", 30000).
    }
    LOCAL impact_depth IS aoso_config_get("DESCENT_IMPACT_DEPTH", 500).
    IF impact_depth < 100 { SET impact_depth TO 100. }
    IF impact_depth > 2000 { SET impact_depth TO 2000. }
    LOCAL site_alt IS aoso_deorbit_site_alt().
    LOCAL target_pe IS site_alt - impact_depth.
    LOCAL radius_floor IS 0 - SHIP:BODY:RADIUS * 0.5.
    IF target_pe < radius_floor { SET target_pe TO radius_floor. }
    RETURN target_pe.
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
    LOCAL burn_eta IS aoso_orbit_eta_apoapsis().
    IF eta_s >= 0 { SET burn_eta TO eta_s. }
    LOCAL nd IS NODE(TIME:SECONDS + burn_eta, 0, 0, dv).
    ADD nd.
    aoso_log_info("DEORBIT", "Deorbit node added: target periapsis=" + ROUND(target_pe_alt, 0) + "m, dv=" + ROUND(dv, 1) + " m/s, in " + ROUND(burn_eta, 0) + "s.").
    RETURN nd.
}
