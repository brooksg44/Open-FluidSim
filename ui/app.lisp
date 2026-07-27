;;;; app.lisp -- the editor.
;;;;
;;;; Two modes. In EDIT you place components from the palette, drag them
;;;; around, and wire ports together; nothing is pressurised. In RUN the
;;;; simulation propagates and the solenoid keys work. Space switches.
;;;;
;;;; Left mouse edits, right mouse pans -- left has too many jobs already
;;;; (place, select, drag, wire) to also be the pan gesture.

(in-package #:open-fluidsim.ui)

(defparameter *port-radius* 2.5
  "Connection point radius, in symbol units. Kept close to the stroke weight so
the rings read as part of the drawing rather than sitting on top of it.")

(defparameter *wire-width* 1.2)

(defstruct editor
  circuit
  (mode :edit)
  (domain :pneumatic)                   ; which palette tab is showing
  (placing nil)                         ; kind awaiting a click on the canvas
  (selected nil)
  (pending nil)                         ; first connector of a wire in progress
  (dragging nil)
  (drag-dx 0.0)
  (drag-dy 0.0)
  ;; A modal text prompt: :rename, :save or :load, with the component being
  ;; retagged when it is :rename.
  (prompt nil)
  (prompt-target nil)
  (prompt-buffer "")
  (status "Click a palette entry, then click the canvas to place it."))

;;; ------------------------------------------------------------------
;;; View
;;; ------------------------------------------------------------------

(defun sync-camera-to-window (camera)
  "Keep the camera's origin centred in the canvas area, right of the palette
and below the HUD.

Done every frame rather than only when IS-WINDOW-RESIZED reports a change, so
the view stays centred throughout a live drag-resize, not just once it ends."
  (let ((offset (rl:camera2d-offset camera)))
    (setf (v:vx offset)
          (+ *palette-width* (/ (- (rl:get-screen-width) *palette-width*) 2.0))
          (v:vy offset)
          (+ *hud-height* (/ (- (rl:get-screen-height) *hud-height*) 2.0)))))

(defun fit-view (camera circuit &key (margin 0.85))
  "Choose a zoom and target that put the whole circuit in the canvas area."
  (multiple-value-bind (min-x min-y max-x max-y) (ofs:circuit-bounds circuit)
    (when min-x
      (let* ((span-x (max 1.0 (- max-x min-x)))
             (span-y (max 1.0 (- max-y min-y)))
             (usable-w (max 1 (- (rl:get-screen-width) *palette-width*)))
             (usable-h (max 1 (- (rl:get-screen-height) *hud-height*)))
             (target (rl:camera2d-target camera)))
        (setf (rl:camera2d-zoom camera)
              (max 0.5 (min 16.0 (* margin (min (/ usable-w span-x)
                                                (/ usable-h span-y)))))
              ;; Camera space is y-down, the model is y-up, so negate.
              (v:vx target) (float (/ (+ min-x max-x) 2) 1.0)
              (v:vy target) (float (- (/ (+ min-y max-y) 2)) 1.0))))))

(defun mouse-model-position (camera)
  "Pointer position in model coordinates (y up)."
  (let ((p (rl:get-screen-to-world-2d (rl:get-mouse-position) camera)))
    (ofs:pt (v:vx p) (- (v:vy p)))))

(defun handle-pan-and-zoom (editor camera)
  (when (mouse-button-down-p :mouse-button-right)
    (let ((delta (rl:get-mouse-delta))
          (zoom (rl:camera2d-zoom camera))
          (target (rl:camera2d-target camera)))
      (decf (v:vx target) (/ (v:vx delta) zoom))
      (decf (v:vy target) (/ (v:vy delta) zoom))))
  (let ((wheel (rl:get-mouse-wheel-move)))
    (unless (zerop wheel)
      (if (in-palette-p (v:vx (rl:get-mouse-position)))
          ;; Over the palette the wheel scrolls the list. It used to zoom the
          ;; canvas from here, which was both surprising and left any entry
          ;; past the bottom of the window with no way to reach it.
          (scroll-palette (editor-domain editor) (round (* wheel -40)))
          (setf (rl:camera2d-zoom camera)
                (max 0.5 (min 16.0 (+ (rl:camera2d-zoom camera) (* wheel 0.4)))))))))

;;; ------------------------------------------------------------------
;;; Editing gestures
;;; ------------------------------------------------------------------

(defun place-component (editor at)
  (let ((component (ofs:make-component-of-kind (editor-placing editor)
                                               :origin at)))
    (ofs:add-component (editor-circuit editor) component)
    (ofs:assign-unique-label (editor-circuit editor) component)
    (setf (editor-selected editor) component
          (editor-placing editor) nil
          (editor-status editor)
          (format nil "Placed ~a~@[ (~a)~]. Press T to retag."
                  (ofs:component-name component)
                  (let ((tag (ofs:component-label component)))
                    (unless (string= "" tag) tag))))
    component))

(defun begin-wire-or-select (editor at)
  (let* ((circuit (editor-circuit editor))
         (connector (ofs:connector-at circuit (ofs:pt-x at) (ofs:pt-y at))))
    (cond
      ;; Second click of a wiring gesture.
      ((and connector (editor-pending editor))
       (let ((result (ofs:toggle-wire circuit (editor-pending editor) connector)))
         (setf (editor-status editor)
               (case result
                 (:connected "Wire connected.")
                 (:disconnected "Wire removed.")
                 (t "Those two ports cannot be wired to each other."))
               (editor-pending editor) nil)))
      ;; First click of a wiring gesture.
      (connector
       (setf (editor-pending editor) connector
             (editor-status editor) "Now click the port to wire it to."))
      (t
       (let ((component (ofs:component-at circuit (ofs:pt-x at) (ofs:pt-y at))))
         (setf (editor-pending editor) nil
               (editor-selected editor) component)
         (when component
           (let ((origin (ofs:component-origin component)))
             (setf (editor-dragging editor) component
                   (editor-drag-dx editor) (- (ofs:pt-x origin) (ofs:pt-x at))
                   (editor-drag-dy editor) (- (ofs:pt-y origin) (ofs:pt-y at))
                   (editor-status editor)
                   (format nil "Selected ~a. Drag to move, Delete to remove."
                           (ofs:component-name component))))))))))

(defun press-button-at (editor at)
  "Press a pushbutton under the pointer. Returns the component, or NIL."
  (let ((component (ofs:component-at (editor-circuit editor)
                                     (ofs:pt-x at) (ofs:pt-y at))))
    (when (and component
               (member (ofs:component-kind component)
                       '(:push-button :push-button-closed)))
      (setf (ofs:component-pressed component) t)
      component)))

(defun handle-mouse (editor camera)
  (let ((screen (rl:get-mouse-position)))
    (cond
      ;; Palette clicks never reach the canvas.
      ((and (mouse-button-pressed-p :mouse-button-left)
            (in-palette-p (v:vx screen)))
       (let ((domain (palette-domain-at (v:vx screen) (v:vy screen)))
             (kind (palette-kind-at (editor-domain editor)
                                    (v:vx screen) (v:vy screen))))
         (cond (domain
                (setf (editor-domain editor) domain
                      (editor-placing editor) nil
                      ;; Back to the top: the position that was legal on the
                      ;; old tab means nothing on a list of a different length.
                      *palette-scroll* 0
                      (editor-status editor)
                      (format nil "~a components." (domain-label domain))))
               (kind
                (setf (editor-placing editor) kind
                      (editor-pending editor) nil
                      (editor-status editor) "Click on the canvas to place it.")))))
      ((mouse-button-pressed-p :mouse-button-left)
       (let ((at (mouse-model-position camera)))
         (cond ((editor-placing editor) (place-component editor at))
               ;; In RUN, clicking a pushbutton presses it instead of selecting.
               ((and (eq (editor-mode editor) :run)
                     (press-button-at editor at)))
               (t (begin-wire-or-select editor at)))))))
  ;; Buttons are momentary: released as soon as the mouse comes up.
  (unless (mouse-button-down-p :mouse-button-left)
    (dolist (component (ofs:circuit-components (editor-circuit editor)))
      (setf (ofs:component-pressed component) nil)))
  ;; Drag the selected component.
  (when (and (editor-dragging editor)
             (mouse-button-down-p :mouse-button-left))
    (let ((at (mouse-model-position camera)))
      (ofs:move-component (editor-dragging editor)
                          (+ (ofs:pt-x at) (editor-drag-dx editor))
                          (+ (ofs:pt-y at) (editor-drag-dy editor)))))
  (unless (mouse-button-down-p :mouse-button-left)
    (setf (editor-dragging editor) nil)))

(defun prompt-label (purpose)
  (ecase purpose
    (:rename "tag")
    (:save "save as")
    (:load "load")))

(defun finish-prompt (editor)
  "Apply whatever the prompt was collecting."
  (let ((text (editor-prompt-buffer editor)))
    (case (editor-prompt editor)
      (:rename
       (let ((component (editor-prompt-target editor)))
         (ofs:rename-component component text)
         (setf (editor-status editor)
               (format nil "Tagged ~a.~@[ Coils: ~a~]" text
                       (let ((coils (ofs:component-solenoids component)))
                         (when coils
                           (format nil "~{~a~^, ~}"
                                   (mapcar #'ofs:solenoid-name coils))))))))
      (:save
       (if (string= "" text)
           (setf (editor-status editor) "Save cancelled: no name given.")
           (handler-case
               (let ((path (ofs:save-circuit (editor-circuit editor)
                                             (ofs:circuit-path text))))
                 (setf (editor-status editor) (format nil "Saved ~a" path)))
             (error (e)
               (setf (editor-status editor) (format nil "Save failed: ~a" e))))))
      (:load
       (if (string= "" text)
           (setf (editor-status editor) "Load cancelled: no name given.")
           (handler-case
               (let ((circuit (ofs:load-circuit (ofs:circuit-path text))))
                 ;; Replace wholesale, and drop every reference into the old
                 ;; circuit -- a stale selection would draw a component that
                 ;; is no longer in the drawing.
                 (setf (editor-circuit editor) circuit
                       (editor-selected editor) nil
                       (editor-dragging editor) nil
                       (editor-pending editor) nil
                       (editor-placing editor) nil
                       (editor-status editor)
                       (format nil "Loaded ~a components."
                               (length (ofs:circuit-components circuit)))))
             (error (e)
               (setf (editor-status editor)
                     (format nil "Load failed: ~a" e)))))))
    (setf (editor-prompt editor) nil
          (editor-prompt-target editor) nil)))

(defun handle-prompt-keys (editor)
  "Collect typed text. Enter accepts, Escape abandons."
  (loop for code = (rl:get-char-pressed)
        until (zerop code)
        do (when (and (>= code 32) (< code 127))
             (setf (editor-prompt-buffer editor)
                   (concatenate 'string (editor-prompt-buffer editor)
                                (string (code-char code))))))
  (when (and (key-pressed-p :key-backspace)
             (plusp (length (editor-prompt-buffer editor))))
    (setf (editor-prompt-buffer editor)
          (subseq (editor-prompt-buffer editor)
                  0 (1- (length (editor-prompt-buffer editor))))))
  (cond ((key-pressed-p :key-escape)
         (setf (editor-prompt editor) nil
               (editor-prompt-target editor) nil
               (editor-status editor) "Cancelled."))
        ((or (key-pressed-p :key-enter) (key-pressed-p :key-kp-enter))
         (finish-prompt editor))))

(defun begin-prompt (editor purpose &key target (initial "") hint)
  (setf (editor-prompt editor) purpose
        (editor-prompt-target editor) target
        (editor-prompt-buffer editor) initial
        (editor-status editor)
        (format nil "Type a ~a, Enter to accept.~@[ ~a~]"
                (prompt-label purpose) hint)))

(defun retag-hint (component)
  "What the tag of COMPONENT means, for kinds whose tag names something else."
  (case (ofs:component-kind component)
    ((:sensor-no :sensor-nc)
     ;; The mounting point lives in the tag, so the prompt has to say so --
     ;; there is nowhere else in the UI that this syntax could be discovered.
     "A cylinder tag: A1 at full extension, A1@0 retracted, A1@50 mid-stroke.")
    ((:contact-no :contact-nc) "The tag of the coil that drives it.")
    (:solenoid-out "The tag of the valve coil it drives.")))

(defun handle-keys (editor camera)
  (when (editor-prompt editor)
    (return-from handle-keys (handle-prompt-keys editor)))
  (let ((circuit (editor-circuit editor)))
    (when (key-pressed-p :key-t)
      (let ((component (editor-selected editor)))
        (when component
          (begin-prompt editor :rename :target component
                               :initial (ofs:component-label component)
                               :hint (retag-hint component)))))
    (when (key-pressed-p :key-s) (begin-prompt editor :save))
    (when (key-pressed-p :key-l) (begin-prompt editor :load))
    (when (key-pressed-p :key-escape)
      (setf (editor-placing editor) nil
            (editor-pending editor) nil
            (editor-status editor) "Cancelled."))
    (when (or (key-pressed-p :key-delete) (key-pressed-p :key-backspace))
      (let ((component (editor-selected editor)))
        (when component
          (ofs:remove-component circuit component)
          (setf (editor-selected editor) nil
                (editor-dragging editor) nil
                (editor-pending editor) nil
                (editor-status editor)
                (format nil "Removed ~a." (ofs:component-name component))))))
    (when (key-pressed-p :key-space)
      (setf (editor-mode editor) (if (eq (editor-mode editor) :run) :edit :run)
            (editor-pending editor) nil
            (editor-status editor)
            (if (eq (editor-mode editor) :run)
                "Running. Click a pushbutton to operate it."
                "Editing. Simulation stopped.")))
    (when (key-pressed-p :key-f)
      (fit-view camera circuit))
    ;; No keyboard override for coils: a valve is shifted by wiring a solenoid
    ;; symbol to its tag and energising it, which is the whole point of the
    ;; electric domain. Keys here would silently fight UPDATE-ELECTRIC.
    circuit))

;;; ------------------------------------------------------------------
;;; Drawing
;;; ------------------------------------------------------------------

(defun conductor-colour (a b grounded)
  "Red carries supply, blue returns to 0V, grey is neither."
  (cond ((or (ofs:pressurised-p a) (ofs:pressurised-p b)) :maroon)
        ((and grounded (or (gethash a grounded) (gethash b grounded))) :blue)
        (t :darkgray)))

(defun draw-wires (circuit grounded)
  (dolist (wire (ofs:circuit-wires circuit))
    (let ((a (car wire)) (b (cdr wire)))
      (rl:draw-line-ex (v2 (ofs:connector-position a))
                       (v2 (ofs:connector-position b))
                       *wire-width*
                       (conductor-colour a b grounded)))))

(defun draw-connection-points (circuit pending grounded)
  "Every connector is a connection point: a ring, filled when it carries.

Filled red is supply, filled blue is a return to 0V, hollow is neither. A
coil's return leg shows blue rather than red because a coil does not conduct,
so that leg is grounded without ever being live -- and an unshaded return
would look identical to a terminal nobody had wired up."
  (dolist (component (ofs:circuit-components circuit))
    (dotimes (index (length (ofs:component-connectors component)))
      (let ((connector (ofs:component-connector component index))
            (centre (v2 (ofs:component-port-position component index))))
        (cond ((eq connector pending)
               (rl:draw-circle-v centre (* 1.6 *port-radius*) :orange))
              ((ofs:pressurised-p connector)
               (rl:draw-circle-v centre *port-radius* :maroon))
              ((and grounded (gethash connector grounded))
               (rl:draw-circle-v centre *port-radius* :blue))
              (t
               (rl:draw-circle-lines-v centre *port-radius* :maroon)))))))

(defun draw-selection (component)
  (when component
    (multiple-value-bind (min-x min-y max-x max-y) (ofs:component-bounds component)
      (when min-x
        (let ((corner (v2 (ofs:pt (- min-x 3) (+ max-y 3)))))
          (rl:draw-rectangle-lines-ex
           (rl:make-rectangle :x (v:vx corner) :y (v:vy corner)
                              :width (float (+ 6 (- max-x min-x)) 1.0)
                              :height (float (+ 6 (- max-y min-y)) 1.0))
           1.0 :orange))))))

(defun draw-ghost (editor camera)
  "Preview of the component about to be placed, following the cursor."
  (let ((kind (editor-placing editor)))
    (when kind
      (let ((at (mouse-model-position camera))
            (preview (palette-preview kind)))
        (ofs:move-component preview (ofs:pt-x at) (ofs:pt-y at))
        (draw-ops (ofs:component-world-geometry preview) :color :gray)))))

(defun draw-cylinder-readouts (circuit)
  "Print each cylinder's extension beside it.

On the canvas rather than in the HUD, because a circuit can hold several
cylinders and a single HUD figure could not say which one it meant."
  (dolist (component (ofs:circuit-components circuit))
    (when (member (ofs:component-kind component) ofs:*cylinder-kinds*)
      (let ((p (v2 (ofs:pt+ (ofs:component-origin component) (ofs:pt 2.0 24.0)))))
        (rl:draw-text (format nil "~d%"
                              (round (* 100 (ofs:component-travel component))))
                      (round (v:vx p)) (round (v:vy p)) 7 :maroon)))))

(defun draw-canvas (editor camera)
  (let* ((circuit (editor-circuit editor))
         ;; Recomputed per frame: contacts open and close, so what is grounded
         ;; changes with them.
         (grounded (ofs:grounded-connectors circuit)))
    (draw-wires circuit grounded)
    (dolist (component (ofs:circuit-components circuit))
      (draw-ops (ofs:component-world-geometry component)))
    (draw-selection (editor-selected editor))
    (draw-cylinder-readouts circuit)
    (draw-connection-points circuit (editor-pending editor) grounded)
    (draw-ghost editor camera)))

(defun draw-hud (editor)
  (let ((running (eq (editor-mode editor) :run)))
    (rl:draw-rectangle 0 0 (rl:get-screen-width) *hud-height* :raywhite)
    (rl:draw-text (if running "RUN" "EDIT") 12 10 20 (if running :maroon :darkgray))
    ;; Clear of the mode label, which is 20px type and wider than it looks.
    (rl:draw-text "space run/stop   S save   L load   T retag   F fit   Del remove   right-drag pan   wheel zoom"
                  84 14 12 :gray)
    (rl:draw-text "click a port then another to wire them; click a wired pair again to unwire"
                  12 34 12 :gray)
    (rl:draw-text (if (editor-prompt editor)
                      (format nil "~a: ~a_" (prompt-label (editor-prompt editor))
                              (editor-prompt-buffer editor))
                      (editor-status editor))
                  12 52 12 (if (editor-prompt editor) :maroon :darkgray))
    (rl:draw-line-ex (v:vec2 0.0 (float *hud-height* 1.0))
                     (v:vec2 (float (rl:get-screen-width) 1.0) (float *hud-height* 1.0))
                     1.0 :gray)))

;;; ------------------------------------------------------------------

(defun run (&key (width 1100) (height 720) circuit)
  "Open the editor.

Starts on the relay demo unless a circuit is supplied: switch to RUN and click
the pushbutton to drive the valve and extend the cylinder."
  (let* ((editor (make-editor :circuit (or circuit (ofs:make-relay-demo-circuit))))
         (camera (rl:make-camera2d :offset (v:vec2 0.0 0.0)
                                   :target (v:vec2 0.0 0.0)
                                   :rotation 0.0
                                   :zoom 3.0))
         ;; The circuit the view was last fitted to. A load swaps the editor's
         ;; circuit for a different object, and this is how the loop notices.
         (fitted nil))
    ;; Must precede window creation -- these flags are read by InitWindow.
    (rl:set-config-flags '(:flag-window-resizable))
    (rl:with-window (width height "Open FluidSim")
      (rl:set-window-min-size 640 400)
      (rl:set-target-fps 60)
      (sync-camera-to-window camera)
      (loop until (window-should-close-p)
            do (sync-camera-to-window camera)
               (handle-pan-and-zoom editor camera)
               (handle-mouse editor camera)
               (handle-keys editor camera)
               ;; Read the circuit back *after* the input handlers, never once
               ;; before the loop: a load replaces it wholesale, and a captured
               ;; reference would leave the simulation running the old circuit
               ;; while the canvas drew the new one -- pressing a button in the
               ;; loaded drawing would then do nothing at all.
               (let ((circuit (editor-circuit editor)))
                 (when (or (not (eq circuit fitted)) (window-resized-p))
                   (fit-view camera circuit)
                   (setf fitted circuit))
                 (if (eq (editor-mode editor) :run)
                     (ofs:step-simulation circuit :dt (rl:get-frame-time))
                     ;; Editing: settle everything to zero so nothing reads live.
                     (ofs:propagate circuit :supply 0.0)))
               (rl:with-drawing
                 (rl:clear-background :raywhite)
                 (rl:with-mode-2d (camera)
                   (draw-canvas editor camera))
                 (draw-palette (editor-domain editor) (editor-placing editor))
                 (draw-hud editor))))))
