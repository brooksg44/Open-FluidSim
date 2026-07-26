;;;; palette.lisp -- the component palette down the left edge.
;;;;
;;;; Entries draw the component's own geometry through DRAW-OPS-FITTED, so a
;;;; palette entry cannot drift out of sync with the thing it places. The Unity
;;;; original kept a separate thumbnail sprite per component and they had to be
;;;; maintained in parallel.

(in-package #:open-fluidsim.ui)

(defparameter *hud-height* 72
  "Vertical space reserved for the HUD across the top of the window.")

(defparameter *palette-width* 148)
(defparameter *palette-entry-height* 76)
(defparameter *palette-gap* 6)

(defvar *palette-previews* (make-hash-table :test #'eq)
  "One prototype component per kind, built lazily, used only for drawing.")

(defun palette-preview (kind)
  (or (gethash kind *palette-previews*)
      (setf (gethash kind *palette-previews*)
            (ofs:make-component-of-kind kind))))

(defparameter *tab-height* 24)

(defun tab-rect (index)
  (let ((w (floor *palette-width* (length (ofs:domains)))))
    (values (* index w) *hud-height* w *tab-height*)))

(defun palette-domain-at (screen-x screen-y)
  "The domain tab under the given screen point, or NIL."
  (loop for domain in (ofs:domains)
        for index from 0
        do (multiple-value-bind (x y w h) (tab-rect index)
             (when (and (<= x screen-x (+ x w)) (<= y screen-y (+ y h)))
               (return domain)))))

(defun palette-entry-rect (index)
  "Screen rectangle of palette entry INDEX, as (values x y w h)."
  (values *palette-gap*
          (+ *hud-height* *tab-height* *palette-gap*
             (* index (+ *palette-entry-height* *palette-gap*)))
          (- *palette-width* (* 2 *palette-gap*))
          *palette-entry-height*))

(defun palette-kind-at (domain screen-x screen-y)
  "The component kind under the given screen point, or NIL."
  (when (< screen-x *palette-width*)
    (loop for (kind . nil) in (ofs:palette-for-domain domain)
          for index from 0
          do (multiple-value-bind (x y w h) (palette-entry-rect index)
               (when (and (<= x screen-x (+ x w))
                          (<= y screen-y (+ y h)))
                 (return kind))))))

(defun in-palette-p (screen-x)
  (< screen-x *palette-width*))

(defun domain-label (domain)
  (ecase domain (:electric "Elec") (:pneumatic "Pneu") (:hydraulic "Hyd")))

(defun draw-palette (domain selected-kind)
  (let ((height (rl:get-screen-height)))
    (rl:draw-rectangle 0 *hud-height* *palette-width* (- height *hud-height*)
                       :lightgray))
  ;; Domain tabs, mirroring the original's Electric / Pneumatic / Hydraulic.
  (loop for d in (ofs:domains)
        for index from 0
        do (multiple-value-bind (x y w h) (tab-rect index)
             (let ((current (eq d domain)))
               (rl:draw-rectangle x y w h (if current :raywhite :gray))
               (rl:draw-rectangle-lines x y w h :darkgray)
               (rl:draw-text (domain-label d) (+ x 8) (+ y 6) 11
                             (if current :maroon :raywhite)))))
  (loop for (kind . label) in (ofs:palette-for-domain domain)
        for index from 0
        do (multiple-value-bind (x y w h) (palette-entry-rect index)
             ;; Stop drawing once entries run past the bottom of the window.
             (when (< y (rl:get-screen-height))
               (let ((chosen (eq kind selected-kind)))
                 (rl:draw-rectangle x y w h (if chosen :beige :raywhite))
                 (rl:draw-rectangle-lines x y w h (if chosen :maroon :gray))
                 ;; The symbol itself, leaving a strip at the bottom for the name.
                 (draw-ops-fitted (ofs:component-world-geometry (palette-preview kind))
                                  x y w (- h 14))
                 (rl:draw-text label (+ x 5) (+ y h -13) 10 :darkgray))))))
