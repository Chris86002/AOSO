# AOSO UI v2 — Flight Deck Architecture

AOSO UI v2 is a clean-room graphical avionics rewrite for the autonomous
grand-tour computer.

The interaction/display techniques were studied from
`giuliodondi/kOS-Shuttle-OPS3`, especially its use of kOS GUI layouts,
image-backed widgets, moving bugs/pippers, trajectory/situation displays,
sliders, phase annunciation, decluttering, and separate HUD/MFD surfaces.

**No OPS3 source code or image asset is copied into AOSO.** The referenced
repository currently does not publish a license. AOSO therefore implements
its own display model, renderer, artwork, naming, and mission-specific
instruments.

## Non-negotiable architecture rule

The UI is never a flight controller.

```text
guidance / mission / vehicle / world models
                    |
                    v
              hud_data.ks
                    |
                    v
             UI v2 renderers
          /         |          \
 tactical HUD      MFD       flight-director vectors
```

A GUI failure must not stage, steer, throttle, warp, retarget, or change a
mission state. UI callbacks may change display mode/page/filter only.

Existing `AOSO_HUD_DATA`, alerts, flight-director vectors, digital-twin
model, event history, and telemetry bus remain the data foundation.

## Display surfaces

### Tactical glass HUD

`ui2_hud.ks`

A separate draggable flight-director window for high-workload flight:

- image-backed central flight-director frame;
- moving commanded-attitude diamond/pipper;
- heading, velocity, altitude/radar altitude, vertical speed;
- vertical-speed tape;
- burn/fuel progress tape;
- maneuver/SOI/landing annunciation;
- master caution / warning takeover;
- phase-driven declutter plus manual DCL;
- day/night text brightness;
- REC position reset;
- MFD button to return to the full mission computer.

This is the AOSO adaptation of OPS3's separate HUD philosophy. It is not a
copy of the Shuttle symbology: the information is tailored to rockets,
transfers, capture, survey and powered landing.

### Primary Flight Display (PFD)

`ui2_instruments.ks`

The FLT page is now a graphical PFD with a smoothly moving guidance bug.
The pipper projects the current AOSO steering target into the vessel frame.
Speed, altitude, attitude, TWR, throttle, propellant and system state surround
the central director.

### Navigation Situation Display

The NAV page uses an image-backed situation display with:

- ship bug;
- target/SOI bug;
- maneuver-node bug;
- recent-position trail;
- AP/PE/inclination;
- next patch and ETA;
- node dV and burn remaining;
- explicit course-quality annunciation such as
  `ROUGH / SAFE`, `MANEUVER READY`, `BURN EXECUTION`, and
  `UNEXPECTED PATCH`.

The orbit drawing is intentionally marked **SCHEMATIC**. It communicates
navigation state and timing without pretending to be KSP's full map-view
patched-conic renderer.

### Mission / Grand Tour display

`ui2_mfd.ks`

The mission page has an avionics-style route strip:

- up to 16 visible destination tiles;
- green completed destinations;
- amber current destination;
- dark future destinations;
- skip state;
- mission phase and current body;
- tour progress bar;
- active objective;
- mission / total dV and electrical state.

Strategic replanning can change the route strip without rebuilding the GUI.

### Vehicle / graphical digital twin

The VEH page now hosts a graphical topology area backed by the existing
AOSO digital-twin model:

- topology bands;
- tanks, engines, command, power, ISRU and other grouped nodes;
- live tank/resource percentages;
- live engine state;
- stage changes;
- click a node to use AOSO's existing in-world part highlight;
- limited/aggregated status for large vessels.

The legacy engineering TWIN page remains available during the UI v2 soak
period and is the unrestricted detailed view.

### Surface survey display

The SURFACE/LND display adapts the OPS3 situation-display idea to arbitrary
planetary bodies:

- latitude/longitude survey grid;
- live sub-spacecraft ground-track marker;
- selected landing-site marker;
- polar inclination;
- site score;
- local terrain roughness;
- survey/deorbit/descent state;
- landing dV and burn margin.

The site marker is driven by the same site-selection data that the landing
controller actually uses.

### Vertical Situation / Descent Energy display

When powered descent becomes active, a second situation instrument appears:

- ship position is plotted against remaining radar altitude and descent rate;
- a separate marker shows the computed suicide-burn trigger;
- current radar altitude, trigger altitude, vertical speed and horizontal
  speed are repeated numerically;
- the display disappears when descent is inactive.

This is the AOSO equivalent of an energy/situation display, not a cosmetic
landing gauge.

### Systems / Caution & Warning display

The SYS page now includes a graphical annunciator board for:

- guidance;
- navigation;
- steering;
- throttle;
- staging;
- mission;
- landing;
- power;
- comms;
- watchdog.

Tiles use nominal / standby / caution / fail artwork and are accompanied by
the concrete reason string and CPU/IPU status.

## OPS3 technique coverage

| Technique observed in OPS3 | AOSO UI v2 adaptation | Status |
| --- | --- | --- |
| Separate main GUI and HUD | Full MFD + tactical glass HUD | Implemented |
| Nested H/V GUI layouts | MFD/HUD layout system | Implemented |
| Custom PNG widget/background skin | Original AOSO asset set under `ux/ui2_assets/` | Implemented |
| Movable guidance diamond | Commanded-attitude PFD/HUD pipper | Implemented |
| Smooth pipper motion | Configurable interpolation | Implemented |
| Slider/tape instruments | Vertical speed + burn/fuel tape | Implemented |
| Trail bugs | NAV recent-position trail | Implemented |
| Reference/predicted markers | target, SOI, node, landing-site and trigger markers | Implemented |
| Phase-specific labels | AOSO mission/guidance states | Implemented |
| Dynamic caution colors | Caution/warning board and HUD takeover | Implemented |
| GUI minimize / alternate view | TAC/MFD/ENG modes + compact main GUI | Implemented |
| HUD recenter | REC button | Implemented |
| Bright/dark HUD | Sun-relative tactical HUD brightness | Implemented |
| Guidance decluttering | automatic terminal-phase + manual DCL | Implemented |
| Display changes with guidance phase | AUTO MFD page director with 30 s manual inhibit | Implemented |
| Trajectory situation display | NAV transfer/orbit situation display | Initial implementation |
| Vertical situation display | powered-landing altitude/energy display | Initial implementation |
| Landing/approach selection | autonomous graded landing-site display | Implemented |
| Full flight-path/energy curve plotting | atmospheric return / deorbit energy page | Planned |
| Moving predicted-vs-reference trajectory curves | native/addon trajectory sample renderer | Planned |
| Rich operator selectors | display-safe mission/engineering selectors only | Planned |
| Full graphical tank/engine diagram | topology-band graphical twin | Initial implementation |

"Planned" means the architecture reserves it; it is not silently considered
done.

## Automatic page director

With AUTO enabled, the MFD selects the useful page for the current workload:

- ascent / ordinary flight -> FLT;
- transfer planning, maneuver, coast, capture -> NAV;
- polar insertion, site scan, deorbit, descent -> LND;
- system failure -> SYS.

Selecting a tab manually inhibits automatic switching for 30 seconds.
Engineering mode is never auto-switched.

## Performance rules

UI v2 follows AOSO's flight-first scheduler:

- **physics/fast path:** only pipper, core flight tapes and critical values;
- **medium:** orbit/target/landing values;
- **slow:** route, capability, topology and system summaries;
- **event driven:** topology rebuild, stage/SOI/mission-state changes.

Static PNGs are loaded once. Widgets are built once and updated in place.
The renderer must not rebuild an instrument every physics tick.

At high/critical CPU load, flight guidance wins. Expensive twin/strategic
work remains deferrable.

## Migration plan

The first UI v2 milestones intentionally leave the old textual values under
the new instruments. That makes the first in-game test debuggable and gives
a direct value-for-value comparison.

After the graphical values survive a real launch -> transfer -> SOI ->
capture -> polar survey -> landing test:

1. collapse duplicate text under FLT/NAV/MSN/VEH/LND/SYS;
2. merge PRP + STG into VEH/ENG;
3. keep LOG and DBG as engineering subpages;
4. retire the old text-first presentation code;
5. retain the terminal fallback only for GUI failure/headless debugging.

This staged cutover changes presentation without destabilizing autonomous
flight.
