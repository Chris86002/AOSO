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
// parachutes still have room to work. Airless PE used to be a global
// DESCENT_SAFE_PE_ALT (8 km). On Minmus that parked Acacius on a 25x8 km
// ellipse: suicide trigger was ~2.5 km (TWR 41) so the hoverslam never
// started and descent looped apo-to-pe forever. Airless PE is now the
// scanned site terrain plus DESCENT_PE_MARGIN so the ground is actually
// inside the suicide radar, with a small floor to avoid lithobrakes.
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
    LOCAL margin IS aoso_config_get("DESCENT_PE_MARGIN", 600).
    IF margin < 300 { SET margin TO 300. }
    IF margin > 2500 { SET margin TO 2500. }
    LOCAL site_alt IS aoso_deorbit_site_alt().
    LOCAL target_pe IS site_alt + margin.
    LOCAL min_pe IS 400.
    IF SHIP:BODY:RADIUS < 80000 {
        SET min_pe TO 250.
    }
    IF target_pe < min_pe { SET target_pe TO min_pe. }
    LOCAL cap IS aoso_config_get("DESCENT_SAFE_PE_ALT", 8000).
    IF cap > SHIP:BODY:RADIUS * 0.15 {
        SET cap TO MAX(1500, SHIP:BODY:RADIUS * 0.08).
    }
    IF target_pe > cap { SET target_pe TO cap. }
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