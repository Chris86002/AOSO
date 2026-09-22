# AOSO — Autonomous Operating System / Orbiter

A modular, autonomous spacecraft operating system for Kerbal Space Program, written entirely in **KerboScript (kOS)**.

> This repository is being built out by the Copilot coding agent across 12 ordered phases.
> All scripts live under the `AOSO/` folder, intended to be copied into `GameData` and mounted as a kOS volume.

## Install

**Recommended: use the updater.** Keep these files together (Desktop is fine):

- `Watch-AOSO.bat` — leave this window open; it auto-updates
- `Update-AOSO.bat` — one-time update
- `Update-AOSO.ps1`

Double-click `Watch-AOSO.bat` and leave that window open. It checks GitHub every 10 minutes and syncs `AOSO/` into:

`.../Kerbal Space Program/Ships/Script/AOSO/`

Updates run even if KSP is open. Every file from GitHub is written, including `mission_plan.ks` when that file is in the repo. Close the window (or Ctrl+C) to stop.

For a single update instead, double-click `Update-AOSO.bat`. If Windows blocks writing under Program Files, right-click the `.bat` and choose **Run as administrator**.

If KSP is not in the default Steam folder, create `kos-root.txt` next to the updater and put the full path to `Ships\Script` on the first line.

The updater also replaces itself from GitHub.

### Manual copy
1. Copy the `AOSO/` folder into `.../Kerbal Space Program/Ships/Script/` (kOS archive) or `.../Kerbal Space Program/GameData/`.
2. Mount it as a kOS volume if you used GameData.
3. From the kOS terminal: `run "AOSO/main".`

By default (no `AOSO/mission_plan.ks`), AOSO runs a **grand tour**: launch (if still on the ground), visit every stock planet and moon the *vessel can actually finish*, land and ISRU-refuel where it can take off again and needs propellant, then return to Kerbin and land at KSC. The itinerary is planned, not hard-coded: a **vehicle class** (hopper, nuclear interplanetary, spaceplane, tug, mothership, …) changes priorities without forbidding destinations; a **capability matrix** scores each body as CAPABLE / MARGIN / CONFIDENCE for orbit, land, and return; **CAN vs SHOULD** opportunity scores plus transfer-window efficiency feed a **cluster-greedy route** (Jool’s moons are one interplanetary hop). If the stack cannot complete the full tour, AOSO logs the maximum achievable sequence instead of marching into a SKIP. Jool is orbited, not landed. High-g bodies the ship cannot leave (Eve, Tylo at low TWR) are visited in orbit only. Add an `AOSO/mission_plan.ks` alongside `main.ks` (using `aoso_mission_plan_add()`/`aoso_mission_step_*()` followed by `aoso_mission_start()`) to run a custom mission instead.

AOSO is vessel-agnostic: on boot (and after staging, docking, landing, or a part-count change) it builds a **vehicle profile** — structure, propulsion, power, mobility, ISRU, navigation, mission hardware — then a capability profile with confidence scores (`can_land`, `can_isru`, `can_dock`, …). A structured snapshot (parts / engines / tanks / mass / stages / docking / drills / solar / thrust) is compared every couple of seconds; only the subsystem that changed is rebuilt (mass/fuel → dV budget, engine-out → propulsion, docking/status → full profile). Delta-v is the remaining stack, not just the active stage, carved into total / unusable / reserve / landing / return / abort / **mission-usable** dV, with a predicted next-stage TWR ("if I stage now…"). Before each tour stop a **feasibility engine** reads a **world model** (`AOSO/world/`: gravity, atmosphere, ore, landing/escape difficulty, comms) and answers reach / orbit / land / takeoff / refuel / return — SKIP a body the ship cannot reach, ORBIT_ONLY rather than landing a ship that cannot leave. Every SKIP is logged with the matrix reason (`skip Laythe: via Jool then ISRU hop …`). An ISRU hopper prices later hops against a **full tank after refuel**, not leftover from the previous burn, and moons of a reachable parent (Laythe from Jool, not LKO→Laythe) are hops off that parent. After every ascent a **flight-performance database** (`0:/aoso_learn.json`) compares this stack's fuel-to-orbit against its own best and average. A **PRINT AT terminal HUD** (no kOS GUI window) redraws in place with what the ship is doing — searching an intercept, scoring the tour, rails-warping to a node, burning, coasting to a patch — so a long PLAN think after circularization does not look idle. Landings capture **into a polar orbit at periapsis** (bind a high ellipse, plane-change at the slow apoapsis node, then circularize) instead of a 140 m/s normal burn after circularizing at 15 km. Long coasts use **rails warp**. After rails, AOSO physics-warps **2x** while SAS points, then **1x for the last ~10 s** before ignition / SOI / suicide (physics 4x slewed Acacius off the circularization node). The full profile is persisted to `0:/aoso_profile.json`. The planned route is persisted to `0:/aoso_route.json`.

Long burns follow the live node marker until a few seconds remain, then feather; short burns lock facing at ignition unless periapsis is still in atmosphere (then they follow the marker so an off-axis light cannot zero remaining_along and cut with 28 m/s left). Timewarp rails to ~50 s out, then **physics 2x** while SAS points, then **1x for the last ~10 s**; a missed or incomplete burn is dropped and re-planned on the next pass, and a circularization that cuts with peri still in the air is treated as incomplete and retried, and empty stages are lit even if throttle is already at zero. Auto-staging fires on empty current-stage fuel (absolute residue or 1.5% of tank capacity) and on AVAILABLETHRUST collapsing for 0.2 s, not only after kOS's lagged FLAMEOUT flag, so dry tanks are dropped during a coast instead of sitting through the next node. Mixed solid+LFO in one KSP stage only drops when **every** present fuel type is gone (an empty SF tank must not dump a still-fueled LF booster). After a drop, a 0.8 s spool is a timestamp, not a WAIT; one extra STAGE is allowed only if the new current stage is also empty. Moon/planet intercepts first match the target plane using a node whose sign is taken from nd:ORBIT (not VCRS), then search around the Hohmann window for the **best patched periapsis** (not the first SOI clip — a T+219 s Minmus graze at 61 km used to beat the later 15 km Hohmann). A 5 s refine plus hill-climb on time/prograde/radial/normal aims PE at a capture altitude. There is **no blind Hohmann**: if this window has no patch, the node is removed and the next orbit is retried. Transfer dV is clamped to 98% of escape (a 1.15× Minmus Hohmann was 1045 m/s vs Kerbin escape ~941 and became a solar hyperbola). A patched intercept does **not** apo-cap the burn (that leftover 4.6 m/s at e=0.973 lost the Minmus patch); throttle cuts on a patch only if remaining < 20 m/s or eccentricity > 0.98, and still emergency-cuts at e≥0.995. After the burn, a poor PE gets a mid-course before SOI. **Capture is always at periapsis (Oberth)** — never recapture the departure body after a missed moon transfer (that was the 2.5-day 0.5 m/s Kerbin PE-raise). A grazing flyby lowers PE first; a long circularize on a hyperbola binds AP inside the SOI at PE first so the burn actually happens at the Oberth peak. When fuel is tight — or a flyby saves ~12% — an inner moon of the current body (Mun toward Minmus, Ike toward Duna’s escape, etc.) is compared with a direct Hohmann and used as a gravity assist instead of capturing there. Ascent is MechJeb Classic's pitch-vs-altitude program (`pitch = 90 - ((alt-start)/(end-start))^shape * (90-endAngle)`, AoA-limited, default shape 0.45 / startAlt 1000 m / endAlt 0.93×atm / maxAoA 7°). Throttle holds TWR near 2.2 while the flight path is still steep so gravity can pull the trajectory over; after it shallows, the 45 s-to-AP hold, then **cuts when apoapsis reaches ASCENT_TARGET_APO (80 km on Kerbin)** and coasts — parking 100 km is not the gravity-turn burn. Each ascent is sectioned into VERTICAL / STARTTURN / DENSE_AIR / UPPER_ATM / COAST / CIRCULARIZE with leftover fuel, mean TWR, AoA and Q per period (`0:/aoso_ascent_opt.json`). Across pad reverts AOSO tries start speeds 70 / 85 / 100 / 115 / 130 m/s (six flights, then locks the leftover-LF winner, penalising high circularization dV). Set `ASCENT_OPTIMIZE` false in `0:/aoso_config.json` to freeze the current start speed, or delete `0:/aoso_ascent_opt.json` to search again. Every completed ascent also appends LiquidFuel remaining / used / circularization dV to `0:/aoso_ascent_runs.json` so profiles can be ranked. Capture circularizes at periapsis instead of targeting a parking apoapsis below the current PE. Before landing the tour plane-changes to a polar orbit, scans the ground track for a site scored on slope, altitude (takeoff dV), latitude (solar), and terrain (`landing/site.ks`) — kOS can query terrain from anywhere, so the pick is instant, then AOSO rails-warps **two orbits** over the track so a live overflight can beat the prediction — then deorbits to a periapsis *above* the highlands (not sea level). The suicide burn uses surface-velocity stopping distance (`v_srf² / 2(a-g)`), stays surface-retrograde until both horizontal and vertical speed are small, and will not switch to a 3 m/s vertical hold while still hypersonic. Rails warp is **released from LOCK STEERING** until ~50 s before a burn (kOS cannot rails-warp a steered ship — that is why a Minmus mid-course and the post-deorbit coast to periapsis kept dropping out of warp). After a deorbit, descent warps to **periapsis** (`ETA:PERIAPSIS`), not a radar/speed TTI computed at apoapsis.

### kOS settings (IPU + HUD)

AOSO is a full autopilot. On boot it raises `CONFIG:IPU` to **`IPU_TARGET` (default 2000)** if the kOS default is lower. **2000 is headroom, not a utilization target.** Background work stops before a protected opcode reserve (absolute 400 + 18% + extra during ascent/descent) so steering never starves. Do not keep raising IPU in the difficulty menu to “make it think harder” — the extra opcodes are a safety budget. Override `IPU_TARGET` in `0:/aoso_config.json` if you must; the kOS tab still shows the live `CONFIG:IPU`.

The HUD is a **mission computer**, not a PRINT dump:

- **GUI window** (draggable) with FLT / NAV / MSN / VEH / PRP / LND / STG / SYS / **TWIN** / LOG / DBG pages
- **Digital Twin** schematic of the vessel AOSO is actually flying: tanks, engines, command, power. Geometry rebuilds on stage/dock/part-count; **fills update live** on the tanks that are feeding. Views: NORM / EXP / STG / SYS / STAT / FUEL / PWR / ENG / CTL. Click a node for UID, mass, resources, modules, and a world HIGHLIGHT.
- **Tactical terminal strip** at the top of the kOS window (always on)
- **Flight-director VECDRAW** arrows (PRO / TGT / BURN / LAND) — `SET VEC`, not `VECUPDATER`
- **HUDTEXT alerts** with cooldowns

Buttons: **TAC** hides the GUI, **GUI** brings it back, **ENG** jumps to the Digital Twin. Click a twin node to `HIGHLIGHT` that part in the world. Flow tags are labelled **APPROXIMATE** — kOS does not expose a full crossfeed solver.

Do not name locals `r`, `v`, or `q` — those clobber kOS builtins `R()`, `V()`, `Q()` (`CLOBBERBUILTINS`).

Buttons: **TAC** hides the GUI (flight HUD only), **GUI** brings the computer back, **ENG** jumps to SYSTEMS. Data is cached at three rates (flight ~8 Hz, orbit/fuel ~2 Hz, vehicle from the existing profile ~0.4 Hz). The HUD never `LIST PARTS`. CPU HIGH slows cosmetic updates; CRITICAL keeps a 3-line strip only.

GOTO and descent run as their own scheduler tasks instead of nested inside the tour FSM. That was the `aoso_goto_update` stack overflow on Acacius (kOS 3000-slot argument cap).

### What persists across re-runs, and what doesn't
Every `run "AOSO/main".` rebuilds the mission plan and starts a brand-new log file (`0:/aoso_log.txt`) from scratch, so a second try never mixes its output with an earlier one or silently launches with duplicate/stale steps left over from a previous attempt. Your operator settings (`0:/aoso_config.json`) and, only when you actually resume a mission (`aoso_mission_start(TRUE)` from your own `mission_plan.ks`), the last saved step (`0:/aoso_checkpoints.json`) are the only things intentionally kept between runs. Ascent fuel-to-orbit records (`0:/aoso_ascent_runs.json`) and the flight-performance database (`0:/aoso_learn.json`) also persist so the same vessel configuration can be compared across pad tests; they are not a mission checkpoint. v2 also persists a launch **configuration id** (`0:/aoso_cfg_id.json`) and bounded experience models (`0:/aoso_xp.json`, copied to `archive:/`) keyed by that id so learning survives a revert and actually changes later dV predictions.

### Flight log files
Three separate streams, not one dump:
- **Event log** (`0:/aoso_log.txt`) — human-readable PRINT + file, default INFO. Reset every boot.
- **Telemetry** (`0:/aoso_telemetry.csv`) — timed CSV samples (AUTO rate by phase), RAM-buffered and flushed every few seconds or on STAGE/BURN/LAND. Append-only.
- **Events + flight record** (`0:/aoso_events.csv`, `0:/aoso_flightrec.txt`) — structured decisions/anomalies and a pre-event ring dump around STAGE/BURN/LAND/ABORT, plus a few post samples. Append-only mission history.

Ascent steering is MechJeb Classic's pitch-vs-altitude program (shape exponent, AoA-limited), not a prograde lead angle. While in atmosphere the HUD shows `Q` (SHIP:Q, Kerbin atmospheres), AoA, and drag kN. Drag comes from MechJeb (`ADDONS:MJ:VESSEL:DRAG`) when the kOS.MechJeb2 addon is present, otherwise from an accelerometer residual, otherwise Q-only (no kN). A rising-Q throttle cap (`ASCENT_MAX_Q`, default 0.30 atm) pulls throttle before max-Q instead of after it. Leftover-LF still ranks pad-revert trials; a start that slams Q and AoA without beating the best LF is not followed by a *faster* start.

## Optional addons (all with pure-kOS fallbacks)
- kOS.MechJeb2.Addon (MechJeb) — also live drag / Cd / AoA for ascent
- kOS-Astrogator (detected for status only; ignored for intercepts. AOSO porkchop + Hohmann + patched-PE hill-climb owns intercept planning; mid-course stays `aoso_rendezvous_add_correction_node`.)
- kOS-KerbalEngineer (performance/sensors; no drag force)
- kOS-simpleJson (persistence)

No addon is a hard dependency — the system degrades gracefully if any are absent. Ferram (kOS-Ferram) is not used.

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
- [x] v2.2 — topology as the structural source of truth, mission certification / assurance / departure cert, verified action results, controller authority, warp deadlines, surface stability + strategic ISRU fill, IPU 2000 with a leftover opcode reserve. See `docs/AOSO_ARCHITECTURE.md`.

kOS 1.4 hot paths now lock-once cooked throttle/steering to cheap globals (LOCK expressions re-eval every physics tick; locking to a user function burns IPU/EC at 25 Hz). LIST ENGINES/PARTS/DOCKINGPORTS is cached until STAGE:NUMBER changes (engine refs stay live). Staging fills one snapshot per tick and debounces the 0.1 s auto-stage + ascent double call. The 2 s profile walk is skipped unless stage/status/mass actually moved. Ascent flies MechJeb Classic pitch (not a 3° prograde lead). Staging waits 0.45 s for spool, cools down 1.2 s, and will not walk unignited lander engines. Observability splits the human log, telemetry CSV, and a structured event/flight-record stream with CPU load-shed.
