# AOSO vessel topology

The topology model is the authoritative source of vessel structure.
No other subsystem performs a full structural `LIST PARTS` / `HASMODULE`
census unless it owns topology.

```
raw parts cache (parts.ks)
        ↓
  TOPOLOGY MODEL
        ↓
  derived views: profile, capabilities, classify, budget
```

## Graph representation

KerboScript cannot cheaply store a giant object graph. Topology uses:

| Structure | What |
|---|---|
| `AOSO_TOPO` | Compact census lexicon |
| `AOSO_TOPO_PARENT` | `uid → parent uid` |
| `AOSO_TOPO_GROUPS` | `""+DECOUPLEDIN` → stage-local tanks, engines, hardware |

Part identity is `PART:UID`. Stage ownership is `DECOUPLEDIN` (the
KSP stage that will drop that part). Parent links exist for later
walks; consumers should use groups, not ad-hoc parent chasing.

## Fingerprint vs revisions

- **Fingerprint** `fp`: `parts|engines|STAGE:NUMBER|rootUID|docks|controlUID`
- **`rev`**: increments on a structural rebuild
- **`dyn_rev`**: increments when only mass/thrust changed

`aoso_topo_refresh()` rebuilds only when `fp` changes (or `force`).
Fuel drain does **not** rebuild structure. Dynamic fuel amounts in
groups currently refresh on the next structural rebuild or a forced
`profile_refresh`.

## Groups

Each `DECOUPLEDIN` group records parts, engines, tanks, legs, drills,
converters, RW/RCS, wet/dry mass, and stage-local `lf/ox/sf/xe/mp`.

Layers are sorted high-`DECOUPLEDIN` first and labeled `BOOSTER` /
`STAGE` / `CORE`.

`aoso_topo_fuel_of(decoupled_in)` is the resource-access view: a
particular engine group should use **that stage's tanks**, not vessel
totals.

## Hardware census (`hw`)

One `HASMODULE` walk fills solar, generator, fuel cells, wheels,
heatshield, science, kOS, lifting, chutes, legs, drills, converters,
radiators, antenna, cargo, fairing, decoupler, RCS, reaction wheels,
intakes, nuke, ion.

Profile, vessel, and classify **read `hw`**. They keep a fallback walk
only if topology has not been built yet.

## Stage prediction

`next_stage` answers "what disappears if I stage now?":

```
parts_lost, engines_lost, tanks_lost, legs_lost, isru_lost,
dry_mass_lost, wet_mass_lost, mass_next, role_this, role_next
```

Staging still **executes** in `staging.ks`. Topology predicts. Do not
add a second independent drop calculator.

## Control / turn lead

`control.turn_lead_s` (50 / 70 / 80) is a cheap pointing estimate from
mass + RW/RCS. Maneuver align time uses the larger of this and
`MANEUVER_ALIGN_S`.

## When to rebuild

Full rebuild: boot, `profile_refresh`, fingerprint mismatch (stage,
dock, part count, control point), manual `aoso_topo_refresh(TRUE)`.

Never rebuild every physics tick.
