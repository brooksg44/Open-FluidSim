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
  (placing nil)                         ; kind awaiting a click on the canvas
  (selected nil)
  (pending nil)                         ; first connector of a wire in progress
  (dragging nil)
  (drag-dx 0.0)
  (drag-dy 0.0)
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

(defun handle-pan-and-zoom (camera)
  (when (rl:is-mouse-button-down :mouse-button-right)
    (let ((delta (rl:get-mouse-delta))
          (zoom (rl:camera2d-zoom camera))
          (target (rl:camera2d-target camera)))
      (decf (v:vx target) (/ (v:vx delta) zoom))
      (decf (v:vy target) (/ (v:vy delta) zoom))))
  (let ((wheel (rl:get-mouse-wheel-move)))
    (unless (zerop wheel)
      (setf (rl:camera2d-zoom camera)
            (max 0.5 (min 16.0 (+ (rl:camera2d-zoom camera) (* wheel 0.4))))))))

;;; ------------------------------------------------------------------
;;; Editing gestures
;;; ------------------------------------------------------------------

(defun place-component (editor at)
  (let ((component (ofs:make-component-of-kind (editor-placing editor)
                                               :origin at)))
    (ofs:add-component (editor-circuit editor) component)
    (setf (editor-selected editor) component
          (editor-placing editor) nil
          (editor-status editor)
          (format nil "Placed ~a." (ofs:component-name component)))
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

(defun handle-mouse (editor camera)
  (let ((screen (rl:get-mouse-position)))
    (cond
      ;; Palette clicks never reach the canvas.
      ((and (rl:is-mouse-button-pressed :mouse-button-left)
            (in-palette-p (v:vx screen)))
       (let ((kind (palette-kind-at (v:vx screen) (v:vy screen))))
         (when kind
           (setf (editor-placing editor) kind
                 (editor-pending editor) nil
                 (editor-status editor) "Click on the canvas to place it."))))
      ((rl:is-mouse-button-pressed :mouse-button-left)
       (let ((at (mouse-model-position camera)))
         (if (editor-placing editor)
             (place-component editor at)
             (begin-wire-or-select editor at))))))
  ;; Drag the selected component.
  (when (and (editor-dragging editor)
             (rl:is-mouse-button-down :mouse-button-left))
    (let ((at (mouse-model-position camera)))
      (ofs:move-component (editor-dragging editor)
                          (+ (ofs:pt-x at) (editor-drag-dx editor))
                          (+ (ofs:pt-y at) (editor-drag-dy editor)))))
  (unless (rl:is-mouse-button-down :mouse-button-left)
    (setf (editor-dragging editor) nil)))

(defun handle-keys (editor camera)
  (let ((circuit (editor-circuit editor)))
    (when (rl:is-key-pressed :key-escape)
      (setf (editor-placing editor) nil
            (editor-pending editor) nil
            (editor-status editor) "Cancelled."))
    (when (or (rl:is-key-pressed :key-delete) (rl:is-key-pressed :key-backspace))
      (let ((component (editor-selected editor)))
        (when component
          (ofs:remove-component circuit component)
          (setf (editor-selected editor) nil
                (editor-dragging editor) nil
                (editor-pending editor) nil
                (editor-status editor)
                (format nil "Removed ~a." (ofs:component-name component))))))
    (when (rl:is-key-pressed :key-space)
      (setf (editor-mode editor) (if (eq (editor-mode editor) :run) :edit :run)
            (editor-pending editor) nil
            (editor-status editor)
            (if (eq (editor-mode editor) :run)
                "Running. Hold 1 and 2 for the solenoid coils."
                "Editing. Simulation stopped.")))
    (when (rl:is-key-pressed :key-f)
      (fit-view camera circuit))
    ;; Coils are momentary, and drive every valve in the circuit.
    (when (eq (editor-mode editor) :run)
      (dolist (component (ofs:circuit-components circuit))
        (let ((solenoids (ofs:component-solenoids component)))
          (when (= 2 (length solenoids))
            (setf (ofs:solenoid-active (first solenoids)) (rl:is-key-down :key-one)
                  (ofs:solenoid-active (second solenoids)) (rl:is-key-down :key-two))))))))

;;; ------------------------------------------------------------------
;;; Drawing
;;; ------------------------------------------------------------------

(defun draw-wires (circuit)
  (dolist (wire (ofs:circuit-wires circuit))
    (let ((a (car wire)) (b (cdr wire)))
      (rl:draw-line-ex (v2 (ofs:connector-position a))
                       (v2 (ofs:connector-position b))
                       *wire-width*
                       (if (or (ofs:pressurised-p a) (ofs:pressurised-p b))
                           :maroon :darkgray)))))

(defun draw-connection-points (circuit pending)
  (dolist (component (ofs:circuit-components circuit))
    (dotimes (index (length (ofs:component-connectors component)))
      (let ((connector (ofs:component-connector component index))
            (centre (v2 (ofs:component-port-position component index))))
        (cond ((eq connector pending)
               (rl:draw-circle-v centre (* 1.6 *port-radius*) :orange))
              ((ofs:pressurised-p connector)
               (rl:draw-circle-v centre *port-radius* :maroon))
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

(defun draw-canvas (editor camera)
  (let ((circuit (editor-circuit editor)))
    (draw-wires circuit)
    (dolist (component (ofs:circuit-components circuit))
      (draw-ops (ofs:component-world-geometry component)))
    (draw-selection (editor-selected editor))
    (draw-connection-points circuit (editor-pending editor))
    (draw-ghost editor camera)))

(defun draw-hud (editor)
  (let ((running (eq (editor-mode editor) :run)))
    (rl:draw-rectangle 0 0 (rl:get-screen-width) *hud-height* :raywhite)
    (rl:draw-text (if running "RUN" "EDIT") 12 10 20 (if running :maroon :darkgray))
    ;; Clear of the mode label, which is 20px type and wider than it looks.
    (rl:draw-text "space run/stop   F fit   Esc cancel   Del remove   right-drag pan   wheel zoom"
                  84 14 12 :gray)
    (rl:draw-text "click a port then another to wire them; click a wired pair again to unwire"
                  12 34 12 :gray)
    (rl:draw-text (editor-status editor) 12 52 12 :darkgray)
    (rl:draw-line-ex (v:vec2 0.0 (float *hud-height* 1.0))
                     (v:vec2 (float (rl:get-screen-width) 1.0) (float *hud-height* 1.0))
                     1.0 :gray)))

;;; ------------------------------------------------------------------

(defun run (&key (width 1100) (height 720) circuit)
  "Open the editor. Starts on the worked demo circuit unless one is supplied."
  (let* ((circuit (or circuit (ofs:make-demo-circuit)))
         (editor (make-editor :circuit circuit))
         (camera (rl:make-camera2d :offset (v:vec2 0.0 0.0)
                                   :target (v:vec2 0.0 0.0)
                                   :rotation 0.0
                                   :zoom 3.0)))
    ;; Must precede window creation -- these flags are read by InitWindow.
    (rl:set-config-flags '(:flag-window-resizable))
    (rl:with-window (width height "Open FluidSim")
      (rl:set-window-min-size 640 400)
      (rl:set-target-fps 60)
      (sync-camera-to-window camera)
      (fit-view camera circuit)
      (loop until (rl:window-should-close)
            do (sync-camera-to-window camera)
               (when (rl:is-window-resized) (fit-view camera circuit))
               (handle-pan-and-zoom camera)
               (handle-mouse editor camera)
               (handle-keys editor camera)
               (if (eq (editor-mode editor) :run)
                   (ofs:step-simulation circuit :dt (rl:get-frame-time))
                   ;; Editing: settle everything to zero so nothing reads live.
                   (ofs:propagate circuit :supply 0.0))
               (rl:with-drawing
                 (rl:clear-background :raywhite)
                 (rl:with-mode-2d (camera)
                   (draw-canvas editor camera))
                 (draw-palette (editor-placing editor))
                 (draw-hud editor))))))
