;;;; geometry.lisp -- points and backend-agnostic drawing operations.
;;;;
;;;; A symbol is a list of drawing operations in its own local coordinate
;;;; system, with +y upward. Nothing here knows about raylib: a renderer walks
;;;; the list and dispatches on operation type, so the same geometry can drive
;;;; an OpenGL window, an SVG file, or a test that just inspects coordinates.

(in-package #:open-fluidsim)

(defstruct (pt (:constructor pt (x y)))
  (x 0.0 :type real)
  (y 0.0 :type real))

(defun pt+ (a b) (pt (+ (pt-x a) (pt-x b)) (+ (pt-y a) (pt-y b))))
(defun pt- (a b) (pt (- (pt-x a) (pt-x b)) (- (pt-y a) (pt-y b))))
(defun pt-scale (a s) (pt (* (pt-x a) s) (* (pt-y a) s)))

;;; Drawing operations.

(defstruct (polyline (:constructor polyline (points &key (width 1.0))))
  points (width 1.0))

(defstruct (poly (:constructor poly (points)))          ; filled polygon
  points)

(defstruct (disc (:constructor disc (center radius &key filled)))
  center radius filled)

(defstruct (box (:constructor box (x y w h &key (width 1.0))))
  x y w h (width 1.0))

(defstruct (caption (:constructor caption (pos text &key (size 10))))
  pos text (size 10))

(defun translate-op (op dx dy)
  "Return OP shifted by DX, DY."
  (flet ((shift (p) (pt (+ (pt-x p) dx) (+ (pt-y p) dy))))
    (etypecase op
      (polyline (polyline (mapcar #'shift (polyline-points op))
                          :width (polyline-width op)))
      (poly     (poly (mapcar #'shift (poly-points op))))
      (disc     (disc (shift (disc-center op)) (disc-radius op)
                      :filled (disc-filled op)))
      (box      (box (+ (box-x op) dx) (+ (box-y op) dy)
                     (box-w op) (box-h op) :width (box-width op)))
      (caption  (caption (shift (caption-pos op)) (caption-text op)
                         :size (caption-size op))))))

(defun translate-ops (ops dx dy)
  (mapcar (lambda (op) (translate-op op dx dy)) ops))

(defun op-points (op)
  "Every point OP touches, for bounds calculation."
  (etypecase op
    (polyline (polyline-points op))
    (poly     (poly-points op))
    (disc     (let ((c (disc-center op)) (r (disc-radius op)))
                (list (pt (- (pt-x c) r) (- (pt-y c) r))
                      (pt (+ (pt-x c) r) (+ (pt-y c) r)))))
    (box      (list (pt (box-x op) (box-y op))
                    (pt (+ (box-x op) (box-w op)) (+ (box-y op) (box-h op)))))
    (caption  (list (caption-pos op)))))

(defun ops-bounds (ops)
  "Return (values min-x min-y max-x max-y) covering OPS, or NIL if empty."
  (let ((points (mapcan (lambda (op) (copy-list (op-points op))) ops)))
    (when points
      (values (reduce #'min points :key #'pt-x)
              (reduce #'min points :key #'pt-y)
              (reduce #'max points :key #'pt-x)
              (reduce #'max points :key #'pt-y)))))
