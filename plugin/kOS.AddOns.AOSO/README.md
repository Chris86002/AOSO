# kOS.AddOns.AOSO

Optional native numerical backend for the AOSO KerboScript autopilot.

Phase 1 exposes Lambert; Phase 2 adds a chunked patched-conic porkchop candidate search. The DLL does **not** create maneuver
nodes, steer, throttle, stage, warp, or otherwise fly the vessel. AOSO's
KerboScript remains the executive and remains fully functional without this DLL.

## Requirements

- Kerbal Space Program 1.12.x
- kOS 1.3 or newer
- .NET Framework 4.6.1 targeting pack / a compatible Visual Studio or MSBuild
- The KSP install path supplied as `KSP_ROOT` when it is not the default Steam path

The project targets `net461` and references the KSP/kOS assemblies directly
from `KSP_ROOT`.

## Build

From this directory in a Visual Studio Developer Command Prompt:

```bat
dotnet build kOS.AddOns.AOSO.csproj -c Release -p:KSP_ROOT="C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program"
```

If your environment uses MSBuild instead of the .NET CLI:

```bat
msbuild kOS.AddOns.AOSO.csproj /p:Configuration=Release /p:KSP_ROOT="D:\Games\Kerbal Space Program"
```

The DLL is produced at:

```text
bin\Release\net461\kOS.AddOns.AOSO.dll
```

## Install

Create `<KSP>\GameData\AOSO\Plugins` if needed, then copy:

```bat
copy bin\Release\net461\kOS.AddOns.AOSO.dll "<KSP>\GameData\AOSO\Plugins\kOS.AddOns.AOSO.dll"
```

Restart KSP after installing or replacing the DLL. kOS discovers third-party
addons during KSP startup.

From KerboScript, AOSO itself performs detection through
`AOSO/core/addons.ks`. Other script modules must not access `ADDONS:AOSO`
directly.

## Exposed suffixes

- `ADDONS:AOSO:VERSION` — addon version string.
- `ADDONS:AOSO:LAMBERT(pos1, pos2, tof_s, mu [, long_way])` — native
  zero-revolution Vallado universal-variable Lambert solve.
- `ADDONS:AOSO:PORKCHOPSTART(hopBody, optionsLex)` — start the chunked
  patched-conic candidate search.
- `ADDONS:AOSO:PORKCHOPPOLL()` — run one bounded native search slice.
- `ADDONS:AOSO:PORKCHOPRESULT()` — retrieve completed candidate burns.
- `ADDONS:AOSO:PORKCHOP(hopBody, optionsLex)` — bounded one-shot convenience
  call; returns `async_required` if the search would exceed 40 ms.

The Lambert suffix returns a lexicon containing `ok`, `vel1`, `vel2`,
`err`, `src`, `z`, and `tof_err`. On invalid arguments or a numerical
failure it returns `ok=false` instead of throwing into the kOS VM.
`aoso_lambert_solve` still falls back to KerboScript when `ok=false` or
when `tof_err` exceeds `LAMBERT_TOF_TOL`.

## Fallback

Do not make the DLL a mission dependency. `aoso_lambert_solve` dispatches to
the native solver only when the addon is available, returns `ok=true`, and
includes a `tof_err` within `LAMBERT_TOF_TOL`. Otherwise it immediately uses
`aoso_lambert_solve_ks`, the original KerboScript implementation.


## Build and install helper

On Windows, build against the exact KSP/kOS assemblies and install the DLL with:

```powershell
.\Build-And-Install.ps1 -KspRoot "C:\Program Files (x86)\Steam\steamapps\common\Kerbal Space Program"
```

Restart KSP after replacing the DLL. The current assembly version is
`0.2.0.0`. AOSO selftest should report `native phase2 suffixes current`.
The first accepted Lambert and completed native porkchop search also emit
explicit native-active log messages.
