# Open-FluidSim

A fluid power (pneumatic / hydraulic) circuit simulator in Common Lisp, rebuilt
from the Unity original. Targets macOS and Windows.

## Status

Early, but end to end. `run.sh` opens a worked circuit — air supply, 5/2
double-solenoid detented valve, both exhausts, and a double-acting cylinder,
wired together — so every layer is exercised: component model, valve position
logic, pressure propagation, cylinder motion, composable symbol geometry, and
rendering.

Hold `1` and the cylinder extends; **release it and the cylinder keeps going**,
because the detent holds the valve where it was put. That is the behaviour the
whole component exists for, and it is what a spring-return valve would not do.

Live pressure is drawn in red: pressurised wires and filled connection points,
against grey and hollow rings for the rest.

What does not exist yet: save/load, undo, orthogonal wire routing (wires are
drawn straight between ports), sensors, and any way to edit a component's
label from the UI — so relay links use their defaults (`K1`, `Sol 1`).

## Components

26 kinds across three domains, each on its own palette tab.

**Pneumatic / Hydraulic** — 2/2, 3/2, 5/2, 5/2 double-solenoid, 5/2 detented
and 5/3 closed-centre valves; double- and single-acting cylinders; supply and
exhaust (pneumatic); pump and reservoir (hydraulic).

**Electric** — +24V and 0V rails, NO/NC contacts, NO/NC pushbuttons, relay
coil, solenoid.

Valves are **data, not code**. They are all the same drawing — N position
boxes, flow arrows inside, actuators on the ends, fixed ports the body slides
behind — so a `valve-spec` gives the port layout, connection tables and
actuator stacks, and one geometry function draws every one of them. Adding a
valve is a new spec, not a new function.

Pneumatic and hydraulic versions share a spec and differ only in arrowhead
fill: hollow for pneumatic, solid for hydraulic, per ISO 1219.

## The electrical side

Electric components reuse the fluid engine unchanged — a wire is a wire, and
an open contact blocks exactly like a shut valve port, so the same flood fill
serves both.

Energisation is the one thing that differs. A coil needs current *in* and
*out*, so it is energised only when one terminal is reachable from a supply
rail and the other from 0V — two floods, not one. Wiring a coil to +24V alone
leaves it dead, as it should.

Components link by **label**: a coil labelled `K1` actuates every contact
labelled `K1`, and a solenoid labelled `Sol 1` drives the valve coil of that
name. `make-relay-demo-circuit` wires up the full chain — button → K1 coil →
K1 contact → Sol 1 → valve → cylinder.

## The editor

Two modes, toggled with `space`:

| | |
|---|---|
| **EDIT** | place, move, wire and delete. Nothing is pressurised. |
| **RUN** | the simulation propagates and the solenoid keys work. |

| gesture | does |
|---|---|
| click a palette entry, then the canvas | place a component |
| drag a component | move it |
| click a port, then another port | wire them together |
| click that same pair again | unwire them |
| `T` | retag the selected component |
| `S` / `L` | save / load a circuit by name |
| `Del` / `Backspace` | remove the selected component and its wires |
| `Esc` | cancel a placement or a half-finished wire |
| right-drag / wheel / `F` | pan, zoom, fit to window |
| click a pushbutton (RUN only) | press it while the mouse is held |

Valves are shifted **only** by wiring a solenoid symbol to their coil tag and
energising it — there is no keyboard override, which would silently fight the
electrical simulation.

Cylinders print their extension as a percentage beside them, on the canvas
rather than in the HUD, since a circuit can hold more than one.

## Saving

`S` and `L` prompt for a name; bare names resolve to `~/circuits/<name>.ofs`,
and anything with a slash is treated as a path.

A circuit is written as a plain s-expression — component kinds, positions,
tags and states, plus wires as index quadruples. No schema, no parser, no
serialisation library; `read` and `print` do the work. Valve positions and
piston travel are saved too, so a detented valve reloads where you left it
rather than snapping back to rest. Files are read with `*read-eval*` bound to
`nil`.

## Colours

Conductors are shaded by what they carry: **red** for supply, **blue** for a
return to 0V, hollow grey for neither. The blue matters because a coil does
not conduct, so its return leg is grounded without ever being live — with a
single colour it would look identical to a terminal nobody had wired up.

Left mouse does the editing and **right mouse pans** — left already has four
jobs and can't also be the pan gesture.

Palette entries draw the component's own geometry through `draw-ops-fitted`,
so an entry cannot drift out of sync with what it places. The Unity original
kept a separate thumbnail sprite per component that had to be maintained in
parallel with the symbol.

A placed supply pressurises the circuit by virtue of its kind — the editor has
no way to call `add-source`, so `source-connectors` treats every `:supply`
component as one.

## Architecture

Three ASDF systems, deliberately layered:

| System | Depends on | Purpose |
|---|---|---|
| `open-fluidsim` | *nothing* | Component model, simulation engine, symbol geometry |
| `open-fluidsim/ui` | core, `cl-raylib`, `3d-vectors` | Interactive window |
| `open-fluidsim/tests` | core, `fiveam` | Test suite |

The core has no external dependencies and no knowledge of any renderer. It
emits **drawing operations** — polylines, filled polygons, discs, boxes,
captions — in a y-up coordinate system. `ui/render.lisp` is the only file that
knows raylib exists, so an SVG or PDF exporter is a second renderer rather than
a change to the symbol definitions.

### Symbols are code, not sprites

In the Unity original every combination of actuators needed its own
pre-composited PNG: adding a detent to a double-solenoid 5/2 valve meant
hand-painting a new 280×74 sprite and giving it a custom pivot because the
result was asymmetric. Here actuators are composable glyphs
(`glyph-solenoid`, `glyph-spring`, `glyph-detent`) placed by translation, so a
new variant is a new list, not a new asset.

Following ISO 1219, only *powered* actuators are boxed — the solenoid gets a
rectangle, the spring and detent are drawn bare, and the detent sits adjacent
to the body with the coil outboard of it.

### Propagation

The Unity version spread pressure by recursive callback, which made loops in a
circuit a hazard and evaluation order hard to reason about. Here it is a flood
fill over an undirected graph whose edges are the wires plus each component's
internal connections for its current position. Cycles are handled by the
visited set, and the result does not depend on traversal order.

### The detent

A detented valve holds its last commanded position when both coils are off —
and when both are on. In `update-actuators` that behaviour is the *absence* of
an else branch: nothing resets the state, so it persists. Four tests pin this
down, since it is the property that distinguishes the component from a
spring-return valve.

## Running

Requires SBCL, Quicklisp, and raylib (`brew install raylib` on macOS).

```sh
./run.sh          # open the simulator
./run.sh --test   # run the test suite
```

Hold `1` to extend the cylinder, `2` to retract, drag to pan, wheel to zoom,
`F` to fit the circuit to the window. Release both keys and the spool stays
where you put it — that is the detent.

The window is resizable, and refits the view on resize so shrinking it never
hides the drawing.

### Adding a component

A component kind needs two clauses, both in `src/library.lisp`: one in
`component-ports` giving the positions wires attach to, and one in
`component-geometry` returning its drawing operations. A test walks every
component in the demo circuit and fails if either is missing, so a half-added
kind is caught by the suite rather than at draw time.

From a REPL instead:

```lisp
(push #p"~/common-lisp/Open-FluidSim/" asdf:*central-registry*)
(ql:quickload :open-fluidsim/ui)
(open-fluidsim.ui:run)
```

## Building an executable

```sh
sbcl --noinform --disable-debugger --non-interactive --load build.lisp
```

Gives a 13 MB native binary. See [BUILDING.md](BUILDING.md) for .app bundles,
code signing, and the Windows story — which is constrained by SBCL being
unable to cross-compile an image.

## Notes on portability

`cl-raylib`'s bindings are from 2024 and predate raylib 6.0, but they load and
pass structs correctly against it — verified by round-tripping a point through
a `Camera2D`. On macOS raylib runs on OpenGL 4.1 via Metal; Apple deprecated
OpenGL in 2018 but still ships it. If that ever ends, the renderer is one file.

SBCL cannot cross-compile an image, so a Windows binary has to be produced on
Windows — a CI runner is the intended route rather than a local machine.
