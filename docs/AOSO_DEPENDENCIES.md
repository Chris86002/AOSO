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
→ checkpoints → feasibility → matrix → windows → score → route → planner
→ certify → assurance → goto → tour → mission → brain
→ docking → watchdog → HUD → telemetry
```

Function bodies may call later modules. Load-time code must not.

## Runtime graph

```
KSP / kOS observe
        ↓
  vessel topology
        ↓
  resources / capabilities / profile view
        ↓
  mission certification → assurance → planner → decision → action
        ↓
  authority / controller → verify → result
        ↓
  learning / health → re-certify → replan
```

## Scheduler tasks

| Task | Prio | Notes |
|---|---|---|
| goto, descent, auto_staging, mission, watchdog | 0 | flight |
| auto_power | 1 | until space deploy done |
| hud, brain, telemetry | 2 | shed at CRITICAL |
| vehicle_profile, checkpoint_autosave | 3 | shed at RED |

Brain interval 2 s. It drains at most 4 events per tick.

## Optional addons

Astrogator: intercept **seed** after porkchop misses. Never the only
path. KER: performance TWR fallback. Trajectories: unused by core.
