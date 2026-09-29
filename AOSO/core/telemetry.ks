// AOSO/core/telemetry.ks
// Timed CSV telemetry. Separate from the human log (core/logger.ks) and
// from structured events / the flight record (core/observe.ks).
// Scheduler interval is 0.1 s; this module internally skips so AUTO is
// ~0.2 s in ASCENT/DESCENT/BURN/LANDING, ~1 s in cruise, ~5 s on the pad.
// Samples go to a RAM buffer and flush every ~8 rows / 2 s / important
// event -- not a WRITELN every physics tick. Do not LIST PARTS. One
// SHIP:RESOURCES loop covers LF/OX/EC plus SolidFuel, Ore, Ablator, and
// MonoPropellant. Below 10 km, or whenever throttle is open, the row
// stays at 1 Hz even if the CPU band would otherwise shed telemetry.

GLOBAL AOSO_TELEMETRY_HEADER_WRITTEN IS FALSE.
GLOBAL AOSO_TELEM_BUF IS LIST().
GLOBAL AOSO_TELEM_LAST_FLUSH IS 0.

FUNCTION aoso_telemetry_header {
    RETURN "ut,met,body,lat,lng,alt,radar,srf,orb,vs,hs,pitch,hdg,aoa,q,drag,throt,thrust,mass,stg,lf,ox,ec,sf,ore,ablator,mp,apo,pe,inc,ecc,etaap,phase,cpu".
}

FUNCTION aoso_telemetry_hot {
    IF SHIP:UNPACKED {
        IF THROTTLE > 0.02 { RETURN TRUE. }
        IF ALT:RADAR < 10000 { RETURN TRUE. }
    }
    IF ALTITUDE < 10000 { RETURN TRUE. }
    RETURN FALSE.
}

FUNCTION aoso_telemetry_interval {
    LOCAL rate IS "AUTO".
    IF AOSO_CONFIG:HASKEY("TELEM_RATE") { SET rate TO AOSO_CONFIG["TELEM_RATE"]. }
    IF rate = "OFF" { RETURN 99. }
    IF rate = "FAST" { RETURN 0.1. }
    IF rate = "NORMAL" { RETURN 0.5. }
    IF rate = "SLOW" {
        IF aoso_telemetry_hot() { RETURN 1. }
        RETURN 2.
    }
    LOCAL hot IS aoso_telemetry_hot().
    IF AOSO_CPU_LEVEL >= 2 {
        IF hot { RETURN 1. }
        IF AOSO_CPU_LEVEL >= 3 { RETURN 99. }
        RETURN 5.
    }
    IF hot {
        IF AOSO_CPU_LEVEL >= 1 { RETURN 1. }
    }
    IF AOSO_CPU_LEVEL >= 1 { RETURN 2. }
    LOCAL p IS AOSO_OBS_PHASE.
    IF p = "ASCENT" { RETURN 0.2. }
    IF p = "DESCENT" { RETURN 0.2. }
    IF p = "BURN" { RETURN 0.2. }
    IF p = "LANDING" { RETURN 0.2. }
    IF p = "PRELAUNCH" { RETURN 5. }
    IF p = "SURFACE" { RETURN 5. }
    IF hot { RETURN 1. }
    RETURN 1.
}

FUNCTION aoso_telemetry_row {
    LOCAL lf_amt IS aoso_resource_amount("LiquidFuel").
    LOCAL ox_amt IS aoso_resource_amount("Oxidizer").
    LOCAL ec_amt IS aoso_resource_amount("ElectricCharge").
    LOCAL sf_amt IS aoso_resource_amount("SolidFuel").
    LOCAL ore_amt IS aoso_resource_amount("Ore").
    LOCAL ab_amt IS aoso_resource_amount("Ablator").
    LOCAL mp_amt IS aoso_resource_amount("MonoPropellant").

    LOCAL pitch IS 90 - VANG(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR).
    IF pitch < 0 { SET pitch TO 0. }
    IF pitch > 90 { SET pitch TO 90. }
    LOCAL fpa IS 90.
    LOCAL srfvel IS SHIP:VELOCITY:SURFACE.
    LOCAL srf IS srfvel:MAG.
    IF srf >= 1 {
        SET fpa TO 90 - VANG(SHIP:UP:VECTOR, srfvel).
        IF fpa < 0 { SET fpa TO 0. }
        IF fpa > 90 { SET fpa TO 90. }
    }
    LOCAL aoa IS pitch - fpa.
    LOCAL vs IS VERTICALSPEED.
    LOCAL hs IS 0.
    LOCAL vs2 IS vs * vs.
    IF srf * srf > vs2 { SET hs TO SQRT(srf * srf - vs2). }
    LOCAL alt_m IS ALTITUDE.
    LOCAL radar_m IS -1.
    IF SHIP:UNPACKED { SET radar_m TO ALT:RADAR. }
    LOCAL throt_now IS 0.
    IF SHIP:UNPACKED { SET throt_now TO THROTTLE. }

    RETURN ROUND(TIME:SECONDS, 2) + "," + ROUND(MISSIONTIME, 1) + "," + SHIP:BODY:NAME + "," +
        ROUND(SHIP:LATITUDE, 4) + "," + ROUND(SHIP:LONGITUDE, 4) + "," +
        ROUND(alt_m, 1) + "," + ROUND(radar_m, 1) + "," +
        ROUND(srf, 2) + "," + ROUND(SHIP:VELOCITY:ORBIT:MAG, 2) + "," +
        ROUND(vs, 2) + "," + ROUND(hs, 2) + "," +
        ROUND(pitch, 2) + "," + ROUND(SHIP:FACING:YAW, 1) + "," + ROUND(aoa, 2) + "," +
        ROUND(SHIP:Q, 4) + "," + ROUND(aoso_aero_drag_kn(), 2) + "," +
        ROUND(throt_now, 3) + "," + ROUND(SHIP:AVAILABLETHRUST, 2) + "," + ROUND(SHIP:MASS, 3) + "," +
        STAGE:NUMBER + "," + ROUND(lf_amt, 1) + "," + ROUND(ox_amt, 1) + "," + ROUND(ec_amt, 1) + "," +
        ROUND(sf_amt, 1) + "," + ROUND(ore_amt, 1) + "," + ROUND(ab_amt, 1) + "," + ROUND(mp_amt, 1) + "," +
        ROUND(APOAPSIS, 1) + "," + ROUND(PERIAPSIS, 1) + "," +
        ROUND(SHIP:ORBIT:INCLINATION, 3) + "," + ROUND(SHIP:ORBIT:ECCENTRICITY, 5) + "," +
        ROUND(ETA:APOAPSIS, 1) + "," + AOSO_OBS_PHASE + "," + AOSO_CPU_NAME.
}

FUNCTION aoso_telemetry_flush {
    IF AOSO_TELEM_BUF:LENGTH = 0 {
        SET AOSO_TELEM_LAST_FLUSH TO TIME:SECONDS.
        SET AOSO_TELEM_FLUSH_NOW TO FALSE.
        RETURN.
    }
    LOCAL file_path IS AOSO_CONST["TELEMETRY_FILE"].
    IF NOT AOSO_TELEMETRY_HEADER_WRITTEN {
        IF NOT EXISTS(file_path) {
            LOCAL header_file IS CREATE(file_path).
            header_file:WRITELN(aoso_telemetry_header()).
        }
        SET AOSO_TELEMETRY_HEADER_WRITTEN TO TRUE.
    }
    LOCAL f IS OPEN(file_path).
    UNTIL AOSO_TELEM_BUF:LENGTH = 0 {
        LOCAL line IS AOSO_TELEM_BUF[0].
        AOSO_TELEM_BUF:REMOVE(0).
        f:WRITELN(line).
    }
    SET AOSO_TELEM_LAST_FLUSH TO TIME:SECONDS.
    SET AOSO_TELEM_FLUSH_NOW TO FALSE.
}

FUNCTION aoso_telemetry_tick {
    LOCAL now IS TIME:SECONDS.
    LOCAL interval IS aoso_telemetry_interval().
    LOCAL force IS FALSE.
    IF AOSO_POST_LEFT > 0 { SET force TO TRUE. }
    IF AOSO_TELEM_FLUSH_NOW { SET force TO TRUE. }
    IF NOT force {
        IF now - AOSO_OBS_TELEM_LAST < interval { RETURN. }
    }
    SET AOSO_OBS_TELEM_LAST TO now.

    LOCAL packed IS aoso_telemetry_row().
    aoso_observe_ring_push(packed).
    IF AOSO_POST_LEFT > 0 { aoso_observe_post_sample(packed). }

    AOSO_TELEM_BUF:ADD(packed).
    IF AOSO_TELEM_BUF:LENGTH > 40 { AOSO_TELEM_BUF:REMOVE(0). }

    LOCAL flush IS FALSE.
    IF AOSO_TELEM_FLUSH_NOW { SET flush TO TRUE. }
    IF AOSO_POST_LEFT > 0 { SET flush TO TRUE. }
    IF AOSO_TELEM_BUF:LENGTH >= 8 { SET flush TO TRUE. }
    IF (now - AOSO_TELEM_LAST_FLUSH) >= 2 { SET flush TO TRUE. }
    IF flush { aoso_telemetry_flush(). }
}

FUNCTION aoso_telemetry_register_task {
    PARAMETER interval_s IS 0.5.
    aoso_sched_add("telemetry", interval_s, aoso_telemetry_tick@).
}
