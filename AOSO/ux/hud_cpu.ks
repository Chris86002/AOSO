// AOSO/ux/hud_cpu.ks
// Optional second-processor HUD. Boot this file on a kOS core tagged HUD.
// This core has its own IPU. It never steers, stages, or burns.
// Live ship suffixes are read here. AOSO intent comes from 0:/aoso_hud_bus.txt
// written by the flight CPU.
//
// VAB: add a second kOS processor, name-tag it HUD, boot file = AOSO/ux/hud_cpu.ks

SWITCH TO 0.

CLEARSCREEN.
PRINT "AOSO HUD CPU".
PRINT "This core only paints. Flight stays on the other CPU.".

LOCAL g IS GUI(420).
SET g:X TO 20.
SET g:Y TO 60.
SET g:DRAGGABLE TO TRUE.
LOCAL title IS g:ADDLABEL("<b><color=#7EC8FF>AOSO</color>  HUD CPU</b>").
SET title:STYLE:HSTRETCH TO TRUE.
LOCAL w_sys IS g:ADDLABEL("SYS  -").
SET w_sys:STYLE:HSTRETCH TO TRUE.
LOCAL w_do IS g:ADDLABEL("DOING  -").
SET w_do:STYLE:HSTRETCH TO TRUE.
LOCAL w_dt IS g:ADDLABEL("").
SET w_dt:STYLE:HSTRETCH TO TRUE.
LOCAL w_alt IS g:ADDLABEL("ALT  -").
SET w_alt:STYLE:HSTRETCH TO TRUE.
LOCAL w_spd IS g:ADDLABEL("SPD  -").
SET w_spd:STYLE:HSTRETCH TO TRUE.
LOCAL w_orb IS g:ADDLABEL("ORB  -").
SET w_orb:STYLE:HSTRETCH TO TRUE.
LOCAL w_twr IS g:ADDLABEL("TWR  -").
SET w_twr:STYLE:HSTRETCH TO TRUE.
LOCAL w_node IS g:ADDLABEL("NODE  -").
SET w_node:STYLE:HSTRETCH TO TRUE.
LOCAL w_cpu IS g:ADDLABEL("FLIGHT CPU  -").
SET w_cpu:STYLE:HSTRETCH TO TRUE.
g:SHOW().

LOCAL last_do IS "".
LOCAL last_sys IS "".
LOCAL last_alt IS "".
LOCAL last_spd IS "".
LOCAL last_orb IS "".
LOCAL last_twr IS "".
LOCAL last_node IS "".
LOCAL last_cpu IS "".
LOCAL last_dt IS "".
LOCAL bus_do IS "".
LOCAL bus_dt IS "".
LOCAL bus_sys IS "".
LOCAL bus_cpu IS "".
LOCAL bus_ut IS 0.

FUNCTION hudcpu_km {
    PARAMETER meters.
    IF meters < 0 { RETURN ROUND(meters, 0) + " m". }
    IF meters >= 10000 { RETURN ROUND(meters / 1000, 1) + " km". }
    RETURN ROUND(meters, 0) + " m".
}

FUNCTION hudcpu_set {
    PARAMETER w.
    PARAMETER last_name.
    PARAMETER txt.
    IF last_name = "do" {
        IF txt = last_do { RETURN. }
        SET last_do TO txt.
    }
    IF last_name = "sys" {
        IF txt = last_sys { RETURN. }
        SET last_sys TO txt.
    }
    IF last_name = "alt" {
        IF txt = last_alt { RETURN. }
        SET last_alt TO txt.
    }
    IF last_name = "spd" {
        IF txt = last_spd { RETURN. }
        SET last_spd TO txt.
    }
    IF last_name = "orb" {
        IF txt = last_orb { RETURN. }
        SET last_orb TO txt.
    }
    IF last_name = "twr" {
        IF txt = last_twr { RETURN. }
        SET last_twr TO txt.
    }
    IF last_name = "node" {
        IF txt = last_node { RETURN. }
        SET last_node TO txt.
    }
    IF last_name = "cpu" {
        IF txt = last_cpu { RETURN. }
        SET last_cpu TO txt.
    }
    IF last_name = "dt" {
        IF txt = last_dt { RETURN. }
        SET last_dt TO txt.
    }
    SET w:TEXT TO txt.
}

FUNCTION hudcpu_bus {
    IF TIME:SECONDS - bus_ut < 0.2 { RETURN. }
    SET bus_ut TO TIME:SECONDS.
    LOCAL pth IS "0:/aoso_hud_bus.txt".
    IF NOT EXISTS(pth) { RETURN. }
    LOCAL fh IS OPEN(pth).
    LOCAL line IS fh:READLINE().
    LOCAL left IS line.
    LOCAL fields IS LIST().
    LOCAL guard IS 0.
    UNTIL guard >= 8 {
        SET guard TO guard + 1.
        LOCAL bar IS left:FIND("|").
        IF bar < 0 {
            fields:ADD(left).
            BREAK.
        }
        IF bar = 0 { fields:ADD(""). }
        ELSE { fields:ADD(left:SUBSTRING(0, bar)). }
        IF bar + 1 >= left:LENGTH {
            fields:ADD("").
            BREAK.
        }
        SET left TO left:SUBSTRING(bar + 1, left:LENGTH - bar - 1).
    }
    IF fields:LENGTH >= 4 {
        SET bus_do TO fields[0].
        SET bus_dt TO fields[1].
        SET bus_sys TO fields[2].
        SET bus_cpu TO fields[3].
    }
}

FUNCTION hudcpu_paint {
    hudcpu_bus().
    LOCAL doing IS bus_do.
    IF doing = "" { SET doing TO SHIP:STATUS. }
    hudcpu_set(w_do, "do", "DOING  " + doing).
    hudcpu_set(w_dt, "dt", bus_dt).
    hudcpu_set(w_sys, "sys", "SYS  " + bus_sys + "  " + SHIP:BODY:NAME + "  " + SHIP:STATUS + "  STG " + STAGE:NUMBER).
    hudcpu_set(w_alt, "alt", "ALT  " + hudcpu_km(ALTITUDE) + "   VS " + ROUND(VERTICALSPEED, 1) + " m/s").
    LOCAL in_atm IS FALSE.
    IF SHIP:BODY:ATM:EXISTS {
        IF ALTITUDE < SHIP:BODY:ATM:HEIGHT { SET in_atm TO TRUE. }
    }
    IF in_atm {
        hudcpu_set(w_spd, "spd", "SRF " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + "  GS " + ROUND(SHIP:GROUNDSPEED, 0) + " m/s").
    } ELSE {
        hudcpu_set(w_spd, "spd", "ORB " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 0) + "  SRF " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) + " m/s").
    }
    hudcpu_set(w_orb, "orb", "AP " + hudcpu_km(APOAPSIS) + "  PE " + hudcpu_km(PERIAPSIS)).
    LOCAL g0 IS 9.81.
    LOCAL rad IS SHIP:BODY:RADIUS + ALTITUDE.
    IF rad > 0 { SET g0 TO SHIP:BODY:MU / (rad * rad). }
    LOCAL twr IS 0.
    IF SHIP:MASS > 0 {
        IF g0 > 0 { SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * g0). }
    }
    hudcpu_set(w_twr, "twr", "TWR " + ROUND(twr, 2) + "  THR " + ROUND(THROTTLE * 100, 0) + "%  MASS " + ROUND(SHIP:MASS, 2) + " t").
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        hudcpu_set(w_node, "node", "NODE  " + ROUND(nd:DELTAV:MAG, 1) + " m/s  T-" + ROUND(nd:ETA, 0) + "s").
    } ELSE {
        hudcpu_set(w_node, "node", "NODE  none").
    }
    hudcpu_set(w_cpu, "cpu", "FLIGHT CPU  " + bus_cpu + "  this IPU " + CONFIG:IPU).
}

UNTIL FALSE {
    hudcpu_paint().
    WAIT 0.
}