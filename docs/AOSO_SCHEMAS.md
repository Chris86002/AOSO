# AOSO v2.2 schemas

Lexicons only. No nested callbacks.

Persistent files stamp `schema_version`. Current
`AOSO_CONST["SCHEMA_VERSION"]` is **2**. A missing key on read is
treated as v1 (`aoso_json_migrate`). Unrecognized versions still load;
do not invent a giant migrator.

## Event

```
id, type, source, data, ut
```

Queue cap 32, drain 4 per brain tick. `data` is a string.

## Action (`aoso_action_create`)

```
action_id, decision_id, type, target, controller,
predicted_dv, predicted_fuel, predicted_duration, confidence,
start_body, start_mass, start_fuel, started_at,
topology_revision, vehicle_revision, plan_revision
```

Current action: `AOSO_ACTION_CUR` (0 or lexicon). Never `GLOBAL AOSO_ACTION`.

## Action result (`aoso_result_make`)

```
action_id, decision_id, action_type, status, reason,
started_at, completed_at, duration,
start_body, end_body,
predicted_dv, actual_dv, dv_error,
predicted_fuel, actual_fuel, fuel_used,
confidence, anomalies
```

`status`: `SUCCESS` | `PARTIAL` | `FAILED` | `ABORTED`. Emit via
`aoso_result_emit` (ingests XP when predicted > 0, publishes
`TYPE_STATUS`, and may publish `CORRECT_REQUESTED` /
`REPLAN_REQUESTED` from `|dv_error|`). Clears `AOSO_ACTION_CUR`.

`action_type` values used as XP ops: `ASCENT`, `CIRCULARIZATION`,
`MANEUVER`, `TRANSFER`, `CAPTURE`, `LANDING`, `TAKEOFF`, `STAGING`,
`REFUEL`, `RETURN`.

## Verify (`aoso_verify_*`)

```
ok, reason, status   // SUCCESS | PARTIAL | FAILED
```

Transfer also: `patch_body`, `periapsis`, `encounter_eta`.
Capture takes optional `expect_body`.
Landing reason includes vs / srf / tilt.

Apply with `aoso_verify_apply_result(res, v)` before emit.

## Open decision (`aoso_decide_open`)

```
id, type, decision, selected, reason, predicted, created_at
```

`aoso_decide` (optional 6th `predicted`) logs CSV and **returns** the
id when `AOSO_OPEN_DECISIONS` exists.

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
plan_n, plan_next, plan_from, plan_provisional,
dirty_vehicle, dirty_cap, dirty_budget, dirty_feas,
dirty_opp, dirty_route, dirty_plan, dirty_topo
```

## Topology (`AOSO_TOPO`)

```
fp, rev, dyn_rev, part_n, engine_n, dock_n, stage, max_depth,
hw, layers, prop, landing, isru, control, next_stage, mass, thrust, scanned_at
```

`hw`: solar, generator, fuelcell, wheels, heatshield, science, kos,
lifting, chute, legs, drill, converter, radiator, antenna, cargo,
fairing, decoupler, rcs, rwheel, tanks, intakes, nuke, ion.

`prop[]`: `id, stage, role, engines, dry_mass, current_mass, lf, ox`.
`role`: BOOSTER | STAGE | CORE | LANDER.

## Projected state

```
body, situation, mass, fuel_mass, fuel_pct,
dv_remaining, reserve_remaining,
topology_revision, configuration_id,
refueled, landed, orbiting,
ok, fail_step, last_step, last_cost, confidence
```

`aoso_project_seq` result:

```
can_reach, can_orbit, can_land, can_takeoff,
leftover, fail_step, dv_after_transfer, dv_after_capture
```

`AOSO_PROJECT_LAST`:

```
order, legs{ dest → have_in, leftover_out, margin, ok, fail_step, refueled },
weakest, min_margin, min_twr, next_refuel, ok, end_dv, end_body, at
```

## Plan (`AOSO_PLAN_LAST`)

```
targets, skipped, orbit_only, class, mode, from,
mission_dv, full_tank_dv, isru, provisional,
rev, rev_topo, rev_cap, rev_budget, rev_world, rev_xp,
built_at, at, schema_version
```

`aoso_plan_stale`: `rev_topo` / `rev_budget` / `rev_world` drifted.

## Certification (`AOSO_CERT_LAST`)

```
status, mission, hard_blockers, warnings, uncertainties,
ability, confidence, weakest, min_margin, at
```

`status`: `CERTIFIED` | `CONDITIONAL` | `NOT_CERTIFIED`

## Assurance (`AOSO_ASSURE_LAST`)

```
health, cert, mission_dv, fuel_pct, weak_body, weak_margin,
min_twr_margin, next_refuel, return_margin, can_return,
confidence, at
```

`health`: `OK` | `TIGHT` | `AT_RISK` | `BLOCKED` | `FUEL`

Depart: `status` `READY` | `READY_WITH_WARNING` | `NOT_READY`.

## Surface (`AOSO_SURFACE_LAST`)

```
phase, reason     // NONE | HOLD | REFUEL | LAUNCH
```

## Checkpoint

```
step_index, step_name, data, saved_at, schema_version
```

`data` includes `cfg_id, body, status, topo_fp, tour_index`.

## Experience model

Key: `cfg_id|body|OP`

```
n, sum_ratio, mean_ratio, best, worst, corr, conf
```

`corr = 1 + (mean_ratio-1) * n/(n+XP_MIN_SAMPLES)`, then clamped to
`1 ± XP_MAX_CORRECTION`.

## Feasibility report

```
result: FEASIBLE | ORBIT_ONLY | SKIP
continuation: SAFE | LOW | DEAD_END
leftover_dv, xfer_only_dv, dv_after_transfer, dv_after_capture
hop_budget, surface_twr, steps[]
```

`DEAD_END` demotes `result` from `FEASIBLE` to `ORBIT_ONLY`.

## Configuration id

Locked on the pad: `NAME|M{bucket}|E{engines}|S{stages}|LF{cap}|ISRU{n}|D{docks}`.
Persisted `0:/aoso_cfg_id.json`. Staging in flight does not mint a new id.
