# Data ownership

One writer per fact. Readers go through the owning accessor.

| Fact | Owner | Readers |
|---|---|---|
| Part lists / engine list / docks | `parts.ks` cache | topology, staging, capabilities |
| Structure, hw census, stage groups | `topology.ks` | profile, vessel, classify, cert, surface, staging log |
| Capability flags / TWR / dV stack | `capabilities.ks` + `budget.ks` | planner, feas, HUD |
| Human/planner summary | `profile.ks` (view over topology) | classify, cert, HUD VEH |
| Class label | `classify.ks` (`AOSO_CLASS_LAST`) | CTX, HUD, route |
| World / body numbers | `bodydb.ks` + `world/body.ks` | feas, cert, matrix |
| Experience models | `experience.ks` keyed `cfg_id\|body\|OP` | feas costs |
| Plan / targets | `planner.ks` `AOSO_PLAN_LAST` | tour, assure, HUD |
| Events | `events.ks` queue | brain drain only |
| Action results / heartbeats | `result.ks` | XP, watchdog, HUD |
| Authority | `authority.ks` | steering wrappers |
| Warp deadlines | `warp.ks` | `aoso_warp_request` |
| Cert / assure snapshots | `certify.ks` / `assurance.ks` | brain, HUD, tour launch |
| Checkpoints | `checkpoints.ks` | boot compare, mission resume |
| CPU load | `observe.ks` | scheduler, HUD, brain |

## Persist files

| File | Owner | Survives reboot? |
|---|---|---|
| `0:/aoso_config.json` | config | yes |
| `0:/aoso_cfg_id.json` | context | yes (launch identity) |
| `0:/aoso_xp.json` | experience | yes |
| `0:/aoso_checkpoints.json` | checkpoints | yes, loaded every boot |
| `0:/aoso_profile.json` | profile | overwritten |
| `0:/aoso_route.json` | planner | overwritten |
| `0:/aoso_log.txt` / events / telemetry | observe/logger | **wiped every boot** |

Topology, cert, and assure are RAM-only. After a restart, rebuild
topology from the live ship, compare checkpoint `topo_fp` / body /
status, then re-certify. Prefer observed state over the saved
expectation.

Persistent schema changes require a migration in the loader, not a
silent new required key.
