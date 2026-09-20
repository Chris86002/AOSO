# AOSO v2.2 architecture

AOSO is still a set of kOS FSMs (ascent, goto, descent, tour, …). v2
did not replace them. v2.2 puts one structural model, one projected-state
ledger, and a verify/authority layer under those machines.

```
OBSERVE
   ↓
TOPOLOGY / WORLD STATE
   ↓
CAPABILITIES
   ↓
PROJECT FUTURE STATE
   ↓
FEASIBILITY
   ↓
PLAN
   ↓
DECISION
   ↓
ACTION
   ↓
CONTROLLER  (existing FSMs; brain never flies)
   ↓
VERIFY RESULT
   ↓
MEASURE
   ↓
LEARN
   ↓
UPDATE MODEL
   ↓
REPLAN IF NEEDED
```

## Loop

| Step | What | Where |
|---|---|---|
| OBSERVE | Body, situation, fuel, EC, mass, nodes | `aoso_ctx_refresh_env`, `observe.ks` |
| TOPOLOGY | Structure, hw, stage groups, prop roles | `topology.ks` |
| DYNAMIC | Fuel/mass in-place (`dyn_rev`) | `aoso_topo_refresh_dynamic` |
| UNDERSTAND | Dirty flags + vehicle/budget refresh | `brain.ks` `aoso_brain_refresh_dirty` |
| CAPABILITIES | Live TWR + topology-backed stage dV | `capabilities.ks` |
| PROJECT | Sequential leftover ledger | `mission/project.ks` |
| FEASIBILITY | FEASIBLE / ORBIT_ONLY / SKIP from seq | `feasibility.ks` |
| CERTIFY / ASSURE | Attempt / continue / depart | `certify.ks`, `assurance.ks` |
| PREDICT | Analytical cost × bounded experience | `aoso_xp_apply` / `aoso_xp_predict` |
| DECIDE | Scores, route, nodes | `score.ks`, `route.ks`, porkchop |
| ACTION | Identity on `AOSO_ACTION_CUR` | `result.ks` `aoso_action_*` |
| EXECUTE | Existing FSMs | `ascent`, `goto`, `maneuver`, `descent` |
| AUTHORITY | Who may command steering/throttle/warp/stage | `authority.ks`, `aoso_staging_do` |
| MEASURE | Heartbeats + **verified** action results | `verify.ks`, `aoso_hb_set`, `aoso_result_emit` |
| LEARN | bounded primary cost plus secondary TIME / BURN_TIME / TWR corrections | `experience.ks` |
| UPDATE MODELS | XP/profile revisions dirty downstream feasibility/opportunity/route/plan state | events `MODEL_UPDATED`, `PROFILE_UPDATED` |
| REPLAN | Debounced `aoso_plan_build` when quiet | `aoso_brain_do_replan`, `aoso_plan_stale` |

## Source of truth (one writer per fact)

| Fact | Owner |
|---|---|
| Vessel structure | topology |
| Dynamic fuel / mass in groups | topology `refresh_dynamic` |
| Stage performance / live TWR | capabilities (from topology + live engines) |
| Mission costs | projected-state / feasibility |
| Strategic plan | planner |
| Control ownership | authority |
| Action success | verifier |
| Observed outcome | result |
| Learned correction | experience |
| Current snapshot | context |
| Replan policy | brain |

## Duplicate-path verdict

| Path | Verdict |
|---|---|
| `topology.ks` DECOUPLEDIN groups | KEEP — structural SSOT |
| `capabilities` independent part regroup | MIGRATE — uses `AOSO_TOPO_GROUPS` when populated; part-walk FALLBACK ONLY |
| `profile_surface_twr` all-engines | KEEP — pad/live launch TWR, not future Tylo |
| `aoso_caps_surface_twr_for_config` | KEEP — future LANDER/CORE/BOOSTER TWR |
| `experience.ks` | KEEP — operational prediction correction |
| `ascent_opt.ks` | KEEP — specialized start-speed search |
| `learn.ks` | DEMOTE — leftover-LF diary + XP circ migration source. Do not feed feas. |
| `parts.ks` engine lists | KEEP — live IGNITION/FLAMEOUT census; roles owned by topology |
| Independent hop_budget vs each cost | REMOVE — sequential `aoso_project_seq` |
| Tank Ore = biome empty | REMOVE — stall on no fuel/ore progress |

## Think windows

Expensive work (porkchop, route, feas catalog, `aoso_project_route`)
only runs when the ship can sit still:

- **Pad / landed / splashed** — calculate before launch if needed.
- **Bound orbit** with no burn in progress and no node inside
  `BRAIN_THINK_LEAD_S` (default 600 s).
- **Never** during `FLYING`, `SUB_ORBITAL`, atmosphere, or a live burn.
- **CPU CRITICAL** never thinks. **CPU HIGH** replans only if quiet.

`aoso_brain_wait_think(why)` holds up to `BRAIN_THINK_WAIT_S` for that
window, then calculates anyway. Porkchop calls it **once** at the start
of the grid, not per cell. Mid-course waits only if SOI is still more
than the lead time away.

Do not full-rebuild topology, matrix, route, XP aggregation, or JSON
persistence inside critical flight loops.

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
`Update-AOSO.ps1` is not part of this architecture and must not be
edited on this branch unless the user asks.
