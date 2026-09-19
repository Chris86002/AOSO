# AOSO v2 architecture

AOSO is still a set of kOS FSMs (ascent, goto, descent, tour, …). v2 does
not replace them. It adds one executive loop so those machines share a
world, remember what worked, and replan when the world changes.

```
OBSERVE → UNDERSTAND → PREDICT → DECIDE → EXECUTE → MEASURE → LEARN → UPDATE MODELS → REPLAN
```

## Loop

| Step | What | Where |
|---|---|---|
| OBSERVE | Body, situation, fuel, EC, mass, nodes | `aoso_ctx_refresh_env`, `observe.ks` |
| UNDERSTAND | Dirty flags + vehicle/budget refresh | `brain.ks` `aoso_brain_refresh_dirty` |
| PREDICT | Analytical cost × bounded experience | `aoso_xp_apply` / `aoso_xp_predict` |
| DECIDE | Feasibility, scores, route, nodes | `feasibility.ks`, `score.ks`, `route.ks`, porkchop |
| EXECUTE | Existing FSMs. Brain never flies. | `ascent`, `goto`, `maneuver`, `descent` |
| MEASURE | Heartbeats + action results | `aoso_hb_set`, `aoso_result_emit` |
| LEARN | `actual/predicted` into XP models | `experience.ks` |
| UPDATE MODELS | Dirty feas/route after XP or profile | events `MODEL_UPDATED`, `PROFILE_UPDATED` |
| REPLAN | Debounced `aoso_plan_build` when quiet | `aoso_brain_do_replan` |

## Think windows

Expensive work (porkchop, route, feas catalog) only runs when the ship
can sit still:

- **Pad / landed / splashed** — calculate before launch if needed.
- **Bound orbit** with no burn in progress and no node inside
  `BRAIN_THINK_LEAD_S` (default 600 s).
- **Never** during `FLYING`, `SUB_ORBITAL`, atmosphere, or a live burn.

`aoso_brain_wait_think(why)` holds up to `BRAIN_THINK_WAIT_S` for that
window, then calculates anyway. Porkchop calls it **once** at the start
of the grid, not per cell. Mid-course waits only if SOI is still more
than the lead time away.

## Configuration identity

Experience is keyed `cfg_id|body|OP`, not `SHIP:NAME`. The id is locked
on the pad (`NAME|Mbucket|E|S|LF|ISRU|D`) and restored from
`0:/aoso_cfg_id.json` after a revert. Staging in flight does not mint a
new id.

## Events

Publish never calls a subscriber. `aoso_event_publish` queues (cap 32);
`aoso_brain_tick` drains at most 4. That avoids nested kOS stack blows
from PLAN → event → replan → PLAN.

## What must not change

Public function names, existing FSMs, the scheduler, and `ascent_opt`
stay. The brain is another scheduled task. It can request a replan; it
cannot steal steering or throttle.
