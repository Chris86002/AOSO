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

    // Kerbin moons: ISRU/hopper prefers Minmus first (cheap refuel).
    IF planet_name = "Kerbin" {
        IF aoso_classify_get("prefer_refuel_first", FALSE) {
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

FUNCTION aoso_route_hop_cost {
    PARAMETER from_planet.
    PARAMETER to_planet.
    LOCAL dv_cost IS aoso_feas_transfer_cost(from_planet, to_planet).
    LOCAL win IS aoso_window_evaluate(from_planet, to_planet).
    LOCAL w IS aoso_opp_weights().
    LOCAL wait_pen IS win["wait_days"] * 25 * w["time"].
    LOCAL eff_pen IS (1 - win["efficiency"]) * 200 * w["window"].
    RETURN dv_cost + wait_pen + eff_pen.
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

    LOCAL current_planet IS here_planet.
    UNTIL remaining:LENGTH = 0 {
        LOCAL planets IS aoso_route_unique_planets(remaining).
        LOCAL best_planet IS planets[0].
        LOCAL best_cost IS 999999.
        FOR p_name IN planets {
            LOCAL c IS aoso_route_hop_cost(current_planet, p_name).
            IF c < best_cost {
                SET best_cost TO c.
                SET best_planet TO p_name.
            }
        }
        LOCAL expanded IS aoso_route_expand(best_planet, remaining).
        IF expanded:LENGTH = 0 {
            SET remaining TO aoso_route_without(remaining, remaining[0]).
        } ELSE {
            FOR n IN expanded {
                order:ADD(n).
                SET remaining TO aoso_route_without(remaining, n).
            }
            SET current_planet TO best_planet.
        }
    }

    SET AOSO_ROUTE_LAST TO LEXICON(
        "order", order,
        "from", here_name,
        "class", aoso_classify_name(),
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
