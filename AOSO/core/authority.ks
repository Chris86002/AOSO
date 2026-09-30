// AOSO/core/authority.ks
// Explicit ownership of flight-control resources. Steering/throttle still
// lock-once in flight/steering.ks. Authority decides WHO may command them.
// Empty owner = anyone only when the resource is also unowned. Named
// controllers must acquire before command wrappers will act.

GLOBAL AOSO_AUTH IS LEXICON(
    "STEERING", "",
    "THROTTLE", "",
    "STAGING", "",
    "WARP", "",
    "RCS", "",
    "SAS", "",
    "TARGETING", ""
).
GLOBAL AOSO_AUTH_PRIO IS LEXICON().
GLOBAL AOSO_AUTH_WHO IS "".

FUNCTION aoso_auth_owner {
    PARAMETER res_name.
    IF AOSO_AUTH:HASKEY(res_name) { RETURN AOSO_AUTH[res_name]. }
    RETURN "".
}

FUNCTION aoso_auth_has {
    PARAMETER who.
    PARAMETER res_name.
    LOCAL owner IS aoso_auth_owner(res_name).
    IF owner = "" { RETURN TRUE. }
    RETURN owner = who.
}

FUNCTION aoso_auth_acquire {
    PARAMETER who.
    PARAMETER res_name.
    PARAMETER prio IS 1.
    LOCAL owner IS aoso_auth_owner(res_name).
    IF owner = "" {
        SET AOSO_AUTH[res_name] TO who.
        SET AOSO_AUTH_PRIO[res_name] TO prio.
        aoso_log_info("AUTH", who + " acquired " + res_name + " (prio " + prio + ").").
        RETURN TRUE.
    }
    IF owner = who {
        SET AOSO_AUTH_PRIO[res_name] TO prio.
        RETURN TRUE.
    }
    LOCAL hold IS 0.
    IF AOSO_AUTH_PRIO:HASKEY(res_name) { SET hold TO AOSO_AUTH_PRIO[res_name]. }
    IF prio > hold {
        aoso_log_warn("AUTH", who + " preempts " + owner + " for " + res_name + " (" + hold + " -> " + prio + ").").
        SET AOSO_AUTH[res_name] TO who.
        SET AOSO_AUTH_PRIO[res_name] TO prio.
        RETURN TRUE.
    }
    aoso_log_warn_every(8, "AUTH", who + " denied " + res_name + " (held by " + owner + " prio " + hold + ").").
    RETURN FALSE.
}

FUNCTION aoso_auth_release {
    PARAMETER who.
    PARAMETER res_name.
    IF aoso_auth_owner(res_name) = who {
        SET AOSO_AUTH[res_name] TO "".
        SET AOSO_AUTH_PRIO[res_name] TO 0.
        aoso_log_info("AUTH", who + " released " + res_name + ".").
    }
}

FUNCTION aoso_auth_release_all {
    PARAMETER who.
    LOCAL names IS LIST().
    FOR k IN AOSO_AUTH:KEYS { names:ADD(k). }
    FOR k IN names {
        IF AOSO_AUTH[k] = who { aoso_auth_release(who, k). }
    }
}

FUNCTION aoso_auth_use {
    PARAMETER who.
    SET AOSO_AUTH_WHO TO who.
}

FUNCTION aoso_auth_can_cmd {
    PARAMETER res_name.
    LOCAL owner IS aoso_auth_owner(res_name).
    IF owner = "" { RETURN TRUE. }
    IF AOSO_AUTH_WHO = "" {
        aoso_log_warn_every(8, "AUTH", "empty controller denied " + res_name + " (held by " + owner + ").").
        RETURN FALSE.
    }
    RETURN owner = AOSO_AUTH_WHO.
}

FUNCTION aoso_safe_hold {
    PARAMETER reason.
    LOCAL prior_who IS AOSO_AUTH_WHO.
    aoso_auth_use("watchdog").
    aoso_auth_acquire("watchdog", "WARP", 5).
    aoso_throttle_set(0).
    aoso_steer_release().
    aoso_warp_hard_stop().
    aoso_auth_release_all("watchdog").
    aoso_auth_release_all(prior_who).
    aoso_auth_use("").
    aoso_log_warn("HOLD", reason).
    IF DEFINED AOSO_EVENTS { aoso_event_publish("HOLD", "safe", reason). }

}
