// AOSO/core/observe.ks
// Structured flight observability. Separate from the human log
// (core/logger.ks) and from timed telemetry (ux/telemetry.ks):
//   events     0:/aoso_events.csv      decisions / stages / anomalies
//   flightrec  0:/aoso_flightrec.txt   pre-event ring + post samples
// Hot paths: no JSON, no LIST PARTS, ring capped, CPU load-shed drops
// HUD/telem/debug first. Staging/ascent/maneuver/descent always run.
// Do not name locals `path` -- that clobbers kOS's builtin PATH().

GLOBAL AOSO_OBS_PHASE IS "BOOT".
GLOBAL AOSO_CPU_LEVEL IS 0.
GLOBAL AOSO_CPU_NAME IS "NORMAL".
GLOBAL AOSO_PROF IS LEXICON().
GLOBAL AOSO_PROF_T0 IS 0.
GLOBAL AOSO_PROF_NAME IS "".
GLOBAL AOSO_RING IS LIST().
GLOBAL AOSO_RING_I IS 0.
GLOBAL AOSO_RING_N IS 0.
GLOBAL AOSO_RING_CAP IS 120.
GLOBAL AOSO_EVT_BUF IS LIST().
GLOBAL AOSO_EVT_LAST_FLUSH IS 0.
GLOBAL AOSO_POST_LEFT IS 0.
GLOBAL AOSO_FINGERPRINT IS "".
GLOBAL AOSO_FINGERPRINT_N IS 0.
GLOBAL AOSO_OBS_TELEM_LAST IS 0.
GLOBAL AOSO_CPU_UT0 IS 0.
GLOBAL AOSO_CPU_OP0 IS 0.
GLOBAL AOSO_CPU_RT0 IS 0.
GLOBAL AOSO_CPU_SPILLS IS 0.
GLOBAL AOSO_CPU_LAST_WALL IS 0.
GLOBAL AOSO_CPU_FRAC IS 0.
GLOBAL AOSO_CPU_USED IS 0.
GLOBAL AOSO_CPU_LEFT IS 0.
GLOBAL AOSO_CPU_STREAK IS 0.
GLOBAL AOSO_CPU_LOG_UT IS 0.
GLOBAL AOSO_CPU_LOG_NAME IS "NORMAL".
GLOBAL AOSO_CPU_HOLD_UT IS 0.
GLOBAL AOSO_CPU_RECOVER IS 0.
GLOBAL AOSO_DUMP_PENDING IS "".
GLOBAL AOSO_TELEM_FLUSH_NOW IS FALSE.
GLOBAL AOSO_PHYS_DT IS 0.
GLOBAL AOSO_PHYS_LAST_UT IS 0.
GLOBAL AOSO_WALL_DT IS 0.
GLOBAL AOSO_TICK_LAST_RT IS 0.
GLOBAL AOSO_TICK_GAP_N IS 0.
GLOBAL AOSO_TICK_GAP_MAX IS 0.
GLOBAL AOSO_TICK_N IS 0.
GLOBAL AOSO_TICK_WARN_UT IS 0.

FUNCTION aoso_observe_reset_files {
    // Keep exactly one previous session instead of appending forever. Long
    // AOSO test cycles had grown events/flightrec/telemetry into multi-MB
    // files; synchronous OPEN/WRITELN work on those files adds needless KSP
    // main-thread pressure. Rotation happens once at boot, never in a hot loop.
    LOCAL evpath IS AOSO_CONST["EVENTS_FILE"].
    LOCAL evprev IS AOSO_CONST["EVENTS_PREV_FILE"].
    IF EXISTS(evprev) { DELETEPATH(evprev). }
    IF EXISTS(evpath) { MOVEPATH(evpath, evprev). }

    LOCAL recpath IS AOSO_CONST["FLIGHTREC_FILE"].
    LOCAL recprev IS AOSO_CONST["FLIGHTREC_PREV_FILE"].
    IF EXISTS(recprev) { DELETEPATH(recprev). }
    IF EXISTS(recpath) { MOVEPATH(recpath, recprev). }

    LOCAL telempath IS AOSO_CONST["TELEMETRY_FILE"].
    LOCAL telemprev IS AOSO_CONST["TELEMETRY_PREV_FILE"].
    IF EXISTS(telemprev) { DELETEPATH(telemprev). }
    IF EXISTS(telempath) { MOVEPATH(telempath, telemprev). }
}

FUNCTION aoso_observe_init {
    aoso_observe_reset_files().
    SET AOSO_RING TO LIST().
    LOCAL i IS 0.
    UNTIL i >= AOSO_RING_CAP {
        AOSO_RING:ADD("").
        SET i TO i + 1.
    }
    SET AOSO_RING_I TO 0.
    SET AOSO_RING_N TO 0.
    SET AOSO_EVT_BUF TO LIST().
    SET AOSO_EVT_LAST_FLUSH TO TIME:SECONDS.
    SET AOSO_POST_LEFT TO 0.
    SET AOSO_CPU_LEVEL TO 0.
    SET AOSO_CPU_NAME TO "NORMAL".
    SET AOSO_CPU_SPILLS TO 0.
    SET AOSO_CPU_FRAC TO 0.
    SET AOSO_CPU_USED TO 0.
    SET AOSO_CPU_LEFT TO 0.
    SET AOSO_CPU_STREAK TO 0.
    SET AOSO_CPU_LOG_UT TO 0.
    SET AOSO_CPU_LOG_NAME TO "NORMAL".
    SET AOSO_CPU_HOLD_UT TO 0.
    SET AOSO_CPU_RECOVER TO 0.
    SET AOSO_DUMP_PENDING TO "".
    SET AOSO_PROF TO LEXICON().
    SET AOSO_PROF_NAME TO "".
    SET AOSO_OBS_TELEM_LAST TO 0.
    SET AOSO_TELEM_FLUSH_NOW TO FALSE.
    SET AOSO_PHYS_DT TO 0.
    SET AOSO_PHYS_LAST_UT TO TIME:SECONDS.
    SET AOSO_WALL_DT TO 0.
    SET AOSO_TICK_LAST_RT TO KUNIVERSE:REALTIME.
    SET AOSO_TICK_GAP_N TO 0.
    SET AOSO_TICK_GAP_MAX TO 0.
    SET AOSO_TICK_N TO 0.
    SET AOSO_TICK_WARN_UT TO 0.

    SET AOSO_OBS_PHASE TO "BOOT".
    IF SHIP:STATUS = "PRELAUNCH" { SET AOSO_OBS_PHASE TO "PRELAUNCH". }
    IF SHIP:STATUS = "LANDED" { SET AOSO_OBS_PHASE TO "SURFACE". }
    IF SHIP:STATUS = "SPLASHED" { SET AOSO_OBS_PHASE TO "SURFACE". }
    IF SHIP:STATUS = "ORBITING" { SET AOSO_OBS_PHASE TO "ORBIT". }
    IF SHIP:STATUS = "ESCAPING" { SET AOSO_OBS_PHASE TO "TRANSFER". }
    IF SHIP:STATUS = "FLYING" { SET AOSO_OBS_PHASE TO "ASCENT". }
    IF SHIP:STATUS = "SUB_ORBITAL" { SET AOSO_OBS_PHASE TO "ASCENT". }

    LOCAL evpath IS AOSO_CONST["EVENTS_FILE"].
    IF NOT EXISTS(evpath) {
        LOCAL f IS CREATE(evpath).
        f:WRITELN("ut,met,phase,type,severity,state,msg").
    }

    aoso_observe_event("BOOT", "INFO", "BOOT", SHIP:NAME).
    SET AOSO_FINGERPRINT TO aoso_observe_fingerprint().
    SET AOSO_FINGERPRINT_N TO 0.
    aoso_observe_flush().
}

FUNCTION aoso_observe_set_phase {
    PARAMETER p.
    IF p = AOSO_OBS_PHASE { RETURN. }
    LOCAL old IS AOSO_OBS_PHASE.
    SET AOSO_OBS_PHASE TO p.
    aoso_observe_event("PHASE", "INFO", p, old + "->" + p).
}

// Coarse phase from a state-machine transition. Cheap string compares.
FUNCTION aoso_observe_on_state {
    PARAMETER new_state.
    IF new_state = "LIFTOFF" { aoso_observe_set_phase("ASCENT"). RETURN. }
    IF new_state = "GRAVITY_TURN" { aoso_observe_set_phase("ASCENT"). RETURN. }
    IF new_state = "CIRCULARIZE" { aoso_observe_set_phase("ASCENT"). RETURN. }
    IF new_state = "ASCEND" { aoso_observe_set_phase("ASCENT"). RETURN. }
    IF new_state = "LAUNCH" { aoso_observe_set_phase("ASCENT"). RETURN. }
    IF new_state = "FREEFALL" { aoso_observe_set_phase("DESCENT"). RETURN. }
    IF new_state = "DESCEND" { aoso_observe_set_phase("DESCENT"). RETURN. }
    IF new_state = "DEORBIT" { aoso_observe_set_phase("DESCENT"). RETURN. }
    IF new_state = "FINAL_APPROACH" { aoso_observe_set_phase("LANDING"). RETURN. }
    IF new_state = "TOUCHDOWN" { aoso_observe_set_phase("SURFACE"). RETURN. }
    IF new_state = "REFUEL" { aoso_observe_set_phase("SURFACE"). RETURN. }
    IF new_state = "HARVEST" { aoso_observe_set_phase("SURFACE"). RETURN. }
    IF new_state = "DEPLOY" { aoso_observe_set_phase("SURFACE"). RETURN. }
    IF new_state = "STOW" { aoso_observe_set_phase("SURFACE"). RETURN. }
    IF new_state = "GOTO" { aoso_observe_set_phase("TRANSFER"). RETURN. }
    IF new_state = "RETURN" { aoso_observe_set_phase("TRANSFER"). RETURN. }
    IF new_state = "WAIT" { aoso_observe_set_phase("CRUISE"). RETURN. }
    IF new_state = "POLAR" { aoso_observe_set_phase("ORBIT"). RETURN. }
    IF new_state = "SCAN" { aoso_observe_set_phase("ORBIT"). RETURN. }
    IF new_state = "ALIGN" { aoso_observe_set_phase("ORBIT"). RETURN. }
    IF new_state = "CAPTURE" { aoso_observe_set_phase("BURN"). RETURN. }
    IF new_state = "KSC" { aoso_observe_set_phase("DESCENT"). RETURN. }
    IF new_state = "HANDOFF" { aoso_observe_set_phase("DESCENT"). RETURN. }
    IF new_state = "PLAN" { aoso_observe_set_phase("CRUISE"). RETURN. }
    IF new_state = "APPROACH" { aoso_observe_set_phase("ORBIT"). RETURN. }
    IF new_state = "FINAL" { aoso_observe_set_phase("ORBIT"). RETURN. }
    IF new_state = "COAST" {
        IF AOSO_OBS_PHASE = "ASCENT" { RETURN. }
        aoso_observe_set_phase("CRUISE").
        RETURN.
    }
    IF new_state = "BURN" {
        IF AOSO_OBS_PHASE = "DESCENT" {
            aoso_observe_set_phase("LANDING").
            RETURN.
        }
        IF AOSO_OBS_PHASE = "LANDING" { RETURN. }
        aoso_observe_set_phase("BURN").
        RETURN.
    }
    IF new_state = "DONE" {
        IF AOSO_OBS_PHASE = "ASCENT" { aoso_observe_set_phase("ORBIT"). RETURN. }
        RETURN.
    }
}

FUNCTION aoso_observe_event {
    PARAMETER etype.
    PARAMETER severity.
    PARAMETER state_or_tag.
    PARAMETER message.

    IF AOSO_CONFIG:HASKEY("OBS_ENABLED") {
        IF NOT AOSO_CONFIG["OBS_ENABLED"] { RETURN. }
    }

    IF AOSO_CPU_LEVEL >= 3 {
        LOCAL keep IS FALSE.
        IF severity = "WARN" { SET keep TO TRUE. }
        IF severity = "ERROR" { SET keep TO TRUE. }
        IF severity = "FATAL" { SET keep TO TRUE. }
        IF etype = "STAGE" { SET keep TO TRUE. }
        IF etype = "STAGE_GUARD" { SET keep TO TRUE. }
        IF etype = "BURN_GAP" { SET keep TO TRUE. }
        IF etype = "RELIGHT" { SET keep TO TRUE. }
        IF etype = "ABORT" { SET keep TO TRUE. }
        IF etype = "ANOMALY" { SET keep TO TRUE. }
        IF etype = "BURN" { SET keep TO TRUE. }
        IF NOT keep { RETURN. }
    }

    IF DEFINED AOSO_HUD_READY {
        IF AOSO_HUD_READY {
            aoso_hud_on_event(etype, severity, state_or_tag, message).
        }
    }

    LOCAL ut IS TIME:SECONDS.
    LOCAL met IS MISSIONTIME.
    LOCAL line IS ROUND(ut, 2) + "," + ROUND(met, 1) + "," + AOSO_OBS_PHASE + "," + etype + "," + severity + "," + state_or_tag + "," + message.
    AOSO_EVT_BUF:ADD(line).

    LOCAL dump IS FALSE.
    IF etype = "STAGE" { SET dump TO TRUE. }
    IF etype = "STAGE_GUARD" { SET dump TO TRUE. }
    IF etype = "BURN_GAP" { SET dump TO TRUE. }
    IF etype = "BURN" { SET dump TO TRUE. }
    IF etype = "ABORT" { SET dump TO TRUE. }
    IF etype = "ANOMALY" { SET dump TO TRUE. }
    IF etype = "LAND" { SET dump TO TRUE. }
    IF etype = "TOUCHDOWN" { SET dump TO TRUE. }
    IF etype = "RELIGHT" { SET dump TO TRUE. }
    IF dump {
        SET AOSO_DUMP_PENDING TO etype + " " + message.
        SET AOSO_POST_LEFT TO 8.
        SET AOSO_TELEM_FLUSH_NOW TO TRUE.
    }

    LOCAL must_flush IS FALSE.
    IF severity = "ERROR" { SET must_flush TO TRUE. }
    IF severity = "FATAL" { SET must_flush TO TRUE. }
    IF AOSO_EVT_BUF:LENGTH >= 20 { SET must_flush TO TRUE. }
    IF AOSO_EVT_BUF:LENGTH > 80 { SET must_flush TO TRUE. }
    IF (ut - AOSO_EVT_LAST_FLUSH) >= 5 {
        LOCAL busy IS FALSE.
        IF DEFINED AOSO_CPU_LEVEL {
            IF AOSO_CPU_LEVEL >= 2 { SET busy TO TRUE. }
        }
        IF NOT busy { SET must_flush TO TRUE. }
        IF AOSO_EVT_BUF:LENGTH >= 12 { SET must_flush TO TRUE. }
    }
    IF must_flush {
        IF OPCODESLEFT < aoso_cpu_headroom() {
            SET must_flush TO FALSE.
        }
    }
    IF must_flush { aoso_observe_flush(). }
}

FUNCTION aoso_observe_flush {
    IF AOSO_EVT_BUF:LENGTH = 0 {
        SET AOSO_EVT_LAST_FLUSH TO TIME:SECONDS.
        RETURN.
    }
    LOCAL evpath IS AOSO_CONST["EVENTS_FILE"].
    LOCAL f IS 0.
    IF EXISTS(evpath) {
        SET f TO OPEN(evpath).
    } ELSE {
        SET f TO CREATE(evpath).
        f:WRITELN("ut,met,phase,type,severity,state,msg").
    }
    UNTIL AOSO_EVT_BUF:LENGTH = 0 {
        LOCAL line IS AOSO_EVT_BUF[0].
        AOSO_EVT_BUF:REMOVE(0).
        f:WRITELN(line).
    }
    SET AOSO_EVT_LAST_FLUSH TO TIME:SECONDS.
}

FUNCTION aoso_decide {
    PARAMETER tag.
    PARAMETER decision.
    PARAMETER selected.
    PARAMETER reason.
    PARAMETER inputs_str.
    PARAMETER predicted IS 0.
    aoso_observe_event("DECIDE", "INFO", tag, "dec=" + decision + " sel=" + selected + " why=" + reason + " in=" + inputs_str).
    IF DEFINED AOSO_OPEN_DECISIONS {
        RETURN aoso_decide_open(tag, decision, selected, reason, predicted).
    }
    RETURN 0.
}

FUNCTION aoso_observe_anomaly {
    PARAMETER atype.
    PARAMETER severity.
    PARAMETER expected.
    PARAMETER actual.
    aoso_observe_event("ANOMALY", severity, atype, "type=" + atype + " exp=" + ROUND(expected, 2) + " act=" + ROUND(actual, 2)).
}

FUNCTION aoso_observe_ring_push {
    PARAMETER packed_row.
    IF AOSO_RING:LENGTH < AOSO_RING_CAP { RETURN. }
    SET AOSO_RING[AOSO_RING_I] TO packed_row.
    SET AOSO_RING_I TO AOSO_RING_I + 1.
    IF AOSO_RING_I >= AOSO_RING_CAP { SET AOSO_RING_I TO 0. }
    SET AOSO_RING_N TO AOSO_RING_N + 1.
}

FUNCTION aoso_observe_flightrec_append {
    PARAMETER line.
    LOCAL recpath IS AOSO_CONST["FLIGHTREC_FILE"].
    LOCAL f IS 0.
    IF EXISTS(recpath) {
        SET f TO OPEN(recpath).
    } ELSE {
        SET f TO CREATE(recpath).
    }
    f:WRITELN(line).
}

FUNCTION aoso_observe_dump_pre {
    PARAMETER why.
    LOCAL recpath IS AOSO_CONST["FLIGHTREC_FILE"].
    LOCAL f IS 0.
    IF EXISTS(recpath) {
        SET f TO OPEN(recpath).
    } ELSE {
        SET f TO CREATE(recpath).
    }
    f:WRITELN("#PRE " + why).
    LOCAL cap IS AOSO_RING_CAP.
    LOCAL n IS AOSO_RING_N.
    IF n > cap { SET n TO cap. }
    LOCAL start IS 0.
    IF AOSO_RING_N >= cap { SET start TO AOSO_RING_I. }
    LOCAL i IS 0.
    UNTIL i >= n {
        LOCAL idx IS start + i.
        IF idx >= cap { SET idx TO idx - cap. }
        LOCAL row IS AOSO_RING[idx].
        IF row <> "" { f:WRITELN(row). }
        SET i TO i + 1.
    }
    f:WRITELN("#EVENT " + why).
}

FUNCTION aoso_observe_post_sample {
    PARAMETER packed_row.
    IF AOSO_POST_LEFT <= 0 { RETURN. }
    aoso_observe_flightrec_append("#POST " + packed_row).
    SET AOSO_POST_LEFT TO AOSO_POST_LEFT - 1.
}

FUNCTION aoso_observe_tick_begin {
    LOCAL now_ut IS TIME:SECONDS.
    LOCAL now_rt IS KUNIVERSE:REALTIME.
    LOCAL dt IS now_ut - AOSO_PHYS_LAST_UT.
    LOCAL wall_dt IS now_rt - AOSO_TICK_LAST_RT.
    IF AOSO_PHYS_LAST_UT <= 0 { SET dt TO 0. }
    IF AOSO_TICK_LAST_RT <= 0 { SET wall_dt TO 0. }
    SET AOSO_PHYS_LAST_UT TO now_ut.
    SET AOSO_TICK_LAST_RT TO now_rt.
    SET AOSO_TICK_N TO AOSO_TICK_N + 1.
    IF WARP > 0 {
        IF WARPMODE = "RAILS" { SET dt TO 0. }
    }
    SET AOSO_PHYS_DT TO dt.
    SET AOSO_WALL_DT TO wall_dt.

    LOCAL critical IS FALSE.
    IF AOSO_OBS_PHASE = "ASCENT" OR AOSO_OBS_PHASE = "BURN" OR
       AOSO_OBS_PHASE = "DESCENT" OR AOSO_OBS_PHASE = "LANDING" {
        SET critical TO TRUE.
    }
    IF NOT critical { RETURN. }

    LOCAL warn_dt IS aoso_config_get("TICK_DT_WARN", 0.12).
    LOCAL warn_wall IS aoso_config_get("TICK_WALL_WARN", 0.12).

    // Physics warp intentionally lengthens game-time physics steps. Treat the
    // documented PHYSICSDELTAT as the expected cadence instead of reporting
    // every 2x/3x/4x physics-warp tick as a hitch. Real wall-time stalls still
    // trip warn_wall regardless of warp.
    IF WARPMODE = "PHYSICS" {
        LOCAL expected_dt IS KUNIVERSE:TIMEWARP:PHYSICSDELTAT.
        IF expected_dt > 0 {
            LOCAL phys_warn IS expected_dt * 3.
            IF phys_warn > warn_dt { SET warn_dt TO phys_warn. }
        }
    }

    LOCAL coarse IS FALSE.
    IF dt > warn_dt { SET coarse TO TRUE. }
    IF wall_dt > warn_wall { SET coarse TO TRUE. }
    IF coarse {
        SET AOSO_TICK_GAP_N TO AOSO_TICK_GAP_N + 1.
        IF dt > AOSO_TICK_GAP_MAX { SET AOSO_TICK_GAP_MAX TO dt. }
        IF now_ut - AOSO_TICK_WARN_UT > 1 {
            SET AOSO_TICK_WARN_UT TO now_ut.
            LOCAL stage_age IS -1.
            IF DEFINED AOSO_STAGING_LAST_STAGE_UT {
                IF AOSO_STAGING_LAST_STAGE_UT >= 0 {
                    SET stage_age TO now_ut - AOSO_STAGING_LAST_STAGE_UT.
                }
            }
            aoso_observe_event("TICK", "WARN", AOSO_OBS_PHASE,
                "game_dt=" + ROUND(dt, 4) +
                " wall_dt=" + ROUND(wall_dt, 4) +
                " stage_age=" + ROUND(stage_age, 3) +
                " warp=" + WARP + " mode=" + WARPMODE +
                " op=" + OPCODESLEFT).
        }
    }

    IF NOT aoso_config_get("TICK_DEBUG", TRUE) { RETURN. }
    LOCAL every IS aoso_config_get("TICK_DEBUG_EVERY", 2).
    IF every < 1 { SET every TO 1. }
    LOCAL rem IS AOSO_TICK_N - FLOOR(AOSO_TICK_N / every) * every.
    IF rem <> 0 { RETURN. }

    LOCAL node_dv IS -1.
    LOCAL node_eta IS -999.
    IF HASNODE {
        SET node_dv TO NEXTNODE:BURNVECTOR:MAG.
        SET node_eta TO NEXTNODE:ETA.
    }
    LOCAL cmd_t IS 0.
    IF DEFINED AOSO_CMD_THROTTLE { SET cmd_t TO AOSO_CMD_THROTTLE. }
    LOCAL stage_age_row IS -1.
    IF DEFINED AOSO_STAGING_LAST_STAGE_UT {
        IF AOSO_STAGING_LAST_STAGE_UT >= 0 {
            SET stage_age_row TO now_ut - AOSO_STAGING_LAST_STAGE_UT.
        }
    }
    LOCAL row IS "TICK ut=" + ROUND(now_ut, 3) +
        " dt=" + ROUND(dt, 4) +
        " wall=" + ROUND(wall_dt, 4) +
        " stage_age=" + ROUND(stage_age_row, 3) +
        " phase=" + AOSO_OBS_PHASE +
        " warp=" + WARP +
        " mode=" + WARPMODE +
        " op=" + OPCODESLEFT +
        " thr=" + ROUND(cmd_t, 3) +
        " spd=" + ROUND(SHIP:VELOCITY:ORBIT:MAG, 2) +
        " vs=" + ROUND(VERTICALSPEED, 2) +
        " node=" + ROUND(node_dv, 3) +
        " eta=" + ROUND(node_eta, 2).
    aoso_observe_ring_push(row).
    aoso_observe_post_sample(row).
}

FUNCTION aoso_prof_start {
    PARAMETER name.
    IF AOSO_CONFIG:HASKEY("PROF_ENABLED") {
        IF NOT AOSO_CONFIG["PROF_ENABLED"] { RETURN. }
    }
    SET AOSO_PROF_NAME TO name.
    SET AOSO_PROF_T0 TO KUNIVERSE:REALTIME.
}

FUNCTION aoso_prof_end {
    IF AOSO_PROF_NAME = "" { RETURN. }
    LOCAL dt IS KUNIVERSE:REALTIME - AOSO_PROF_T0.
    LOCAL name IS AOSO_PROF_NAME.
    SET AOSO_PROF_NAME TO "".
    IF NOT AOSO_PROF:HASKEY(name) {
        SET AOSO_PROF[name] TO LEXICON("n", 0, "last", 0, "sum", 0, "max", 0).
    }
    LOCAL s IS AOSO_PROF[name].
    SET s["n"] TO s["n"] + 1.
    SET s["last"] TO dt.
    SET s["sum"] TO s["sum"] + dt.
    IF dt > s["max"] { SET s["max"] TO dt. }
}

GLOBAL AOSO_CPU_ROOM IS 400.
GLOBAL AOSO_CPU_ROOM_UT IS -1.

FUNCTION aoso_cpu_headroom {
    // Scheduler asks for this several times per physics tick. The answer
    // cannot change until the next tick, so reuse it.
    IF AOSO_CPU_ROOM_UT = TIME:SECONDS { RETURN AOSO_CPU_ROOM. }
    LOCAL ipu IS CONFIG:IPU.
    LOCAL frac IS aoso_config_get("CPU_RESERVE_FRAC", 0.18).
    LOCAL n IS FLOOR(ipu * frac).
    LOCAL abs_n IS aoso_config_get("CPU_RESERVE_ABS", 400).
    IF n < abs_n { SET n TO abs_n. }
    LOCAL phase IS AOSO_OBS_PHASE.
    LOCAL phase_n IS 0.
    IF phase = "ASCENT" { SET phase_n TO aoso_config_get("CPU_RESERVE_ASCENT", 500). }
    IF phase = "BURN" { SET phase_n TO aoso_config_get("CPU_RESERVE_MANEUVER", 500). }
    IF phase = "DESCENT" { SET phase_n TO aoso_config_get("CPU_RESERVE_DESCENT", 650). }
    IF phase = "LANDING" { SET phase_n TO aoso_config_get("CPU_RESERVE_DESCENT", 650). }
    IF phase = "ORBIT" { SET phase_n TO aoso_config_get("CPU_RESERVE_ORBIT", 350). }
    IF phase = "CRUISE" { SET phase_n TO aoso_config_get("CPU_RESERVE_COAST", 250). }
    IF phase = "TRANSFER" { SET phase_n TO aoso_config_get("CPU_RESERVE_COAST", 250). }
    IF phase_n > n { SET n TO phase_n. }
    LOCAL half IS FLOOR(ipu * 0.5).
    IF n > half { SET n TO half. }
    IF n < 80 { SET n TO 80. }
    SET AOSO_CPU_ROOM TO n.
    SET AOSO_CPU_ROOM_UT TO TIME:SECONDS.
    RETURN n.
}

FUNCTION aoso_cpu_band {
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF lvl <= 0 { RETURN "GREEN". }
    IF lvl = 1 { RETURN "YELLOW". }
    IF lvl = 2 { RETURN "RED". }
    RETURN "CRITICAL".
}

FUNCTION aoso_cpu_can_run {
    PARAMETER prio_class.
    RETURN aoso_cpu_allow(prio_class).
}

FUNCTION aoso_cpu_should_yield {
    IF OPCODESLEFT < aoso_cpu_headroom() { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION aoso_cpu_budget_remaining {
    RETURN OPCODESLEFT.
}

FUNCTION aoso_cpu_allow {
    PARAMETER cls.
    LOCAL lvl IS 0.
    IF DEFINED AOSO_CPU_LEVEL { SET lvl TO AOSO_CPU_LEVEL. }
    IF cls <= 0 { RETURN TRUE. }
    IF lvl >= 3 {
        IF cls >= 2 { RETURN FALSE. }
        RETURN TRUE.
    }
    IF lvl >= 2 {
        IF cls >= 3 { RETURN FALSE. }
        RETURN TRUE.
    }
    RETURN TRUE.
}

FUNCTION aoso_yield_hud {
    WAIT 0.
    IF DEFINED AOSO_HUD_READY {
        IF AOSO_HUD_READY { aoso_hud_fast_tick(). }
    }
}

FUNCTION aoso_observe_idle {
    IF AOSO_DUMP_PENDING = "" {
        IF AOSO_EVT_BUF:LENGTH < 8 { RETURN. }
    }
    IF OPCODESLEFT < aoso_cpu_headroom() { RETURN. }
    IF AOSO_DUMP_PENDING <> "" {
        LOCAL why IS AOSO_DUMP_PENDING.
        SET AOSO_DUMP_PENDING TO "".
        aoso_observe_dump_pre(why).
        IF OPCODESLEFT < aoso_cpu_headroom() { RETURN. }
    }
    IF AOSO_EVT_BUF:LENGTH >= 8 { aoso_observe_flush(). }
}

FUNCTION aoso_observe_cpu_end {
    LOCAL spilled IS FALSE.
    LOCAL rails_jump IS FALSE.
    IF TIME:SECONDS <> AOSO_CPU_UT0 {
        IF WARP > 0 {
            IF WARPMODE = "RAILS" { SET rails_jump TO TRUE. }
        }
        IF rails_jump {
            SET spilled TO FALSE.
        } ELSE {
            SET spilled TO TRUE.
        }
    }
    LOCAL op_used IS 0.
    LOCAL left_now IS OPCODESLEFT.
    SET AOSO_CPU_LEFT TO left_now.
    IF rails_jump {
        SET op_used TO 0.
        SET AOSO_CPU_STREAK TO 0.
    } ELSE {
        IF spilled {
            SET op_used TO CONFIG:IPU.
            SET AOSO_CPU_SPILLS TO AOSO_CPU_SPILLS + 1.
            SET AOSO_CPU_STREAK TO AOSO_CPU_STREAK + 1.
        } ELSE {
            SET op_used TO AOSO_CPU_OP0 - left_now.
            IF op_used < 0 { SET op_used TO 0. }
            SET AOSO_CPU_STREAK TO 0.
        }
    }
    LOCAL ipu IS CONFIG:IPU.
    IF ipu < 1 { SET ipu TO 1. }
    LOCAL frac IS op_used / ipu.
    LOCAL wall IS KUNIVERSE:REALTIME - AOSO_CPU_RT0.
    LOCAL level IS 0.
    LOCAL cname IS "NORMAL".
    // A TIME:SECONDS step means this slice used more than IPU. That is
    // one physics frame of overrun, not a stall. CRITICAL is a real hitch
    // (wall >= 0.15 s) or a long unbroken spill streak.
    IF spilled {
        IF wall >= 0.15 {
            SET level TO 3.
            SET cname TO "CRITICAL".
        } ELSE {
            IF AOSO_CPU_STREAK >= 20 {
                SET level TO 3.
                SET cname TO "CRITICAL".
            } ELSE {
                SET level TO 2.
                SET cname TO "HIGH".
            }
        }
    } ELSE {
        IF frac >= 0.92 {
            SET level TO 2.
            SET cname TO "HIGH".
        } ELSE {
            IF wall >= 0.08 {
                SET level TO 2.
                SET cname TO "HIGH".
            } ELSE {
                IF frac >= 0.70 {
                    SET level TO 1.
                    SET cname TO "ELEVATED".
                }
            }
        }
    }
    LOCAL prev IS AOSO_CPU_LEVEL.
    LOCAL now_ut IS TIME:SECONDS.
    IF level > prev {
        SET AOSO_CPU_HOLD_UT TO now_ut + 1.2.
        IF level >= 3 { SET AOSO_CPU_HOLD_UT TO now_ut + 2.5. }
        SET AOSO_CPU_RECOVER TO 0.
    } ELSE {
        IF level < prev {
            IF now_ut < AOSO_CPU_HOLD_UT {
                SET level TO prev.
            } ELSE {
                SET AOSO_CPU_RECOVER TO AOSO_CPU_RECOVER + 1.
                IF AOSO_CPU_RECOVER < 4 {
                    SET level TO prev.
                } ELSE {
                    SET level TO prev - 1.
                    SET AOSO_CPU_RECOVER TO 0.
                    SET AOSO_CPU_HOLD_UT TO now_ut + 0.8.
                }
            }
        } ELSE {
            SET AOSO_CPU_RECOVER TO 0.
        }
    }
    IF level <= 0 { SET cname TO "NORMAL". }
    IF level = 1 { SET cname TO "ELEVATED". }
    IF level = 2 { SET cname TO "HIGH". }
    IF level >= 3 { SET cname TO "CRITICAL". SET level TO 3. }
    SET AOSO_CPU_LEVEL TO level.
    SET AOSO_CPU_NAME TO cname.
    SET AOSO_CPU_LAST_WALL TO wall.
    SET AOSO_CPU_FRAC TO frac.
    SET AOSO_CPU_USED TO op_used.
    IF cname <> AOSO_CPU_LOG_NAME {
        IF now_ut - AOSO_CPU_LOG_UT >= 8 {
            SET AOSO_CPU_LOG_UT TO now_ut.
            SET AOSO_CPU_LOG_NAME TO cname.
            aoso_observe_event("CPU", "INFO", cname, "level=" + prev + "->" + level + " frac=" + ROUND(frac, 2) + " wall=" + ROUND(wall, 3) + " band=" + aoso_cpu_band()).
            IF DEFINED AOSO_EVENTS {
                IF level >= 3 { aoso_event_publish("CPU_LOAD_CRITICAL", "cpu", cname). }
                ELSE {
                    IF level >= 2 { aoso_event_publish("CPU_LOAD_HIGH", "cpu", cname). }
                }
            }
        }
    }
}

FUNCTION aoso_observe_fingerprint {
    LOCAL n_parts IS 0.
    LOCAL n_eng IS 0.
    LOCAL n_tank IS 0.
    LOCAL dv IS 0.
    IF DEFINED AOSO_VESSEL {
        IF AOSO_VESSEL:HASKEY("part_count") { SET n_parts TO AOSO_VESSEL["part_count"]. }
        IF AOSO_VESSEL:HASKEY("engine_count") { SET n_eng TO AOSO_VESSEL["engine_count"]. }
    }
    IF DEFINED AOSO_PROFILE {
        IF AOSO_PROFILE:HASKEY("snapshot") {
            LOCAL snap IS AOSO_PROFILE["snapshot"].
            IF snap:HASKEY("parts") { SET n_parts TO snap["parts"]. }
            IF snap:HASKEY("engines") { SET n_eng TO snap["engines"]. }
            IF snap:HASKEY("tanks") { SET n_tank TO snap["tanks"]. }
        }
        IF AOSO_PROFILE:HASKEY("propulsion") {
            IF AOSO_PROFILE["propulsion"]:HASKEY("dv_total") {
                SET dv TO AOSO_PROFILE["propulsion"]["dv_total"].
            }
        }
    }
    RETURN SHIP:NAME + "|" + SHIP:BODY:NAME + "|" + n_parts + "|" + n_eng + "|" + n_tank + "|" + STAGE:NUMBER + "|" + ROUND(SHIP:MASS, 2) + "|" + ROUND(dv, 0) + "|" + SHIP:STATUS.
}

FUNCTION aoso_observe_on_fingerprint {
    LOCAL fp IS aoso_observe_fingerprint().
    IF fp = AOSO_FINGERPRINT { RETURN. }
    SET AOSO_FINGERPRINT TO fp.
    SET AOSO_FINGERPRINT_N TO AOSO_FINGERPRINT_N + 1.
    aoso_observe_event("FINGERPRINT", "INFO", "" + AOSO_FINGERPRINT_N, fp).
}
