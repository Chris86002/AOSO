# CPU / IPU performance

`CONFIG:IPU = 2000` is **headroom, not a utilization target**.
AOSO still yields with `WAIT 0` and stops background work before the
protected opcode reserve.

## IPU configuration

One place: `AOSO_CONFIG["IPU_TARGET"]` (default 2000). `aoso_boot`
raises `CONFIG:IPU` to that value once. AOSO does not keep bumping IPU
in response to load.

## Protected reserve

```
reserve = max(CPU_RESERVE_ABS, CONFIG:IPU * CPU_RESERVE_FRAC, phase)
cap at 50% of IPU, floor 80
```

Defaults: abs 400, frac 0.18.

Phase reserves: COAST 250, ORBIT 350, ASCENT/MANEUVER 500,
DOCKING 600, DESCENT 650.

Scheduler tasks stop when `OPCODESLEFT < aoso_cpu_headroom()`.

## Priority classes (mapped onto existing 0–3)

| Class | Tasks | Load-shed |
|---|---|---|
| 0 CRITICAL | goto, descent, auto_staging, mission, watchdog | never delayed |
| 1 HIGH | power (until panels deployed) | runs at RED |
| 2 NORMAL | HUD, brain, telemetry | skipped at CRITICAL |
| 3 BACKGROUND | profile, checkpoint | skipped at RED+ |

## Load bands

Existing `AOSO_CPU_LEVEL` 0–3 maps to `GREEN / YELLOW / RED / CRITICAL`
via `aoso_cpu_band()`. Display names `NORMAL / ELEVATED / HIGH /
CRITICAL` stay for logs.

| Band | Behavior |
|---|---|
| GREEN | all tasks |
| YELLOW | background slowed (floor / skip_n) |
| RED | defer profile, checkpoints, expensive think if not quiet |
| CRITICAL | flight + safety only; brain will not think |

Events `CPU_LOAD_HIGH` / `CPU_LOAD_CRITICAL` fire on **name change**,
not every tick.

## Task profiling

Each scheduler task tracks `last_op`, `sum_op`, `max_op`,
`deferred_n`, `shed_n`. Enable `CPU_PROFILE` or `PROF_ENABLED` for
wall-time `last_dt` as well.

HUD DBG: IPU, used, left, band, deferred, shed.

## Safe compute windows

The brain already refuses expensive work unless
`aoso_brain_is_quiet()`: pad, landed, splashed, or a bound orbit with
no node inside `BRAIN_THINK_LEAD_S`. Replan requests during descent
stay queued until that window (or until CPU is not HIGH while flying).

## Flight-control first

Do not put `LIST PARTS`, JSON writes, route searches, HUD redraws,
or `aoso_project_route` inside ascent/descent/maneuver ticks.
Topology **rebuilds** are event-driven. `aoso_topo_refresh_dynamic`
is a fuel/mass walk (no HASMODULE census) from capabilities refresh,
not from steering. HUD rates already drop under HIGH/CRITICAL.

## Future modules

Document for each new task: priority class, frequency, event-driven?,
expected cost, safe to defer, which dirty flags trigger it.
