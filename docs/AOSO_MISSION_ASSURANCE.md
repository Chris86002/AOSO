# Mission assurance

Assurance answers: *can this real spacecraft still finish the intended
mission?* It is not a second planner.

```
topology + profile + budget + experience
        ↓
  PROJECTED STATE  (remaining route ledger)
        ↓
  CERTIFY  (snapshot: can we attempt this mission?)
        ↓
  ASSURE   (continuation from the current state)
        ↓
  DEPART   (may I leave this surface / pad?)
```

Projected state (`AOSO_PROJECT_LAST`) is the source of leftover,
weakest remaining operation, next refuel, and return margin. Do not
compare each remaining destination independently against current dV.

## Preflight certification — `aoso_cert_eval`

Statuses:

| Status | Meaning |
|---|---|
| `CERTIFIED` | No known hard blocker. **Not a guarantee.** |
| `CONDITIONAL` | Warnings (Eve/Tylo LANDER TWR, no ISRU, no heatshield, projected route fail, weak margin) |
| `NOT_CERTIFIED` | Hard blocker (no usable dV, certifying mid-ascent) |

Grand-tour Eve/Tylo/ISRU/heatshield issues are **warnings**, not hard
blocks: the planner still marks those bodies `ORBIT_ONLY` / `SKIP`
through sequential feasibility. Certification names the risk; CAN
still decides membership. Eve/Tylo TWR is LANDER-config, not
booster-inclusive pad TWR.

Report copies `weakest` / `min_margin` from the projector when present.

Runs at boot, after topology-changing checkpoints, and every ~30 s
while the brain is quiet.

## Re-certification

Meaningful spacecraft changes dirty topology/vehicle. The brain
rebuilds the profile when quiet, then certifies again. Do not treat a
pad snapshot as truth after a booster drop or a Minmus refuel.

## Continuation — `aoso_assure_eval`

Health: `OK` / `TIGHT` / `AT_RISK` / `BLOCKED` / `FUEL`.

When `AOSO_PROJECT_LAST` exists:

| Field | Source |
|---|---|
| `weak_body` / `weak_margin` | sequential leftover at the worst remaining dest |
| `min_twr_margin` | projector `min_twr` (live caps TWR snapshot) |
| `next_refuel` | first remaining dest that can ISRU |
| `return_margin` | `end_dv` after the route walk |
| `confidence` | 0.75 when a projected route exists |

Fallback (no projector yet): remaining planner target with the
smallest `mission_dv − transfer_dv`.

## Departure certification — `aoso_depart_certify`

Mandatory before surface / pad launch.

| Status | Meaning |
|---|---|
| `READY` | TWR, fuel, and station-keeping look launchable |
| `READY_WITH_WARNING` | Launchable, but TWR/legs/takeoff table is tight |
| `NOT_READY` | Hard inability: LANDER TWR < 1.05, no propulsion, fuel < 8%, takeoff_dv > mission_dv, or still moving |

Tour `LAUNCH` (and pad `BOOT`) will **not** call `aoso_ascent_start`
while the status is `NOT_READY`. It holds and retries.

## Safe hold

`aoso_safe_hold(reason)` zeros throttle, releases steering, sets warp
0, drops authority, publishes `HOLD`. Use when the planner cannot
produce a safe action, topology mismatches a checkpoint, a controller
fails, or the watchdog escalates a non-critical stall. The ship
should sit and re-evaluate, not loop a dead command.

## Accomplishment vs visited

Tour `data["accomplished"][body]`:

`SKIPPED` / `ORBITED` / `LANDED` / `COMPLETED`

Passing through Jool SOI is not a Jool landing. Gas giants are
orbited. A `DEAD_END` lander is `ORBIT_ONLY` and marked `ORBITED` or
`SKIPPED`, never `COMPLETED`.
