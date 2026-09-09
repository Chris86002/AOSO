// AOSO/vehicle/resources.ks
// Resource queries and fuel-reserve/abort checks. "Stage propellant" here
// means the resources pooled to the currently active stage (STAGE:RESOURCES),
// which is what actually matters for an abort decision -- upper/lower stage
// tanks not yet connected by fuel flow don't help the active engines.
// Electric charge is deliberately excluded: it is not a propellant and is
// usually plentiful, so including it would mask a genuine fuel shortage.

FUNCTION aoso_resource_amount {
    PARAMETER res_name.
    FOR r IN SHIP:RESOURCES {
        IF r:NAME = res_name { RETURN r:AMOUNT. }
    }
    RETURN 0.
}

FUNCTION aoso_resource_capacity {
    PARAMETER res_name.
    FOR r IN SHIP:RESOURCES {
        IF r:NAME = res_name { RETURN r:CAPACITY. }
    }
    RETURN 0.
}

FUNCTION aoso_resource_pct {
    PARAMETER res_name.
    LOCAL cap IS aoso_resource_capacity(res_name).
    IF cap <= 0 { RETURN 0. }
    RETURN (aoso_resource_amount(res_name) / cap) * 100.
}

// Lowest fill percentage among the current stage's tracked propellants (i.e.
// the "weakest link" resource). Returns 100 when the stage has no propellant
// tanks connected (e.g. a coast stage with no engine), so reserve/abort
// checks don't misfire on stages that aren't burning anything.
FUNCTION aoso_stage_propellant_pct {
    LOCAL res IS STAGE:RESOURCES.
    LOCAL min_pct IS 100.
    LOCAL found IS FALSE.
    FOR r IN res {
        IF r:NAME <> "ElectricCharge" AND r:CAPACITY > 0 {
            SET found TO TRUE.
            LOCAL pct IS (r:AMOUNT / r:CAPACITY) * 100.
            IF pct < min_pct { SET min_pct TO pct. }
        }
    }
    IF NOT found { RETURN 100. }
    RETURN min_pct.
}

FUNCTION aoso_fuel_reserve_ok {
    RETURN aoso_stage_propellant_pct() > aoso_config_get("FUEL_RESERVE_PCT", 10).
}

// Returns TRUE only when the active stage's propellant has dropped to/below
// the configured abort threshold AND there is no way to recover thrust. A low
// active-stage reading is normal mid-ascent: lower stages and spent boosters
// run dry and get jettisoned by vehicle/staging.ks, after which the next
// stage's fuller tanks take over. So this defers to vehicle/parts.ks's
// aoso_parts_thrust_recoverable() -- if the vehicle is still burning, can drop
// spent boosters, or has an un-ignited stage to fall back on, the answer is
// "stage", not "abort". Only once thrust is genuinely unrecoverable (nothing
// burning and nothing left to stage to) does this abort, which is exactly the
// case where continuing is pointless.
//
// The logger call is made unconditionally (core/logger.ks is always loaded
// first by main.ks's RUN ONCE order, so aoso_log_warn always exists): a
// former "IF should_abort AND DEFINED aoso_log_warn" guard crashed the ascent
// the first time this was reached (on the first GRAVITY_TURN tick). kOS never
// short-circuits AND, so "DEFINED aoso_log_warn" was always evaluated, and
// "DEFINED <bare function name>" in a shared RUN-ONCE context auto-calls that
// function with zero arguments -- invoking aoso_log_warn() with no tag/message
// threw "Too few arguments" every time (KSP-KOS/KOS#2159).
FUNCTION aoso_fuel_abort_check {
    LOCAL pct IS aoso_stage_propellant_pct().
    IF pct > aoso_config_get("ABORT_FUEL_PCT", 3) { RETURN FALSE. }
    IF aoso_parts_thrust_recoverable() { RETURN FALSE. }
    aoso_log_warn("FUEL", "Stage propellant at " + ROUND(pct, 1) + "% with no recoverable thrust -- aborting.").
    RETURN TRUE.
}
