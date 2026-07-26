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

(defun palette-entry-rect (index)
  "Screen rectangle of palette entry INDEX, as (values x y w h)."
  (values *palette-gap*
          (+ *hud-height* *palette-gap*
             (* index (+ *palette-entry-height* *palette-gap*)))
          (- *palette-width* (* 2 *palette-gap*))
          *palette-entry-height*))

(defun palette-kind-at (screen-x screen-y)
  "The component kind under the given screen point, or NIL."
  (when (< screen-x *palette-width*)
    (loop for (kind . nil) in ofs:*palette*
          for index from 0
          do (multiple-value-bind (x y w h) (palette-entry-rect index)
               (when (and (<= x screen-x (+ x w))
                          (<= y screen-y (+ y h)))
                 (return kind))))))

(defun in-palette-p (screen-x)
  (< screen-x *palette-width*))

(defun draw-palette (selected-kind)
  (let ((height (rl:get-screen-height)))
    (rl:draw-rectangle 0 *hud-height* *palette-width* (- height *hud-height*)
                       :lightgray))
  (loop for (kind . label) in ofs:*palette*
        for index from 0
        do (multiple-value-bind (x y w h) (palette-entry-rect index)
             (let ((chosen (eq kind selected-kind)))
               (rl:draw-rectangle x y w h (if chosen :beige :raywhite))
               (rl:draw-rectangle-lines x y w h (if chosen :maroon :gray))
               ;; The symbol itself, leaving a strip at the bottom for the name.
               (draw-ops-fitted (ofs:component-world-geometry (palette-preview kind))
                                x y w (- h 16))
               (rl:draw-text label (+ x 6) (+ y h -14) 10 :darkgray)))))
