# AI context — AOSO / kOS

Read this before changing AOSO. The user cannot run a shell in KSP;
they watch the kOS terminal and the HUD.

## Non-negotiable kOS rules

- **No AND/OR short-circuit.** Both sides always run. Nest `IF` when a
  suffix might be missing (`IF HASNODE { IF NEXTNODE:ETA < x { } }`).
- **`DEFINED` is for variables, not functions.** `DEFINED aoso_plan_build`
  is invalid. Check `DEFINED AOSO_PLAN_LAST`.
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
  topology.
- Capabilities are derived from topology and dynamic state. Profile is
  a summary/view, not an independent structural truth.
- Staging uses topology prediction, then executes.
- Controllers do not define strategic objectives. They must own
  authority before commanding flight controls.
- An action is not successful until its postconditions are verified.
- Trajectory corrections are normal actions, not necessarily mission
  failures. `CORRECT_LOCAL_DV` vs `REPLAN_DV_ERROR`.
- Mission strategy is re-certified after meaningful spacecraft changes.
- Surface takeoff requires departure certification.
- Persistent schema changes require migration.
- One authoritative body knowledge source (`bodydb` + `world/body`).
- Duplicate calculations should be removed after migration.
- Prefer real observed state over saved expectations after restart.
- When uncertain, enter a safe evaluative state instead of continuing
  blindly (`aoso_safe_hold`).
- `CONFIG:IPU` defaults to 2000. That is headroom, not a target
  utilization. Critical flight always outranks UI and strategy.
- Background work stops before the protected opcode reserve.
- Full topology scans are event-driven. Replan may wait for a quiet
  window. HUD/telemetry must never starve flight control.
- Ascent AoA limit is **asymmetric**: tight nose-up, wider nose-down
  so a lofted flight path can still catch the pitch program. Do not
  judge THRUST_MISMATCH in the same tick as `STAGE()`.

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
  SKIP vs not.
- `DEAD_END` continuation demotes `FEASIBLE` → `ORBIT_ONLY`. Tour
  lands only on `result = FEASIBLE`.
- After a surface launch, replan remaining and `index = 0`. Do not
  also `aoso_tour_advance`.
- Do not drill while sliding. Do not launch at an arbitrary fuel %.
  `aoso_depart_certify` must be READY / READY_WITH_WARNING.
- Track `accomplished` as SKIPPED / ORBITED / LANDED / COMPLETED.

## Branching

Work lives on `aoso-v2-integration`. Do not merge to `main` unless the
user authorizes it. `Watch-AOSO.ps1` still tracks `main`, so a flying
copy does not auto-overwrite onto this branch.

## Self-test

`run "AOSO/dev/selftest".` after a normal AOSO boot (or it RUN ONCEs
the core it needs). It must not STAGE, LOCK, WARP, or THROTTLE.
