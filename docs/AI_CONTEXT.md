# AI context — AOSO / kOS

Read this before changing AOSO. The user cannot run a shell in KSP;
they watch the kOS terminal and the log files.

## Non-negotiable kOS rules

- **No AND/OR short-circuit.** Both sides always run. Nest `IF` when a
  suffix might be missing (`IF HASNODE { IF NEXTNODE:ETA < x { } }`).
- **`DEFINED` is for variables, not functions.** `DEFINED aoso_plan_build`
  is invalid. Check `DEFINED AOSO_PLAN_LAST`. kOS allows only one unary
  prefix, so `IF NOT DEFINED x` is a parse error — nest `IF DEFINED x { … }`.
- **Identifiers are case-insensitive.** A `FUNCTION aoso_const` collides
  with `GLOBAL AOSO_CONST`. Never name a local `path`, `obt`, `note`,
  `alt`, `r`, `v`, `q`, or `status` (builtins). Never pair
  `FUNCTION aoso_foo` with `GLOBAL AOSO_FOO` — kOS fails at compile with
  `Cannot find label …'0-default`.
- **No nested callbacks / deep transition stacks.** Entry handlers must
  not call `aoso_state_transition` in a way that runs the next entry on
  the same stack. Events must queue-then-drain.
- **`LOCK STEERING` blocks `WARPTO`.** Release steering before rails.
  `WAIT 0` under rails jumps UT and cancels `WARPTO`; long coasts use
  `SET WARP`.
- Preserve public function names. Do not rewrite FSMs from scratch.

## Architectural invariants

- The topology model is the authoritative source of vessel structure.
  No subsystem performs a full structural vessel scan unless it owns
  topology. Fuel drain uses `aoso_topo_refresh_dynamic` (`dyn_rev`);
  do not rebuild structure for mass/fuel. Do not name
  `FUNCTION aoso_project` or `FUNCTION aoso_surface` (globals
  `AOSO_PROJECT_LAST` / `AOSO_SURFACE_LAST`). Use `AOSO_ACTION_CUR`,
  never `GLOBAL AOSO_ACTION`.
- Capabilities are derived from topology and dynamic state. Profile is
  a summary/view, not an independent structural truth. Future TWR
  (Tylo/Eve lander) uses `aoso_caps_surface_twr_for_config("LANDER")`,
  not pad all-engine TWR.
- Pad / PRELAUNCH departure cert uses ALL-engine TWR
  (`aoso_caps_surface_twr_for_config("ALL")`). LANDED takeoff uses
  LANDER-config. Never score a Kerbin pad launch as LANDER TWR.
- Mission costs are sequential leftover from `mission/project.ks`, not
  independent comparisons of every cost to the original hop budget.
  Capture is split out of transfer (`aoso_project_xfer_only`).
- Staging uses topology prediction, then `aoso_staging_do` (authority).
- Controllers do not define strategic objectives. They must own
  authority before commanding flight controls.
- An action is not successful until its postconditions are verified.
  `aoso_decide` returns an id; `aoso_action_create` / `begin` bind
  results to that id, not the latest sequence number.
- Trajectory corrections are normal actions, not necessarily mission
  failures. `CORRECT_LOCAL_DV` vs `REPLAN_DV_ERROR`.
- Mission strategy is re-certified after meaningful spacecraft changes.
  `aoso_plan_stale` is topo/budget/world rev drift.
- Surface takeoff requires departure certification. Hard inability
  (TWR, takeoff_dv, sliding, fuel) is `NOT_READY`. Unlit pad engines
  are not `no propulsion` — `AVAILABLETHRUST` is 0 until ignition.
- Persistent files stamp `schema_version` (current 2). Missing key
  migrates as v1. Do not add required keys without a loader migrate.
- One authoritative body knowledge source (`bodydb` + `world/body`).
- Duplicate calculations should be removed after migration.
- Prefer real observed state over saved expectations after restart.
- When uncertain, enter a safe evaluative state instead of continuing
  blindly (`aoso_safe_hold`). Watchdog stall without critical
  fuel/EC requests REPLAN (not during ascent/descent); critical +
  stall still aborts.
- `CONFIG:IPU` defaults to 2000. That is headroom, not a target
  utilization. Critical flight always outranks UI and strategy.
- Background work stops before the protected opcode reserve.
- Full topology scans are event-driven. Replan may wait for a quiet
  window. Telemetry must never starve flight control. Do not
  `aoso_project_route` / matrix rebuild / JSON persist in a critical
  flight tick.
  Rails warp UT jumps are not IPU spills — do not mark CPU HIGH/CRITICAL
  from `TIME:SECONDS` stepping under RAILS.
- Ascent AoA is tight nose-up. Extra nose-down applies only when
  `loft_flagged` (FPA still steep at altitude). Do not treat the
  pitchover program gap as loft — that flattens a low-TWR stack into
  dense air. Keep TWR-capped throttle in dense air (below
  `ASCENT_DENSE_ALT`); the 45 s AP-hold is for the thin upper air.
  Circularize must `aoso_ascent_yield_burn` so maneuver can take
  STEERING/THROTTLE (equal prio cannot preempt). Gravity-turn steering
  is LOOKDIRUP(look, current top) with ROLLCONTROLANGLERANGE=1 (no
  roll-upright hunt). Stock steering is restored before the circ node.
  Coast must not lock the launch heading inside the unpack window —
  that yawed through prograde at physics 2x and the node was missed.
  Align is physics 1x. Maneuver locks `NEXTNODE:BURNVECTOR` only.
  Do not judge THRUST_MISMATCH in the same tick as `STAGE()`.
- Rails coasts use SET WARP only (WARPTO dies on WAIT 0). Step down
  via `aoso_warp_rails_want` and `MAX_WARP_FACTOR`. Mid-course nodes
  sit minutes out, not hours. A missed correction decrements
  `correct_count` and replans immediately — there is no next pass on
  a transfer.
- Tank Ore near zero is not biome-empty. ISRU progress is fuel/ore
  movement; stall is `REFUEL_STALL_S`. STOW is SUCCESS / PARTIAL /
  FAILED / ABORTED.
- `learn.ks` is a leftover-LF diary. Operational correction is
  `experience.ks`. Ascent start-speed search is `ascent_opt.ks`.

## Think windows

Sit on the pad, on the surface, or in a bound orbit, then take the time
the math needs. Do not porkchop during ascent, atmosphere, or a burn.
`aoso_brain_wait_think` is the gate. Pad and landed **are** valid think
windows — calculate before launch when the plan needs it.
`aoso_brain_think_ok` also refuses `AOSO_CPU_LEVEL >= 3`. Replan at
HIGH (2) waits until quiet.

## Learning must change behavior

XP corrections feed `aoso_feas_evaluate` costs. Logging-only stats in
`learn.ks` are not enough. Clamp every correction. Do not let one bad
burn zero a cost.

## Planner / tour

- Opportunity scores change **order**, not membership. CAN is still
  SKIP vs not. 1-hop leftover is a score bonus only.
- `DEAD_END` continuation demotes `FEASIBLE` → `ORBIT_ONLY`. Tour
  lands only on `result = FEASIBLE`.
- After a surface launch, replan remaining and `index = 0`. Do not
  also `aoso_tour_advance`.
- Do not drill while sliding. Do not launch at an arbitrary fuel %.
  `aoso_depart_certify` must be READY / READY_WITH_WARNING.
- Track `accomplished` as SKIPPED / ORBITED / LANDED / COMPLETED.

## Projection

See `docs/AOSO_PROJECTION.md`. Sequential leftover is the cost truth.
`aoso_feas_evaluate(dest_name)` is unchanged as a public signature.

## Branching

Work on `main`. `Watch-AOSO.ps1` tracks it. v2.2 is merged; do not
revive `aoso-v2-integration`.

## Self-test

`run "AOSO/dev/selftest".` after a normal AOSO boot (or it RUN ONCEs
the core it needs). It must not STAGE, LOCK, WARP, or THROTTLE.
Manual KSP flights: `docs/AOSO_SCENARIOS.md`.

There is no flight HUD. Do not add one back. Display work was removed so
IPU stays on steering, staging, and the mission.

