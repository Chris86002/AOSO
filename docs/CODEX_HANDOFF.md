# Codex handoff — AOSO current state

Updated: 2026-09-23

This file is a short handoff for the current AOSO debugging cycle. Read
AGENTS.md first. Use this file when continuing the current Minmus flight /
UI2 validation work; it is not a replacement for the subsystem docs.

## Current test priority

Before extending UI2 or adding new navigation features, run one clean flight
from Kerbin toward Minmus and verify the fixes below in the real KSP/kOS
runtime.

The previous failing run was aoso_log(10).txt.

## What failed in that run

### 1. "Bounded 1x" planning waits advanced enormous UT

The log repeatedly showed:

- Unexpected next SOI Mun while targeting Minmus
- Planning pause: mid-course correction (1x, bounded wait)
- Quiet wait expired

One example began near UT 1,283,930 and expired near UT 1,332,938. The
nominal few-second real-time wait advanced about 49,000 seconds of game time.

Root cause: WAIT 0 was executed while rails warp / the rails-to-physics
transition was not actually settled.

### 2. Repeated Mun obstruction loop

The run logged 56 occurrences of:

Unexpected next SOI Mun while targeting Minmus

The controller repeatedly did COAST -> detect Mun -> correction/replan ->
PLAN -> accept later Minmus patch -> COAST -> detect Mun again.

That consumed most of the flight time.

### 3. Minmus capture retried a meaningless 270 m PE adjustment

At Minmus:
- desired park PE: 15,000 m
- actual PE: about 14,730 m
- orbit was still hyperbolic

The old capture path treated 14,730 m as needing PE repair rather than
proceeding to the actual binding burn. The tiny correction repeatedly failed
to produce a useful node.

### 4. False arrival and invalid landing

After three failed capture-node attempts the old code marked Minmus arrived
even though the orbit was still hyperbolic (e about 5.942).

Tour then entered POLAR, failed an apoapsis operation on a hyperbola, and
started FREEFALL/descent from roughly 2.15 million metres altitude.

A destination SOI is not arrival.

## Fixes now on main

### Warp/planning ownership

- aoso_warp_hard_stop() is now non-blocking: it only requests WARP=0.
- Code that needs unpacked physics must call
  aoso_warp_ensure_physics_idle() across scheduler ticks.
- Rails-mode transitions in aoso_warp_approach() no longer WAIT 0.
- GOTO PLAN and CAPTURE entries requeue themselves until physics 1x is
  actually settled.
- Mid-course correction, porkchop search, capture PE tuning, and polar-scan
  handoff explicitly require settled physics before doing patched-conic/node
  work.
- aoso_brain_wait_think() will not enter its WAIT loop until physics 1x is
  confirmed settled.

### Unexpected-SOI recovery

- Count recovery cycles rather than scheduler ticks.
- Try a direct repair.
- If the same unrelated moon obstruction persists and its flyby PE is verified
  safe, accept it as a recovery via leg instead of repeating PLAN/COAST.
- Repeated unsafe/unrepairable obstruction enters safe hold rather than an
  infinite loop.

### Capture / arrival

- Near-target PE uses tolerance: a Minmus PE around 14.7 km for a 15 km target
  proceeds toward the binding burn instead of wasting retries on a 270 m PE
  correction.
- Capture failure cannot mark destination arrival unless the orbit is verified
  parked/bound.
- Repeated capture failure at the goal enters safe hold if still unbound.
- Tour refuses POLAR/LANDING from a hyperbolic arrival.
- Stabilization/circularization failure is a hold, not permission to descend.

## Expected next-run signatures

Good:

- rails -> transition -> PHYSICS 1x settles over scheduler ticks;
- no multi-thousand-second UT jump inside a "bounded wait";
- a repeated Mun obstruction is repaired once, converted to a verified-safe
  recovery leg, or held — not repeated dozens of times;
- a safe rough Minmus encounter is allowed to depart and later refined;
- at Minmus, PE near the accepted capture target proceeds to a real binding
  burn;
- GOTO only logs Arrived at Minmus after a verified bound/parked orbit;
- Tour only enters POLAR/SCAN after a bound stable arrival.

Bad / regression:

- repeated PLAN -> COAST -> unexpected Mun every few seconds;
- Planning pause followed by thousands of seconds of UT advancement;
- "Capture failed ... marking arrived" while eccentricity >= 1;
- POLAR/SCAN/DESCEND while aoso_orbit_is_hyperbolic() is true;
- FREEFALL starting from a high-altitude hyperbolic flyby;
- WAIT 0 added to warp-stop or warp-mode-transition code.

## UI2 status

UI2 first-pass implementation is on main, but real KSP runtime validation is
still pending. The first UI test should happen after/with the clean flight.

Expected startup:
- UI header: UI2 READY
- log: UI2 Startup self-test READY

Authoritative UI runtime doc: docs/AOSO_UI2.md.
docs/AOSO_UI_V2.md is design/history context if it differs.

## Native addon

The addon is expected to be v0.4.2. The updater requires 0.4.2.0; an older loaded DLL may be pending until KSP closes.
After updating/rebuilding, boot should identify the loaded native addon version.

Do not claim the native DLL or UI runtime is validated unless KSP was actually
run.

## Recommended continuation loop

1. Update local AOSO + native addon.
2. Start one clean Minmus test.
3. Capture aoso_log, events/telemetry if useful, and KSP.log if the game
   freezes/errors.
4. Reconstruct the state timeline before editing.
5. Compare against the expected/bad signatures above.
6. Make the smallest coherent multi-file fix that removes the observed cause.
7. Run the KerboScript static gate from AGENTS.md.
8. Commit directly to main.
