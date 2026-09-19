// AOSO/core/context.ks
// Compact shared world snapshot. Subsystems read aoso_ctx_get / write
// via aoso_ctx_set and dirty flags. Do not copy giant lexicons here.

GLOBAL AOSO_CTX IS LEXICON().
GLOBAL AOSO_CFG_ID IS "".
GLOBAL AOSO_CFG_LOCKED IS FALSE.

FUNCTION aoso_ctx_init {
    SET AOSO_CTX TO LEXICON(
        "cfg_id", "",
        "class", "",
        "mass", 0,
        "body", "",
        "situation", "",
        "fuel_pct", 0,
        "ec_pct", 0,
        "mission_dv", 0,
        "total_dv", 0,
        "goal", "",
        "target", "",
        "action", "",
        "controller", "",
        "progress", 0,
        "progress_at", 0,
        "quiet", FALSE,
        "confidence", 0.5,
        "rev_vehicle", 0,
        "rev_cap", 0,
        "rev_budget", 0,
        "rev_world", 0,
        "rev_plan", 0,
        "rev_xp", 0,
        "dirty_vehicle", TRUE,
        "dirty_cap", TRUE,
        "dirty_budget", TRUE,
        "dirty_feas", TRUE,
        "dirty_opp", TRUE,
        "dirty_route", TRUE,
        "dirty_plan", TRUE
    ).
    aoso_ctx_refresh_env().
}

FUNCTION aoso_ctx_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_CTX:HASKEY(key) { RETURN AOSO_CTX[key]. }
    RETURN default_value.
}

FUNCTION aoso_ctx_set {
    PARAMETER key.
    PARAMETER value.
    SET AOSO_CTX[key] TO value.
}

FUNCTION aoso_ctx_bump {
    PARAMETER rev_key.
    IF AOSO_CTX:HASKEY(rev_key) {
        SET AOSO_CTX[rev_key] TO AOSO_CTX[rev_key] + 1.
    }
}

FUNCTION aoso_ctx_dirty {
    PARAMETER flag.
    SET AOSO_CTX[flag] TO TRUE.
}

FUNCTION aoso_ctx_clear_dirty {
    PARAMETER flag.
    SET AOSO_CTX[flag] TO FALSE.
}

FUNCTION aoso_ctx_is_dirty {
    PARAMETER flag.
    IF AOSO_CTX:HASKEY(flag) { RETURN AOSO_CTX[flag]. }
    RETURN FALSE.
}

FUNCTION aoso_cfg_mass_bucket {
    LOCAL m IS SHIP:MASS.
    LOCAL b IS FLOOR(m / 5) * 5.
    RETURN ROUND(b, 0).
}

FUNCTION aoso_cfg_id_make {
    LOCAL n_eng IS 0.
    LOCAL n_stg IS STAGE:NUMBER.
    LOCAL lf_cap IS 0.
    LOCAL isru_n IS 0.
    LOCAL dock_n IS 0.
    IF DEFINED AOSO_PROFILE {
        IF AOSO_PROFILE:HASKEY("snapshot") {
            LOCAL snap IS AOSO_PROFILE["snapshot"].
            IF snap:HASKEY("engines") { SET n_eng TO snap["engines"]. }
            IF snap:HASKEY("stages") { SET n_stg TO snap["stages"]. }
            IF snap:HASKEY("docking") { SET dock_n TO snap["docking"]. }
            IF snap:HASKEY("drills") { SET isru_n TO snap["drills"]. }
        }
        IF AOSO_PROFILE:HASKEY("isru") {
            IF AOSO_PROFILE["isru"]:HASKEY("can_mine") {
                IF AOSO_PROFILE["isru"]["can_mine"] {
                    IF isru_n < 1 { SET isru_n TO 1. }
                }
            }
        }
    }
    IF DEFINED AOSO_VESSEL {
        IF AOSO_VESSEL:HASKEY("resources") {
            FOR res_row IN AOSO_VESSEL["resources"] {
                IF res_row["name"] = "LiquidFuel" { SET lf_cap TO ROUND(res_row["capacity"], 0). }
            }
        }
    }
    RETURN SHIP:NAME + "|M" + aoso_cfg_mass_bucket() + "|E" + n_eng + "|S" + n_stg + "|LF" + lf_cap + "|ISRU" + isru_n + "|D" + dock_n.
}

FUNCTION aoso_cfg_id_save {
    aoso_json_write(AOSO_CONST["CFG_ID_FILE"], LEXICON("id", AOSO_CFG_ID, "name", SHIP:NAME, "ut", TIME:SECONDS)).
}

FUNCTION aoso_cfg_id_lock {
    IF AOSO_CFG_LOCKED {
        IF DEFINED AOSO_CTX {
            SET AOSO_CTX["cfg_id"] TO AOSO_CFG_ID.
        }
        RETURN AOSO_CFG_ID.
    }
    IF SHIP:STATUS = "PRELAUNCH" {
        SET AOSO_CFG_ID TO aoso_cfg_id_make().
        aoso_cfg_id_save().
        SET AOSO_CFG_LOCKED TO TRUE.
        SET AOSO_CTX["cfg_id"] TO AOSO_CFG_ID.
        aoso_log_info("CTX", "Launch configuration locked: " + AOSO_CFG_ID + ".").
        RETURN AOSO_CFG_ID.
    }
    LOCAL loaded IS aoso_json_read(AOSO_CONST["CFG_ID_FILE"], 0).
    IF loaded:ISTYPE("Lexicon") {
        IF loaded:HASKEY("id") {
            IF loaded["id"] <> "" {
                SET AOSO_CFG_ID TO loaded["id"].
                SET AOSO_CFG_LOCKED TO TRUE.
                SET AOSO_CTX["cfg_id"] TO AOSO_CFG_ID.
                aoso_log_info("CTX", "Restored launch configuration: " + AOSO_CFG_ID + ".").
                RETURN AOSO_CFG_ID.
            }
        }
    }
    SET AOSO_CFG_ID TO aoso_cfg_id_make().
    aoso_cfg_id_save().
    SET AOSO_CFG_LOCKED TO TRUE.
    SET AOSO_CTX["cfg_id"] TO AOSO_CFG_ID.
    aoso_log_info("CTX", "Configuration identity: " + AOSO_CFG_ID + ".").
    RETURN AOSO_CFG_ID.
}

FUNCTION aoso_cfg_id {
    IF AOSO_CFG_ID <> "" { RETURN AOSO_CFG_ID. }
    IF SHIP:STATUS = "PRELAUNCH" { RETURN aoso_cfg_id_lock(). }
    SET AOSO_CFG_ID TO aoso_cfg_id_make().
    SET AOSO_CTX["cfg_id"] TO AOSO_CFG_ID.
    RETURN AOSO_CFG_ID.
}

FUNCTION aoso_ctx_refresh_env {
    SET AOSO_CTX["body"] TO SHIP:BODY:NAME.
    SET AOSO_CTX["situation"] TO SHIP:STATUS.
    SET AOSO_CTX["mass"] TO SHIP:MASS.
    IF DEFINED AOSO_CLASSIFY {
        IF AOSO_CLASSIFY:HASKEY("name") { SET AOSO_CTX["class"] TO AOSO_CLASSIFY["name"]. }
    }
    IF DEFINED AOSO_BUDGET {
        IF AOSO_BUDGET:HASKEY("mission_dv") { SET AOSO_CTX["mission_dv"] TO AOSO_BUDGET["mission_dv"]. }
        IF AOSO_BUDGET:HASKEY("total_dv") { SET AOSO_CTX["total_dv"] TO AOSO_BUDGET["total_dv"]. }
    }
    IF AOSO_CFG_ID <> "" { SET AOSO_CTX["cfg_id"] TO AOSO_CFG_ID. }
    SET AOSO_CTX["fuel_pct"] TO aoso_resource_pct("LiquidFuel").
    SET AOSO_CTX["ec_pct"] TO aoso_resource_pct("ElectricCharge").
}

FUNCTION aoso_ctx_mark_vehicle {
    aoso_ctx_bump("rev_vehicle").
    aoso_ctx_dirty("dirty_vehicle").
    aoso_ctx_dirty("dirty_cap").
    aoso_ctx_dirty("dirty_budget").
    aoso_ctx_dirty("dirty_feas").
    aoso_ctx_dirty("dirty_opp").
    aoso_ctx_dirty("dirty_route").
    aoso_ctx_dirty("dirty_plan").
}

FUNCTION aoso_ctx_mark_budget {
    aoso_ctx_bump("rev_budget").
    aoso_ctx_dirty("dirty_budget").
    aoso_ctx_dirty("dirty_feas").
    aoso_ctx_dirty("dirty_opp").
    aoso_ctx_dirty("dirty_route").
}

FUNCTION aoso_ctx_mark_world {
    aoso_ctx_bump("rev_world").
    aoso_ctx_dirty("dirty_feas").
    aoso_ctx_dirty("dirty_opp").
    aoso_ctx_dirty("dirty_route").
    aoso_ctx_dirty("dirty_plan").
}

FUNCTION aoso_ctx_mark_plan {
    aoso_ctx_bump("rev_plan").
    aoso_ctx_dirty("dirty_plan").
}
