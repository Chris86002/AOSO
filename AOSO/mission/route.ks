// AOSO/mission/route.ks
// Solar-system graph + cluster-greedy tour. Jool's moons are one
// interplanetary hop, not five. No brute-force 16! -- nearest remaining
// cluster, then expand the cluster by SMA (inner moons first) with a
// class-aware swap (ISRU hopper does Minmus before Mun).

GLOBAL AOSO_ROUTE_LAST IS LEXICON().

FUNCTION aoso_route_catalog {
    RETURN aoso_matrix_catalog().
}

FUNCTION aoso_route_cluster_planet {
    PARAMETER dest_name.
    RETURN aoso_feas_planet_of(dest_name).
}

FUNCTION aoso_route_members {
    PARAMETER planet_name.
    LOCAL catalog IS aoso_route_catalog().
    LOCAL out IS LIST().
    FOR dest_name IN catalog {
        IF aoso_route_cluster_planet(dest_name) = planet_name {
            out:ADD(dest_name).
        }
    }
    RETURN out.
}

FUNCTION aoso_route_visitable {
    LOCAL catalog IS aoso_route_catalog().
    LOCAL out IS LIST().
    FOR dest_name IN catalog {
        LOCAL scored IS aoso_opp_get(dest_name).
        IF scored["can"] { out:ADD(dest_name). }
    }
    RETURN out.
}

FUNCTION aoso_route_in_list {
    PARAMETER names.
    PARAMETER needle.
    FOR n IN names {
        IF n = needle { RETURN TRUE. }
    }
    RETURN FALSE.
}

FUNCTION aoso_route_without {
    PARAMETER names.
    PARAMETER skip_name.
    LOCAL out IS LIST().
    FOR n IN names {
        IF n <> skip_name { out:ADD(n). }
    }
    RETURN out.
}

FUNCTION aoso_route_intersect {
    PARAMETER names.
    PARAMETER allowed.
    LOCAL out IS LIST().
    FOR n IN names {
        IF aoso_route_in_list(allowed, n) { out:ADD(n). }
    }
    RETURN out.
}

FUNCTION aoso_route_sma {
    PARAMETER dest_name.
    LOCAL entry IS aoso_body_database_get(dest_name).
    IF entry:HASKEY("SMA") { RETURN entry["SMA"]. }
    RETURN 0.
}

FUNCTION aoso_route_pick_min_sma {
    PARAMETER names.
    LOCAL best_i IS 0.
    LOCAL best_sma IS 999999999.
    LOCAL i IS 0.
    UNTIL i >= names:LENGTH {
        LOCAL sma_val IS aoso_route_sma(names[i]).
        IF sma_val < best_sma {
            SET best_sma TO sma_val.
            SET best_i TO i.
        }
        SET i TO i + 1.
    }
    RETURN best_i.
}

FUNCTION aoso_route_expand {
    PARAMETER planet_name.
    PARAMETER allowed.
    LOCAL members IS aoso_route_intersect(aoso_route_members(planet_name), allowed).
    IF members:LENGTH = 0 { RETURN LIST(). }

    LOCAL ordered IS LIST().
    LOCAL rest IS members.

    // Planet itself first when it is a visitable stop (Jool, Eve, Duna).
    IF aoso_route_in_list(rest, planet_name) {
        ordered:ADD(planet_name).
        SET rest TO aoso_route_without(rest, planet_name).
    }

    // Kerbin moons: Minmus first when this class prefers a cheap
    // refuel, or when Minmus is a SHOULD and tanks are already low.
    IF planet_name = "Kerbin" {
        LOCAL put_minmus IS FALSE.
        IF aoso_classify_get("prefer_refuel_first", FALSE) { SET put_minmus TO TRUE. }
        IF aoso_route_in_list(rest, "Minmus") {
            LOCAL scored IS aoso_opp_get("Minmus").
            IF scored["should"] {
                LOCAL fuel_pct IS aoso_resource_pct("LiquidFuel").
                IF fuel_pct < aoso_config_get("TOUR_REFUEL_BELOW_PCT", 60) {
                    SET put_minmus TO TRUE.
                }
            }
        }
        IF put_minmus {
            IF aoso_route_in_list(rest, "Minmus") {
                ordered:ADD("Minmus").
                SET rest TO aoso_route_without(rest, "Minmus").
            }
        }
    }

    UNTIL rest:LENGTH = 0 {
        LOCAL pick_i IS aoso_route_pick_min_sma(rest).
        LOCAL picked IS rest[pick_i].
        ordered:ADD(picked).
        SET rest TO aoso_route_without(rest, picked).
    }
    RETURN ordered.
}

FUNCTION aoso_route_cluster_score {
    PARAMETER planet_name.
    LOCAL best IS 0.
    LOCAL isru_bonus IS 0.
    LOCAL members IS aoso_route_members(planet_name).
    FOR dest_name IN members {
        LOCAL scored IS aoso_opp_get(dest_name).
        IF scored["score"] > best { SET best TO scored["score"]. }
        LOCAL row IS aoso_matrix_get(dest_name).
        IF row["can_refuel"] {
            SET isru_bonus TO aoso_config_get("ROUTE_FUTURE_ISRU", 180).
        }
    }
    RETURN LEXICON("score", best, "isru", isru_bonus).
}

FUNCTION aoso_route_hop_cost {
    PARAMETER from_planet.
    PARAMETER to_planet.
    LOCAL dv_cost IS aoso_feas_transfer_cost(from_planet, to_planet).
    LOCAL win IS aoso_window_evaluate(from_planet, to_planet).
    LOCAL w IS aoso_opp_weights().
    LOCAL trip_days IS win["wait_days"].
    IF win:HASKEY("total_s") { SET trip_days TO win["total_s"] / 21600. }
    LOCAL wait_pen IS trip_days * 12 * w["time"].
    LOCAL eff_pen IS (1 - win["efficiency"]) * 200 * w["window"].
    LOCAL bonus IS aoso_route_cluster_score(to_planet).
    LOCAL score_w IS aoso_config_get("ROUTE_SCORE_WEIGHT", 8).
    RETURN dv_cost + wait_pen + eff_pen - bonus["score"] * score_w - bonus["isru"].
}

FUNCTION aoso_route_unique_planets {
    PARAMETER allowed.
    LOCAL planets IS LIST().
    FOR dest_name IN allowed {
        LOCAL p_name IS aoso_route_cluster_planet(dest_name).
        IF NOT aoso_route_in_list(planets, p_name) { planets:ADD(p_name). }
    }
    RETURN planets.
}

FUNCTION aoso_route_copy_list {
    PARAMETER src.
    LOCAL out IS LIST().
    FOR x IN src { out:ADD(x). }
    RETURN out.
}

FUNCTION aoso_route_beam_trim {
    PARAMETER states.
    PARAMETER width.
    LOCAL pool IS aoso_route_copy_list(states).
    LOCAL out IS LIST().
    UNTIL pool:LENGTH = 0 OR out:LENGTH >= width {
        LOCAL best_i IS 0.
        LOCAL best_cost IS pool[0]["cost"].
        LOCAL i IS 1.
        UNTIL i >= pool:LENGTH {
            IF pool[i]["cost"] < best_cost {
                SET best_cost TO pool[i]["cost"].
                SET best_i TO i.
            }
            SET i TO i + 1.
        }
        out:ADD(pool[best_i]).
        pool:REMOVE(best_i).
    }
    RETURN out.
}

FUNCTION aoso_route_cluster_order {
    PARAMETER start_planet.
    PARAMETER planets.
    IF planets:LENGTH = 0 { RETURN LIST(). }
    LOCAL beam IS LIST().
    beam:ADD(LEXICON("current", start_planet, "remaining", aoso_route_copy_list(planets),
        "order", LIST(), "cost", 0)).
    LOCAL width IS aoso_config_get("ROUTE_BEAM_WIDTH", 10).
    IF width < 1 { SET width TO 1. }

    UNTIL beam[0]["remaining"]:LENGTH = 0 {
        LOCAL next_states IS LIST().
        FOR st IN beam {
            IF st["remaining"]:LENGTH = 0 {
                next_states:ADD(st).
            } ELSE {
                FOR p_name IN st["remaining"] {
                    LOCAL norder IS aoso_route_copy_list(st["order"]).
                    norder:ADD(p_name).
                    LOCAL nrem IS aoso_route_without(st["remaining"], p_name).
                    LOCAL nc IS st["cost"] + aoso_route_hop_cost(st["current"], p_name).
                    next_states:ADD(LEXICON("current", p_name, "remaining", nrem,
                        "order", norder, "cost", nc)).
                }
            }
        }
        SET beam TO aoso_route_beam_trim(next_states, width).
        IF beam:LENGTH = 0 { RETURN LIST(). }
    }
    RETURN beam[0]["order"].
}

FUNCTION aoso_route_build {
    LOCAL allowed IS aoso_route_visitable().
    LOCAL here_name IS SHIP:BODY:NAME.
    LOCAL here_planet IS aoso_feas_planet_of(here_name).

    LOCAL remaining IS allowed.
    IF aoso_route_in_list(remaining, here_name) {
        SET remaining TO aoso_route_without(remaining, here_name).
    }

    LOCAL order IS LIST().
    LOCAL here_members IS aoso_route_expand(here_planet, remaining).
    FOR n IN here_members {
        order:ADD(n).
        SET remaining TO aoso_route_without(remaining, n).
    }

    LOCAL planets IS aoso_route_unique_planets(remaining).
    LOCAL cluster_order IS aoso_route_cluster_order(here_planet, planets).
    FOR p_name IN cluster_order {
        LOCAL expanded IS aoso_route_expand(p_name, remaining).
        FOR n IN expanded {
            order:ADD(n).
            SET remaining TO aoso_route_without(remaining, n).
        }
    }

    SET AOSO_ROUTE_LAST TO LEXICON(
        "order", order,
        "from", here_name,
        "class", aoso_classify_name(),
        "search", "beam",
        "beam_width", aoso_config_get("ROUTE_BEAM_WIDTH", 10),
        "at", TIME:SECONDS
    ).
    aoso_json_write(AOSO_CONST["ROUTE_FILE"], AOSO_ROUTE_LAST).
    RETURN AOSO_ROUTE_LAST.
}

FUNCTION aoso_route_join {
    PARAMETER names.
    LOCAL txt IS "".
    FOR n IN names {
        IF txt <> "" { SET txt TO txt + " -> ". }
        SET txt TO txt + n.
    }
    RETURN txt.
}
