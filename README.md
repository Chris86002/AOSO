# AOSO — Autonomous Operating System / Orbiter

A modular, autonomous spacecraft operating system for Kerbal Space Program, written entirely in **KerboScript (kOS)**.

> This repository is being built out by the Copilot coding agent across 12 ordered phases.
> All scripts live under the `AOSO/` folder, intended to be copied into `GameData` and mounted as a kOS volume.

## Install (once populated)
1. Copy the `AOSO/` folder into `.../Kerbal Space Program/GameData/`.
2. Mount it as a kOS volume (or copy to your archive).
3. From the kOS terminal: `run "AOSO/main".`

By default (no `AOSO/mission_plan.ks`), AOSO runs a **grand tour**: launch (if still on the ground), visit every stock planet and moon (Mun, Minmus, Eve, Gilly, Moho, Duna, Ike, Dres, Jool, Laythe, Vall, Tylo, Bop, Pol, Eeloo), land and ISRU-refuel where the vessel can take off again and actually needs propellant, then return to Kerbin and land at KSC. Jool is orbited, not landed. High-g bodies the ship cannot leave (Eve, Tylo at low TWR) are visited in orbit only. Add an `AOSO/mission_plan.ks` alongside `main.ks` (using `aoso_mission_plan_add()`/`aoso_mission_step_*()` followed by `aoso_mission_start()`) to run a custom mission instead.

Burns lock facing at ignition and feather throttle against remaining burn-time (not a fixed 2 m/s cutoff), so they no longer chase the live node marker. Timewarp drops with ~45 s of physics time to point the ship before ignition; a missed or incomplete burn is dropped and re-planned on the next pass, and empty stages are lit even if throttle is already at zero. Ascent is a true gravity turn: vertical rise until there is enough speed for the stack to control a kick (later and slower if kOS sees a nose-heavy / long CoM), a small ramped pitchover, a loft holding ~75 deg until apoapsis is ~75 km so we punch out of the atmosphere, then zero angle-of-attack on surface prograde with throttle holding ~45 s to apoapsis (NASA / MechJeb PVG / GravityTurn). Circularization is a vis-viva burn centered on apoapsis after leaving the atmosphere.

### What persists across re-runs, and what doesn't
Every `run "AOSO/main".` rebuilds the mission plan and starts a brand-new log file (`0:/aoso_log.txt`) from scratch, so a second try never mixes its output with an earlier one or silently launches with duplicate/stale steps left over from a previous attempt. Your operator settings (`0:/aoso_config.json`) and, only when you actually resume a mission (`aoso_mission_start(TRUE)` from your own `mission_plan.ks`), the last saved step (`0:/aoso_checkpoints.json`) are the only things intentionally kept between runs.

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
