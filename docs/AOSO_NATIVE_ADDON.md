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

## Native API

| Suffix | Returns | Purpose |
|---|---|---|
| `ADDONS:AOSO:VERSION` | String | Native addon version |
| `ADDONS:AOSO:LAMBERT(pos1, pos2, tof_s, mu [, long_way])` | Lexicon | Zero-revolution Lambert solution |
| `ADDONS:AOSO:PORKCHOP(hopBody, optionsLex)` | Lexicon | Bounded one-shot candidate search; returns `async_required` if the full search would exceed 40 ms |
| `ADDONS:AOSO:PORKCHOPSTART(hopBody, optionsLex)` | Lexicon | Start a chunked native patched-conic search |
| `ADDONS:AOSO:PORKCHOPPOLL()` | Lexicon | Run one bounded search slice |
| `ADDONS:AOSO:PORKCHOPRESULT()` | Lexicon | Return completed candidate burns |

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
solution only when it returns a lexicon with `ok=true` **and** a `tof_err`
within `LAMBERT_TOF_TOL`. Older DLLs that omit `tof_err` fall back to
KerboScript so a 2.5° vis-viva band cannot poison intercepts. Missing DLL,
missing suffix, invalid input, a native numerical non-solution, or a TOF
miss also falls back.

That means installing this DLL is a performance optimization, not a
capability requirement.

## Capture safety

Phase 1 moves Lambert math native. Phase 2 may generate and patch-check
porkchop **candidates** natively, but it still cannot approve a burn.

`nav/rendezvous.ks` re-applies returned radial/normal/prograde values to an
ordinary kOS node and runs `aoso_rendezvous_finalize_node`. If no native
candidate passes that existing capture-PE gate, the node is removed and the
original KerboScript porkchop grid runs as the behavioral oracle/fallback.

The addon never creates or removes maneuver nodes and never commands steering,
throttle, staging, or warp.

## Build

See `plugin/kOS.AddOns.AOSO/README.md`. Typical Windows build:

```bat
dotnet build plugin\kOS.AddOns.AOSO\kOS.AddOns.AOSO.csproj -c Release -p:KSP_ROOT="<KSP>"
```

The project targets .NET Framework 4.8 and declares a minimum kOS assembly
dependency of 1.3.

## Architecture rule

**Brain never flies.** Native code may accelerate pure numerical work; control,
verification, authority, maneuver-node ownership, and final intercept
acceptance remain with AOSO's existing KerboScript modules.


## Phase 2 porkchop search

The Phase 2 search mirrors the current KerboScript search geometry rather than
an older approximation:

- 8 coarse departure samples plus SOI-sized fine samples around the Hohmann
  window.
- Lambert seed TOFs from `PORKCHOP_TOF_MIN` through
  `PORKCHOP_TOF_MAX`, capped at six samples plus the Hohmann TOF.
- Lambert seeds aim beside the target body at the desired parking altitude.
- The base prograde × normal patched-conic grid is preserved.
- Densification uses the current SOI-sized time step and 8 m/s dV/normal
  increments.
- Native scoring receives the current KerboScript PE minimum and maximum,
  including `INTERCEPT_PE_MAX_MULT`.

The default production path is asynchronous:

1. `PORKCHOPSTART` snapshots `shared.Vessel` and creates one search job for
   that kOS processor.
2. `PORKCHOPPOLL` evaluates at most 64 cells and stops after about 8 ms of
   main-thread native work.
3. KerboScript executes `WAIT 0` between polls.
4. `PORKCHOPRESULT` returns up to 20 candidates.

This keeps KSP API calls on the main thread and avoids a single long native
call. The convenience `PORKCHOP` suffix has a hard 40 ms one-shot budget and
returns `async_required` if it cannot finish.

Returned candidates use the existing keys `ut`, `pg`, `rad`, `nml`,
`sc`, `dv`, and `pe`. Native PE is diagnostic/ranking data only; final
acceptance is always KerboScript.

## Runtime proof

When the loaded DLL is actually used, AOSO logs:

- `Native AOSO Lambert active v...` on the first accepted native Lambert
  result.
- `Native AOSO porkchop active v...` when a native Phase 2 result completes.

`AOSO/dev/selftest.ks` also fails `native phase2 suffixes current` if an
older Phase 1-only DLL is loaded.
