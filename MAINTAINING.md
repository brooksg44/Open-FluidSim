# Maintaining Open-FluidSim

A guide for someone who can program, is new to Common Lisp, and has to keep
this codebase working.

`README.md` explains *what* the program does and *why* it is built the way it
is. This file explains *how the code is laid out*, *which Common Lisp you need
to read it*, and *what to do when you want to change something*. Read the
README first; it is short.

The whole thing is about 3,000 lines across 20 files. That is small enough to
read in an afternoon, and this guide is arranged so you can.

---

## 1. Getting it running

```sh
./run.sh          # open the simulator
./run.sh --test   # run the test suite; exits non-zero on failure
```

On Windows use `run.ps1`, which takes the same modes as switches — run
`.\run.ps1 -Setup` first, since nothing on that platform supplies raylib or
cl-raylib for you.

You need SBCL, Quicklisp, and the native raylib library (`brew install sbcl
raylib` on macOS). The test suite needs neither raylib nor a display — the
core has no renderer in it, which is deliberate and is the single most useful
fact about the architecture.

At the time of writing the suite is 43 tests / 272 checks, all passing. If you
break something, `./run.sh --test` will usually tell you exactly what.

### The way you actually want to work

Restarting SBCL for every change is miserable. Use a REPL that stays alive —
Emacs with SLIME or Sly, or VSCode with Alive. Then your loop is:

```lisp
(push #p"~/common-lisp/Open-FluidSim/" asdf:*central-registry*)
(ql:quickload :open-fluidsim/ui)
(open-fluidsim.ui:run)            ; opens the window; close it to return
```

Once loaded, you recompile **one function at a time** (`C-c C-c` in
SLIME/Sly with the cursor inside the function) or one file (`C-c C-k`), and
the change is live in the image immediately. There is no build step. Most
core changes can even be tested without opening a window:

```lisp
(in-package :open-fluidsim)
(multiple-value-bind (circuit valve cylinder) (make-demo-circuit)
  (energise (first (component-solenoids valve)))
  (dotimes (i 120) (step-simulation circuit))
  (component-travel cylinder))     ; => 1.0
```

If a change misbehaves in ways that make no sense, the image may have gone
stale (e.g. you changed a `defstruct`, which does not update instances that
already exist). Quit SBCL and start again. That is the standard cure and it is
not a sign you did anything wrong.

---

## 2. The mental model in thirty seconds

```
   a CIRCUIT holds
      COMPONENTS  (a valve, a cylinder, a pushbutton, ...)
      WIRES       (a cons of two connectors)
      SOURCES     (rarely used; kinds like :supply are sources automatically)

   each COMPONENT holds
      CONNECTORS  (numbered ports, 0..n-1, where wires attach)
      STATE       (:left / :right / :open / :closed / :fixed ...)
      TABLES      (state -> which connectors are joined *inside* the component)

   the ENGINE is a flood fill:
      start at every source connector,
      walk wires and internal connections,
      everything you reach is live.
```

Everything else is decoration on that. Valves are data describing tables and
drawings. Electric parts reuse the same flood fill, because an open contact
blocks exactly like a shut valve port. The renderer never touches any of it —
components emit *drawing operations* (lines, polygons, discs, boxes,
captions), and one file turns those into raylib calls.

---

## 3. The Common Lisp you need

This codebase uses a small, plain subset of the language. No CLOS, no
generic functions, one tiny macro. Here is everything that appears, with a
pointer to where you will meet it.

### Packages and symbols

```lisp
(defpackage #:open-fluidsim
  (:nicknames #:ofs)
  (:use #:cl)
  (:export #:pt #:pt-x ...))
```

A package is a namespace for symbols. `src/package.lisp` declares the core
package and lists every name the outside world may use. `ui/package.lisp` does
the same for the UI and adds **local nicknames** so `ofs:` means
`open-fluidsim:` and `rl:` means `raylib:` inside UI files only.

> **Trap #1, and you will hit it.** If you add a function to `src/` and try to
> call it from `ui/`, you get "symbol OFS:MY-THING not external". The fix is to
> add `#:my-thing` to the `:export` list in `src/package.lisp` and re-evaluate
> that file. Nothing else. There is no other reason for that error.

`#:foo` is an *uninterned symbol* — just a way of writing a name without
polluting the current package. Treat it as "the name foo".

`:keyword` symbols (`:left`, `:valve-5-2`, `:supply`) are self-evaluating
constants used all over this code as enum values. They compare with `eq`,
which is a pointer comparison and is what `case`/`ecase` uses.

### Structures

```lisp
(defstruct connector
  (index 0 :type fixnum)
  (owner nil)
  (pressure 0.0 :type real))
```

This one form defines: the type `connector`, a constructor
`make-connector` taking `:index`/`:owner`/`:pressure`, a predicate
`connector-p`, a copier, and an accessor per slot (`connector-index`, …).
Accessors are `setf`-able:

```lisp
(setf (connector-pressure c) 1.0)
```

`geometry.lisp` uses a variant, the **BOA constructor**:

```lisp
(defstruct (pt (:constructor pt (x y)))
  (x 0.0 :type real)
  (y 0.0 :type real))
```

which means "also give me a positional constructor named `pt`", so you write
`(pt 10.0 -4.0)` rather than `(make-pt :x 10.0 :y -4.0)`. The drawing
operations (`polyline`, `poly`, `disc`, `box`, `caption`) all do this too, with
some arguments positional and some keyword.

> **Trap #2.** Changing a `defstruct` in a live image does not update objects
> that already exist, and can leave you with two incompatible versions of the
> same type. After editing a `defstruct`, restart the REPL.

### Keyword and optional arguments

```lisp
(defun propagate (circuit &key (supply 1.0)) ...)
(propagate circuit)                ; supply defaults to 1.0
(propagate circuit :supply 0.0)    ; the editor uses this to de-pressurise
```

`&key` arguments are named and order-free. This codebase uses them heavily for
anything with a sensible default.

### Multiple values

```lisp
(defun ops-bounds (ops) ... (values min-x min-y max-x max-y))

(multiple-value-bind (min-x min-y max-x max-y) (ops-bounds ops)
  (when min-x                       ; NIL when OPS was empty
    ...))
```

A function can return several values; callers that ignore the extras see only
the first. The `(when min-x ...)` idiom appears everywhere bounds are used,
because `ops-bounds` returns plain `NIL` for an empty list. `make-demo-circuit`
returns `(values circuit valve cylinder)` for the same reason.

### Lists, vectors, hash tables

- Lists: `'(:left :right)`, built with `push`, walked with `dolist`/`loop`.
  `push` prepends, so **`circuit-components` runs newest-first**. That is
  load-bearing — see `component-at` in `editing.lisp`, which relies on it for
  correct hit-test ordering.
- An **alist** is a list of conses used as a lookup table:
  `'((:left . #(3 4 -1 0 1)) (:right . #(2 3 0 1 -1)))`, read with
  `(cdr (assoc key alist))`. That is how port tables are stored.
- `#(3 4 -1 0 1)` is a literal vector, indexed with `aref`. Port tables and
  connector arrays are vectors because they are indexed by connector number.
- Hash tables: `(make-hash-table :test #'eq)`, `(gethash k table)`,
  `(setf (gethash k table) v)`. Used for the kind registry, the valve-spec
  registry, and — importantly — as **sets**, where only the presence of a key
  matters (`flood` returns one of these).

`gethash` returns two values: the value, and whether the key was present.
`update-electric` uses the second value deliberately:

```lisp
(multiple-value-bind (energised present) (gethash name tags)
  (when present ...))   ; "absent" and "present but NIL" must behave differently
```

### Iteration

`dolist`, `dotimes`, and `loop`. `loop` is a mini-language; the forms used
here are all readable in context:

```lisp
(loop for component in components
      for i from 0
      do ...)
(loop for kind in kinds when (eq domain (kind-domain kind)) collect kind)
(loop for p across some-vector append (glyph-port-stub p))
```

`in` for lists, `across` for vectors, `collect`/`append` to build a result.

### Functions as values

The registry stores functions in struct slots:

```lisp
(register-kind :supply :make (lambda () ...) :ports #'single-top-port ...)
...
(funcall (kind-info-ports (kind-info kind)) component)
```

`#'name` means "the function named `name`". `funcall` calls a function held in
a variable. This is how new component kinds plug in without editing a central
`case` statement.

### `etypecase` / `ecase`

```lisp
(etypecase op
  (polyline ...)
  (poly     ...)
  ...)
```

Dispatch on type (`etypecase`) or on value (`ecase`), where the `e` means "and
signal an error if nothing matches". `geometry.lisp` and `ui/render.lisp` both
walk drawing operations this way.

> **Trap #3.** If you add a *new kind of drawing operation*, you must add a
> clause in **three** places: `translate-op` and `op-points` in
> `src/geometry.lisp`, and `draw-op` in `ui/render.lisp`. The `etypecase` will
> tell you at runtime, but only when that op is first drawn.

### `defvar` / `defparameter` / `defconstant`

- `defvar` — set only if currently unbound. Reloading the file does *not*
  reset it. Used for registries (`*kinds*`, `*valve-specs*`,
  `*palette-previews*`), which must survive a reload, and for live UI state
  like `*palette-scroll*`, which should not jump back to the top when you
  recompile the file.
- `defparameter` — always reset on reload. Used for tunables you want to
  change and re-evaluate: `*port-radius*`, `*palette-width*`, `*lead*`,
  `*sensor-band*`.
- `defconstant` — `+box-w+`, `+cylinder-length+`, `+save-format-version+`.
  The `+plus+` naming is convention only.

> **Trap #4.** `defconstant` re-evaluated with a value that is not `eql` to the
> old one signals an error. The existing constants are floats and small
> integers, which are fine. If you ever add a constant holding a **string or a
> list**, reloading that file will break; use `defparameter` instead.

The `*earmuffs*` on special variables are also convention, but a strong one:
they mark globals that can be dynamically rebound. `ui/render.lisp` does
exactly that in `draw-ops-fitted`:

```lisp
(let ((*view-scale* scale) (*view-dx* ...) (*view-dy* ...))
  (draw-ops ops))   ; v2 inside sees the rebound values, then they revert
```

### The one macro

`src/valves.lisp` has a `macrolet` named `both-domains` that registers a
pneumatic and a hydraulic version of each valve from one body. It exists only
to avoid writing every valve spec twice. You can copy the existing uses
without understanding macros; if you want to know, `,foo` splices a value into
generated code and `,@body` splices a list of forms.

### Reader conditionals

`build.lisp` contains `#+win32 "open-fluidsim.exe" #-win32 "open-fluidsim"`.
`#+feature` includes the next form only if the feature is present at *read*
time; `#-` is the negation. This is how one build script serves two platforms.

---

## 4. The files, in load order

ASDF loads with `:serial t`, so each file may use everything above it and
nothing below. That order is in `open-fluidsim.asd` and is worth respecting.

### Core — `open-fluidsim`, no external dependencies

| File | Lines | What it is |
|---|---|---|
| `src/package.lisp` | 53 | The package and its export list. Edit when you add a public name. |
| `src/geometry.lisp` | 71 | `pt`, the five drawing operations, `translate-ops`, `ops-bounds`. |
| `src/glyphs.lisp` | 99 | Reusable ISO 1219 pieces: solenoid, spring, detent, arrow, blocked port, port stub. |
| `src/model.lisp` | 84 | The `component`, `connector`, `solenoid` and `circuit` structs. **Read this one twice.** |
| `src/engine.lisp` | 142 | Flood fill, valve actuation, cylinder motion, `step-simulation`. |
| `src/registry.lisp` | 86 | `register-kind` and the kind table; how a kind maps to make/ports/geometry. |
| `src/valves.lisp` | 266 | `valve-spec`, the one geometry function that draws every valve, and the twelve valve registrations. |
| `src/actuators.lisp` | 61 | Cylinders (four kinds), tagged `A1`, `A2`... so a proximity switch can name one. |
| `src/sources.lisp` | 63 | Supply, exhaust, pump, reservoir. |
| `src/electric.lisp` | 257 | Rails, contacts, buttons, coils, proximity switches, and `update-electric` — the electrical behaviour. |
| `src/library.lisp` | 142 | The three demo circuits. Good worked examples of the API. |
| `src/editing.lisp` | 110 | Hit testing, move/wire/remove, labelling. Renderer-free so it stays testable. |
| `src/persist.lisp` | 113 | Save and load, as an s-expression. |

### UI — `open-fluidsim/ui`, needs cl-raylib

| File | Lines | What it is |
|---|---|---|
| `ui/package.lisp` | 9 | Package with the `ofs:` / `rl:` / `v:` local nicknames. |
| `ui/render.lisp` | 91 | **The only file that knows raylib exists.** Turns drawing ops into draw calls. |
| `ui/palette.lisp` | 135 | The component palette down the left edge: layout constants, scrolling, and the entry hit test. |
| `ui/app.lisp` | 461 | The editor: state struct, mouse and key handling, HUD, and the main loop. |

### Tests

`tests/tests.lisp` (708 lines) uses FiveAM. `(test name ...)` defines a test,
`(is expr "message")` is an assertion, `(signals error ...)` asserts a throw.
Several tests are labelled "Regression:" and pin down bugs that were fixed —
if one of those fails, you have reintroduced a specific past bug, and the
comment says which.

---

## 5. What happens in one frame

The main loop is the bottom of `ui/app.lisp`. Per frame:

```
sync-camera-to-window      keep the canvas centred (also during a live resize)
handle-pan-and-zoom        right-drag pans; the wheel zooms, or scrolls the palette
handle-mouse               palette clicks, placing, wiring, dragging, buttons
handle-keys                mode toggle, prompts, delete, fit
read (editor-circuit editor) back     <- *after* the handlers, never before
  if RUN:  step-simulation                 the loop; L replaces it wholesale
  if EDIT: propagate with :supply 0.0   <- makes everything read dead
draw:  canvas (in camera space) -> palette -> HUD
```

> **Trap #5.** Do not hoist the circuit into a local outside the loop. Loading
> swaps `editor-circuit` for a *different object*, and drawing already reads it
> fresh — so a captured reference silently simulates the old circuit while the
> canvas shows the new one, and pressing a button in the loaded drawing does
> nothing at all. The loop also refits the view when the circuit changes
> identity, or a loaded circuit laid out elsewhere lands off-screen.

And `step-simulation` (`src/engine.lisp`) is:

```
propagate          flood from sources, so the electrical side can see what is live
update-electric    energise coils; open/close contacts and prox switches; drive
                   valve solenoids by tag
update-valves      move each valve's spool from its coils (or hold, if detented)
propagate          again, so fluid paths reflect the valves' *new* positions
update-cylinders   advance piston travel toward its target
```

The double `propagate` is intentional and commented. Without it, a valve
shifted this frame would not route pressure until the next one.

### How electric parts drive fluid parts

There is no object reference between them. The link is **string equality on
labels**, resolved every frame in `update-electric`:

```
a :coil labelled "K1"  ->  every :contact-no / :contact-nc labelled "K1"
a :solenoid-out labelled "Y1a"  ->  the valve coil (a SOLENOID struct) named "Y1a"
a valve labelled "Y1"  ->  names its own coils "Y1a" and "Y1b"
a :sensor-no labelled "A1@50"  ->  the cylinder labelled "A1", at half stroke
```

`refresh-solenoid-tags` (in `valves.lisp`) keeps the third of those in step,
and `rename-component` calls it, so retagging a valve retags its coils.

The last one runs the other way — fluid state actuating an electrical part — and
is how a circuit becomes self-sequencing rather than needing a button press per
move. `sensor-target` splits the tag at the `@`; everything after it is a
percentage of stroke, defaulting to the extended end. Putting the mounting
point in the tag rather than in a slot of its own means the retag prompt
already edits it and the save format already stores it, with no version bump.

> **Trap #6.** The word "solenoid" means two different things.
> A `solenoid` **struct** is a coil *inside a valve* (`component-solenoids`).
> A `:solenoid-out` **component** is the electrical symbol you place on the
> canvas. They are joined only by name string.

Similarly, components have both a `name` and a `label`:

- `component-name` — the human-readable name shown in status messages
  ("Cylinder", "Exhaust A"). Cosmetic.
- `component-label` — the **tag** used for electrical linking ("K1", "Y1",
  "Sol 1"). Functional. This is what `T` edits in the UI.

---

## 6. The component struct, slot by slot

Everything in `src/model.lisp`. You will refer back to this.

| Slot | Meaning |
|---|---|
| `name` | Display name. Cosmetic. |
| `kind` | The keyword that indexes the registry: `:valve-3-2`, `:supply`, `:coil`, … |
| `domain` | `:pneumatic` / `:hydraulic` / `:electric`. Chooses the palette tab, and hollow vs solid arrowheads. |
| `state` | Current position: `:left`, `:right`, `:middle`, `:open`, `:closed`, `:fixed`. Selects a port table. |
| `origin` | A `pt`. Where the component sits in model coordinates. |
| `connectors` | Simple vector of `connector` structs, index 0..n-1. |
| `solenoids` | List of `solenoid` structs — the valve's own coils. Empty for non-valves. |
| `hold` | `:spring` (return to `rest-state` with no coil on) or `:detent` (hold position). |
| `rest-state`, `left-state`, `right-state` | Which state each coil commands, and which is the rest position. |
| `label` | The linking tag. See above. On a proximity switch it also carries the mounting point after an `@`. |
| `energised` | Coils only: is current flowing through it right now. |
| `pressed` | Pushbuttons only: is the mouse held on it. |
| `tables` | Alist of `state -> vector of connector indices`, `-1` meaning blocked. |
| `travel` | Cylinders: piston extension, 0.0 to 1.0. Also what a proximity switch reads. |
| `travel-rate` | Cylinders: strokes per second. |
| `shift` | **Currently unused.** See §10. |

### Port tables

A port table is a vector, one entry per connector, saying which *other*
connector it is joined to inside the component, or `-1` for blocked.

```lisp
'((:left  . #(3 4 -1 0 1))
  (:right . #(2 3 0 1 -1)))
```

Read `:left` as: connector 0 joins 3, connector 1 joins 4, connector 2 is
blocked, connector 3 joins 0, connector 4 joins 1. Note the mapping is
**symmetric** — 0→3 and 3→0 both appear. The engine treats it as an undirected
edge set, so an asymmetric table will produce flow that works in one direction
only, which is almost never what you want.

> **Trap #7.** These table vectors come from the valve *spec* and are
> **shared by every instance of that kind**. Never `setf` into one at runtime;
> you would change every valve of that type in the circuit. Change
> `component-state` to pick a different table instead.

---

## 7. Coordinates

The core is **y-up**, like maths. raylib is **y-down**, like most screen APIs.
The conversion happens in exactly two places:

- `v2` in `ui/render.lisp` negates y and applies the view transform.
- `fit-view` and `mouse-model-position` in `ui/app.lisp` negate y when moving
  between camera space and model space.

Do the negation nowhere else. A symbol drawn "upside down" is almost always a
sign that a second, accidental flip crept in.

Boxes add one more wrinkle: a core `box` is anchored at its **lower-left**
corner (y-up), a raylib rectangle at its **upper-left** (y-down). `draw-op`
converts by adding the height before flipping. That is the only place it
matters.

---

## 8. Recipes

### Add a component kind

Two things are required: a registration, and enough for it to draw and wire.
Put it in whichever `src/` file it belongs to — there is no central list.

```lisp
(defun my-thing-geometry (component)
  (declare (ignore component))
  (list (box -8.0 -8.0 16.0 16.0)
        (polyline (list (pt 0.0 8.0) (stub-end (pt 0.0 8.0))))))

(defun my-thing-ports (component)
  (declare (ignore component))
  (vector (stub-end (pt 0.0 8.0))))     ; one connection point, at the stub's far end

(register-kind :my-thing
  :label "My Thing"                     ; palette caption
  :domain :pneumatic
  :make (lambda ()
          (let ((c (make-component :name "My Thing" :kind :my-thing
                                   :domain :pneumatic
                                   :state :fixed
                                   :tables (fixed-table 1))))
            (setf (component-connectors c) (make-connectors c 1))
            c))
  :ports #'my-thing-ports
  :geometry #'my-thing-geometry)
```

Rules that the test suite enforces for you:

- `component-ports` must return **exactly as many** points as there are
  connectors, in the same order.
- The component's current `state` must have an entry in `tables`, and that
  vector must be as long as the connector count. `(fixed-table n)` gives you
  "n connectors, none joined".
- Geometry must be non-empty.

`every-registered-kind-is-usable` in the test suite checks all of that for
every kind in the registry, so run `./run.sh --test` and a half-added kind
fails there rather than at click time.

Palette order is registration order, which is file order. Nothing else needs
changing — the palette entry draws the component's real geometry, so it cannot
drift out of sync.

If the kind should get auto-numbered tags (K1, K2, …), pass
`:label-prefix "K"`. Leave it off if the tag *refers* to something else (a
contact naming its coil, a proximity switch naming its cylinder), because
`assign-unique-label` would renumber it and break the link the user is about to
make.

### Give a component a parameter, without touching the save format

Proximity switches need a number — where on the stroke they are mounted — and
they get it out of the tag rather than out of a new struct slot: the tag
`A1@50` means "on cylinder A1, at half stroke", parsed by `sensor-target` in
`src/electric.lisp`.

This is worth copying when a kind needs one small parameter. A new slot on
`component` means teaching `circuit-form` to write it, `circuit-from-form` to
read it, and probably bumping `+save-format-version+`. Riding in the label
costs none of that — the `T` prompt already edits it and the save format
already stores it — and it keeps a component "a shape plus a piece of text",
which is the property the whole linking scheme rests on.

The costs are real, so weigh them: the tag is free text a user types, so
parsing must never signal (`sensor-target` falls back to the extended end on
anything it cannot read, and there are tests for `A1@`, `A1@abc` and `A1@999`),
and a parameter that is not naturally one short token does not belong here.

### Add a valve

Do not write a new function. Write a spec. `both-domains` is a `macrolet`, so
it only exists *inside* the big `(macrolet ((both-domains ...)) ...)` form near
the bottom of `src/valves.lisp` — add your valve alongside the others in that
block:

```lisp
(both-domains :valve-4-2 "4/2 Valve"
  (make-valve-spec
   :ports *ports-5-2*                    ; or a new (vector (pt x y) ...)
   :states '(:left :right)               ; left-to-right order of the boxes
   :tables '((:left . #(3 4 -1 0 1)) (:right . #(2 3 0 1 -1)))
   :flows  '((:left . ((3 . 0) (1 . 4))) (:right . ((3 . 1) (0 . 2))))
   :rest :right
   :hold :spring                         ; or :detent
   :left-actuators '(:solenoid)          ; listed inner -> outer
   :right-actuators '(:spring)))
```

`:tables` is what the simulation does; `:flows` is what gets *drawn* (the
arrows). They are separate because a blocked port draws a capped stub rather
than an arrow, and because the arrow direction is a drawing choice. Keep them
consistent by hand — nothing checks that they agree.

`both-domains` registers a pneumatic and a hydraulic copy; use `register-valve`
directly if you only want one. The number of `:solenoid` entries in the
actuator lists determines how many coils the valve gets, so `update-valves`
picks the right behaviour automatically (1 coil = shift or return, 2 coils =
left/right with spring or detent). Ports positioned with positive y are drawn
and connected on top; negative y on the bottom.

### Change how something looks

Symbol geometry lives in the `*-geometry` function for that kind. Compose from
the glyphs in `src/glyphs.lisp` and translate them into place with
`translate-ops`. Everything is in symbol units; a valve position box is
`+box-w+` × `+box-h+` = 24 × 20, so keep new symbols in that neighbourhood or
they will dwarf everything else.

To see a change, just recompile the function — the palette preview and the
canvas both call it fresh.

### Add a key binding

`handle-keys` in `ui/app.lisp`. Note the early return at the top: while a
prompt is open, all keys go to the text buffer instead. Add your key inside
the `let` below that. Keys are plain, unmodified letters, so pick one that is
free (`s`, `l`, `t`, `f`, space, escape, delete and backspace are taken).

### Change the save format

`src/persist.lisp`. If you add a field to what is written, and old files should
still load, keep `+save-format-version+` as is and use `&key` destructuring —
a missing key just comes out `NIL` and the loader guards each field with
`when`. If old files must be *rejected*, bump the version; the loader already
errors on a mismatch.

`label` is the exception to that pattern: rather than `when`, it takes the
saved tag if there is one and falls back to `assign-unique-label` if it is
blank. That is what lets files written before a kind had tags at all come back
numbered — cylinders had none until proximity switches needed something to
name, and a switch mounted on a nameless cylinder could never find it. Note
that this is a *widening* change of exactly the kind that does not need a
version bump: new files carry the field, old files still load, and the meaning
of every field that was already there is unchanged.

Wires are stored as `(component-index port-index component-index port-index)`
because connectors are objects with no identity outside the running image.
Components are written in placement order (`reverse` of the internal list) so
those indices stay meaningful.

Files are read with `*read-eval*` bound to `NIL`, which stops `#.` in a
downloaded file from executing code. Do not remove that.

### Add a test

Append to `tests/tests.lisp`, inside the existing suite:

```lisp
(test what-should-be-true
  (let ((circuit (ofs:make-circuit)))
    ...
    (is (eq :left (ofs:component-state valve)) "message when it fails")))
```

`settle` (defined in that file) runs enough steps for a cylinder to finish its
stroke. Use it rather than a bare `step-simulation` whenever motion is
involved.

---

## 9. Traps, collected

Beyond the numbered ones above:

- **`component-at` uses bounding boxes, not shapes.** Overlapping components
  are resolved by list order — newest first, which matches drawing order.
- **`ops-bounds` only counts a caption's anchor point, not its text.** Long
  labels can overflow a component's computed bounds, which affects both
  selection rectangles and `F` (fit to window).
- **`draw-op` assumes every `poly` has exactly three points**
  (`destructuring-bind (a b c)`). Every polygon in the current symbol set is a
  triangle. Add a quadrilateral and the renderer will error at draw time.
- **A coil deliberately does not conduct** (`:load` maps to `#(-1 -1)` in
  `electric-tables`). This is not an oversight; the long comment there explains
  the bug it prevents, and `coils-sharing-a-return-bus-energise-independently`
  is the regression test. Do not "fix" it.
- **`update-electric` records every solenoid tag, energised or not.** If you
  change it to collect only energised ones, spring-return valves will stay
  shifted forever — there would be nothing left to switch the coil off. There
  is a regression test for this too.
- **A proximity switch senses a band, not a point** (`*sensor-band*`). Narrow
  it and a mid-stroke switch becomes unreliable: `update-cylinders` advances
  travel by `travel-rate × dt` per step, so a piston can jump clean over a
  window narrower than one step. The band must stay comfortably wider than
  the largest step you expect. End-of-stroke switches are safe either way,
  since the piston parks exactly on 0.0 or 1.0 and stays there.
- **`assign-unique-label` runs on load for anything saved with a blank tag.**
  That is what lets circuits written before cylinders had tags come back with
  `A1`, `A2`... rather than nameless, which a proximity switch could never
  find. The cost is that deliberately blanking an auto-numbered tag does not
  survive a save/load round trip.
- **There is no keyboard override for valve coils.** That is deliberate: keys
  would silently fight `update-electric`. Shift a valve by wiring a
  `:solenoid-out` symbol to its coil tag.
- **`register-kind` only pushes to `*kind-order*` if the kind is new**, so
  reloading a file does not duplicate palette entries. But if you *rename* a
  kind, the old one stays in the registry until you restart.
- **`make-valve-5-2-double-solenoid` builds a `:valve-5-2-detented`.** The name
  is historical and misleading; it is kept because tests and older callers use
  it. `:valve-5-2-double` is a different, spring-centred kind.

---

## 10. Loose ends

Things that are half-present. None break anything; all are worth knowing
before you go looking for the other half.

- `component-shift` — a slot on `component`, exported, never read or written
  anywhere. Valve body offset is computed from `+box-w+` in
  `valve-geometry-from-spec` instead.
- `pt-` and `pt-scale` — exported from the core, unused by anything.
- `add-source` / `circuit-sources` — still supported, but only the tests use
  them. In practice `source-connectors` treats any `:supply`, `:pump` or
  `:power-24v` component as a source, because the editor has no way to call
  `add-source`.

---

## 11. Debugging

- **`./run.sh --test` first.** It is fast and needs no window.
- **Poke at it in the REPL.** The core is pure data; you can build a circuit,
  step it, and inspect any slot without opening a window. See §1.
- **An unhandled error opens the debugger** with a stack of restarts. In a
  terminal, `0` or `q` usually aborts back to the REPL. In SLIME you get a
  clickable backtrace, which is far more useful.
- **`(describe some-component)`** and **`(inspect some-component)`** print every
  slot. `inspect` is interactive.
- **`(trace ofs:update-electric)`** prints calls and returns. `(untrace)`
  stops. For a function that is *not* in the export list — most of the
  `*-geometry` helpers, `internal-neighbours`, `valve-box-ops` — use a
  **double colon**: `(trace ofs::internal-neighbours)`. `::` reaches internal
  symbols; `:` only reaches exported ones.
- **`(break)`** dropped into a function stops there with the full environment
  live, which beats print statements.
- Common errors and what they actually mean:

  | Message | Cause |
  |---|---|
  | `symbol OFS:FOO not external` | Missing from the `:export` list in `src/package.lisp`. |
  | `Component X has no port table for state :Y` | `tables` lacks an entry for the current `state`. |
  | `Unknown component kind :FOO` | Kind never registered, or its file did not load. |
  | `fell through ETYPECASE` | New drawing operation without clauses in all three places. |
  | `The value NIL is not of type ...` in drawing | Usually `ops-bounds` returning `NIL` for empty geometry. |

---

## 12. Where to start reading

If you read four files, read these, in this order:

1. `src/model.lisp` — the data. 84 lines.
2. `src/engine.lisp` — the simulation. 142 lines, and the comments explain the
   design decisions.
3. `src/library.lisp` — three worked circuits that use the whole API.
4. `src/valves.lisp` — the specification-driven approach that most of the
   component library rests on.

Then `ui/app.lisp` when you need to change the editor, and `ui/render.lisp`
when you need to change how anything is drawn.
