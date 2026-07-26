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

What does not exist yet: save/load, the electrical side (relays, contacts),
undo, and orthogonal wire routing — wires are drawn straight between ports.
Four component kinds so far.

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
| `Del` / `Backspace` | remove the selected component and its wires |
| `Esc` | cancel a placement or a half-finished wire |
| right-drag / wheel / `F` | pan, zoom, fit to window |
| `1` and `2` (RUN only) | the two solenoid coils |

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
