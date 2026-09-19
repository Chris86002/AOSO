# AOSO v2.2 architecture

AOSO is still a set of kOS FSMs (ascent, goto, descent, tour, …). v2
did not replace them. v2.2 puts a single structural model and a
verify/authority layer under those machines.

```
OBSERVE → TOPOLOGY → CAPABILITY → CERTIFY → PLAN
→ DECISION → ACTION → AUTHORITY/CONTROLLER → VERIFY → RESULT
→ LEARN → RE-CERTIFY → REPLAN
```

## Loop

| Step | What | Where |
|---|---|---|
| OBSERVE | Body, situation, fuel, EC, mass, nodes | `aoso_ctx_refresh_env`, `observe.ks` |
| TOPOLOGY | Structure, hw, stage groups, next drop | `topology.ks` |
| UNDERSTAND | Dirty flags + vehicle/budget refresh | `brain.ks` `aoso_brain_refresh_dirty` |
| CERTIFY / ASSURE | Can we attempt / continue / depart | `certify.ks`, `assurance.ks` |
| PREDICT | Analytical cost × bounded experience | `aoso_xp_apply` / `aoso_xp_predict` |
| DECIDE | Feasibility, scores, route, nodes | `feasibility.ks`, `score.ks`, `route.ks`, porkchop |
| EXECUTE | Existing FSMs. Brain never flies. | `ascent`, `goto`, `maneuver`, `descent` |
| AUTHORITY | Who may command steering/throttle/warp | `authority.ks` |
| MEASURE | Heartbeats + **verified** action results | `verify.ks`, `aoso_hb_set`, `aoso_result_emit` |
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
- **CPU CRITICAL** never thinks. **CPU HIGH** replans only if quiet.

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

Also: `HOLD`, `CPU_LOAD_HIGH`, `CPU_LOAD_CRITICAL`, `NAV_FALLBACK`,
`CORRECT_REQUESTED`. `PLAN_UPDATED` is published after a replan; the
brain does not subscribe to it.

## IPU

`IPU_TARGET` 2000 is applied once at boot. Protected opcode reserve
(abs + fraction + phase) keeps leftover for steering. See
`docs/AOSO_PERFORMANCE.md`.

## What must not change

Public function names, existing FSMs, the scheduler run-loop, and
`ascent_opt` stay. The brain is another scheduled task. It can request
a replan; it cannot steal steering or throttle. Authority is who may
command; verify is whether the action worked.
