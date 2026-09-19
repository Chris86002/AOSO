# AOSO vessel topology

The topology model is the authoritative source of vessel structure.
No other subsystem performs a full structural `LIST PARTS` / `HASMODULE`
census unless it owns topology.

```
raw parts cache (parts.ks)
        ↓
  TOPOLOGY MODEL          (structure + prop roles)
        ↓  aoso_topo_refresh_dynamic
  group fuel / mass       (dyn_rev)
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
| `AOSO_TOPO["prop"]` | Engine-bearing groups with inferred role |

Part identity is `PART:UID`. Stage ownership is `DECOUPLEDIN` (the
KSP stage that will drop that part). Parent links exist for later
walks; consumers should use groups, not ad-hoc parent chasing.

## Fingerprint vs revisions

- **Fingerprint** `fp`: `parts|engines|STAGE:NUMBER|rootUID|docks|controlUID`
- **`rev`**: increments on a structural rebuild
- **`dyn_rev`**: increments when fuel/mass/thrust changed without a rebuild

`aoso_topo_refresh()` rebuilds only when `fp` changes (or `force`).
Fuel drain does **not** rebuild structure.

| Call | What |
|---|---|
| `aoso_topo_refresh(FALSE)` | rebuild if fp moved, else `touch_dynamic` (mass/thrust only) |
| `aoso_topo_refresh_dynamic()` | rewrite group fuel/mass in place, bump `dyn_rev` |
| `aoso_topo_touch_dynamic()` | mass/thrust only (cheap, every fp-stable refresh) |

Capabilities refresh calls `refresh_dynamic` so stage dV is not stale.
Do not call the full resource walk from a critical flight tick.

`layers[]` / `prop[]` fuel copies update on structural rebuild. Group
lexicons (`AOSO_TOPO_GROUPS`) are the live fuel view.

## Groups

Each `DECOUPLEDIN` group records parts, engines, tanks, legs, drills,
converters, RW/RCS, wet/dry mass, and stage-local `lf/ox/sf/xe/mp`.

Layers are sorted high-`DECOUPLEDIN` first. Display role: `BOOSTER` /
`STAGE` / `CORE`. Propulsion role (`prop_role`): same, overridden to
`LANDER` when the group has legs **and** engines.

`aoso_topo_fuel_of(decoupled_in)` is the resource-access view: a
particular engine group should use **that stage's tanks**, not vessel
totals.

`aoso_topo_prop_of(role)` returns the first prop group with that role
(LANDER / CORE / BOOSTER / STAGE).

## Crossfeed limitation (stock kOS)

kOS does not expose a reliable per-engine crossfeed graph. Topology
treats same-`DECOUPLEDIN` tanks as accessible to that group's engines.
That is usually right for serial stacks and onion staging. Asparagus
crossfeed across groups is an approximation: experience/measurement
can correct dV after the fact. Do not pretend it is exact.

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

Staging still **executes** in `staging.ks` via `aoso_staging_do`.
Topology predicts. Do not add a second independent drop calculator.

Hot-sep: the drop group is the parent-chain separator that this
`STAGE()` actually fires, not `DECOUPLEDIN = STAGE:NUMBER` (off-by-one).
Refuse to drop a group that still has MASSFLOW.

## Control / turn lead

`control.turn_lead_s` (50 / 70 / 80) is a cheap pointing estimate from
mass + RW/RCS. Maneuver align time uses the larger of this and
`MANEUVER_ALIGN_S`.

## Future TWR

`aoso_caps_surface_twr_for_config("LANDER", body)` uses LANDER+CORE
engines and group mass at the destination's sea-level pressure.
Pad launch TWR (`aoso_profile_surface_twr`) still uses all attached
engines — that is the live ship on the pad, not a Tylo landing.

`aoso_caps_twr_for_state` / `aoso_caps_dv_for_config` exist for
projected-state consumers; mission feas currently uses LANDER TWR
with live mass.

## When to rebuild

Full rebuild: boot, `profile_refresh`, fingerprint mismatch (stage,
dock, part count, control point), manual `aoso_topo_refresh(TRUE)`.

Never rebuild every physics tick.
