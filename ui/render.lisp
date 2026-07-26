;;;; render.lisp -- draw open-fluidsim geometry with raylib.
;;;;
;;;; The core emits drawing operations in a y-up coordinate system and knows
;;;; nothing about raylib; this file is the only place that knows raylib
;;;; exists. Adding an SVG exporter later means writing a second file like
;;;; this one, not touching the symbol definitions.
;;;;
;;;; Two ways to draw the same operations:
;;;;
;;;;   - On the canvas, inside RL:WITH-MODE-2D, where the camera does the
;;;;     scaling and the view transform below is identity.
;;;;   - As a palette thumbnail, via DRAW-OPS-FITTED, which scales geometry
;;;;     into a screen-space rectangle. Palette entries are therefore the real
;;;;     symbol rather than a separate icon that can drift out of sync.

(in-package #:open-fluidsim.ui)

(defvar *view-scale* 1.0)
(defvar *view-dx* 0.0)
(defvar *view-dy* 0.0)

(defun v2 (p)
  "Convert a y-up core point to a y-down raylib vector under the view transform."
  (v:vec2 (float (+ *view-dx* (* *view-scale* (ofs:pt-x p))) 1.0)
          (float (- *view-dy* (* *view-scale* (ofs:pt-y p))) 1.0)))

(defun stroke-width (width)
  (max 1.0 (float (* *view-scale* width) 1.0)))

(defun draw-op (op color)
  (etypecase op
    (ofs:polyline
     (let ((points (ofs:polyline-points op))
           (width (stroke-width (ofs:polyline-width op))))
       (loop for (a b) on points while b
             do (rl:draw-line-ex (v2 a) (v2 b) width color))))
    (ofs:poly
     ;; Every polygon in the symbol set is a triangle (arrow heads and the
     ;; detent pawl). Hollow ones are pneumatic flow arrows, solid ones
     ;; hydraulic -- the ISO 1219 distinction between the two.
     (destructuring-bind (a b c) (ofs:poly-points op)
       (if (ofs:poly-filled op)
           ;; raylib culls by winding order, so draw both orientations rather
           ;; than depend on how the points were listed.
           (progn (rl:draw-triangle (v2 a) (v2 b) (v2 c) color)
                  (rl:draw-triangle (v2 a) (v2 c) (v2 b) color))
           (let ((w (stroke-width 1.0)))
             (rl:draw-line-ex (v2 a) (v2 b) w color)
             (rl:draw-line-ex (v2 b) (v2 c) w color)
             (rl:draw-line-ex (v2 c) (v2 a) w color)))))
    (ofs:disc
     (let ((centre (v2 (ofs:disc-center op)))
           (radius (float (* *view-scale* (ofs:disc-radius op)) 1.0)))
       (if (ofs:disc-filled op)
           (rl:draw-circle-v centre radius color)
           (rl:draw-circle-lines-v centre radius color))))
    (ofs:box
     ;; Core boxes are y-up anchored at the lower-left corner; raylib
     ;; rectangles are y-down anchored at the upper-left, so flip to the top edge.
     (let ((corner (v2 (ofs:pt (ofs:box-x op)
                               (+ (ofs:box-y op) (ofs:box-h op))))))
       (rl:draw-rectangle-lines-ex
        (rl:make-rectangle :x (v:vx corner)
                           :y (v:vy corner)
                           :width (float (* *view-scale* (ofs:box-w op)) 1.0)
                           :height (float (* *view-scale* (ofs:box-h op)) 1.0))
        (stroke-width (ofs:box-width op))
        color)))
    (ofs:caption
     (let ((p (v2 (ofs:caption-pos op))))
       (rl:draw-text (ofs:caption-text op)
                     (round (v:vx p)) (round (v:vy p))
                     (max 1 (round (* *view-scale* (ofs:caption-size op))))
                     color)))))

(defun draw-ops (ops &key (color :black))
  (dolist (op ops) (draw-op op color)))

(defun draw-ops-fitted (ops x y w h &key (color :black) (margin 0.8))
  "Draw OPS scaled to fit the screen-space rectangle X Y W H."
  (multiple-value-bind (min-x min-y max-x max-y) (ofs:ops-bounds ops)
    (when min-x
      (let* ((span-x (max 1.0 (- max-x min-x)))
             (span-y (max 1.0 (- max-y min-y)))
             (scale (* margin (min (/ w span-x) (/ h span-y))))
             (centre-x (/ (+ min-x max-x) 2.0))
             (centre-y (/ (+ min-y max-y) 2.0))
             (*view-scale* scale)
             (*view-dx* (- (+ x (/ w 2.0)) (* scale centre-x)))
             (*view-dy* (+ (+ y (/ h 2.0)) (* scale centre-y))))
        (draw-ops ops :color color)))))
