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
GLOBAL AOSO_RING_CAP IS 40.
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
GLOBAL AOSO_TELEM_FLUSH_NOW IS FALSE.

FUNCTION aoso_observe_init {
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
    SET AOSO_PROF TO LEXICON().
    SET AOSO_PROF_NAME TO "".
    SET AOSO_OBS_TELEM_LAST TO 0.
    SET AOSO_TELEM_FLUSH_NOW TO FALSE.

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
        IF severity <> "WARN" {
            IF severity <> "ERROR" {
                IF severity <> "FATAL" {
                    RETURN.
                }
            }
        }
    }

    LOCAL ut IS TIME:SECONDS.
    LOCAL met IS MISSIONTIME.
    LOCAL line IS ROUND(ut, 2) + "," + ROUND(met, 1) + "," + AOSO_OBS_PHASE + "," + etype + "," + severity + "," + state_or_tag + "," + message.
    AOSO_EVT_BUF:ADD(line).

    LOCAL dump IS FALSE.
    IF etype = "STAGE" { SET dump TO TRUE. }
    IF etype = "BURN" { SET dump TO TRUE. }
    IF etype = "ABORT" { SET dump TO TRUE. }
    IF etype = "ANOMALY" { SET dump TO TRUE. }
    IF etype = "LAND" { SET dump TO TRUE. }
    IF etype = "TOUCHDOWN" { SET dump TO TRUE. }
    IF etype = "DECIDE" { SET dump TO TRUE. }
    IF etype = "RELIGHT" { SET dump TO TRUE. }
    IF dump {
        aoso_observe_dump_pre(etype + " " + message).
        SET AOSO_POST_LEFT TO 15.
        SET AOSO_TELEM_FLUSH_NOW TO TRUE.
    }

    LOCAL must_flush IS FALSE.
    IF severity = "ERROR" { SET must_flush TO TRUE. }
    IF severity = "FATAL" { SET must_flush TO TRUE. }
    IF AOSO_EVT_BUF:LENGTH >= 20 { SET must_flush TO TRUE. }
    IF AOSO_EVT_BUF:LENGTH > 80 { SET must_flush TO TRUE. }
    IF (ut - AOSO_EVT_LAST_FLUSH) >= 5 { SET must_flush TO TRUE. }
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
    aoso_observe_event("DECIDE", "INFO", tag, "dec=" + decision + " sel=" + selected + " why=" + reason + " in=" + inputs_str).
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

FUNCTION aoso_observe_cpu_end {
    LOCAL spilled IS FALSE.
    IF TIME:SECONDS <> AOSO_CPU_UT0 { SET spilled TO TRUE. }
    LOCAL op_used IS 0.
    IF spilled {
        SET op_used TO CONFIG:IPU.
        SET AOSO_CPU_SPILLS TO AOSO_CPU_SPILLS + 1.
    } ELSE {
        SET op_used TO AOSO_CPU_OP0 - OPCODESLEFT.
        IF op_used < 0 { SET op_used TO 0. }
    }
    LOCAL ipu IS CONFIG:IPU.
    IF ipu < 1 { SET ipu TO 1. }
    LOCAL frac IS op_used / ipu.
    LOCAL wall IS KUNIVERSE:REALTIME - AOSO_CPU_RT0.
    LOCAL level IS 0.
    LOCAL cname IS "NORMAL".
    IF spilled {
        SET level TO 3.
        SET cname TO "CRITICAL".
    } ELSE {
        IF frac >= 0.9 {
            SET level TO 2.
            SET cname TO "HIGH".
        } ELSE {
            IF wall >= 0.08 {
                SET level TO 2.
                SET cname TO "HIGH".
            } ELSE {
                IF frac >= 0.65 {
                    SET level TO 1.
                    SET cname TO "ELEVATED".
                }
            }
        }
    }
    LOCAL prev IS AOSO_CPU_LEVEL.
    SET AOSO_CPU_LEVEL TO level.
    SET AOSO_CPU_NAME TO cname.
    SET AOSO_CPU_LAST_WALL TO wall.
    IF level <> prev {
        aoso_observe_event("CPU", "INFO", cname, "level=" + prev + "->" + level + " frac=" + ROUND(frac, 2) + " wall=" + ROUND(wall, 3)).
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
