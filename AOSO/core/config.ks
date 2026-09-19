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
    "LOG_LEVEL", "INFO",                // TRACE..FATAL  (INFO default; TRACE is for hard bugs)
    "TELEM_RATE", "AUTO",               // AUTO | FAST | NORMAL | SLOW | OFF
    "OBS_ENABLED", TRUE,
    "PROF_ENABLED", FALSE,
    "PRECISION_LANDING_RADIUS", 150,    // m, acceptable TARGET_ERROR for KSC return
    "MAX_SLOPE_DEG", 15,                // landing-site scoring cutoff
    "DEORBIT_PE_ALT", 30000,            // m, target periapsis for deorbit burns
    "SAFE_MODE", FALSE,
    "AUTO_CHECKPOINT_INTERVAL", 30,     // s between automatic checkpoint saves
    "WATCHDOG_TIMEOUT", 120,            // s of no-progress before watchdog intervenes
    "WATCHDOG_EC_CRITICAL_PCT", 5,       // % ElectricCharge at/below which hardening/watchdog.ks treats power as critical
    "ASCENT_PITCHOVER_SPEED", 80,       // m/s, vertical rise until the gravity turn starts (optimizer searches this)
    "ASCENT_PITCHOVER_MIN_ALT", 200,    // m, extra floor besides speed (raised if nose-heavy / long stack)
    "ASCENT_TURN_BIAS_DEG", 3.2,        // kept so old JSON loads; steering is now MJ classic pitch
    "ASCENT_TURN_BLEND_S", 8,           // kept so old JSON loads; unused by the pitch program
    "ASCENT_TURN_START_ALT", 1000,      // m, MJ classic turn starts here (raised if TWR<1.35 / long stack)
    "ASCENT_TURN_END_ALT", 0,           // m, 0 = auto 0.93 * ATM:HEIGHT; Kerbin about 65100
    "ASCENT_TURN_END_ANGLE", 0,         // deg, pitch at turn end
    "ASCENT_TURN_SHAPE", 0.45,          // MJ shape exponent; 0.25-0.8
    "ASCENT_MAX_AOA", 7,                // deg, Limit AoA around flight-path pitch
    "ASCENT_TWR_LIMIT", 2.2,            // hold TWR here while the flight path is still steep so gravity can turn
    "ASCENT_HOLD_AP_S", 45,             // s, time-to-apoapsis the gravity-turn throttle holds AFTER the path shallows
    "ASCENT_TARGET_APO", 80000,         // m, gravity-turn cuts here; Kerbin 80 km
    "ASCENT_DENSE_ALT", 40000,          // m, splits DENSE_AIR vs UPPER_ATM phase records in flight/ascent_opt.ks
    "ASCENT_OPTIMIZE", TRUE,            // try a grid of turn *start speeds* across pad reverts; lock the leftover-LF winner
    "ASCENT_OPT_MAX_TRIALS", 6,         // pad flights in the start-speed search (5 grid points + 1 optional edge refine)
    "STAGING_FUEL_EMPTY", 0.25,         // units, stage when current-stage LF/Ox/SF drops to/below this
    "STAGING_FUEL_EMPTY_PCT", 1.5,      // % of stage tank capacity also treated as empty (big-tank residue)

    "STAGING_DEAD_S", 0.2,              // s of AVAILABLETHRUST~0 before a thrust-collapse stage
    "STAGING_SPOOL_S", 0.8,             // s after STAGE before we judge thrust (no WAIT; timestamp)
    "STAGING_COOLDOWN_S", 1.2,          // s after STAGE before another auto-stage (flameout still allowed)
    "STAGING_MAX_EXTRA", 1,             // extra STAGE that may drop leftover fuel (relight only)
    "STAGING_MAX_EMPTY_WALK", 6,        // empty fairing/decoupler stages we may walk to reach the next engines
    "MANEUVER_NO_THRUST_TICKS", 40,     // execute_next retries staging this many ticks before declaring a burn dead
    "MANEUVER_FEATHER_S", 2,            // s, remaining burn-time window over which maneuver throttle fades to cut
    "MANEUVER_ALIGN_S", 50,             // s rails lead before ignition; physics 2x after that until WARP_CRUCIAL_S
    "MANEUVER_PHYSICS_UNTIL_S", 10,     // s of 1x remaining (burns / SOI). Align uses physics 2x, not 4x (4x slewed Acacius)
    "WARP_PHYSICS_CRUISE", 2,           // physics-warp multiplier while pointing / atm / ISRU. 2=2x, 3=3x. Never 1x for idle.
    "WARP_CRUCIAL_S", 10,               // last N seconds always 1x (ignition, SOI, suicide)
    "MANEUVER_FOLLOW_ABOVE_S", 8,       // s of remaining burn-time above which we follow the live node instead of locking
    "GOTO_CORRECT_WITHIN_S", 28800,     // s (~8 h): only mid-course a graze this close to SOI; lithobrake still corrects immediately
    "GOTO_CORRECT_MAX", 5,              // mid-course PE retunes per hop (was 3; grazes need more)
    "PORKCHOP_ENABLED", TRUE,           // patched-conic porkchop is the intercept (slow, accurate)
    "PORKCHOP_DEP_SAMPLES", 24,         // departure samples (soon band + Hohmann window)
    "PORKCHOP_DV_SAMPLES", 18,          // prograde Δv samples from ~0.35 Hohmann to near-escape
    "PORKCHOP_NML_SAMPLES", 5,          // small normal/plane samples (odd, centered on 0)
    "PORKCHOP_TOF_SAMPLES", 8,          // Lambert fallback TOFs if the patched grid finds nothing
    "PORKCHOP_TOF_MIN", 0.06,
    "PORKCHOP_TOF_MAX", 1.7,
    "GOTO_PATCH_FLICKER_S", 15,         // s of physics-2x after a patch vanishes, so conics can rebuild before we resume rails
    "GOTO_PATCH_TRUST_S", 600,          // s past expected SOI before we give up on a vanished intercept
    "TOUR_REFUEL_BELOW_PCT", 60,        // % LiquidFuel at/below which the grand tour will land and ISRU-refuel
    "TOUR_MIN_LAND_TWR", 1.4,           // surface TWR required before the grand tour will attempt a landing
    "TOUR_POLAR_INCLINATION", 90,       // deg, parking inclination before a landing-site scan
    "TOUR_POLAR_TOLERANCE_DEG", 15,     // deg, |inc-90| at/below which the orbit is polar enough to scan
    "DV_RESERVE_MIN", 200,              // m/s, floor on the dV budget reserve (also FUEL_RESERVE_PCT of total)
    "DV_ABORT_MIN", 100,                // m/s, abort-budget floor carved out of usable dV
    "FEAS_DV_MARGIN", 1.15,             // multiplier on table dV costs before a destination is declared reachable
    "WINDOW_MAX_WAIT_S", 3888000,       // s (~45 Kerbin days): planner treats longer waits as a reason to pick another cluster first
    "WINDOW_MIN_EFFICIENCY", 0.82,      // 0-1, current-phase vs Hohmann phase; below this the window is "poor"
    "PLANNER_MIN_SHOULD_SCORE", 30,     // 0-100, CAN destinations below this are not SHOULD
    "LANDING_SCAN_SAMPLES", 36,         // ground-track samples scored before picking a landing site
    "LANDING_SCAN_ORBITS", 2,           // orbits to rails-warp while confirming the predicted site
    "MAX_Q_LIMIT_MULT", 1.0,            // extra throttle cap near this-flight peak Q (1.0=off; ASCENT_MAX_Q is the real limiter)
    "ASCENT_MAX_Q", 0.30,               // atm (SHIP:Q). Throttle down while Q is still rising above this. 0=off. 0.30≈30 kPa.
    "DESCENT_BURN_MARGIN_S", 4,         // s of surface-speed reaction time added to the suicide-burn trigger altitude
    "DESCENT_STOP_MARGIN", 1.2,         // extra multiplier on kinematic stop distance (elwanderer / MechJeb-style pad)
    "DESCENT_RADAR_OFFSET", 0,          // m, extra radar offset; 0 = measure from the lowest part at descent start
    "DESCENT_FINAL_APPROACH_ALT", 150,  // m, radar altitude where descent *may* switch to a slow vertical hold
    "DESCENT_FINAL_SPEED_MAX", 25,      // m/s surface speed required before leaving suicide burn for final approach
    "DESCENT_FINAL_SPEED", -3,          // m/s, target vertical speed held during final approach
    "DESCENT_TOUCHDOWN_ALT", 0.5,       // m, radar altitude below which touchdown is declared
    "DESCENT_SAFE_PE_ALT", 8000,        // m, airless deorbit ceiling if no site (never sea level / lithobrake)
    "DESCENT_PE_MARGIN", 600,           // m above scanned site terrain for airless deorbit PE (8 km was above suicide range on Minmus)
    "LOW_EC_PCT", 20,                   // % ElectricCharge at/below which fuel cells are enabled
    "FUEL_CELL_DISABLE_PCT", 90,        // % ElectricCharge at/above which fuel cells are disabled
    "PANEL_MAX_AIRSPEED", 50,           // m/s, airspeed inside atmosphere above which panels retract
    "REFUEL_TARGET_PCT", 95,            // % capacity of a harvested resource considered "full enough"
    "REFUEL_ORE_MIN_AMOUNT", 0.01,      // Ore units; NOT used as biome-empty. Harvest stall is REFUEL_STALL_S.
    "REFUEL_STALL_S", 90,               // s without fuel/ore progress before harvest is considered stalled
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
    "DOCKING_RCS_GAIN", 0.5,             // unitless, velocity error(m/s) * gain = RCS translation command (-1..1, clamped)
    "XP_MIN_SAMPLES", 3,                // samples before a learned correction has moderate influence
    "XP_MAX_CORRECTION", 0.35,          // max |corr-1|; 0.35 => 0.65x..1.35x
    "BRAIN_THINK_LEAD_S", 600,          // s of node ETA required before expensive nav/plan work
    "BRAIN_THINK_WAIT_S", 90,           // s to sit in orbit waiting for a quiet window
    "BRAIN_REPLAN_DEBOUNCE_S", 45,      // s minimum between full route rebuilds
    "ROUTE_SCORE_WEIGHT", 8,            // opportunity-score influence on cluster hop cost (higher = score matters more)
    "ROUTE_FUTURE_ISRU", 180,           // hop-cost discount when the destination can refill the tank
    "WATCHDOG_PROGRESS_S", 90,          // s of no controller heartbeat progress before a stall is considered
    "IPU_TARGET", 2000,                 // CONFIG:IPU headroom applied once at boot (not a utilization target)
    "CPU_RESERVE_ABS", 400,             // leftover opcodes background work must not consume
    "CPU_RESERVE_FRAC", 0.18,           // fraction of CONFIG:IPU also reserved
    "CPU_RESERVE_ASCENT", 500,
    "CPU_RESERVE_MANEUVER", 500,
    "CPU_RESERVE_DESCENT", 650,
    "CPU_RESERVE_DOCKING", 600,
    "CPU_RESERVE_ORBIT", 350,
    "CPU_RESERVE_COAST", 250,
    "CORRECT_LOCAL_DV", 25,             // m/s residual treated as a local correction, not a replan
    "REPLAN_DV_ERROR", 250,             // m/s prediction error that requests a strategic replan
    "CPU_PROFILE", FALSE                // extra per-task opcode stats (also honors PROF_ENABLED)
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
    // Old kick-angle configs commanded 10-20 deg off vertical. The 1.8 deg
    // / 12 s "smooth" config produced a sounding rocket (Acacius FPA 83 deg
    // at 30 km, 1807 m/s circ). Reset those leftovers.
    IF AOSO_CONFIG:HASKEY("ASCENT_TURN_BLEND_S") {
        IF AOSO_CONFIG["ASCENT_TURN_BLEND_S"] > 10 {
            SET AOSO_CONFIG["ASCENT_TURN_BLEND_S"] TO 8.
            IF AOSO_CONFIG:HASKEY("ASCENT_TURN_BIAS_DEG") {
                IF AOSO_CONFIG["ASCENT_TURN_BIAS_DEG"] <= 2 {
                    SET AOSO_CONFIG["ASCENT_TURN_BIAS_DEG"] TO 3.2.
                }
            }
        }
    }
    IF AOSO_CONFIG:HASKEY("ASCENT_TURN_BIAS_DEG") {
        IF AOSO_CONFIG["ASCENT_TURN_BIAS_DEG"] > 5 {
            SET AOSO_CONFIG["ASCENT_TURN_BIAS_DEG"] TO 5.
        }
        IF AOSO_CONFIG["ASCENT_TURN_BIAS_DEG"] < 0 {
            SET AOSO_CONFIG["ASCENT_TURN_BIAS_DEG"] TO 0.
        }
    }
    IF AOSO_CONFIG:HASKEY("ASCENT_TURN_BLEND_S") {
        IF AOSO_CONFIG["ASCENT_TURN_BLEND_S"] < 5 {
            SET AOSO_CONFIG["ASCENT_TURN_BLEND_S"] TO 5.
        }
        IF AOSO_CONFIG["ASCENT_TURN_BLEND_S"] > 12 {
            SET AOSO_CONFIG["ASCENT_TURN_BLEND_S"] TO 12.
        }
    }
    IF AOSO_CONFIG:HASKEY("ASCENT_TWR_LIMIT") {
        IF AOSO_CONFIG["ASCENT_TWR_LIMIT"] < 1.3 {
            SET AOSO_CONFIG["ASCENT_TWR_LIMIT"] TO 1.3.
        }
        IF AOSO_CONFIG["ASCENT_TWR_LIMIT"] > 2.4 {
            SET AOSO_CONFIG["ASCENT_TWR_LIMIT"] TO 2.4.
        }
    }
    IF AOSO_CONFIG:HASKEY("STAGING_SPOOL_S") {
        IF AOSO_CONFIG["STAGING_SPOOL_S"] < 0.5 {
            SET AOSO_CONFIG["STAGING_SPOOL_S"] TO 0.8.
        }
    }
    IF AOSO_CONFIG:HASKEY("ASCENT_TURN_SHAPE") {
        IF AOSO_CONFIG["ASCENT_TURN_SHAPE"] < 0.25 {
            SET AOSO_CONFIG["ASCENT_TURN_SHAPE"] TO 0.25.
        }
        IF AOSO_CONFIG["ASCENT_TURN_SHAPE"] > 0.8 {
            SET AOSO_CONFIG["ASCENT_TURN_SHAPE"] TO 0.8.
        }
    }
    IF AOSO_CONFIG:HASKEY("ASCENT_MAX_AOA") {
        IF AOSO_CONFIG["ASCENT_MAX_AOA"] < 3 {
            SET AOSO_CONFIG["ASCENT_MAX_AOA"] TO 3.
        }
        IF AOSO_CONFIG["ASCENT_MAX_AOA"] > 15 {
            SET AOSO_CONFIG["ASCENT_MAX_AOA"] TO 15.
        }
    }
    // Old JSON sat 120 s at 1x after every rails drop. Cap those leftovers
    // so physics-2x cruise actually runs.
    IF AOSO_CONFIG:HASKEY("MANEUVER_ALIGN_S") {
        IF AOSO_CONFIG["MANEUVER_ALIGN_S"] > 60 {
            SET AOSO_CONFIG["MANEUVER_ALIGN_S"] TO 50.
        }
    }
    IF AOSO_CONFIG:HASKEY("MANEUVER_PHYSICS_UNTIL_S") {
        IF AOSO_CONFIG["MANEUVER_PHYSICS_UNTIL_S"] > 15 {
            SET AOSO_CONFIG["MANEUVER_PHYSICS_UNTIL_S"] TO 10.
        }
    }
    IF AOSO_CONFIG:HASKEY("GOTO_PATCH_FLICKER_S") {
        IF AOSO_CONFIG["GOTO_PATCH_FLICKER_S"] > 20 {
            SET AOSO_CONFIG["GOTO_PATCH_FLICKER_S"] TO 15.
        }
    }
    aoso_log_set_level(aoso_config_get("LOG_LEVEL", "INFO")).
    RETURN AOSO_CONFIG.
}

FUNCTION aoso_config_save {
    aoso_json_write(AOSO_CONST["CONFIG_FILE"], AOSO_CONFIG).
}
