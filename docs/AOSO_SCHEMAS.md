# AOSO v2.2 schemas

Lexicons only. No nested callbacks.

## Event

```
id, type, source, data, ut
```

Queue cap 32, drain 4 per brain tick. `data` is a string.

## Action result (`aoso_result_make`)

```
action_id, action_type, status, reason,
started_at, completed_at, duration,
start_body, end_body,
predicted_dv, actual_dv, dv_error,
predicted_fuel, actual_fuel, fuel_used,
confidence, anomalies
```

`status`: `SUCCESS` | `PARTIAL` | `FAILED` | `ABORTED`. Emit via
`aoso_result_emit` (ingests XP when predicted > 0, publishes
`TYPE_STATUS`, and may publish `CORRECT_REQUESTED` /
`REPLAN_REQUESTED` from `|dv_error|`).

`action_type` values used as XP ops: `ASCENT`, `CIRCULARIZATION`,
`MANEUVER`, `TRANSFER`, `CAPTURE`, `LANDING`, `TAKEOFF`, `STAGING`,
`REFUEL`, `RETURN`.

## Verify (`aoso_verify_*`)

```
ok, reason, status   // SUCCESS | PARTIAL | FAILED
```

Apply with `aoso_verify_apply_result(res, v)` before emit.

## Open decision (`aoso_decide_open`)

```
id, type, decision, selected, reason, predicted, created_at
```

`aoso_decide` (5 args) still logs CSV; it also opens a decision when
`AOSO_OPEN_DECISIONS` exists.

## Heartbeat (`aoso_hb_set`)

```
controller, state, progress, progress_at
```

`progress_at` advances only when `state` changes or `|Δprogress| > 0.015`.

## Context (`AOSO_CTX`)

```
cfg_id, class, mass, body, situation, fuel_pct, ec_pct,
mission_dv, total_dv, goal, target, action, controller,
progress, progress_at, quiet, confidence,
rev_vehicle, rev_cap, rev_budget, rev_world, rev_plan, rev_xp, rev_topo,
dirty_vehicle, dirty_cap, dirty_budget, dirty_feas,
dirty_opp, dirty_route, dirty_plan, dirty_topo
```

## Topology (`AOSO_TOPO`)

```
fp, rev, dyn_rev, part_n, engine_n, dock_n, stage, max_depth,
hw, layers, landing, isru, control, next_stage, mass, thrust, scanned_at
```

`hw`: solar, generator, fuelcell, wheels, heatshield, science, kos,
lifting, chute, legs, drill, converter, radiator, antenna, cargo,
fairing, decoupler, rcs, rwheel, tanks, intakes, nuke, ion.

## Certification (`AOSO_CERT_LAST`)

```
status, mission, hard_blockers, warnings, uncertainties,
ability, confidence, at
```

`status`: `CERTIFIED` | `CONDITIONAL` | `NOT_CERTIFIED`

## Assurance (`AOSO_ASSURE_LAST`)

```
health, cert, mission_dv, fuel_pct, weak_body, weak_margin,
can_return, at
```

`health`: `OK` | `TIGHT` | `AT_RISK` | `BLOCKED` | `FUEL`

Depart: `status` `READY` | `READY_WITH_WARNING` | `NOT_READY`.

## Checkpoint

```
step_index, step_name, data, saved_at
```

`data` includes `cfg_id, body, status, topo_fp, tour_index`.

## Experience model

Key: `cfg_id|body|OP`

```
n, sum_ratio, mean_ratio, best, worst, corr, conf
```

`corr = 1 + (mean_ratio-1) * n/(n+XP_MIN_SAMPLES)`, then clamped to
`1 ± XP_MAX_CORRECTION`.

## Feasibility report (added)

```
continuation: SAFE | LOW | DEAD_END
leftover_dv
```

`DEAD_END` demotes `result` from `FEASIBLE` to `ORBIT_ONLY`.

## Configuration id

Locked on the pad: `NAME|M{bucket}|E{engines}|S{stages}|LF{cap}|ISRU{n}|D{docks}`.
Persisted `0:/aoso_cfg_id.json`.
