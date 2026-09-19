# Module dependencies

Stock KSP + kOS only. Optional addons (Astrogator, KER, Trajectories)
are seeds, never hard requirements.

## Load order (`main.ks`)

```
constants → json → logger → addons → config
→ state → scheduler → observe
→ context → events → result → authority → verify → warp → boot
→ vessel → parts → topology → capabilities → performance
→ resources → staging → profile → budget → learn → experience → classify
→ steering → maneuver → ascent_opt → ascent
→ nav → interplanetary → world
→ landing → power → isru → surface/operations
→ return → precision
→ checkpoints → feasibility → project → matrix → windows → score → route → planner
→ certify → assurance → goto → tour → mission → brain
→ docking → watchdog → HUD → telemetry
```

Function bodies may call later modules. Load-time code must not.

Do not name `FUNCTION aoso_project` or `FUNCTION aoso_surface`.

## Runtime graph

```
KSP LIVE STATE
      ↓
PART CACHE
      ↓
TOPOLOGY  (+ dynamic group fuel)
      ↓
CAPABILITY MODEL
      ↓
PROJECTED STATE ENGINE
      ↓
FEASIBILITY
      ↓
CAPABILITY MATRIX
      ↓
OPPORTUNITY SCORING
      ↓
ROUTE / PLAN
      ↓
DECISION
      ↓
ACTION
      ↓
AUTHORITY OWNER
      ↓
CONTROLLER
      ↓
POSTCONDITION VERIFICATION
      ↓
RESULT
      ↓
EXPERIENCE
      ↓
MODEL CORRECTION
      ↓
DIRTY FLAGS / REPLAN
```

## Scheduler tasks

| Task | Prio | Notes |
|---|---|---|
| goto, descent, auto_staging, mission, watchdog | 0 | flight |
| auto_power | 1 | until space deploy done |
| hud, brain, telemetry | 2 | shed at CRITICAL |
| vehicle_profile, checkpoint_autosave | 3 | shed at RED |

Brain interval 2 s. It drains at most 4 events per tick.

`aoso_project_route`, full topology rebuild, matrix rebuild, route
rebuild, XP aggregation, and JSON persistence are think-window work.

## Optional addons

Astrogator: intercept **seed** after porkchop misses. Never the only
path. KER: performance TWR fallback. Trajectories: unused by core.
