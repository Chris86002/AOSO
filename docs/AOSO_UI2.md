# AOSO UI v2

AOSO UI v2 is the presentation layer for the autonomous flight computer. It is
inspired by the interaction techniques demonstrated by kOS-Shuttle-OPS3
(image-backed kOS GUIs, movable bugs/pippers, situation displays, sliders,
annunciators, decluttering and phase-specific displays), but AOSO's code and
artwork are original. No OPS3 source or image assets are copied.

## Non-negotiable architecture rule

UI v2 is **display-only**.

The UI may:
- read AOSO state and telemetry;
- project trajectory/ground-track information for display;
- switch pages and display modes;
- change GUI visibility, scale and declutter state;
- enable/disable 3D display vectors;
- select/highlight a Digital Twin node.

The UI must never:
- use LOCK/UNLOCK STEERING;
- write THROTTLE;
- call STAGE;
- write WARP / WARPMODE;
- write SHIP:CONTROL;
- change SAS/RCS as a flight command;
- create/execute maneuver nodes;
- change mission, tour, goto, landing or ascent state.

Flight and safety always outrank presentation.

## Module ownership

### ux/ui2_instruments.ks
Owns primary flight instrumentation:
- PFD
- graphical NAV situation display
- predicted current-SOI conic
- maneuver / next-SOI / ship bugs
- recent flown trail
- polar survey display
- landing/descent director
- vertical-situation / suicide-burn-margin inset

This module must not contain Mission, Systems or Vehicle page implementations.

### ux/ui2_hud.ks
Owns the separate tactical glass HUD:
- movable guidance pipper
- speed / altitude / vertical-speed presentation
- burn/propellant progress slider
- warning/event annunciation
- day/night brightness
- manual + automatic declutter
- REC recenter and MFD-return controls

### ux/ui2_mfd.ks
Owns:
- Mission / Grand Tour page
- Systems caution-warning panel
- compact graphical Digital Twin / Vehicle page

This is the **only** owner of those page functions/globals. Do not duplicate
them in ui2_instruments.ks.

### ux/hud_gui.ks
Owns:
- MFD window/chrome
- page routing
- page tabs
- HUD/MFD/ENG mode selection
- AUTO page switching
- UI2 startup self-test
- compatibility/detail text below graphical displays

### Existing data/model modules
UI2 deliberately reuses:
- ux/hud_data.ks — telemetry/display model
- ux/hud_twin.ks — Digital Twin data model
- ux/hud_twin_view.ks — full engineering Twin page
- ux/hud_fd.ks — 3D display vectors
- ux/hud_alert.ks — events/alerts

Do not move flight-control logic into the UI just to make a display easier.

## Flight-deck displays

### PFD
Shows the current flight regime rather than a fixed debug table:
- commanded-attitude guidance diamond;
- heading, pitch, roll and AoA;
- speed / vertical speed;
- altitude / apoapsis;
- TWR / throttle;
- propellant;
- steering/warp/stage state;
- master caution/warning.

The guidance diamond represents error/command information only. It is not an
input to steering.

### NAV
The NAV page is a situation display, not a decorative ellipse:
- sparse samples of the vessel's current osculating/patched conic inside the
  current SOI;
- ship marker;
- maneuver node marker;
- next-SOI marker;
- recent flown trail;
- next-patch PE and ETA;
- burn remaining and node ETA;
- encounter status such as ROUGH / SAFE, CAPTURE CORRIDOR, and
  UNEXPECTED PATCH.

The rough/safe presentation intentionally matches AOSO's navigation doctrine:
commit a safe direct encounter, then refine capture geometry later by
mid-course correction.

### TOUR
Shows the strategic mission separately from local guidance:
- up to sixteen visible route annunciators;
- completed/current/future route state;
- current phase/body/objective;
- completion;
- mission/total dV;
- EC;
- feasibility/assurance text.

The route annunciators are not destination buttons.

### VEH
Compact live Digital Twin:
- stage/topology bands;
- tank/engine state text;
- current stage context;
- part selection/highlighting.

The full engineering TWIN page remains available for filters, exploded views,
resource focus and detailed topology.

### SURF
Two modes share the same page.

**POLAR / SCAN**
- latitude/longitude ground-track display;
- vessel marker;
- selected best landing-site marker;
- site score/roughness;
- orbit inclination and AP/PE.

**DEORBIT / DESCEND**
- local east/north error to the selected site;
- current-vessel marker;
- selected-site marker;
- coast-only predicted landing trend bug;
- radar altitude;
- vertical/horizontal speed;
- suicide-burn trigger;
- burn-margin annunciation;
- vertical situation inset.

The coast-prediction bug is informational and is never fed back into guidance.

### SYS
Shuttle-style caution/warning board for:
- Guidance
- Navigation
- Steering
- Throttle
- Staging
- Mission
- Landing
- Power
- Comms
- Watchdog

The page also shows master caution/warning, WHY, CPU/IPU and EC.

## Automatic page switching

When UI2_AUTO_PAGE is enabled:
- system failure -> SYS;
- POLAR/SCAN/DEORBIT/DESCEND -> SURF;
- active maneuver/GOTO -> NAV;
- PLAN/REFUEL/TAKEOFF -> TOUR;
- otherwise -> PFD.

Manual page selection temporarily suspends AUTO for
UI2_MANUAL_PAGE_HOLD_S seconds. The operator can disable AUTO entirely.

## Performance rules

1. Flight/safety tasks always run first.
2. GUI widgets are built once and values are updated in place.
3. NAV conic prediction is wall-clock throttled with KUNIVERSE:REALTIME, not
   UT. Rails warp therefore cannot force a resample every frame.
4. Rails warp increases NAV prediction spacing.
5. Elevated CPU pressure further slows prediction; CRITICAL skips it.
6. Digital Twin geometry/fills retain the existing CPU shedding rules.
7. Hidden pages do not run their expensive page-specific renderer.
8. No UI feature should use WAIT or alter timewarp.

## kOS compiler hazards

AOSO's normal KerboScript rules apply especially strongly to UI code:
- identifiers are case-insensitive;
- never pair FUNCTION aoso_foo with GLOBAL AOSO_FOO;
- do not use locals/parameters named path, obt, note, alt, r, v, q, or status;
- do not write IF NOT DEFINED x; nest the DEFINED check instead.

Before UI changes are considered complete, run the UI cross-module collision
scan and the control-authority scan.

## Startup verification

aoso_ui2_selftest() runs after the MFD is built. It verifies the six primary
graphical surfaces and required artwork files in the archive:

PFD NAV TOUR VEH SURF SYS

A successful boot logs UI2 Startup self-test READY and the header displays
OPS DISPLAY r4 READY. The revision label confirms the updated GUI was built.

A failure logs the exact missing display and marks the header UI2 FAULT.

## Asset and compatibility validation

Run `python tools/check-ui2.py` before publishing UI2 changes. It validates all
27 PNGs (chunk lengths/CRCs, complete zlib stream, scanline sizes/filters and
frame dimensions), UI2 delimiters, helper ownership/load order, reserved names,
unsupported bare CLAMP calls, and direct flight-control writes.

The red/white backgrounds seen on PFD/TOUR/SYS/VEH were malformed PNG files,
not telemetry colors. The original descent and unused legacy vehicle frames
were malformed too. `node tools/build-ui2-frames.cjs` recreates the complete
dark cockpit frame and button set, including NAV/SURF plotting grounds and a
separate translucent HUD. The artwork is original; OPS3 informs its layout and
color language. Each primary MFD page now has a fixed-width display beside a
permanent labelled telemetry bank; no data toggle hides the readings. All tabs
stay selectable, including standby landing and propulsion pages. AUTO page
switching is opt-in. The live markers, route indicators and Digital Twin
buttons remain in the graphical panel. Keep binary assets binary during upload.
PROP, STAGE, LOG, DBG and HELP use the same framed two-bank layout, while
TWIN retains its full-width interactive part schematic and filter controls.

kOS provides MIN/MAX, not CLAMP. All UI2 modules share `aoso_ui2_clamp` from
ui2_instruments.ks, which main.ks loads before ui2_hud.ks and ui2_mfd.ks.

Offline checks do not validate Unity rendering or live KerboScript execution.
After updating the archive, restart AOSO (or KSP) and inspect PFD, NAV, TOUR, VEH, SYS,
SURF (survey and descent), and the separate HUD. Verify dark backgrounds,
legible labels and moving markers, with no Undefined Variable Name 'clamp'.
OPS DISPLAY r4 READY checks widget construction and artwork presence; it does not
prove that textures decoded. The offline PNG validator covers decoding.

## HUD diagnosis and layout iteration

The separate HUD is a 580 x 390 OPS-style instrument with 360 x 240 glass.
Its speed and altitude banks, vertical-speed tape, guidance bug, annunciator,
and dV/propellant bar are visible together. The HUD is draggable. `REC`
restores `UI2_HUD_X` / `UI2_HUD_Y` from `AOSO/core/config.ks` (defaults tuned
for this 2560 x 1440 KSP install).

`TEST` cycles LIVE, CENTER, EDGE, then LIVE. CENTER and EDGE replace displayed
telemetry with known values and put the bug at known glass coordinates. They
only modify UI widgets and never steer, stage, throttle, or warp. If the test
pattern is misplaced, the issue is layout/art. If the pattern is correct but
LIVE is wrong, inspect telemetry or projection. `DUMP` writes
`0:/aoso_hud.json`; the same button is available on the MFD DBG page. The dump
contains readiness, geometry mode, bug coordinates, telemetry age, CPU load,
and last errors. Run `python tools/inspect-hud-dump.py <path-to-aoso_hud.json>`
to get a quick diagnosis. `python tools/render-hud-preview.py out.png` generates
an offline visual sample of the expected geometry (requires Pillow); it does
not replace the in-game TEST check.

If kOS reports that a declaration clobbers a built-in function, run
`powershell -NoProfile -File tools/check-kos-builtins.ps1 -KspRoot 'C:\path\to\Kerbal Space Program'`.
This checks every AOSO script against the built-in functions in that kOS install.
