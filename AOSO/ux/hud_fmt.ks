// AOSO/ux/hud_fmt.ks
// Formatting helpers for the HUD. No vessel queries here.

FUNCTION aoso_hud_km {
    PARAMETER meters.
    IF meters < 0 { RETURN ROUND(meters, 0) + " m". }
    IF meters >= 1000000 { RETURN ROUND(meters / 1000, 0) + " km". }
    IF meters >= 10000 { RETURN ROUND(meters / 1000, 1) + " km". }
    RETURN ROUND(meters, 0) + " m".
}

FUNCTION aoso_hud_eta {
    PARAMETER secs.
    IF secs < 0 { RETURN "now". }
    IF secs < 90 { RETURN ROUND(secs, 0) + "s". }
    IF secs < 3600 { RETURN ROUND(secs / 60, 1) + " min". }
    IF secs < 86400 { RETURN ROUND(secs / 3600, 1) + " h". }
    RETURN ROUND(secs / 86400, 1) + " d".
}

FUNCTION aoso_hud_pad {
    PARAMETER s.
    PARAMETER n.
    LOCAL out IS "" + s.
    UNTIL out:LENGTH >= n {
        SET out TO out + " ".
    }
    IF out:LENGTH > n { RETURN out:SUBSTRING(0, n). }
    RETURN out.
}

FUNCTION aoso_hud_bar {
    PARAMETER pct.
    PARAMETER width IS 14.
    LOCAL p IS pct.
    IF p < 0 { SET p TO 0. }
    IF p > 100 { SET p TO 100. }
    LOCAL filled IS FLOOR((p / 100) * width).
    IF filled > width { SET filled TO width. }
    LOCAL i IS 0.
    LOCAL out IS "".
    UNTIL i >= width {
        IF i < filled { SET out TO out + "#". }
        ELSE { SET out TO out + "-". }
        SET i TO i + 1.
    }
    RETURN out + " " + ROUND(p, 0) + "%".
}

FUNCTION aoso_hud_color {
    PARAMETER hex.
    PARAMETER s.
    RETURN "<color=" + hex + ">" + s + "</color>".
}

FUNCTION aoso_hud_ok { PARAMETER s. RETURN aoso_hud_color("#7CFF8A", s). }
FUNCTION aoso_hud_warn { PARAMETER s. RETURN aoso_hud_color("#FFCC44", s). }
FUNCTION aoso_hud_bad { PARAMETER s. RETURN aoso_hud_color("#FF6B4A", s). }
FUNCTION aoso_hud_info { PARAMETER s. RETURN aoso_hud_color("#7EC8FF", s). }
FUNCTION aoso_hud_mute { PARAMETER s. RETURN aoso_hud_color("#8A93A6", s). }

FUNCTION aoso_hud_st_glyph {
    PARAMETER st.
    IF st = "NOM" { RETURN aoso_hud_ok("ONLINE"). }
    IF st = "DEG" { RETURN aoso_hud_warn("LIMITED"). }
    IF st = "FAIL" { RETURN aoso_hud_bad("OFFLINE"). }
    IF st = "STBY" { RETURN aoso_hud_mute("STANDBY"). }
    RETURN aoso_hud_mute("N/A").
}

FUNCTION aoso_hud_na {
    RETURN aoso_hud_mute("N/A").
}

FUNCTION aoso_hud_heading_deg {
    LOCAL east IS VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
    LOCAL x IS VDOT(SHIP:NORTH:VECTOR, SHIP:FACING:FOREVECTOR).
    LOCAL y IS VDOT(east, SHIP:FACING:FOREVECTOR).
    LOCAL hdg IS ARCTAN2(y, x).
    IF hdg < 0 { SET hdg TO hdg + 360. }
    RETURN hdg.
}

FUNCTION aoso_hud_pitch_deg {
    RETURN 90 - VANG(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR).
}

FUNCTION aoso_hud_roll_deg {
    RETURN SHIP:FACING:ROLL.
}

FUNCTION aoso_hud_aoa_deg {
    IF SHIP:VELOCITY:SURFACE:MAG < 1 { RETURN 0. }
    RETURN VANG(SHIP:FACING:FOREVECTOR, SHIP:VELOCITY:SURFACE).
}
