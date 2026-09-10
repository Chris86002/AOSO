// AOSO/mission/planner.ks
// Orchestrates classify -> capability matrix -> opportunity scores ->
// clustered route. Output is the tour itinerary: what this vessel can
// actually finish, in the cheapest sequence, with mission-compression
// (refuel landings folded into the first cheap ISRU stop of a cluster
// instead of extra trips).
//
// Objectives, in order (weights from OPTIMIZATION_MODE):
//   1. minimize dV
//   2. keep a safety margin
//   3. minimize time (prefer open windows)
//   4. maximize completed destinations
//   5. skip pointless landings (tug / orbit-only)

GLOBAL AOSO_PLAN_LAST IS LEXICON().

FUNCTION aoso_plan_compress {
    PARAMETER names.
    // Adjacent moons of the same planet are already clustered. Compression
    // here is: if the class prefers orbit-only, we still keep the body on
    // the itinerary (the tour will not land) -- no extra Kerbin returns
    // get inserted between cluster members.
    RETURN names.
}

FUNCTION aoso_plan_build {
    aoso_log_info("PLAN", "Building mission plan for " + SHIP:NAME + " from " + SHIP:BODY:NAME +
        " (mode=" + aoso_config_get("OPTIMIZATION_MODE", "BALANCED") + ").").

    aoso_classify_refresh().
    aoso_budget_refresh().
    aoso_matrix_build().
    aoso_opp_build().
    aoso_route_build().

    LOCAL order IS LIST().
    IF AOSO_ROUTE_LAST:HASKEY("order") { SET order TO AOSO_ROUTE_LAST["order"]. }
    SET order TO aoso_plan_compress(order).

    LOCAL provisional IS FALSE.
    IF order:LENGTH = 0 {
        IF SHIP:STATUS = "PRELAUNCH" {
            SET order TO aoso_matrix_catalog().
            SET provisional TO TRUE.
            aoso_log_warn("PLAN", "Pad dV not usable yet (mission dV " + ROUND(aoso_budget_get("mission_dv", 0), 0) +
                " m/s) - provisional full itinerary; will replan in orbit.").
        }
    }

    LOCAL skipped IS LIST().
    LOCAL catalog IS aoso_matrix_catalog().
    FOR dest_name IN catalog {
        LOCAL row IS aoso_matrix_get(dest_name).
        IF row["result"] = "SKIP" { skipped:ADD(dest_name). }
    }

    LOCAL orbit_only IS LIST().
    FOR dest_name IN order {
        LOCAL row IS aoso_matrix_get(dest_name).
        IF row["result"] = "ORBIT_ONLY" { orbit_only:ADD(dest_name). }
    }

    SET AOSO_PLAN_LAST TO LEXICON(
        "targets", order,
        "skipped", skipped,
        "orbit_only", orbit_only,
        "class", aoso_classify_name(),
        "mode", aoso_config_get("OPTIMIZATION_MODE", "BALANCED"),
        "from", SHIP:BODY:NAME,
        "mission_dv", aoso_budget_get("mission_dv", 0),
        "provisional", provisional,
        "at", TIME:SECONDS
    ).
    aoso_json_write(AOSO_CONST["ROUTE_FILE"], AOSO_PLAN_LAST).
    aoso_plan_log().
    RETURN AOSO_PLAN_LAST.
}

FUNCTION aoso_plan_log {
    IF NOT AOSO_PLAN_LAST:HASKEY("targets") { RETURN. }
    LOCAL order_txt IS aoso_route_join(AOSO_PLAN_LAST["targets"]).
    LOCAL skip_txt IS aoso_route_join(AOSO_PLAN_LAST["skipped"]).
    LOCAL orbit_txt IS aoso_route_join(AOSO_PLAN_LAST["orbit_only"]).
    IF AOSO_PLAN_LAST["skipped"]:LENGTH = 0 {
        aoso_log_info("PLAN", "Full tour feasible as " + aoso_classify_name() +
            ". Order: " + order_txt + " then KSC.").
    } ELSE {
        aoso_log_warn("PLAN", "Full tour not feasible for this vessel (" + aoso_classify_name() +
            ", mission dV " + ROUND(AOSO_PLAN_LAST["mission_dv"], 0) + " m/s).").
        aoso_log_warn("PLAN", "Maximum achievable tour: " + order_txt + " then return.").
        aoso_log_warn("PLAN", "Skipped: " + skip_txt + ".").
    }
    IF AOSO_PLAN_LAST["orbit_only"]:LENGTH > 0 {
        aoso_log_info("PLAN", "Orbit only (no landing): " + orbit_txt + ".").
    }
}

FUNCTION aoso_plan_targets {
    IF AOSO_PLAN_LAST:HASKEY("targets") {
        IF AOSO_PLAN_LAST["targets"]:LENGTH > 0 {
            RETURN AOSO_PLAN_LAST["targets"].
        }
    }
    aoso_plan_build().
    IF AOSO_PLAN_LAST:HASKEY("targets") { RETURN AOSO_PLAN_LAST["targets"]. }
    RETURN LIST().
}
