# AGENTS.md — AOSO agent map

AOSO is an autonomous Grand Tour flight computer for Kerbal Space Program
1.12.5. Most flight logic is KerboScript under AOSO/. A native kOS addon lives
under plugin/ and is built against the user's real KSP/kOS assemblies.

## Working style

- Work directly on main unless the user explicitly asks for a branch/PR.
- Inspect the relevant implementation and docs before changing behavior.
- Prefer tying existing systems together over parallel replacement systems.
- Preserve working behavior outside the requested subsystem.
- Do not silently weaken safety gates just to make a mission progress.
- After meaningful edits, run static checks and state what was actually tested.
- Logs are evidence: use aoso_log / events / telemetry / KSP.log to reconstruct
  the state timeline before changing navigation or safety behavior.

## Read the task-specific docs, not every doc

Start with docs/AI_CONTEXT.md for KerboScript hazards and repo-wide rules.
For the active Minmus debugging cycle, docs/CODEX_HANDOFF.md contains the
current diagnosis, fixes already applied, and next-run acceptance signatures.

Use:
- docs/AOSO_ARCHITECTURE.md for subsystem boundaries and scheduler/state design.
- docs/AOSO_DATAFLOW.md and docs/AOSO_DATA_OWNERSHIP.md for model ownership.
- docs/AOSO_ACTION_LIFECYCLE.md for action/result/XP lifecycle.
- docs/AOSO_TOPOLOGY.md for vessel graph/staging/topology work.
- docs/AOSO_PROJECTION.md for planning/performance projection.
- docs/AOSO_MISSION_ASSURANCE.md for feasibility, holds, and safety decisions.
- docs/AOSO_NATIVE_ADDON.md for plugin/, ADDONS:AOSO, Lambert/porkchop/native work.
- docs/AOSO_PERFORMANCE.md for scheduler/IPU/performance changes.
- docs/AOSO_SCENARIOS.md for scenario/testing intent.

## Non-negotiable KerboScript rules

- Identifiers are case-insensitive.
- Never create a FUNCTION whose name collides with a GLOBAL.
- Do not use locals/parameters named path, obt, note, alt, r, v, q, or status.
- Do not write IF NOT DEFINED x; nest the DEFINED check.
- Avoid recursive state transitions. Use queued FSM entry through core/state.ks.
- There is no flight HUD. Do not add a display that competes with steering,
  staging, or the mission for IPU.
- ADDONS:* access belongs in AOSO/core/addons.ks. Other modules use wrappers.

## Warp / patched-conics invariants

These rules come from real AOSO failure runs and must not be relaxed casually.

- Never WAIT 0 while rails warp is active or while a warp-mode transition is
  unsettled. A single rendered frame can advance thousands of seconds of UT.
- aoso_warp_hard_stop() is only a non-blocking stop request.
- Code that mutates maneuver nodes or performs patched-conic searches must wait
  across scheduler ticks until aoso_warp_ensure_physics_idle() returns TRUE.
- Do not command steering while rails warp/packing/unpacking owns the vessel.
- Do not repeatedly PLAN -> COAST -> PLAN for the same unrelated SOI patch.
  Repair once, then accept a verified-safe recovery flyby or hold.
- A destination SOI is not arrival. Capture/arrival requires a verified bound,
  stable/parked orbit unless the mission explicitly requested a flyby.
- Never transition TOUR into POLAR/SCAN/DESCEND from a hyperbolic arrival.
- Near-target capture PE should proceed to the binding burn when it is already
  inside the accepted tolerance; do not waste retries correcting tiny PE error.

## Navigation doctrine

For moon/planet transfers:
1. Prefer a safe direct rough encounter over departure-side perfection.
2. Commit the transfer.
3. Monitor the live patch during coast.
4. Refine capture PE with later mid-course corrections when geometry is better.
5. Enter SOI, bind/capture, stabilize/polarize if required, then survey/land.

A direct parent -> moon transfer must encounter the intended moon as the first
SOI patch. A deeper conic chain such as Kerbin -> Mun -> Kerbin -> Minmus does
not count as a direct Minmus intercept.

## Native addon

- Source lives under plugin/, never inside AOSO/ (AOSO/ is the script volume).
- Keep KerboScript fallback behavior when practical.
- If plugin source changes, bump/version consistently and build/install against
  the user's actual KSP installation before claiming the DLL was tested.
- The updater should make stale native DLL versions visible rather than silently
  accepting them.

## Validation before handoff

For touched KerboScript:
- check balanced braces/parentheses/brackets;
- scan for case-insensitive function/global collisions;
- scan forbidden local/parameter names;
- scan IF NOT DEFINED;
- inspect direct callers when changing helper semantics.

For flight/navigation fixes, identify the log signature that should disappear
and the new signature expected on the next run.

Do not claim in-game validation unless KSP/kOS was actually run.
