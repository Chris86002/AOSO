# kOS.AddOns.AOSO

Optional native numerical backend for the AOSO KerboScript autopilot.

Phase 1 exposes only the Lambert solver. The DLL does **not** create maneuver
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

The Lambert suffix returns a lexicon containing `ok`, `vel1`, `vel2`,
`err`, and `src`. On invalid arguments or a numerical failure it returns
`ok=false` instead of throwing into the kOS VM.

## Fallback

Do not make the DLL a mission dependency. `aoso_lambert_solve` dispatches to
the native solver only when the addon is available and returns `ok=true`.
Otherwise it immediately uses `aoso_lambert_solve_ks`, the original
KerboScript implementation.
