// AOSO/ux/hud_alert.ks
// HUDTEXT alerts + a bounded event ring. Does not replace core/logger.ks.
// Duplicate suppression by key + cooldown. HUDTEXT style 2 = upper center.

GLOBAL AOSO_HUD_EVENTS IS LIST().
GLOBAL AOSO_HUD_EVENT_CAP IS 24.
GLOBAL AOSO_HUD_ALERT_LAST IS LEXICON().
GLOBAL AOSO_HUD_WARN_N IS 0.
GLOBAL AOSO_HUD_ERR_N IS 0.
GLOBAL AOSO_HUD_LAST_WARN IS "".
GLOBAL AOSO_HUD_LAST_ERR IS "".
GLOBAL AOSO_HUD_LAST_EVT IS "".

FUNCTION aoso_hud_alert_init {
    SET AOSO_HUD_EVENTS TO LIST().
    SET AOSO_HUD_ALERT_LAST TO LEXICON().
    SET AOSO_HUD_WARN_N TO 0.
    SET AOSO_HUD_ERR_N TO 0.
    SET AOSO_HUD_LAST_WARN TO "".
    SET AOSO_HUD_LAST_ERR TO "".
    SET AOSO_HUD_LAST_EVT TO "".
}

FUNCTION aoso_hud_event_push {
    PARAMETER sev.
    PARAMETER msg.
    LOCAL line IS "[" + aoso_hud_eta(MISSIONTIME) + "] " + sev + "  " + msg.
    AOSO_HUD_EVENTS:ADD(line).
    UNTIL AOSO_HUD_EVENTS:LENGTH <= AOSO_HUD_EVENT_CAP {
        AOSO_HUD_EVENTS:REMOVE(0).
    }
    SET AOSO_HUD_LAST_EVT TO line.
    IF sev = "WARN" {
        SET AOSO_HUD_WARN_N TO AOSO_HUD_WARN_N + 1.
        SET AOSO_HUD_LAST_WARN TO msg.
    }
    IF sev = "CRIT" {
        SET AOSO_HUD_ERR_N TO AOSO_HUD_ERR_N + 1.
        SET AOSO_HUD_LAST_ERR TO msg.
    }
    IF sev = "ERROR" {
        SET AOSO_HUD_ERR_N TO AOSO_HUD_ERR_N + 1.
        SET AOSO_HUD_LAST_ERR TO msg.
    }
}

FUNCTION aoso_hud_alert {
    PARAMETER key.
    PARAMETER sev.
    PARAMETER msg.
    PARAMETER cooldown_s IS 20.
    PARAMETER hud_s IS 4.

    LOCAL now IS TIME:SECONDS.
    IF AOSO_HUD_ALERT_LAST:HASKEY(key) {
        IF now - AOSO_HUD_ALERT_LAST[key] < cooldown_s { RETURN. }
    }
    SET AOSO_HUD_ALERT_LAST[key] TO now.
    aoso_hud_event_push(sev, msg).

    LOCAL col IS WHITE.
    LOCAL size IS 16.
    IF sev = "INFO" { SET col TO CYAN. SET size TO 14. }
    IF sev = "NOTICE" { SET col TO WHITE. SET size TO 16. }
    IF sev = "WARN" { SET col TO YELLOW. SET size TO 18. }
    IF sev = "CRIT" { SET col TO RED. SET size TO 20. }
    IF sev = "ERROR" { SET col TO RED. SET size TO 20. }
    IF sev = "OK" { SET col TO GREEN. SET size TO 16. }
    HUDTEXT(msg, hud_s, 2, size, col, FALSE).
}

FUNCTION aoso_hud_on_event {
    PARAMETER etype.
    PARAMETER severity.
    PARAMETER state_or_tag.
    PARAMETER message.
    LOCAL sev IS "INFO".
    IF severity = "WARN" { SET sev TO "WARN". }
    IF severity = "ERROR" { SET sev TO "ERROR". }
    IF severity = "FATAL" { SET sev TO "CRIT". }
    LOCAL msg IS etype + "  " + message.
    aoso_hud_event_push(sev, msg).
    IF sev = "WARN" { aoso_hud_alert("obs:" + etype + ":" + message, "WARN", msg, 25, 4). }
    IF sev = "ERROR" { aoso_hud_alert("obs:" + etype + ":" + message, "ERROR", msg, 15, 6). }
    IF sev = "CRIT" { aoso_hud_alert("obs:" + etype + ":" + message, "CRIT", msg, 10, 8). }
}

FUNCTION aoso_hud_watch_alerts {
    LOCAL res IS AOSO_HUD_DATA["res"].
    LOCAL sys IS AOSO_HUD_DATA["systems"].
    LOCAL f IS AOSO_HUD_DATA["flight"].
    IF res:HASKEY("ec") {
        IF res["ec"] <= 8 { aoso_hud_alert("ec_crit", "CRIT", "LOW ELECTRICITY  " + ROUND(res["ec"], 0) + "%", 25, 5). }
        ELSE {
            IF res["ec"] <= 20 { aoso_hud_alert("ec_low", "WARN", "Electricity  " + ROUND(res["ec"], 0) + "%", 40, 4). }
        }
    }
    IF res:HASKEY("stage_pct") {
        IF res["stage_pct"] <= 8 {
            IF f["status"] <> "LANDED" {
                IF f["status"] <> "PRELAUNCH" {
                    aoso_hud_alert("fuel_low", "WARN", "STAGE FUEL  " + ROUND(res["stage_pct"], 0) + "%", 30, 4).
                }
            }
        }
    }
    IF sys:HASKEY("wd") {
        IF sys["wd"] = "FAIL" { aoso_hud_alert("wd", "CRIT", "WATCHDOG TRIPPED", 20, 6). }
    }
    IF AOSO_HUD_DATA["orbit"]["burning"] {
        IF AOSO_STEER_MODE = "OFF" { aoso_hud_alert("steer_off", "WARN", "BURN WITH STEERING OFF", 15, 4). }
    }
    IF AOSO_HUD_DATA["landing"]["active"] {
        IF AOSO_HUD_DATA["landing"]["state"] = "BURN" {
            aoso_hud_alert("suicide", "NOTICE", "SUICIDE BURN", 40, 3).
        }
        IF AOSO_HUD_DATA["res"]["mission_dv"] < AOSO_HUD_DATA["res"]["land_dv"] * 0.5 {
            IF AOSO_HUD_DATA["res"]["land_dv"] > 0 {
                aoso_hud_alert("land_fuel", "WARN", "LOW LANDING FUEL MARGIN", 40, 4).
            }
        }
    }
    IF HASTARGET {
    } ELSE {
        IF AOSO_HUD_CTX = "DOCK" { aoso_hud_alert("tgt_lost", "WARN", "TARGET LOST", 20, 4). }
    }
}
