# AOSO v2 data flow

## Boot order (after all `RUN ONCE`)

1. `aoso_profile_refresh("boot")` — vessel snapshot + dV.
2. `aoso_brain_init()` — empty context + event queue.
3. `aoso_cfg_id_lock()` — pad mint or restore.
4. `aoso_xp_load()` — models keyed by that cfg id.

## Files

| File | What |
|---|---|
| `0:/aoso_cfg_id.json` | Locked launch configuration |
| `0:/aoso_xp.json` + `archive:/aoso_xp.json` | Experience models + last 40 samples |
| `0:/aoso_learn.json` | Legacy ascent fuel-to-orbit (migrated into XP circ) |
| `0:/aoso_route.json` | Last plan |
| `0:/aoso_matrix.json` | Last capability matrix |

## Event types the brain listens for

`STAGE_COMPLETE`, `VEHICLE_CHANGED`, `PROFILE_UPDATED`,
`CAPABILITY_CHANGED`, `SOI_CHANGED`, `ORBIT_ACHIEVED`, `ASCENT_SUCCESS`,
`REFUEL_SUCCESS`, `LANDING_SUCCESS`, `TAKEOFF_COMPLETE`, `ENGINE_ANOMALY`,
`MANEUVER_FAILED`, `MODEL_UPDATED`, `REPLAN_REQUESTED`, `PLAN_UPDATED`.

`aoso_result_emit` publishes `action_type_status` (`ASCENT_SUCCESS`,
`MANEUVER_FAILED`, `LANDING_SUCCESS`, `REFUEL_SUCCESS`).

## Replan triggers (debounced `BRAIN_REPLAN_DEBOUNCE_S`)

Orbit achieved, ascent success, SOI change, refuel success, surface
takeoff, engine anomaly, maneuver failed. Tour also calls
`aoso_tour_replan_remaining` after pad ascent **and** after a surface
launch/refuel — it rebuilds remaining targets and sets index 0. It does
**not** also `advance`, which would skip the next body.

## Prediction consumption

`aoso_feas_evaluate` multiplies transfer / capture / land / takeoff
analytical costs by `aoso_xp_apply` **before** the dV margin. Correction
is clamped to `1 ± XP_MAX_CORRECTION` and ignored until
`XP_MIN_SAMPLES`.

Opportunity scores still do not decide CAN. They discount cluster hop
cost (`ROUTE_SCORE_WEIGHT`) and ISRU stops get `ROUTE_FUTURE_ISRU`.
CAN remains matrix `result <> SKIP`.

## Watchdog

Stalls if **both**:

1. No mission/tour history change for `WATCHDOG_TIMEOUT` **and** no
   controller heartbeat movement for `WATCHDOG_PROGRESS_S`.
2. Fuel or EC is actually critical.

A long porkchop or ISRU harvest with healthy tanks is not an abort.
