# Open-FluidSim

A fluid power (pneumatic / hydraulic) circuit simulator in Common Lisp, rebuilt
from the Unity original. Targets macOS and Windows.

## Status

Early, but end to end. `run.sh` opens a worked circuit — air supply, 5/2
double-solenoid detented valve, both exhausts, and a double-acting cylinder,
wired together — so every layer is exercised: component model, valve position
logic, pressure propagation, cylinder motion, composable symbol geometry, and
rendering.

Press `space` to run, then click the `S1` pushbutton and the cylinder extends.
A tap is enough: **release the button and the cylinder keeps going**, because
the detent holds the valve where it was put. That is the behaviour the whole
component exists for, and it is what a spring-return valve would not do. `S2`
sends it back.

Live pressure is drawn in red: pressurised wires and filled connection points,
against grey and hollow rings for the rest.

Proximity switches close the loop back the other way: mount one on a cylinder
and the rod reaching the end of its stroke drives the next step of the
sequence, so a circuit can cycle itself instead of needing a press per move.

What does not exist yet: undo, orthogonal wire routing (wires are drawn
straight between ports), timers and counters.

## Components

30 kinds across three domains, each on its own palette tab. The list scrolls
with the wheel when it runs past the bottom of the window.

**Pneumatic / Hydraulic** — 2/2, 3/2, 5/2, 5/2 double-solenoid, 5/2 detented
and 5/3 closed-centre valves; double- and single-acting cylinders; supply and
exhaust (pneumatic); pump and reservoir (hydraulic).

**Electric** — +24V and 0V rails, NO/NC contacts, NO/NC pushbuttons, relay
coil, solenoid, NO/NC proximity switches.

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

### Proximity switches

A proximity switch is a contact actuated by a piston instead of a coil, and it
is what closes the loop from the pneumatic side back to the electrical one: the
rod reaching the end of its stroke can now start the next thing to happen,
rather than every move needing a button press.

It follows the same rule as everything else — its tag names the cylinder it is
mounted on, which is why cylinders are tagged `A1`, `A2`... The mounting point
rides in the tag after an `@`, as a percentage of stroke:

| tag | closes when |
|---|---|
| `A1` | cylinder `A1` is fully extended |
| `A1@0` | `A1` is fully retracted |
| `A1@50` | `A1`'s piston passes the middle of its stroke |

Like a real reed switch it senses a *window* rather than a point (`*sensor-band*`,
5% of stroke either side), so a fast piston cannot step clean over it between
one frame and the next.

Wire one to the retract solenoid of a detented valve and a momentary tap on the
extend button gives a complete out-and-back cycle with no second press.

`make-auto-cycle-demo-circuit` is the worked version — a switch at *each* end,
so holding `S1` makes the rod reciprocate continuously and tapping it gives a
single stroke. No relay, and no second button:

```lisp
(open-fluidsim.ui:run :circuit (ofs:make-auto-cycle-demo-circuit))
```

It is also the circuit that shows what the detent is for. A switch is made only
while the piston is within the band, so for most of every stroke *neither* coil
is energised and the spool is holding its own position; a spring-return valve
in the same circuit stalls just off the end and never completes a stroke.
Watch for the rod turning round a few percent short of each end cap — a
proximity switch is made as the piston approaches it, not when it arrives.

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
| wheel over the palette | scroll the component list |
| click a pushbutton (RUN only) | press it while the mouse is held |

Valves are shifted **only** by wiring a solenoid symbol to their coil tag and
energising it — there is no keyboard override, which would silently fight the
electrical simulation.

Cylinders print their extension as a percentage beside them, and their tag
below them — on the canvas rather than in the HUD, since a circuit can hold
more than one and a single HUD figure could not say which it meant.

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

See [MAINTAINING.md](MAINTAINING.md) for a file-by-file tour, the per-frame
data flow, and the Common Lisp you need to read the code — written for someone
who can program but is new to the language.

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
and when both are on. In `update-valves` that behaviour is the *absence* of an
else branch: nothing resets the state, so it persists. Tests pin this down,
since it is the property that distinguishes the component from a spring-return
valve.

## Running

Requires SBCL, Quicklisp, and raylib (`brew install raylib` on macOS).

```sh
./run.sh          # open the simulator
./run.sh --test   # run the test suite
```

`space` toggles between EDIT and RUN. In RUN, click the `S1` pushbutton to
extend the cylinder and `S2` to retract it; right-drag pans, the wheel zooms,
and `F` fits the circuit to the window. Tap a button rather than holding it and
the spool stays where you put it — that is the detent.

The window is resizable, and refits the view on resize so shrinking it never
hides the drawing.

### Adding a component

A component kind is one `register-kind` call, in whichever `src/` file it
belongs to: how to build one, where its wires attach, and how to draw it.
Dispatch is a hash lookup rather than a central `case`, so there is no list to
keep in step. A valve is less than that again — a `valve-spec`, since one
geometry function draws them all.

A test walks every registered kind and fails if it cannot be built, positioned
or drawn, so a half-added kind is caught by the suite rather than at click
time.

[MAINTAINING.md](MAINTAINING.md) has the worked recipe, and the same for
valves, symbols, key bindings and the save format.

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
