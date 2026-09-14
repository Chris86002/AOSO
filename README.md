# AOSO — Autonomous Operating System / Orbiter

A modular, autonomous spacecraft operating system for Kerbal Space Program, written entirely in **KerboScript (kOS)**.

> This repository is being built out by the Copilot coding agent across 12 ordered phases.
> All scripts live under the `AOSO/` folder, intended to be copied into `GameData` and mounted as a kOS volume.

## Install (once populated)
1. Copy the `AOSO/` folder into `.../Kerbal Space Program/GameData/`.
2. Mount it as a kOS volume (or copy to your archive).
3. From the kOS terminal: `run "AOSO/main".`

By default (no `AOSO/mission_plan.ks`), AOSO runs a **grand tour**: launch (if still on the ground), visit every stock planet and moon the *vessel can actually finish*, land and ISRU-refuel where it can take off again and needs propellant, then return to Kerbin and land at KSC. The itinerary is planned, not hard-coded: a **vehicle class** (hopper, nuclear interplanetary, spaceplane, tug, mothership, …) changes priorities without forbidding destinations; a **capability matrix** scores each body as CAPABLE / MARGIN / CONFIDENCE for orbit, land, and return; **CAN vs SHOULD** opportunity scores plus transfer-window efficiency feed a **cluster-greedy route** (Jool’s moons are one interplanetary hop). If the stack cannot complete the full tour, AOSO logs the maximum achievable sequence instead of marching into a SKIP. Jool is orbited, not landed. High-g bodies the ship cannot leave (Eve, Tylo at low TWR) are visited in orbit only. Add an `AOSO/mission_plan.ks` alongside `main.ks` (using `aoso_mission_plan_add()`/`aoso_mission_step_*()` followed by `aoso_mission_start()`) to run a custom mission instead.

AOSO is vessel-agnostic: on boot (and after staging, docking, landing, or a part-count change) it builds a **vehicle profile** — structure, propulsion, power, mobility, ISRU, navigation, mission hardware — then a capability profile with confidence scores (`can_land`, `can_isru`, `can_dock`, …). A structured snapshot (parts / engines / tanks / mass / stages / docking / drills / solar / thrust) is compared every couple of seconds; only the subsystem that changed is rebuilt (mass/fuel → dV budget, engine-out → propulsion, docking/status → full profile). Delta-v is the remaining stack, not just the active stage, carved into total / unusable / reserve / landing / return / abort / **mission-usable** dV, with a predicted next-stage TWR ("if I stage now…"). Before each tour stop a **feasibility engine** reads a **world model** (`AOSO/world/`: gravity, atmosphere, ore, landing/escape difficulty, comms) and answers reach / orbit / land / takeoff / refuel / return — SKIP a body the ship cannot reach, ORBIT_ONLY rather than landing a ship that cannot leave. After every ascent a **flight-performance database** (`0:/aoso_learn.json`) compares this stack's fuel-to-orbit against its own best and average. The HUD shows vessel class, next tour stop, mission dV, and the last feasibility result; the full profile is persisted to `0:/aoso_profile.json`. The planned route is persisted to `0:/aoso_route.json`.

Long burns follow the live node marker until a few seconds remain, then feather; short burns (circularization) still lock facing at ignition. Timewarp drops with ~2 minutes of physics time to point the ship before ignition; a missed or incomplete burn is dropped and re-planned on the next pass, and empty stages are lit even if throttle is already at zero. Auto-staging fires on empty current-stage fuel (absolute residue or 1.5% of tank capacity) and on AVAILABLETHRUST collapsing for 0.2 s, not only after kOS's lagged FLAMEOUT flag, so dry tanks are dropped during a coast instead of sitting through the next node. Mixed solid+LFO in one KSP stage only drops when **every** present fuel type is gone (an empty SF tank must not dump a still-fueled LF booster). After a drop, a 0.8 s spool is a timestamp, not a WAIT; one extra STAGE is allowed only if the new current stage is also empty. Moon/planet intercepts walk the node until patched conics show an actual encounter rather than hoping a Hohmann phase is close enough. Ascent is MechJeb Classic's pitch-vs-altitude program (`pitch = 90 - ((alt-start)/(end-start))^shape * (90-endAngle)`, AoA-limited, default shape 0.45 / startAlt 1000 m / endAlt 0.93×atm / maxAoA 7°). Throttle holds TWR near 2.2 while the flight path is still steep so gravity can pull the trajectory over; after it shallows, the 45 s-to-AP hold, then **cuts when apoapsis reaches ASCENT_TARGET_APO (80 km on Kerbin)** and coasts — parking 100 km is not the gravity-turn burn. Each ascent is sectioned into VERTICAL / STARTTURN / DENSE_AIR / UPPER_ATM / COAST / CIRCULARIZE with leftover fuel, mean TWR, AoA and Q per period (`0:/aoso_ascent_opt.json`). Across pad reverts AOSO tries start speeds 70 / 85 / 100 / 115 / 130 m/s (six flights, then locks the leftover-LF winner, penalising high circularization dV). Set `ASCENT_OPTIMIZE` false in `0:/aoso_config.json` to freeze the current start speed, or delete `0:/aoso_ascent_opt.json` to search again. Every completed ascent also appends LiquidFuel remaining / used / circularization dV to `0:/aoso_ascent_runs.json` so profiles can be ranked. Capture circularizes at periapsis instead of targeting a parking apoapsis below the current PE. Before landing the tour plane-changes to a polar orbit, scans the ground track for a site scored on slope, altitude (takeoff dV), latitude (solar), and terrain (`landing/site.ks`), then deorbits to a periapsis *above* the highlands (not sea level). The suicide burn uses surface-velocity stopping distance (`v_srf² / 2(a-g)`), stays surface-retrograde until both horizontal and vertical speed are small, and will not switch to a 3 m/s vertical hold while still hypersonic.

### What persists across re-runs, and what doesn't
Every `run "AOSO/main".` rebuilds the mission plan and starts a brand-new log file (`0:/aoso_log.txt`) from scratch, so a second try never mixes its output with an earlier one or silently launches with duplicate/stale steps left over from a previous attempt. Your operator settings (`0:/aoso_config.json`) and, only when you actually resume a mission (`aoso_mission_start(TRUE)` from your own `mission_plan.ks`), the last saved step (`0:/aoso_checkpoints.json`) are the only things intentionally kept between runs. Ascent fuel-to-orbit records (`0:/aoso_ascent_runs.json`) and the flight-performance database (`0:/aoso_learn.json`) also persist so the same vessel configuration can be compared across pad tests; they are not a mission checkpoint.

### Flight log files
Three separate streams, not one dump:
- **Event log** (`0:/aoso_log.txt`) — human-readable PRINT + file, default INFO. Reset every boot.
- **Telemetry** (`0:/aoso_telemetry.csv`) — timed CSV samples (AUTO rate by phase), RAM-buffered and flushed every few seconds or on STAGE/BURN/LAND. Append-only.
- **Events + flight record** (`0:/aoso_events.csv`, `0:/aoso_flightrec.txt`) — structured decisions/anomalies and a pre-event ring dump around STAGE/BURN/LAND/ABORT, plus a few post samples. Append-only mission history.

Ascent steering is MechJeb Classic's pitch-vs-altitude program (shape exponent, AoA-limited), not a prograde lead angle.

## Optional addons (all with pure-kOS fallbacks)
- kOS.MechJeb2.Addon (MechJeb)
- kOS-Astrogator (transfer planning)
- kOS-KerbalEngineer (performance/sensors)
- kOS-simpleJson (persistence)

No addon is a hard dependency — the system degrades gracefully if any are absent.

## Status
Built across 12 ordered phases:
- [x] Phase 1 — Core
- [x] Phase 2 — Vehicle
- [x] Phase 3 — Basic flight
- [x] Phase 4 — Orbital nav
- [x] Phase 5 — Interplanetary
- [x] Phase 6 — Landing
- [x] Phase 7 — Refuel & power
- [x] Phase 8 — Return
- [x] Phase 9 — Precision KSC return
- [x] Phase 10 — Mission layer
- [x] Phase 11 — Advanced
- [x] Phase 12 — Hardening & UX

kOS 1.4 hot paths now lock-once cooked throttle/steering to cheap globals (LOCK expressions re-eval every physics tick; locking to a user function burns IPU/EC at 25 Hz). LIST ENGINES/PARTS/DOCKINGPORTS is cached until STAGE:NUMBER changes (engine refs stay live). Staging fills one snapshot per tick and debounces the 0.1 s auto-stage + ascent double call. The 2 s profile walk is skipped unless stage/status/mass actually moved. Ascent flies MechJeb Classic pitch (not a 3° prograde lead). Staging waits 0.45 s for spool, cools down 1.2 s, and will not walk unignited lander engines. Observability splits the human log, telemetry CSV, and a structured event/flight-record stream with CPU load-shed.
