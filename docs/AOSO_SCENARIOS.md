# Manual regression scenarios

kOS cannot drive KSP from this repository. These are repeatable flights
the operator runs in stock KSP + kOS. After each, keep the kOS log,
`0:/aoso_events.csv`, HUD snapshot, and (if it exists) `aoso_xp.json`.

Self-test (`run "AOSO/dev/selftest".`) covers the synthetic cases
without touching the ship. It must not STAGE, LOCK, WARP, or THROTTLE.

Work on `main`. `Watch-AOSO` tracks it.

## Scenario 1 — Kerbin ascent

Pad craft with working boosters + core. Boot AOSO, wait for
`aoso_depart_certify` READY, launch.

Expect:

- Gravity turn, no lofted mismatch abort in the STAGE() tick.
- Navball heading stays near 90 east, not spinning 345→270→178.
- Pitch stays above ~45° at 16 km on a TWR~1.4 hopper (not riding
  +7° AoA with AP-hold throttle in dense air).
- Boosters drop only when that group's MASSFLOW is ~0 (no hot-sep).
- Bound parking, `ASCENT` result with `predicted_dv > 0` ingested.
- Circularize node actually burns (log has `Burn started` / `Node executed`, not a wall of `AUTH maneuver denied STEERING`).
- `verify_ascent` SUCCESS (bound, PE above atmo).

## Scenario 2 — Kerbin → Mun orbit

From LKO, tour or `aoso_goto_start("Mun")`.

Expect:

- TRANSFER action at goto start uses `xfer_only` (capture not mixed in).
- Patch to Mun, SOI emit TRANSFER with `patch_body` / periapsis / ETA.
- Mid-course (if PE is a graze) lights; log has `Burn started`, not
  `Never aligned in time` after `Holding 1x eta=-360`.
- Capture burn, then CAPTURE result via `aoso_verify_capture("Mun")`.
- `result = FEASIBLE` or `ORBIT_ONLY` matches leftover after capture,
  not `mission_dv >= capture` against the original budget.

## Scenario 3 — Mun landing and takeoff

Land, then depart.

Expect:

- LANDING action at descent start; touchdown runs `aoso_verify_landing`
  (status, srf, vs, tilt).
- Surface executive: HOLD until stable; skip ISRU if no ore / no need.
- `aoso_depart_certify` NOT_READY if LANDER TWR < 1.05, no propulsion,
  fuel < 8%, takeoff_dv > mission_dv, or still moving.
- TAKEOFF (not ASCENT) result on a non-Kerbin surface launch;
  `aoso_verify_takeoff`.

## Scenario 4 — Minmus landing + ISRU + takeoff

Expect:

- Fill target from `aoso_refuel_needed_pct` (takeoff + next xfer_only
  + capture + reserve + correction). Next ISRU stop caps ~70% unless
  Eve/Tylo/Moho.
- Tank Ore near zero is **not** biome-empty. Harvest stalls only after
  `REFUEL_STALL_S` with no fuel/ore movement.
- STOW emits SUCCESS / PARTIAL / FAILED from start vs end vs target.
  Abort emits ABORTED.

## Scenario 5 — Duna transfer and capture

Expect:

- Sequential leftover after transfer then capture in the feas report
  (`dv_after_transfer`, `dv_after_capture`, `xfer_only_dv`).
- Capture result is a distinct CAPTURE action, not a second TRANSFER.

## Scenario 6 — Tylo feasibility analysis

A lander whose LANDER-group TWR on Tylo is < 1.4, or whose sequential
land cost exceeds leftover after capture.

Expect:

- Matrix `ORBIT_ONLY` or SKIP, not FEASIBLE.
- Selftest `tylo land not sequential` (`seq 2000/800/400/2270` → no land).
- Cert warning on Tylo LANDER TWR / projected route fail. Grand-tour
  membership is still planner CAN, not a hard cert block.

## Scenario 7 — Intentionally insufficient fuel

Start a hop with ~500 m/s against a 3000+3000 path.

Expect:

- `can_reach` false, result SKIP.
- Continuation DEAD_END if a landing would leave no takeoff/return.
- Do not treat `mission_dv >= capture` as `can_orbit`.

## Scenario 8 — Staging topology change

Drop boosters in flight.

Expect:

- `AOSO_TOPO.rev` increments (fingerprint moved).
- Fuel-only drain: `rev` unchanged, `dyn_rev` increments
  (`aoso_topo_refresh_dynamic`).
- STAGING action records predicted mass vs actual mass.
- `aoso_plan_stale` true after topo/budget/world rev drift.

## Scenario 9 — Reload in orbit

Revert / reboot in Mun orbit with a saved checkpoint.

Expect:

- `cfg_id` restored from `0:/aoso_cfg_id.json` (not a new name).
- Topology rebuilt from the live ship; checkpoint `topo_fp` compared.
- Persistent files with missing `schema_version` migrate as v1.
- Prefer observed body/status over the saved expectation.

## Scenario 10 — Refuel interruption / EC starvation

Start Minmus ISRU, retract panels or wait until EC < 8%.

Expect:

- Harvest pauses (drills/ISRU off), heartbeat `EC_WAIT`.
- Does not emit SUCCESS on empty Ore tank.
- Watchdog: stall **without** critical fuel/EC → REPLAN / HOLD, not
  abort. Stall **during** ascent/descent → no generic recover.
  Stall **plus** critical resources → abort.

## Synthetic self-test (always)

`run "AOSO/dev/selftest".` after a normal boot (or it RUN ONCEs what it
needs):

| Case | Expect |
|---|---|
| `proj reach/capture/land` 5000/3000/1500/1000 | reach yes, orbit yes, land no |
| `xfer_only 3000-1500` | 1500 |
| two actions, complete first | result id is id1, not latest seq |
| ISRU classify 20→55 target 70 | PARTIAL |
| watchdog stall / critical / flying | REPLAN / ABORT / NONE |
| schema version | 2; missing key migrates as v1 |
| XP 1000 vs 1100 ×3 | corr > 1 and ≤ 1.35 |
| Tylo seq land | can_land false |
| topo dyn refresh | struct `rev` unchanged, `dyn_rev` up |
| warp rails 20s vs 50s lead | want 0 |
| warp rails 11 h respects max factor | ≤ 6 |
| steer pitch 90 near up | VANG < 8 |
