# Projected vehicle state

`AOSO/mission/project.ks` is the mission-cost ledger. It does **not**
fly the ship. Feasibility, certification, assurance, refuel fill, and
1-hop lookahead consume it. They must not each keep a second copy of
remaining dV.

Do not name `FUNCTION aoso_project` — `GLOBAL AOSO_PROJECT_LAST` would
collide (kOS identifiers are case-insensitive).

```
KSP live state / budget
        ↓
  aoso_project_state_current
        ↓
  aoso_project_seq / aoso_project_leg / aoso_project_route
        ↓
  feasibility · matrix leftover · certify · assure · score
```

## State

```
body, situation, mass, fuel_mass, fuel_pct,
dv_remaining, reserve_remaining,
topology_revision, configuration_id,
refueled, landed, orbiting,
ok, fail_step, last_step, last_cost,
confidence
```

Clone + `aoso_project_apply_cost(state, step, dv)` is the only way a
step spends dV. A failed state stays failed.

## Sequential accounting

A destination is **not** a set of independent comparisons against the
original hop budget. It is:

```
START  hop_budget
  ↓ transfer_only   (transfer_cost − dest capture)
STATE after transfer
  ↓ capture
STATE after capture   → orbit possible?
  ↓ land
STATE after land      → land possible?
  ↓ optional ISRU reset to full_tank
STATE after refuel
  ↓ takeoff
STATE leftover        → continuation SAFE / LOW / DEAD_END
```

`aoso_project_seq(start, transfer, capture, land, takeoff, do_refuel,
full_tank)` is deterministic (no `SHIP` reads) and is what selftest
uses. Example:

```
start 5000, transfer 3000, capture 1500, land 1000

reach  yes   leftover 2000
orbit  yes   leftover  500
land   no    leftover  500  (does not pay takeoff)
```

### Capture is not double-counted

`aoso_feas_transfer_cost` already includes destination capture.
`aoso_project_xfer_only(transfer, capture)` subtracts capture when
`transfer >= capture`, otherwise returns transfer. Public so
feasibility, goto, and tests share one rule.

## Public operations

| Function | What |
|---|---|
| `aoso_project_state_blank` / `clone` / `state_current` | Snapshot |
| `aoso_project_apply_cost` | Deduct one step |
| `aoso_project_xfer_only` | Split transfer vs capture |
| `aoso_project_seq` | Deterministic hop ledger |
| `aoso_project_costs(from, dest)` | XP-corrected + margin costs |
| `aoso_project_transfer` / `capture` / `land` / `refuel` / `takeoff` / `return` | One operation on a state |
| `aoso_project_leg` | Full dest: xfer → capture → land → optional ISRU → takeoff |
| `aoso_project_route` | Walk remaining plan; write `AOSO_PROJECT_LAST` |
| `aoso_project_lookahead_bonus` | 1-hop leftover score delta |

`aoso_project_costs` applies `aoso_xp_apply` **before** `FEAS_DV_MARGIN`.

## `AOSO_PROJECT_LAST`

Written by `aoso_project_route` (planner, after `route_build`). Never
from a critical flight tick.

```
order, legs{ dest → have_in, leftover_out, margin, ok, fail_step, refueled },
weakest, min_margin, min_twr, next_refuel, ok, end_dv, end_body, at
```

## Who consumes it

| Consumer | How |
|---|---|
| `aoso_feas_evaluate` | `aoso_project_seq` for reach/orbit/land/takeoff; leftover is seq leftover |
| `aoso_matrix_row` | Stores `leftover_dv`; cells still stacked vs original `have` (no double-deduct across destinations) |
| `aoso_opp_score` | 1-hop bonus from route legs, else matrix `leftover_dv` |
| `aoso_cert_eval` | Weakest / min_margin warnings |
| `aoso_assure_eval` | Weakest remaining, return_margin, next_refuel, min TWR |
| `aoso_refuel_needed_pct` | Next hop = `xfer_only + capture` |

## Lookahead (1 hop, not a search)

Opportunity scores still do **not** decide CAN. After a candidate's
own cost, leftover ≥ 1500 adds +8, ≥ 600 adds +3, leftover < 0 or
`ok=false` subtracts. Chicken-egg: `opp_build` runs **before**
`project_route` on the first plan, so that pass uses matrix
`leftover_dv`. Later replans see route legs. Do not loop-rebuild
(IPU).

## Limitations

- Mass / fuel_mass in the projected state are stamped from the live
  ship, not integrated as tanks drain. dV is the ledger, not a
  rocket-equation restack after each burn.
- Crossfeed is still `DECOUPLEDIN` groups (see `AOSO_TOPOLOGY.md`).
- Return cost is continuation (`leftover` vs `return_dv`), not a
  seventh sequential hop inside `aoso_project_seq`.
- `aoso_feas_evaluate` still has a conservative independent takeoff
  gate vs hop_budget; sequential leftover is the hard fail.
- Via-parent ISRU hops can grant `can_reach` after seq transfer
  failed; that path is not a second full seq walk.
