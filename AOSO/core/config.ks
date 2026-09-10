// AOSO/core/config.ks
// Central configuration store with sensible, documented defaults. Persisted
// to AOSO_CONST["CONFIG_FILE"] as JSON and reloaded on boot so operator
// overrides from a previous session survive reloads/resume.

GLOBAL AOSO_CONFIG IS LEXICON(
    "PARKING_ORBIT_ALT", 100000,        // m, default parking orbit altitude
    "FUEL_RESERVE_PCT", 10,             // % of stage fuel kept as untouchable reserve
    "ABORT_FUEL_PCT", 3,                // % remaining that forces an abort
    "MAX_WARP_FACTOR", 6,               // cap on TIMEWARP:WARP used by any module
    "OPTIMIZATION_MODE", "BALANCED",    // FUEL | TIME | SAFETY | BALANCED | MINIMUM_DV
    "LOG_LEVEL", "DEBUG",               // TRACE..FATAL
    "PRECISION_LANDING_RADIUS", 150,    // m, acceptable TARGET_ERROR for KSC return
    "MAX_SLOPE_DEG", 15,                // landing-site scoring cutoff
    "DEORBIT_PE_ALT", 30000,            // m, target periapsis for deorbit burns
    "SAFE_MODE", FALSE,
    "AUTO_CHECKPOINT_INTERVAL", 30,     // s between automatic checkpoint saves
    "WATCHDOG_TIMEOUT", 120,            // s of no-progress before watchdog intervenes
    "WATCHDOG_EC_CRITICAL_PCT", 5,       // % ElectricCharge at/below which hardening/watchdog.ks treats power as critical
    "ASCENT_PITCHOVER_SPEED", 80,       // m/s, vertical rise until pitchover (raised for low TWR / nose-heavy, lowered for high TWR)
    "ASCENT_PITCHOVER_DEG", 10,         // deg from vertical at pitchover; TWR- and CoM-scaled at runtime (~6-14)
    "ASCENT_PITCHOVER_RATE", 0.75,      // deg/s, pitch ramp during pitchover (MechJeb PVG; slower if nose-heavy)
    "ASCENT_PITCHOVER_MIN_ALT", 200,    // m, extra floor besides speed (raised if nose-heavy / long stack)
    "ASCENT_HOLD_AP_S", 45,             // s, time-to-apoapsis the gravity-turn throttle holds AFTER leaving dense air
    "ASCENT_TARGET_APO", 80000,         // m, default target apoapsis for ascent AP
    "ASCENT_FULL_THROTTLE_ALT", 45000,  // m, stay at full throttle (on prograde) until this altitude so 50-70 km is not a 35% crawl
    "MANEUVER_FEATHER_S", 2,            // s, remaining burn-time window over which maneuver throttle fades to cut
    "MANEUVER_ALIGN_S", 120,            // s of physics time after warp, before ignition, to point the ship at the burn
    "MANEUVER_FOLLOW_ABOVE_S", 8,       // s of remaining burn-time above which we follow the live node instead of locking
    "TOUR_REFUEL_BELOW_PCT", 60,        // % LiquidFuel at/below which the grand tour will land and ISRU-refuel
    "TOUR_MIN_LAND_TWR", 1.4,           // surface TWR required before the grand tour will attempt a landing
    "TOUR_POLAR_INCLINATION", 90,       // deg, parking inclination before a landing-site scan
    "TOUR_POLAR_TOLERANCE_DEG", 15,     // deg, |inc-90| at/below which the orbit is polar enough to scan
    "DV_RESERVE_MIN", 200,              // m/s, floor on the dV budget reserve (also FUEL_RESERVE_PCT of total)
    "DV_ABORT_MIN", 100,                // m/s, abort-budget floor carved out of usable dV
    "FEAS_DV_MARGIN", 1.15,             // multiplier on table dV costs before a destination is declared reachable
    "LANDING_SCAN_SAMPLES", 24,         // ground-track samples scored before picking a landing site
    "MAX_Q_LIMIT_MULT", 1.0,            // throttle back factor near max-Q (1.0=off)
    "DESCENT_BURN_MARGIN_S", 4,         // s of surface-speed reaction time added to the suicide-burn trigger altitude
    "DESCENT_STOP_MARGIN", 1.2,         // extra multiplier on kinematic stop distance (elwanderer / MechJeb-style pad)
    "DESCENT_RADAR_OFFSET", 0,          // m, extra radar offset; 0 = measure from the lowest part at descent start
    "DESCENT_FINAL_APPROACH_ALT", 150,  // m, radar altitude where descent *may* switch to a slow vertical hold
    "DESCENT_FINAL_SPEED_MAX", 25,      // m/s surface speed required before leaving suicide burn for final approach
    "DESCENT_FINAL_SPEED", -3,          // m/s, target vertical speed held during final approach
    "DESCENT_TOUCHDOWN_ALT", 0.5,       // m, radar altitude below which touchdown is declared
    "DESCENT_SAFE_PE_ALT", 8000,        // m, airless deorbit periapsis floor (never sea level / lithobrake)
    "LOW_EC_PCT", 20,                   // % ElectricCharge at/below which fuel cells are enabled
    "FUEL_CELL_DISABLE_PCT", 90,        // % ElectricCharge at/above which fuel cells are disabled
    "PANEL_MAX_AIRSPEED", 50,           // m/s, airspeed inside atmosphere above which panels retract
    "REFUEL_TARGET_PCT", 95,            // % capacity of a harvested resource considered "full enough"
    "REFUEL_ORE_MIN_AMOUNT", 0.01,      // Ore units at/below which harvesting is considered depleted
    "HOME_BODY", "Kerbin",              // body return/return.ks treats as the final destination
    "KSC_LAT", -0.0972,                 // deg, precision/kscreturn.ks default target site latitude (stock KSC)
    "KSC_LNG", -74.5577,                // deg, precision/kscreturn.ks default target site longitude (stock KSC)
    "PRECISION_INCLINATION_TOLERANCE_DEG", 1,   // deg from equatorial before precision/kscreturn.ks plane-aligns first
    "PRECISION_MAX_DEORBIT_DELAY_ORBITS", 3,    // extra orbits precision/kscreturn.ks may wait to line up the ground track
    "DOCKING_STANDOFF_DIST", 30,         // m, advanced/docking.ks stand-off waypoint distance out along the target port's facing
    "DOCKING_WAYPOINT_TOLERANCE_M", 2,   // m, distance to the stand-off waypoint before switching to final closing
    "DOCKING_MAX_APPROACH_SPEED", 2,     // m/s, closing speed cap while inbound to the stand-off waypoint
    "DOCKING_MAX_FINAL_SPEED", 0.3,      // m/s, closing speed cap during the direct final approach onto the port
    "DOCKING_ALIGN_TOLERANCE_DEG", 5,    // deg, facing error allowed before advanced/docking.ks starts translating
    "DOCKING_CLOSING_GAIN", 0.3,         // unitless, distance(m) * gain = desired closing speed (m/s), capped above
    "DOCKING_RCS_GAIN", 0.5              // unitless, velocity error(m/s) * gain = RCS translation command (-1..1, clamped)
).

FUNCTION aoso_config_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_CONFIG:HASKEY(key) { RETURN AOSO_CONFIG[key]. }
    RETURN default_value.
}

FUNCTION aoso_config_set {
    PARAMETER key.
    PARAMETER value.
    SET AOSO_CONFIG[key] TO value.
}

FUNCTION aoso_config_load {
    LOCAL loaded IS aoso_json_read(AOSO_CONST["CONFIG_FILE"], LEXICON()).
    IF loaded:ISTYPE("Lexicon") {
        FOR k IN loaded:KEYS {
            SET AOSO_CONFIG[k] TO loaded[k].
        }
    }
    aoso_log_set_level(aoso_config_get("LOG_LEVEL", "DEBUG")).
    RETURN AOSO_CONFIG.
}

FUNCTION aoso_config_save {
    aoso_json_write(AOSO_CONST["CONFIG_FILE"], AOSO_CONFIG).
}
