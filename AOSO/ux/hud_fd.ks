// AOSO/ux/hud_fd.ks
// Flight-director VECDRAW arrows. Vectors are SET each HUD tick (no
// VECUPDATER delegates — those re-eval every physics tick like LOCK-to-
// function and burn IPU). Groups can be forced on/off from the GUI.

GLOBAL AOSO_HUD_FD IS LEXICON().
GLOBAL AOSO_HUD_FD_ON IS FALSE.
GLOBAL AOSO_HUD_FD_LEN IS 12.

FUNCTION aoso_hud_fd_init {
    CLEARVECDRAWS().
    SET AOSO_HUD_FD TO LEXICON().
    SET AOSO_HUD_FD_ON TO FALSE.
    aoso_hud_fd_make("PRO", RGB(0.2, 0.95, 0.45), "PRO").
    aoso_hud_fd_make("RET", RGB(0.95, 0.35, 0.3), "RET").
    aoso_hud_fd_make("NML", RGB(0.55, 0.55, 1.0), "NML").
    aoso_hud_fd_make("TGT", RGB(0.35, 0.75, 1.0), "TGT").
    aoso_hud_fd_make("REL", RGB(1.0, 0.55, 0.15), "REL V").
    aoso_hud_fd_make("BURN", RGB(1.0, 0.85, 0.15), "BURN").
    aoso_hud_fd_make("LAND", RGB(0.85, 0.4, 1.0), "LAND").
    aoso_hud_fd_set("RET", FALSE).
    aoso_hud_fd_set("NML", FALSE).
    aoso_hud_fd_set("REL", FALSE).
}

FUNCTION aoso_hud_fd_make {
    PARAMETER name.
    PARAMETER col.
    PARAMETER label.
    LOCAL vd IS VECDRAW(V(0, 0, 0), V(0, 0, 0), col, label, 1.0, FALSE, 0.2).
    SET AOSO_HUD_FD[name] TO LEXICON("vd", vd, "want", TRUE, "show", FALSE).
}

FUNCTION aoso_hud_fd_set {
    PARAMETER name.
    PARAMETER on.
    IF NOT AOSO_HUD_FD:HASKEY(name) { RETURN. }
    SET AOSO_HUD_FD[name]["want"] TO on.
    IF NOT on {
        SET AOSO_HUD_FD[name]["vd"]:SHOW TO FALSE.
        SET AOSO_HUD_FD[name]["show"] TO FALSE.
    }
}

FUNCTION aoso_hud_fd_enable {
    PARAMETER on.
    SET AOSO_HUD_FD_ON TO on.
    IF NOT on {
        FOR k IN AOSO_HUD_FD:KEYS {
            SET AOSO_HUD_FD[k]["vd"]:SHOW TO FALSE.
            SET AOSO_HUD_FD[k]["show"] TO FALSE.
        }
    }
}

FUNCTION aoso_hud_fd_apply {
    PARAMETER name.
    PARAMETER vec.
    PARAMETER show.
    IF NOT AOSO_HUD_FD:HASKEY(name) { RETURN. }
    LOCAL slot IS AOSO_HUD_FD[name].
    IF NOT slot["want"] { SET show TO FALSE. }
    IF show {
        IF vec:MAG > 0.05 {
            SET slot["vd"]:VEC TO vec:NORMALIZED * AOSO_HUD_FD_LEN.
            IF NOT slot["show"] {
                SET slot["vd"]:SHOW TO TRUE.
                SET slot["show"] TO TRUE.
            }
            RETURN.
        }
    }
    IF slot["show"] {
        SET slot["vd"]:SHOW TO FALSE.
        SET slot["show"] TO FALSE.
    }
}

FUNCTION aoso_hud_fd_tick {
    PARAMETER allow.
    IF NOT allow {
        IF AOSO_HUD_FD_ON { aoso_hud_fd_enable(FALSE). }
        RETURN.
    }
    IF NOT AOSO_HUD_FD_ON { aoso_hud_fd_enable(TRUE). }

    LOCAL ctx IS AOSO_HUD_CTX.
    LOCAL show_pro IS TRUE.
    LOCAL show_ret IS FALSE.
    LOCAL show_tgt IS FALSE.
    LOCAL show_rel IS FALSE.
    LOCAL show_burn IS FALSE.
    LOCAL show_land IS FALSE.

    IF ctx = "LANDING" {
        SET show_pro TO FALSE.
        SET show_land TO TRUE.
    }
    IF ctx = "BURN" { SET show_burn TO TRUE. }
    IF ctx = "DOCK" {
        SET show_tgt TO TRUE.
        SET show_rel TO TRUE.
    }
    IF ctx = "TRANSFER" {
        IF HASTARGET { SET show_tgt TO TRUE. }
        IF HASNODE { SET show_burn TO TRUE. }
    }
    IF ctx = "LAUNCH" { SET show_pro TO TRUE. }

    LOCAL pro IS SHIP:VELOCITY:ORBIT.
    IF ctx = "LAUNCH" { SET pro TO SHIP:VELOCITY:SURFACE. }
    IF ctx = "LANDING" { SET pro TO SHIP:VELOCITY:SURFACE. }
    aoso_hud_fd_apply("PRO", pro, show_pro).
    aoso_hud_fd_apply("RET", -1 * pro, TRUE).
    LOCAL nml IS VCRS(-1 * SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT).
    aoso_hud_fd_apply("NML", nml, TRUE).

    LOCAL tgt_v IS V(0, 0, 0).
    LOCAL rel_v IS V(0, 0, 0).
    IF HASTARGET {
        SET tgt_v TO TARGET:POSITION.
        SET rel_v TO TARGET:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT.
    }
    aoso_hud_fd_apply("TGT", tgt_v, show_tgt).
    aoso_hud_fd_apply("REL", rel_v, HASTARGET).

    LOCAL burn_v IS V(0, 0, 0).
    IF HASNODE { SET burn_v TO NEXTNODE:BURNVECTOR. }
    aoso_hud_fd_apply("BURN", burn_v, show_burn).

    LOCAL land_v IS SHIP:SRFRETROGRADE:VECTOR.
    aoso_hud_fd_apply("LAND", land_v, show_land).
}
