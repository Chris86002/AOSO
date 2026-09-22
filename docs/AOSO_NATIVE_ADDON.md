# AOSO native addon

`kOS.AddOns.AOSO` is an optional numerical backend for AOSO. It moves selected
heavy mathematical routines from the kOS VM into C# running inside KSP while
leaving mission decisions and flight control in KerboScript.

It is **not** another autopilot. It does not create/remove maneuver nodes,
command steering or throttle, stage, warp, or decide whether an intercept is
safe to burn. The brain still never flies.

## Install

Build `plugin/kOS.AddOns.AOSO/kOS.AddOns.AOSO.csproj` and copy the resulting
DLL to:

```text
<KSP>/GameData/AOSO/Plugins/kOS.AddOns.AOSO.dll
```

Restart KSP after changing the DLL.

kOS registration can be checked with:

```kos
PRINT ADDONS:HASADDON("AOSO").
```

AOSO production scripts must not use that expression directly. All addon access
is centralized in `AOSO/core/addons.ks`.

## Phase 1 API

| Suffix | Returns | Purpose |
|---|---|---|
| `ADDONS:AOSO:VERSION` | String | Native addon version |
| `ADDONS:AOSO:LAMBERT(pos1, pos2, tof_s, mu [, long_way])` | Lexicon | Zero-revolution Lambert solution |

Lambert result keys are:

| Key | Type | Meaning |
|---|---|---|
| `ok` | Boolean | Native solve succeeded |
| `vel1` | Vector | Inertial departure velocity, m/s |
| `vel2` | Vector | Inertial arrival velocity, m/s |
| `err` | String | Empty on success; short failure reason otherwise |
| `src` | String | Always `"native"` |
| `z` | Scalar | Universal-variable root (0 for the 180° vis-viva path) |
| `tof_err` | Scalar | Absolute seconds of `|t(z) - TOF|` |

The implementation uses the Vallado universal-variable formulation with
radian trigonometry and a bracketed zero-revolution root solve. The 180-degree
singularity uses a **0.45°** vis-viva fallback (TOF-aware SMA). A 2.5° band
used to return Hohmann speed for the wrong flight time. `aoso_lambert_solve`
rejects a native `ok=true` result when `tof_err` exceeds `LAMBERT_TOF_TOL`
and falls back to KerboScript.

## KerboScript dispatch and fallback

The stable public function remains:

```kos
aoso_lambert_solve(pos1, pos2, tof_s, mu, long_way)
```

The original solver is retained as `aoso_lambert_solve_ks`. The public
function asks `core/addons.ks` for the native backend and uses the native
solution only when it returns a lexicon with `ok=true` and, if present,
`tof_err` within `LAMBERT_TOF_TOL`. Missing DLL, missing suffix, invalid
input, a native numerical non-solution, or a TOF miss falls back to
KerboScript.

That means installing this DLL is a performance optimization, not a
capability requirement.

## Capture safety

Phase 1 changes only Lambert math. Porkchop candidate generation, node
creation, patched-conic evaluation, and `aoso_rendezvous_finalize_node`
remain KerboScript. The native addon does not declare a graze acceptable and
cannot bypass the capture-periapsis gate.

## Build

See `plugin/kOS.AddOns.AOSO/README.md`. Typical Windows build:

```bat
dotnet build plugin\kOS.AddOns.AOSO\kOS.AddOns.AOSO.csproj -c Release -p:KSP_ROOT="<KSP>"
```

The project targets .NET Framework 4.6.1 and declares a minimum kOS assembly
dependency of 1.3.

## Architecture rule

**Brain never flies.** Native code may accelerate pure numerical work; control,
verification, authority, maneuver-node ownership, and final intercept
acceptance remain with AOSO's existing KerboScript modules.
