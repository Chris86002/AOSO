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

`mission/project.ks` loads after feasibility, before matrix.

## Files

See `docs/AOSO_DATA_OWNERSHIP.md` for the full table. Short list:

| File | What |
|---|---|
| `0:/aoso_cfg_id.json` | Locked launch configuration |
| `0:/aoso_xp.json` + `archive:/aoso_xp.json` | Experience models + last 40 samples |
| `0:/aoso_learn.json` | Legacy ascent fuel-to-orbit (migrated into XP circ) |
| `0:/aoso_route.json` | Last plan (`schema_version` stamped) |
| `0:/aoso_matrix.json` | Last capability matrix |
| `0:/aoso_checkpoints.json` | Step index/name + context (cfg_id, body, status, topo_fp, tour_index) |
| `0:/aoso_profile.json` | Profile view (rebuilt from topology) |
| `0:/aoso_config.json` | Operator config |

Writes stamp `schema_version` (current 2). Reads migrate a missing key
as v1. Topology / cert / assure / `AOSO_PROJECT_LAST` are RAM-only.

## Event types the brain listens for

`STAGE_COMPLETE`, `VEHICLE_CHANGED`, `PROFILE_UPDATED`,
`CAPABILITY_CHANGED`, `SOI_CHANGED`, `ORBIT_ACHIEVED`, `ASCENT_SUCCESS`,
`REFUEL_SUCCESS`, `LANDING_SUCCESS`, `TAKEOFF_COMPLETE`, `ENGINE_ANOMALY`,
`MANEUVER_FAILED`, `MODEL_UPDATED`, `REPLAN_REQUESTED`,
`CORRECT_REQUESTED`, `HOLD`.

`aoso_result_emit` publishes `action_type_status` (`ASCENT_SUCCESS`,
`MANEUVER_FAILED`, `LANDING_SUCCESS`, `REFUEL_SUCCESS`,
`CAPTURE_SUCCESS`). Large dV errors publish `REPLAN_REQUESTED` or
`CORRECT_REQUESTED`.

Published but not handled by the brain: `PLAN_UPDATED`, `NAV_FALLBACK`,
`CPU_LOAD_HIGH`, `CPU_LOAD_CRITICAL`.

## Replan triggers (debounced `BRAIN_REPLAN_DEBOUNCE_S`)

Orbit achieved, ascent success, SOI change, refuel success, surface
takeoff, engine anomaly, maneuver failed, large prediction error,
watchdog non-critical stall. Tour also calls
`aoso_tour_replan_remaining` after pad ascent **and** after a surface
launch/refuel — it rebuilds remaining targets and sets index 0. It
does **not** also `advance`, which would skip the next body.

`aoso_plan_build` stamps `rev_topo/cap/budget/world/xp` and calls
`aoso_ctx_mark_plan`. `aoso_plan_stale` is topo/budget/world drift.

HIGH CPU while not quiet: request stays queued.

## Prediction consumption

`aoso_feas_evaluate` runs `aoso_project_seq` after XP × margin. Reach,
orbit, land, takeoff, leftover come from sequential remaining, not
independent comparisons against original `mission_dv`. Transfer cost
is split (`xfer_only`) so dest capture is not paid twice.

Opportunity scores still do not decide CAN. They add a 1-hop leftover
bonus (`aoso_project_lookahead_bonus`, else matrix `leftover_dv`).
CAN remains matrix `result <> SKIP`. First plan: `opp_build` runs
before `project_route`, so that pass uses matrix leftover.

## Watchdog

Stalled (no history growth and no heartbeat movement) then:

1. Critical fuel/EC → abort (`aoso_watchdog_trip`).
2. Ascent / descent / landing → do **not** generic-recover.
3. Otherwise throttle 0, drop a bad node, stop ISRU, publish
   `REPLAN_REQUESTED`. A second long stall → `aoso_safe_hold`.

A long porkchop or healthy ISRU harvest is not an abort.

## Surface / ISRU

Tour `REFUEL` calls `aoso_surface_begin` / `aoso_surface_update`. The
tour FSM is not rewritten. Harvest pauses if EC < 8% or the ship
starts sliding. Progress is fuel/ore movement, not tank Ore ≈ 0.
Fill target is takeoff + next `xfer_only+capture` + reserve +
correction. Next ISRU stop caps ~70% unless Eve/Tylo/Moho. Launch
waits for `aoso_depart_certify`.
