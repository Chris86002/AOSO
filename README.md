# AOSO — Autonomous Operating System / Orbiter

A modular, autonomous spacecraft operating system for Kerbal Space Program, written entirely in **KerboScript (kOS)**.

> This repository is being built out by the Copilot coding agent across 12 ordered phases.
> All scripts live under the `AOSO/` folder, intended to be copied into `GameData` and mounted as a kOS volume.

## Install (once populated)
1. Copy the `AOSO/` folder into `.../Kerbal Space Program/GameData/`.
2. Mount it as a kOS volume (or copy to your archive).
3. From the kOS terminal: `run AOSO/main.`

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
- [ ] Phase 9 — Precision KSC return
- [ ] Phase 10 — Mission layer
- [ ] Phase 11 — Advanced
- [ ] Phase 12 — Hardening & UX
