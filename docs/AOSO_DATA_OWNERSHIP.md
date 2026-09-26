# Data ownership

One writer per fact. Readers go through the owning accessor.

| Fact | Owner | Readers |
|---|---|---|
| Part lists / engine list / docks | `parts.ks` cache | topology, staging, capabilities |
| Structure, hw census, stage groups, prop roles | `topology.ks` | profile, vessel, classify, cert, surface, staging log |
| Dynamic group fuel / mass | `aoso_topo_refresh_dynamic` | capabilities stage dV |
| Capability flags / live TWR / dV stack | `capabilities.ks` + `budget.ks` | planner, feas |
| Future LANDER/CORE TWR | `aoso_caps_surface_twr_for_config` | feas, cert, depart |
| Human/planner summary | `profile.ks` (view over topology) | classify, cert |
| Class label | `classify.ks` (`AOSO_CLASS_LAST`) | CTX, route |
| World / body numbers | `bodydb.ks` + `world/body.ks` | feas, cert, matrix |
| Sequential leftover / projected state | `project.ks` `AOSO_PROJECT_LAST` | feas, matrix leftover, score, cert, assure, surface fill |
| Experience models | `experience.ks` keyed `cfg_id\|body\|OP` | feas / project costs |
| Ascent leftover-LF diary | `learn.ks` (demoted) | operator stats only |
| Ascent start-speed search | `ascent_opt.ks` | pad trials |
| Plan / targets | `planner.ks` `AOSO_PLAN_LAST` | tour, assure |
| Events | `events.ks` queue | brain drain only |
| Open action / result identity | `result.ks` `AOSO_ACTION_CUR` | XP, watchdog |
| Authority | `authority.ks` | steering wrappers, `aoso_staging_do` |
| Warp deadlines | `warp.ks` | `aoso_warp_request` |
| Cert / assure snapshots | `certify.ks` / `assurance.ks` | brain, tour launch |
| Surface executive phase | `surface/operations.ks` `AOSO_SURFACE_LAST` | tour REFUEL |
| Checkpoints | `checkpoints.ks` | boot compare, mission resume |
| CPU load | `observe.ks` | scheduler, brain |
| Current system snapshot | `context.ks` `AOSO_CTX` | everyone (read) |
| Replan policy | `brain.ks` | — |

## Who answers what

| Question | Answer |
|---|---|
| Who owns vessel structure? | topology |
| Who owns dynamic resource state? | topology `refresh_dynamic` + resources for vessel totals |
| Who predicts stage performance? | capabilities from topology groups + live engines |
| Who predicts mission costs? | projected-state / feasibility |
| Who chooses destination? | planner (route from scores; CAN from matrix) |
| Who starts an action? | controller via `aoso_decide` + `aoso_action_create/begin` |
| Who owns controls? | authority (`STEERING`/`THROTTLE`/`STAGING`/`WARP`/…) |
| Who determines success? | verifier (`core/verify.ks`) |
| Who stores learned corrections? | experience |
| Who requests replans? | brain (events + watchdog REPLAN + dirty flags) |

## Persist files

| File | Owner | Survives reboot? |
|---|---|---|
| `0:/aoso_config.json` | config | yes |
| `0:/aoso_cfg_id.json` | context | yes (launch identity) |
| `0:/aoso_xp.json` | experience | yes |
| `0:/aoso_checkpoints.json` | checkpoints | yes, loaded every boot |
| `0:/aoso_profile.json` | profile | overwritten |
| `0:/aoso_route.json` | planner | overwritten |
| `0:/aoso_matrix.json` | matrix | overwritten |
| `0:/aoso_log.txt` / events / telemetry | observe/logger | **wiped every boot** |

Topology, cert, assure, and projected route are RAM-only. After a
restart, rebuild topology from the live ship, compare checkpoint
`topo_fp` / body / status, then re-certify. Prefer observed state
over the saved expectation.

Persistent schema changes require a migration in the loader, not a
silent new required key. Current `SCHEMA_VERSION` is 2. Missing key
on read = v1.
