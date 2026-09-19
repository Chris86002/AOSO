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
  `alt`, `r`, `v`, or `q` (builtins).
- **No nested callbacks / deep transition stacks.** Entry handlers must
  not call `aoso_state_transition` in a way that runs the next entry on
  the same stack. Events must queue-then-drain.
- **`LOCK STEERING` blocks `WARPTO`.** Release steering before rails.
  `WAIT 0` under rails jumps UT and cancels `WARPTO`; long coasts use
  `SET WARP`.
- Preserve public function names. Do not rewrite FSMs from scratch.

## Think windows

Sit on the pad, on the surface, or in a bound orbit, then take the time
the math needs. Do not porkchop during ascent, atmosphere, or a burn.
`aoso_brain_wait_think` is the gate. Pad and landed **are** valid think
windows — calculate before launch when the plan needs it.

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

## Branching

Work lives on `aoso-v2-integration`. Do not merge to `main` unless the
user authorizes it.

## Self-test

`run "AOSO/dev/selftest".` after a normal AOSO boot (or it RUN ONCEs
the core it needs). It must not STAGE, LOCK, WARP, or THROTTLE.
