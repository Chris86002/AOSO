# Encounter warp and disappearing patches

AOSO's GOTO controller uses KSP's live `NEXTPATCH` when available. KSP may
temporarily remove a moon encounter patch during rails warp even when the
vessel continues toward the moon. A missing patch alone is not a missed
intercept.

The Minmus flight log showed the patch vanish at UT 285387, after which AOSO
kept coasting toward its saved SOI time. At UT 424319 the saved clock said 38 s
to SOI, so AOSO unpacked to 1x. The vessel was still in Kerbin's SOI. The
watchdog then called the deliberate wait a stall and placed the mission in
safe hold. The 600 s saved-time grace expired and GOTO replanned. A later
10000x coast also skipped a maneuver node when a safety downshift waited for
KSP's warp-settled flag.

For a moon orbiting the vessel's current body, the missing-patch path now
checks live moon range, SOI radius, and radial closing speed in the common
parent frame. It uses that rolling range clock when the saved patch ETA is
near or when live geometry predicts an earlier crossing. The clock is
deliberately early and capped at a one-hour coast horizon, so AOSO rechecks
the approach often. It only extends trust while the moon is closing and the
estimated boundary is within one day. If range says the vessel is already
inside the SOI but KSP has not switched bodies, it waits at 1x and logs the
handoff discrepancy. Other target types retain the original patch logic.

The watchdog now treats a GOTO `COAST` or `WAIT` as an intentional wait while
preserving its critical fuel/power abort check. Rails downshifts are issued
even while KSP reports a warp-rate transition in progress, and 100000x/10000x
are retired farther from critical events.

To diagnose a later encounter, retain `aoso_log.txt`, `aoso_events.csv`,
`aoso_telemetry.csv`, `aoso_flightrec.txt`, and the game save near the
transition. A `GOTO` line without a live patch now prints the selected clock,
saved ETA, moon range/SOI radius, closing speed, and current warp rate. Verify
that a `RANGE` clock is accompanied by positive closing speed and a range
approaching the SOI radius; a receding moon should trigger re-planning
rather than indefinite warp.
