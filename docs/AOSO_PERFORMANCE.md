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

`0:/aoso_cpu.csv` is the comparison file. It appends one row per task
every `CPU_TRACE_S` real seconds (default 5; `0` turns the timer off)
and again whenever the CPU band or flight phase changes. The previous
boot is kept as `0:/aoso_cpu_prev.csv`.

`win_avg`, `win_runs`, `win_deferred`, and `win_shed` are only the
time since the previous sample, so ascent and landing do not average
together. `last_op` is the most recent run. `max_op` is the worst
single run since boot. `hud_fast` is the instrument path outside the
scheduler. `why` is `timer`, `band`, `phase`, `band+phase`, or `boot`.
Rows for tasks that did nothing in a timer window are omitted.

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

Fast HUD painting is decimated with `HUD_FAST_EVERY` and only runs when
there is headroom above the protected reserve. Flight control remains ahead
of display work.
