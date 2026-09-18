// AOSO/main.ks
// Top-level entry point (see README.md's "run \"AOSO/main\"." install step).
// Loads every AOSO module in dependency order (core first, per
// core/boot.ks's own header comment: constants -> logger -> addons ->
// config -> json -> everything else; every other file only calls into
// core's functions from inside a function body, never at load time, so the
// rest of the load order does not matter), runs the boot sequence, arms
// every subsystem/hardening/UX scheduler task, then drives the main loop.
//
// This file avoids hard-coding mission/mission.ks's AOSO_MISSION_PLAN --
// building a plan (which body, which orbit, whether to dock/refuel/return)
// is mission-specific and left to the operator. Create an
// "AOSO/mission_plan.ks" alongside this file with your own
// aoso_mission_plan_add()/aoso_mission_step_*() calls followed by
// aoso_mission_start(); main.ks RUNs it automatically if present and always
// registers the mission scheduler task so a custom plan that only calls
// start() still ticks. Without one, AOSO still boots and arms hardening/UX/
// vehicle automation, then starts the default grand tour (every stock planet
// and moon, ISRU refuel where the ship can and needs to, then KSC return)
// from wherever the vessel currently is -- pad, orbit, or another body.

// --- Core (order matters; see core/boot.ks) --------------------------------
RUN ONCE "AOSO/core/constants".
RUN ONCE "AOSO/core/json".
RUN ONCE "AOSO/core/logger".
RUN ONCE "AOSO/core/addons".
RUN ONCE "AOSO/core/config".
RUN ONCE "AOSO/core/state".
RUN ONCE "AOSO/core/scheduler".
RUN ONCE "AOSO/core/observe".
RUN ONCE "AOSO/core/boot".

// --- Vehicle ----------------------------------------------------------------
RUN ONCE "AOSO/vehicle/vessel".
RUN ONCE "AOSO/vehicle/parts".
RUN ONCE "AOSO/vehicle/capabilities".
RUN ONCE "AOSO/vehicle/performance".
RUN ONCE "AOSO/vehicle/resources".
RUN ONCE "AOSO/vehicle/staging".
RUN ONCE "AOSO/vehicle/profile".
RUN ONCE "AOSO/vehicle/budget".
RUN ONCE "AOSO/vehicle/learn".
RUN ONCE "AOSO/vehicle/classify".

// --- Basic flight -----------------------------------------------------------
RUN ONCE "AOSO/flight/steering".
RUN ONCE "AOSO/flight/maneuver".
RUN ONCE "AOSO/flight/ascent_opt".
RUN ONCE "AOSO/flight/ascent".

// --- Orbital nav --------------------------------------------------------
RUN ONCE "AOSO/nav/orbit".
RUN ONCE "AOSO/nav/hohmann".
RUN ONCE "AOSO/nav/planechange".
RUN ONCE "AOSO/nav/rendezvous".

// --- Interplanetary -----------------------------------------------------
RUN ONCE "AOSO/interplanetary/bodydb".
RUN ONCE "AOSO/interplanetary/transfer".
RUN ONCE "AOSO/interplanetary/ejection".
RUN ONCE "AOSO/interplanetary/assist".

// --- World model --------------------------------------------------------
RUN ONCE "AOSO/world/body".
RUN ONCE "AOSO/world/resources".
RUN ONCE "AOSO/world/orbit".
RUN ONCE "AOSO/world/network".
RUN ONCE "AOSO/world/world".

// --- Landing -------------------------------------------------------------
RUN ONCE "AOSO/landing/site".
RUN ONCE "AOSO/landing/deorbit".
RUN ONCE "AOSO/landing/descent".
RUN ONCE "AOSO/landing/parachute".

// --- Refuel & power -------------------------------------------------------
RUN ONCE "AOSO/power/power".
RUN ONCE "AOSO/refuel/isru".

// --- Return ----------------------------------------------------------------
RUN ONCE "AOSO/return/moonescape".
RUN ONCE "AOSO/return/return".

// --- Precision KSC return -------------------------------------------------
RUN ONCE "AOSO/precision/targeting".
RUN ONCE "AOSO/precision/kscreturn".

// --- Mission layer -----------------------------------------------------
RUN ONCE "AOSO/mission/checkpoints".
RUN ONCE "AOSO/mission/feasibility".
RUN ONCE "AOSO/mission/matrix".
RUN ONCE "AOSO/mission/windows".
RUN ONCE "AOSO/mission/score".
RUN ONCE "AOSO/mission/route".
RUN ONCE "AOSO/mission/planner".
RUN ONCE "AOSO/mission/goto".
RUN ONCE "AOSO/mission/tour".
RUN ONCE "AOSO/mission/mission".

// --- Advanced --------------------------------------------------------------
RUN ONCE "AOSO/advanced/docking".

// --- Hardening & UX (Phase 12) ---------------------------------------------
RUN ONCE "AOSO/hardening/watchdog".
RUN ONCE "AOSO/ux/hud".
RUN ONCE "AOSO/ux/telemetry".

// Registers every subsystem's own automation task (auto-staging, power
// management, checkpoint autosave) plus this phase's hardening/UX tasks.
// Nested FSMs (ascent/goto/descent/...) are still ticked by the plan or
// tour; the mission scheduler task itself is always armed in aoso_main().
FUNCTION aoso_main_register_tasks {
    aoso_staging_register_task(0.1).
    aoso_profile_register_task().
    aoso_power_register_task().
    aoso_checkpoints_register_task().
    aoso_watchdog_register_task().
    aoso_hud_register_task().
    aoso_telemetry_register_task().
}

FUNCTION aoso_main {
    aoso_boot().
    aoso_main_register_tasks().

    // Always rebuild the plan from empty, even on a same-session re-run of
    // this file (a full "run AOSO/main." without power-cycling the kOS CPU)
    // where core/boot.ks's RUN ONCE guards mean mission/mission.ks's own
    // GLOBAL AOSO_MISSION_PLAN IS LIST() line is skipped and would otherwise
    // still hold whatever an earlier attempt already added -- without this,
    // a second try appends a duplicate step onto the old list instead of
    // starting clean.
    aoso_mission_plan_clear().

    IF EXISTS("AOSO/mission_plan.ks") {
        RUN ONCE "AOSO/mission_plan".
    } ELSE {
        aoso_log_info("MAIN", "No AOSO/mission_plan.ks found - defaulting to a grand tour of every stock body, ISRU refuel where needed, then KSC return.").
        aoso_mission_plan_add(aoso_mission_step_grand_tour()).
        aoso_mission_start().
    }
    aoso_mission_register_task().

    aoso_log_info("MAIN", "Entering main loop.").

    UNTIL FALSE {
        SET AOSO_CPU_UT0 TO TIME:SECONDS.
        SET AOSO_CPU_OP0 TO OPCODESLEFT.
        SET AOSO_CPU_RT0 TO KUNIVERSE:REALTIME.
        aoso_sched_run().
        aoso_observe_cpu_end().
        WAIT 0.
    }
}

aoso_main().
