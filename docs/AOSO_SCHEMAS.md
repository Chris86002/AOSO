# AOSO v2 schemas

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

`status`: `SUCCESS` | `FAILED` | `ABORTED`. Emit via `aoso_result_emit`
(ingests XP when predicted > 0, publishes `TYPE_STATUS`).

`action_type` values used as XP ops: `ASCENT`, `CIRCULARIZATION`,
`MANEUVER`, `TRANSFER`, `CAPTURE`, `LANDING`, `TAKEOFF`, `STAGING`,
`REFUEL`, `RETURN`.

## Open decision (`aoso_decide_open`)

```
id, type, decision, selected, reason, predicted, created_at
```

`aoso_decide` (5 args) still logs CSV; it also opens a decision when
`AOSO_DECIDE_OPEN` exists.

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
rev_vehicle, rev_cap, rev_budget, rev_world, rev_plan, rev_xp,
dirty_vehicle, dirty_cap, dirty_budget, dirty_feas,
dirty_opp, dirty_route, dirty_plan
```

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

`NAME|M{floor(mass/5)*5}|E{engines}|S{stages}|LF{lf_cap}|ISRU{n}|D{dock}`
