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
| 2 NORMAL | brain, telemetry | skipped at CRITICAL |
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

`0:/aoso_cpu.csv` is the comparison file. It appends one row per task
every `CPU_TRACE_S` real seconds (default 5; `0` turns the timer off)
and again whenever the CPU band or flight phase changes. The previous
boot is kept as `0:/aoso_cpu_prev.csv`.

`win_avg`, `win_runs`, `win_deferred`, and `win_shed` are only the
time since the previous sample, so ascent and landing do not average
together. `last_op` is the most recent run. `max_op` is the worst
single run since boot. `why` is `timer`, `band`, `phase`, `band+phase`, or `boot`.
Rows for tasks that did nothing in a timer window are omitted.

## Safe compute windows

The brain already refuses expensive work unless
`aoso_brain_is_quiet()`: pad, landed, splashed, or a bound orbit with
no node inside `BRAIN_THINK_LEAD_S`. Replan requests during descent
stay queued until that window (or until CPU is not HIGH while flying).

## Flight-control first

Do not put `LIST PARTS`, JSON writes, route searches,
or `aoso_project_route` inside ascent/descent/maneuver ticks.
Topology **rebuilds** are event-driven. `aoso_topo_refresh_dynamic`
is a fuel/mass walk (no HASMODULE census) from capabilities refresh,
not from steering.

## Future modules

Document for each new task: priority class, frequency, event-driven?,
expected cost, safe to defer, which dirty flags trigger it.


## Physics-tick control discipline

kOS runs the CPU against KSP physics FixedUpdate ticks. AOSO measures actual
simulated delta-time as `AOSO_PHYS_DT` at the start of every main-loop
slice; it does not assume 0.02 s.

During ASCENT/BURN/DESCENT/LANDING, `TICK_DEBUG` samples a compact in-memory
trace: UT, measured dt, warp/mode, opcodes left, commanded throttle, orbital
speed, vertical speed, node remaining dV, and node ETA. It intentionally does
not write a file every tick. The existing flight-recorder ring is dumped
around burn/anomaly/stage events, preserving the useful pre-event history.

Maneuver throttle also has a last-line per-tick guard. Estimated dV delivered
during the next measured physics tick is capped by `MANEUVER_TICK_GUARD`.
This is specifically for short burns and coarse/physics-warp ticks.

Flight control remains ahead of telemetry and background work.

## RAM caches

Caches are RAM only. A miss or a forced rebuild is the correct value.
Disk JSON is not a hot path and is never written from ascent, descent,
or maneuver ticks.

| What | Key | Owner | Never cache |
|---|---|---|---|
| `LIST PARTS` / `ENGINES` / `DOCKINGPORTS`, uid→part | `aoso_parts_cache_fp()` = part count \| stage \| root UID \| control UID. `STAGE:NUMBER` is the fast reject. `aoso_parts_cache_invalidate()` after `STAGE()`. | `parts.ks` | Steering, throttle, `MASSFLOW`, `NEXTNODE:BURNVECTOR` |
| Topology structure | Same fingerprint. `rev` increments only on rebuild. | `topology.ks` | Live part/engine/module refs in JSON |
| Group fuel / mass | `dyn_rev`. Skip when fp is unchanged and mass / vessel LF / OX are inside epsilon. Walks tank UIDs only. | `aoso_topo_refresh_dynamic` | Full `HASMODULE` census |
| Typed uid lists (tanks, engines-by-group, seps, solar, drills, converters, chutes, legs) | Topology `rev` / `idx` | `topology.ks` | A second census in profile, classify, or vessel once `rev` exists |
| Body constants and Hohmann pair (MU, radius, ATM, period, SMA, required phase, TOF, v_inf) | Body name, `from\|to` | `windows.ks` (body set check in `bodydb.ks`) | Live phase, wait, efficiency |
| Feasibility row, matrix row | `dest\|rev_topo\|rev_budget\|rev_world\|rev_xp` | `feasibility.ks` / `matrix.ks` | Approval of a burn |
| Project leftover | `plan_n\|targets\|rev_budget\|rev_xp` | `project.ks` | |
| Descent radar offset, ascent stack layout, bounds offset | Topology `rev` (legs-extending still resamples bounds) | descent / ascent | Live `ALT:RADAR` and throttle |
| KS Lambert inside one search | Quantized pos1, pos2, tof, mu, long-way | `lambert.ks` | Native Lambert path |
| Last KS intercept candidate | Hop, epoch bucket, and no `SOI_CHANGED` / `MANEUVER_FAILED` / `VEHICLE_CHANGED` since store | `rendezvous.ks` | Capture PE gate (`finalize_node` still runs) |

`AOSO_CPU_LEVEL >= 2` skips matrix, project, and window-static fills unless `aoso_brain_is_quiet()`. Level 3 remains flight and safety only. Debug lines are `CACHE hit|miss <class> key=...` with class `parts`, `topo_dyn`, `feas`, `window`, or `lambert`.

