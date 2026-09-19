# Action lifecycle

An action is successful **only** when its postconditions have been
independently verified. A controller finishing is not success.

```
PLAN → DECISION → ACTION
  → PRECONDITION
  → AUTHORITY ACQUISITION
  → EXECUTION
  → POSTCONDITION VERIFICATION
  → RESULT
  → LEARNING
  → RE-CERTIFY / REPLAN if needed
```

## Preconditions

Examples the machines already enforce:

- Ascent: pad / surface, TWR via depart cert on tour launch
- ISRU: landed, `aoso_surface_stable`, drills+converter present
- Maneuver: a live node, thrust available
- Descent: a deorbit that actually reaches suicide altitude

If a precondition fails, do not start. Hold or replan.

## Authority

Resources: `STEERING`, `THROTTLE`, `STAGING`, `WARP`, `RCS`, `SAS`,
`TARGETING`.

A named controller calls `aoso_auth_use(who)` then
`aoso_auth_acquire(who, resource, prio)`. Empty owner = anyone
(backward compatible). Higher prio preempts; equal prio is denied.

Ascent (prio 3), maneuver (3), descent (4) acquire on start and
`aoso_auth_release_all` on done/abort. Tracking locks
(`prograde` / `srf_retro` / `up`) now honor `aoso_auth_can_cmd`.
`aoso_steer_release` stays ungated so HOLD can always drop the lock.

## Execution

Existing FSMs fly the ship. The brain never steers.

Warp: controllers should `aoso_warp_deadline_set` then
`aoso_warp_request`. Actual `SET WARP` / `WARPTO` still live in
`aoso_warp_approach`. Maneuver registers the node UT so a long rails
coast cannot skip ignition.

## Postconditions — `core/verify.ks`

| Action | Verifier | Success means |
|---|---|---|
| Ascent / takeoff | `aoso_verify_ascent` | Bound orbit, PE above atmo/floor |
| Maneuver | `aoso_verify_maneuver` | Burn result not missed/incomplete/no-thrust |
| Transfer | `aoso_verify_transfer` | In goal SOI or a live patch to it |
| Capture | `aoso_verify_capture` | Bound, PE safe |
| Landing | `aoso_verify_landing` | LANDED/SPLASHED, not sliding, not falling |

Statuses: `SUCCESS` / `PARTIAL` / `FAILED`.

`aoso_verify_apply_result` copies that onto the action result before
`aoso_result_emit`.

## Local correction vs strategic replan

| Residual | Action |
|---|---|
| `≥ CORRECT_LOCAL_DV` (25 m/s) and `< REPLAN_DV_ERROR` | `CORRECT_REQUESTED` — mid-course, not a new tour |
| `≥ REPLAN_DV_ERROR` (250 m/s) | `REPLAN_REQUESTED` — brain rebuilds when quiet |

Tiny errors are normal. Do not replan a 7 m/s leftover.

## Navigation fallback

Porkchop is preferred. Zero hits → log `NAV_FALLBACK` → Astrogator
seed → Hohmann windows. Each step is explainable in the log.

## Learning

`aoso_result_emit` still ingests XP when predicted dV > 0. Learning
must change the next feasibility cost (`aoso_xp_apply`).
