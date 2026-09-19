# Mission assurance

Assurance answers: *can this real spacecraft still finish the intended
mission?* It is not a second planner.

```
topology + profile + budget + experience
        ↓
  CERTIFY  (snapshot: can we attempt this mission?)
        ↓
  ASSURE   (continuation from the current state)
        ↓
  DEPART   (may I leave this surface / pad?)
```

## Preflight certification — `aoso_cert_eval`

Statuses:

| Status | Meaning |
|---|---|
| `CERTIFIED` | No known hard blocker. **Not a guarantee.** |
| `CONDITIONAL` | Warnings (Eve/Tylo TWR, no ISRU, no heatshield, …) |
| `NOT_CERTIFIED` | Hard blocker (no usable dV, certifying mid-ascent) |

Grand-tour Eve/Tylo/ISRU/heatshield issues are **warnings**, not hard
blocks: the planner still marks those bodies `ORBIT_ONLY` / `SKIP`
through feasibility. Certification names the risk; CAN still decides
membership.

Runs at boot, after topology-changing checkpoints, and every ~30 s
while the brain is quiet.

## Re-certification

Meaningful spacecraft changes dirty topology/vehicle. The brain
rebuilds the profile when quiet, then certifies again. Do not treat a
pad snapshot as truth after a booster drop or a Minmus refuel.

## Continuation — `aoso_assure_eval`

Health: `OK` / `TIGHT` / `AT_RISK` / `BLOCKED` / `FUEL`.

`weak_body` / `weak_margin` is the remaining planner target with the
smallest `mission_dv − transfer_dv`. It is a bottleneck hint, not a
full chain simulation.

## Departure certification — `aoso_depart_certify`

Mandatory before surface / pad launch.

| Status | Meaning |
|---|---|
| `READY` | TWR, fuel, and station-keeping look launchable |
| `READY_WITH_WARNING` | Launchable, but TWR/legs/takeoff table is tight |
| `NOT_READY` | TWR < 1.05, fuel < 8%, or sliding |

Tour `LAUNCH` (and pad `BOOT`) will **not** call `aoso_ascent_start`
while the status is `NOT_READY`. It holds and retries.

## Safe hold

`aoso_safe_hold(reason)` zeros throttle, releases steering, sets warp
0, drops authority, publishes `HOLD`. Use when the planner cannot
produce a safe action, topology mismatches a checkpoint, or a
controller fails. The ship should sit and re-evaluate, not loop a
dead command.

## Accomplishment vs visited

Tour `data["accomplished"][body]`:

`SKIPPED` / `ORBITED` / `LANDED` / `COMPLETED`

Passing through Jool SOI is not a Jool landing. Gas giants are
orbited. A `DEAD_END` lander is `ORBIT_ONLY` and marked `ORBITED` or
`SKIPPED`, never `COMPLETED`.
