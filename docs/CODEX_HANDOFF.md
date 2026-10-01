# Codex handoff — AOSO current state

Updated: 2026-09-30

## Latest Minmus control/trajectory fix — 2026-10-01 UTC

Evidence: `aoso_log/events/flightrec(20261001-010919)` and accompanying
telemetry/CPU/checkpoint/XP files. The vessel successfully braked from
HS 182 m/s to 13.2 m/s at radar 564 m, but stayed in BURN at full throttle
through positive VS and nose-down thrust. Flameout was followed by a 7.44 s
control gap, stage walking, and a 1.004 t/no-propellant remainder. The record
cannot distinguish the exact part destruction/separation sequence.

Implemented directly on main:

- BURN checks velocity arrest **before** issuing full throttle. It hands off
  regardless of radar altitude and anticipates the response interval. Braking
  steering cannot request a nose-down vector, and thrust is inhibited while
  the actual nose points below the horizon.
- FINAL_APPROACH uses an upright command with a 35-degree tilt limit and
  attitude gating. An early terrain arrest regains a bounded descending sink
  rather than hovering high or thrusting through velocity reversal. Re-arming
  needs a descending, fast vessel at braking clearance; HS alone cannot bounce
  the FSM between BURN and FINAL_APPROACH. Radar proximity alone cannot declare
  TOUCHDOWN; real contact and the existing stability verifier gate refueling.
- STAGING queues result/XP ingestion to a quiet scheduler task. XP persistence
  is dirty-buffered and refuses ascent, burn, descent, landing, packed/warping,
  or thrusting states. Deferred data flushes when unpacked and safely idle.
  This removes the synchronous XP serialization/Archive-write path present
  in the recorded flameout tick; runtime latency still needs a flight test.
- Landing-only future positions subtract the **current** SOI-body position,
  not POSITIONAT(body, ut). kOS's VesselTarget.GetPositionAtUT uses the current
  patch reference-body centre; subtracting the future parent-orbit position
  was double-counting Minmus travel. Cross-SOI navigation helpers are unchanged.
  Source checked: KSP-KOS/KOS develop `src/kOS/Suffixed/VesselTarget.cs` and
  https://ksp-kos.github.io/KOS/commands/prediction.html.
- The deorbit timing proxy now uses the first descending surface crossing of
  the proposed ellipse, before periapsis, including body rotation. The actual
  planned node and live post-burn conic both need an impact miss within
  DEORBIT_SITE_TOL_M. No crossing/unacceptable miss rejects the plan. A live
  post-burn rejection reparks near apoapsis when altitude/time/thrust permit;
  otherwise descent survival takes precedence over target accuracy.
- One shared same-body retry/time budget replaces the 376-rejection / 39 h
  survey loop. Defaults: three rejected/recovery plans, six orbital periods,
  and 24000 s total maximum. Independent-sample count resets on each survey.
  A missed window never forces a burn against stale geometry. Exhaustion
  enters LAND_HOLD on this mandatory stop; restarting the tour explicitly
  renews its budget. No stop is marked complete or silently skipped.
- Unsafe suborbital recovery never goes into SCAN. A single propulsion-backed
  emergency descent is permitted; unrecoverable repeated failure holds.
- Hot telemetry runs before lower-priority clock-return gates, preserving the
  existing 1 Hz sampling at high CPU load. Signed pitch is retained, and LAND
  status reports vessel LF/OX fill instead of the empty-stage 100% sentinel.

Validation performed:

- `python tools/check-landing-regressions.py` evaluates selected production
  KerboScript helpers in a limited scalar/vector evaluator. Logged initial
  braking stays active; the -3 VS / 13.2 HS arrest hands off. A constant-gravity
  local recovery from 564 m reaches ground in 48.8 s at VS -2.06 / HS 0.16 m/s
  using 26.9 m/s ideal thrust dV. This omits attitude slew, changing terrain,
  engine spool, staging, and KSP physics and is **not** in-game validation.
- The surface-crossing helper independently satisfies the ellipse equation:
  Minmus 29260 m AP / -500 m PE crosses sea level after 161.81 degrees and
  1415.9 s, before the 1516.6 s periapsis. Budget/frame/coordination checks pass.
- Changed-script delimiter/identifier/IF NOT DEFINED gates and git diff --check
  pass. Added vessel-safe self-tests for arrest/crossing/budget predicates.
  The actual kOS compiler/selftest and KSP flight were not run here.
- Native addon source/DLL is unchanged.

Next-run acceptance:

- LAND_TRAJECTORY_CHECK accepted=True before ignition and after deorbit, with
  consistent impact coordinates/miss. No unexplained 70-160 km drift.
- LAND_BRAKE_COMPLETE before positive VS; no repeated full-throttle
  TURNAROUND/nose-down oscillations. LAND_REARM only after a recovery coast
  reaches braking clearance. Then a real LANDED / LAND_TOUCHDOWN and ISRU.
- No multi-second staging/XP control gap near terrain; LF/OX status decreases
  and hot telemetry covers the burn rather than losing 23 minutes.
- Planning terminates within the shared budget with a viable deorbit or an
  explicit LAND_HOLD. No hundreds of SCAN/DEORBIT cycles and no orbital survey
  from the near-ground, powerless remainder.

Limits: impact validation is an unpowered-conic geometry gate, not a powered
precision-landing solution. Distant terrain queries remain unverified; the
live radar/look-ahead safety controller still owns collision avoidance.
Atmospheric trajectories retain their existing drag/chute behavior and do not
use this airless impact gate. User policy of landing/full ISRU before departure
remains in force.

## Mandatory landing and full ISRU (user policy correction)

This supersedes the preceding policy that a failed Minmus landing could
advance the tour. Every surface destination must land, finish ISRU with
all carried refillable propellants full, and complete certified takeoff
before the itinerary can move on. Jool has no surface and remains an
orbit-only stop. Initial PRELAUNCH at KSC still uses the normal launch gate.

- Repeated unsafe/unreachable site rejection re-enters the live survey on
  the same body without changing the stop index. Descent interruption
  returns to refuel if landed, otherwise retries survey/capture/descent
  according to the live orbit. It never authorizes onward navigation.
- Surface bodies classified ORBIT_ONLY are still mandatory landing stops;
  existing flight/landing safety gates remain. An unreachable destination
  holds and rechecks live feasibility rather than incrementing the index.
- Replanning retains all requested stops, including bodies omitted by the
  capability ranking, and removes only completed stops. An old checkpoint
  index cannot skip an unverified stop in a differently rebuilt route.
  Starting in a non-Kerbin surface body's orbit services that body first.
- Tour drives the existing ISRU FSM with an explicit 100% target for every
  present LiquidFuel/Oxidizer/MonoPropellant tank. Other ISRU callers keep
  their optimized targets. Completion checks allow only 0.01 percentage
  point capacity-readout tolerance. Missing hardware, power or known Ore
  blocks departure. Stalled/partial/aborted ISRU retries after 60 seconds.
- Launch independently requires a verified full ISRU cycle on the current
  body, live full-tank readings, surface stability and departure certificate.
  Fill levels are checked before ignition, not after ascent consumes fuel.
- ISRU progress now tracks every requested product, not only LiquidFuel.
  Already-full tanks stow successfully before the stall test, and a
  LiquidFuel-only success cannot hide an incomplete other resource.

Validation: static delimiter/name/collision/whitespace checks passed for
the changed scripts. Source control-flow checks cover every landing failure
exit and launch gating; decision-table models cover partial fill, absent or
wrong-body ISRU verification, and full refill. Added vessel-safe kOS
selftests for the actual fill/verification helpers. No KSP/kOS execution
was available. This enforces persistence and departure gating; it does
not establish that the current deorbit proxy can reach every safe site.

Next flight: `LAND_RETRY` must retain Minmus after each rejection, with no
Minmus ORBITED mark or next-body navigation. After touchdown expect target
100%, then `ISRU_FULL` before LAUNCH. Missing resources or a stall must
print an ISRU hold and remain on Minmus. Landing search safety tolerances
were not relaxed to force a burn.

## Minmus unintended plane-match escape (033129 run)

Capture succeeded: at UT 1531959.95 the vessel was bound at roughly
17.3 km altitude, inclination 89.271 deg, eccentricity 0.001. POLAR added
no burn. The survey/deorbit search then rejected two targets; the second
best miss was 36,419 m against a 6,000 m limit. TOUR marked Minmus ORBITED
and advanced toward Mun. This landing reachability limitation remains;
the safety gate was not weakened.

The faulty burn began at UT 1537436.76: GOTO selected the parent hop
Minmus -> Kerbin and compared the Minmus parking plane with Kerbin's
solar plane. It applied -243.48 m/s normal only, opening eccentricity
from 0.0008 to 2.5952. This was neither capture nor survey polarization.

Fixes:

- GOTO computes relative inclination only when ship and target orbit the
  same primary. Cross-body departures go to escape/ejection planning.
- Both transfer-plane helpers also reject mismatched primaries so direct
  mission calls cannot bypass the routing gate.
- Dedicated target-plane turns use normal = speed*sin(angle) and
  prograde = speed*(cos(angle)-1), rather than applying the total turn
  magnitude entirely along normal. Trial signs must improve inclination,
  remain elliptic, clear the safe PE floor/atmosphere, and keep AP inside
  the current SOI. The final node is checked again and uses the selected
  absolute UT rather than moving its epoch by the trial-search duration.
- Terminal messages make landing skips and intentional parent departures
  visible. A tour may still leave Minmus intentionally after rejecting
  landing; this change removes the accidental plane-match escape.

Validation: touched scripts passed delimiter, forbidden-name, IF NOT
DEFINED, function/global collision and whitespace checks. A deterministic
circular-orbit model reproduces escape from the logged normal burn and
verifies speed conservation for turns from 0 through 180 deg. Added
vessel-safe selftests for primary matching and large-turn components;
these selftests and the navigation flow have not been run in KSP/kOS.

Next-run signatures: no `Plane match first` for Minmus -> Kerbin. Expect
`Skipping cross-body plane match ... using departure planner`, followed
by `Planning intentional escape ... (goal Mun)` and MOONESCAPE if the
tour still advances after LAND_TARGET_REJECT. Successful landing remains
subject to finding a safe reachable site. For same-primary plane turns,
expect both normal and prograde components and `bound orbit verified`.

## True suicide-burn controller (2026-09-30)

The previous landing controller was a powered descent, not a suicide burn. It
compared full-vector stopping distance with vertical radar altitude, ignited
kilometres early on a shallow approach, then used a sink schedule that could
settle near hover thrust. That behavior has been removed.

Current airless landing behavior:

- Deorbit targets a periapsis 500 m below the selected terrain by default, so
  FREEFALL is an impact trajectory rather than an orbit that must be hovered
  down from periapsis.
- FREEFALL numerically integrates an immediate full-thrust,
  surface-retrograde burn in local horizontal/vertical coordinates. The
  predictor includes gravity and the radial curvature term from tangential
  velocity, and returns the vertical clearance that the burn consumes.
- Ignition occurs only when terrain-aware clearance reaches that prediction,
  after rails warp has stopped and the vessel has aligned.
- BURN commands surface retrograde and 100% throttle continuously. Throttle
  modulation is confined to the low terminal flare after horizontal and
  vertical velocity enter the terminal envelope.
- The kOS terminal prints `LAND SUICIDE ... thr=100%` every two seconds during
  the burn, followed by `LAND TERMINAL ...` during the flare.

This edit has static and deterministic controller-model coverage only; it has
not yet flown in KSP. On the previous Minmus failure sample (about 169 m/s
horizontal and -12.4 m/s vertical), the numerical model predicts roughly 90 m
of vertical drop during the braking burn, not the old multi-kilometre scalar
stopping distance. The next flight should therefore remain at throttle zero at
2.5 km, log one late `SUICIDE_COMMIT`, hold `thr=100%` through BURN, and enter
TERMINAL only near the surface. It must not show the old 3-4% high-altitude
hover equilibrium.

## Landing guidance update (2026-09-28)

The Minmus deorbit path was confirmed to optimize the geographic position of
the *new periapsis*, not the later terrain intersection. Its site coordinate
is body-fixed; `aoso_tour_pe_ground()` maps the future inertial periapsis into
the current body frame and subtracts body rotation through periapsis time.
That rotation correction is confined to the periapsis proxy. It does not
predict or correct the actual surface impact during descent. This explains why
a 16.9 km periapsis-proxy miss could still be committed after a long wait.

Changes now on main:

- Added `AOSO/landing/impact.ks`: an airless-body, unpowered-conic predictor
  that samples the live KSP patched-conic trajectory, bisects the first
  terrain crossing, and converts impact longitude to the body's future-fixed
  frame. It reports impact UT, lat/lng, radial/terrain altitude, inertial
  speed, and miss distance to the selected target.
- The descent FREEFALL loop emits rate-limited `LAND_PREDICT` observations,
  then `SUICIDE_COMMIT` and `LAND_TOUCHDOWN` records with speed, braking,
  thrust, mass, gravity, target miss, and elapsed landing data.
- The default periapsis-proxy search horizon is now two orbits (still
  configurable, capped at four), and the site survey can end early after
  verified low-risk terrain and repeated safe live samples.
- The new longitude wrapping / rotation transform has deterministic checks
  in `AOSO/dev/selftest.ks`.

Limits for the next flight: the impact predictor runs only after the deorbit
burn is executed and predicts an *unpowered* conic. It does not model
atmospheric drag, pending finite burns, or the trajectory change from powered
lateral corrections. The deorbit candidate search still targets periapsis as
an initial approximation, and descent still brakes surface-relative velocity
without closed-loop lateral correction toward the selected site. Do not treat
a low `LAND_PREDICT miss` as an in-game validated solution until it converges
against observed touchdown. The essential next implementation is a bounded
impact-target correction law with a survival override, followed by live
Minmus verification.

Next-run signatures:

- The deorbit line should say it is selecting a periapsis-proxy candidate and
  should not wait more than two orbits by default.
- Expect `LAND_PREDICT` to show the predicted body-fixed impact point, target,
  miss, and time to impact. If it says `no_surface_intersection`, inspect the
  actual PE and body terrain height; if the point jumps with time, compare
  consecutive logs and the body's rotation period.
- Review references: Garwel's `SBLAND2` uses stopping time and target
  distance to estimate a braking range
  (https://github.com/GarwelGarwel/kOS-lib/blob/master/SBLAND2.ks). Its
  `DTLZ` estimate is useful as a guidance idea, but does not replace an
  impact predictor. CalebJ2's landing script queries the Trajectories addon
  for impact position
  (https://github.com/CalebJ2/kOS-landing-script/blob/master/land.ks); AOSO
  remains stock-only and does not depend on it.
- `SUICIDE_COMMIT` should include clearance, full speed vector, available
  thrust, mass, TWR, gravity, net deceleration, stopping distance, and the
  most recent predicted target miss.
- `LAND_TOUCHDOWN` should report the actual coordinates and miss. Compare it
  with the last few `LAND_PREDICT` entries to estimate predictor residual.

## This cycle (Acacius Minmus capture miss, log UT ~1521160–1530287)

Intercept was good (PE 13770 m vs park 15000 m). Capture added the polar
apoapsis node (dv=-126.2 m/s, ETA ~9037 s) and then never flew it. Last
coast line was `COAST T-8335s RAILS 10000x`; next warp line was
`UNPACK T-32s RAILS 100x`; maneuver logged `Missed node (ETA=-18.3s)`.
One rails frame at 10000x/1000x/100x was larger than the old floors.
After the miss, `Already past periapsis on a hyperbola - no apoapsis-change
node` fired three times in one second and GOTO safe-held a still-capturable
hyperbola (e=3.385, PE=13770 m, ~18 km, climbing).

Not flown in KSP after this edit. Next-run signatures:

- Coasts do not sit at `RAILS 10000x` inside ~2 h of a node. Expect the
  drop from 1000x while the node is still thousands of seconds out.
- A hitch inside one frame of the node logs `urgent drop` and is at
  physics 1x before PE, not `Missed node` from 100x.
- If PE is already behind, log `binding from the current point` and fly
  that retrograde node. Do not log `no apoapsis-change node` followed by
  `Capture failed 3x` while PE is still above the safe floor.

## Previous cycle (Acacius Minmus capture, log UT ~785706–1097683)

Capture promised a polar orbit at inc 10.3, then deferred because e=0.98
and circularized 62 m/s into a 15 km orbit at inc 10.2. GOTO marked that
parked. Tour then spent 42 m/s raising apoapsis back to 270 km. Inclination
was still 10.2 when the log ended. The e<0.18 / first-node gate made an
in-SOI polar burn impossible on a real arrival, and the inclination picker
could commit the first normal sign even when predicted inclination did not
improve.

Not flown in KSP after this edit. Next-run signatures:

- Do not log `Polar capture deferred` or `circularizing at periapsis` while inclination is still outside `TOUR_POLAR_TOLERANCE_DEG` of 90.
- Do log `setting apoapsis to` before the plane change, then `plane-changing at the slow AN/DN` / `Inclination node added` with predicted inc near 90.
- SCAN only after inc is within about 5 deg of 90. A 15 km circle at ~10 deg is not parked-and-done for a landing.
- Still no coast `deg off polar`, `Early polar SOI aim`, or `PE/polar approach correction`.

## Previous cycle (Acacius Kerbin → Minmus, log UT ~797866–1609793)

Polar intercepts were a coast objective. `AOSO_WANT_POLAR` made
`orbit_needs_correct` stay true for the whole transfer, stretched the
correction window to a day, and hill-climbed inclination at transfer
speed (`inc N deg off polar`, 21 m/s then 2.5 m/s, GOTO_CORRECT_MAX).
RSVP does not do that: one departure burn aims the B-plane (prograde by
default) and the arrival inclination is whatever that aim produces.
AOSO still raises apoapsis and plane-changes once inside SOI (tour POLAR).

Landing burned 433 m/s vs 180 predicted. Suicide started at radar 3532 m
with vVert -17.6 and vSrf 211 because stop distance used the full
surface-speed vector against vertical radar. Final approach then sat at
throttle 0 while VS was about -14 (PID sign was backwards). Bounds
offset flickered 0–14 m and spammed the log.

Not flown in KSP after this edit. Next-run signatures:

- One departure burn. Log `Departure aim prograde` or `departure accepted`
  with a capture-band PE. Do not log `deg off polar`, `Early polar SOI aim`,
  or `PE/polar approach correction`.
- At most one `Mid-course PE correction` if the live patch leaves the band.
- Suicide log shows `tti` near `tStop`, not radar 3500 m with vVert tens of m/s.
- Final approach must not hold throttle 0 while falling faster than -3 m/s.

## Previous cycle

Updated: 2026-09-23

This file is a short handoff for the current AOSO debugging cycle. Read
AGENTS.md first. Use this file when continuing the current Minmus flight /
navigation work; it is not a replacement for the subsystem docs.
The flight HUD has been removed. Do not treat a missing display as a bug.

## Current test priority

Before adding new navigation features, run one clean flight
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

## Display

There is no HUD, MFD, or CRT. Boot should not open a GUI. The log and
`0:/aoso_telemetry.csv` are the flight record.

## Native addon

The addon is expected to be v0.4.2. The updater requires 0.4.2.0; an older loaded DLL may be pending until KSP closes.
After updating/rebuilding, boot should identify the loaded native addon version.

Do not claim the native DLL is validated unless KSP was actually
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
