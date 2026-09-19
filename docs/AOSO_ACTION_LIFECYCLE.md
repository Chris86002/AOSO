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

Identity must correspond:

```
DECISION 41  TRANSFER Duna  predicted 1080 m/s
ACTION   41  START
ACTION   41  COMPLETE
RESULT   41  actual 1127  error +47  SUCCESS
```

Do not stamp results from the latest global sequence. `aoso_decide`
**returns** the id. `aoso_action_create(id, type, target, predicted_dv)`
builds the lexicon. `aoso_action_begin` sets `AOSO_ACTION_CUR`.
`aoso_result_make` / `aoso_result_from_action` copy that id.
`aoso_result_emit` closes the decision, ingests XP, and clears
`AOSO_ACTION_CUR`.

Never name `GLOBAL AOSO_ACTION` (collides with `FUNCTION aoso_action_*`
if someone adds `aoso_action`). The current object is
`AOSO_ACTION_CUR`.

## Action schema

```
action_id, decision_id, type, target, controller,
predicted_dv, predicted_fuel, predicted_duration, confidence,
start_body, start_mass, start_fuel, started_at,
topology_revision, vehicle_revision, plan_revision
```

Types used as XP ops: `ASCENT`, `CIRCULARIZATION`, `MANEUVER`,
`TRANSFER`, `CAPTURE`, `LANDING`, `TAKEOFF`, `STAGING`, `REFUEL`,
`RETURN`.

## Who starts what

| Action | Where |
|---|---|
| ASCENT / TAKEOFF | `ascent_start` — TAKEOFF if landed off-Kerbin |
| MANEUVER | `maneuver` finish; creates action if `ACTION_CUR` empty |
| TRANSFER | `goto_start` with `xfer_only` (capture not mixed in) |
| CAPTURE | `goto_done` + `aoso_verify_capture(goal)` |
| LANDING | `descent_start`; touchdown verifies srf/vs/tilt |
| REFUEL | `refuel_start`; stow classifies SUCCESS/PARTIAL/FAILED |
| STAGING | `aoso_staging_emit` after `aoso_staging_do` (pred mass vs actual) |

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
`aoso_auth_release_all` on done/abort. `aoso_staging_do` allows
ascent / maneuver / descent / goto / auto_staging (WHO-empty still
bypasses until callers all set identity).

`aoso_steer_release` stays ungated so HOLD can always drop the lock.

## Execution

Existing FSMs fly the ship. The brain never steers.

Warp: controllers should `aoso_warp_deadline_set` then
`aoso_warp_request`. Actual `SET WARP` / `WARPTO` still live in
`aoso_warp_approach`. Many controllers still `SET WARP TO 0` as a
hard stop (proven, not aesthetic purity). Maneuver registers the
node UT so a long rails coast cannot skip ignition.

## Postconditions — `core/verify.ks`

| Action | Verifier | Success means |
|---|---|---|
| Ascent / takeoff | `aoso_verify_ascent` / `takeoff` | Bound orbit, PE above atmo/floor |
| Maneuver | `aoso_verify_maneuver` | Burn result not missed/incomplete/no-thrust |
| Transfer | `aoso_verify_transfer` | In goal SOI or a live patch; `patch_body`, periapsis, encounter ETA |
| Capture | `aoso_verify_capture(expect_body)` | Correct body, bound, PE safe |
| Landing | `aoso_verify_landing` | LANDED/SPLASHED, not sliding, not falling, tilt ≤ 55° |
| Refuel | classify start/end/target | SUCCESS / PARTIAL / FAILED / ABORTED |

Statuses: `SUCCESS` / `PARTIAL` / `FAILED` / `ABORTED`.

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
must change the next feasibility cost (`aoso_xp_apply`). REFUEL uses
fuel-pct, not a dV model. STAGING uses predicted vs actual mass
(stored in the dV fields).
