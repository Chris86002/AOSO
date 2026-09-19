# AOSO v2.2 data flow

## Boot order (after all `RUN ONCE`)

1. Raise `CONFIG:IPU` to `IPU_TARGET` (2000).
2. `aoso_profile_refresh("boot")` — topology rebuild + dV.
3. `aoso_brain_init()` — empty context + event queue; copy `rev_topo`.
4. `aoso_cfg_id_lock()` — pad mint or restore.
5. `aoso_xp_load()` — models keyed by that cfg id.
6. `aoso_checkpoints_load()` — compare expected body/status/topo_fp
   against the live ship, then re-certify if the fingerprint moved.
7. `aoso_cert_eval("grand_tour")` + `aoso_assure_eval()`.

## Files

See `docs/AOSO_DATA_OWNERSHIP.md` for the full table. Short list:

| File | What |
|---|---|
| `0:/aoso_cfg_id.json` | Locked launch configuration |
| `0:/aoso_xp.json` + `archive:/aoso_xp.json` | Experience models + last 40 samples |
| `0:/aoso_learn.json` | Legacy ascent fuel-to-orbit (migrated into XP circ) |
| `0:/aoso_route.json` | Last plan |
| `0:/aoso_matrix.json` | Last capability matrix |
| `0:/aoso_checkpoints.json` | Step index/name + context (cfg_id, body, status, topo_fp, tour_index) |
| `0:/aoso_profile.json` | Profile view (rebuilt from topology) |

Topology / cert / assure are RAM-only.

## Event types the brain listens for

`STAGE_COMPLETE`, `VEHICLE_CHANGED`, `PROFILE_UPDATED`,
`CAPABILITY_CHANGED`, `SOI_CHANGED`, `ORBIT_ACHIEVED`, `ASCENT_SUCCESS`,
`REFUEL_SUCCESS`, `LANDING_SUCCESS`, `TAKEOFF_COMPLETE`, `ENGINE_ANOMALY`,
`MANEUVER_FAILED`, `MODEL_UPDATED`, `REPLAN_REQUESTED`,
`CORRECT_REQUESTED`, `HOLD`.

`aoso_result_emit` publishes `action_type_status` (`ASCENT_SUCCESS`,
`MANEUVER_FAILED`, `LANDING_SUCCESS`, `REFUEL_SUCCESS`). Large dV
errors publish `REPLAN_REQUESTED` or `CORRECT_REQUESTED`.

Published but not handled by the brain: `PLAN_UPDATED`, `NAV_FALLBACK`,
`CPU_LOAD_HIGH`, `CPU_LOAD_CRITICAL`.

## Replan triggers (debounced `BRAIN_REPLAN_DEBOUNCE_S`)

Orbit achieved, ascent success, SOI change, refuel success, surface
takeoff, engine anomaly, maneuver failed, large prediction error. Tour
also calls `aoso_tour_replan_remaining` after pad ascent **and** after a
surface launch/refuel — it rebuilds remaining targets and sets index 0.
It does **not** also `advance`, which would skip the next body.

HIGH CPU while not quiet: request stays queued.

## Prediction consumption

`aoso_feas_evaluate` multiplies transfer / capture / land / takeoff
analytical costs by `aoso_xp_apply` **before** the dV margin. Correction
is `1 + (mean_ratio-1) * n/(n+XP_MIN_SAMPLES)`, then clamped to
`1 ± XP_MAX_CORRECTION`. Small n ⇒ small influence; it is not ignored
until min samples.

Opportunity scores still do not decide CAN. They discount cluster hop
cost (`ROUTE_SCORE_WEIGHT`) and ISRU stops get `ROUTE_FUTURE_ISRU`.
CAN remains matrix `result <> SKIP`.

## Watchdog

Stalls if **both**:

1. No mission/tour history change for `WATCHDOG_TIMEOUT` **and** no
   controller heartbeat movement for `WATCHDOG_PROGRESS_S`.
2. Fuel or EC is actually critical.

A long porkchop or ISRU harvest with healthy tanks is not an abort.

## Surface / ISRU

Tour waits for `aoso_surface_stable` before `aoso_refuel_start`.
Harvest pauses if EC < 8% or the ship starts sliding. Fill target is
`aoso_refuel_needed_pct()` (takeoff + next hop + reserve), not always
95%. Launch waits for `aoso_depart_certify`.
