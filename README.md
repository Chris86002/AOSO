# AOSO — Autonomous Operating System / Orbiter

A modular, autonomous spacecraft operating system for Kerbal Space Program, written entirely in **KerboScript (kOS)**.

> This repository is being built out by the Copilot coding agent across 12 ordered phases.
> All scripts live under the `AOSO/` folder, intended to be copied into kOS's Archive volume.

## Install (once populated)
1. Copy the `AOSO/` folder (keep the name and capitalization as `AOSO`) so it sits directly
   inside kOS's **Archive** folder, which by default is
   `.../Kerbal Space Program/Ships/Script/` — i.e. you should end up with
   `.../Ships/Script/AOSO/main.ks`. Do **not** put it in `GameData/`; that folder is for mods,
   not for kOS scripts.
2. In-game, open a kOS terminal on your vessel and switch to the Archive volume before running
   anything: `switch to 0.`
3. From the kOS terminal (now on the Archive volume): `run AOSO/main.`
   - If you'd rather stay on the ship's local volume, you can instead run it directly with an
     explicit volume prefix: `run 0:/AOSO/main.`

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
