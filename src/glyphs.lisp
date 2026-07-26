;;;; glyphs.lisp -- reusable ISO 1219 symbol elements.
;;;;
;;;; Each glyph is a list of drawing operations occupying (0,0)-(w,h) in its
;;;; own local frame, so symbols are composed by translating glyphs into place.
;;;; This is the point of the rewrite: in the Unity original every combination
;;;; of actuators needed its own pre-composited PNG, so adding a detent meant
;;;; hand-painting a new 280x74 sprite. Here a detented double-solenoid valve
;;;; is just a different list of glyphs.

(in-package #:open-fluidsim)

(defconstant +box-w+ 24.0 "Width of one valve position box.")
(defconstant +box-h+ 20.0 "Height of a valve body.")

(defconstant +actuator-h+ 10.0
  "Actuator glyphs are half body height, so two of them stack against the end
of a position box and together span it exactly.")

(defun glyph-solenoid (&key (w 14.0) (h +actuator-h+))
  "Solenoid actuator: a short box with a diagonal, per ISO 1219.
Only powered actuators are boxed, which is why the spring and detent are not."
  (list (box 0.0 0.0 w h)
        (polyline (list (pt 1.5 1.5) (pt (- w 1.5) (- h 1.5))))))

(defun glyph-spring (&key (w 14.0) (h +actuator-h+) (coils 3))
  "Return-spring: a continuous zigzag, drawn bare (no box)."
  (let ((points '())
        (step (/ w (* 2.0 coils))))
    (dotimes (i (1+ (* 2 coils)))
      (push (pt (* i step) (if (evenp i) 2.0 (- h 2.0))) points))
    (list (polyline (nreverse points)))))

(defun glyph-detent (&key (w 14.0) (h +actuator-h+))
  "Detent: a notched rail with a pawl seated in a notch.

Drawn bare rather than boxed -- ISO 1219 boxes only powered actuators. The
flat segments between the V notches are what distinguish it at a glance from
GLYPH-SPRING, which is a continuous zigzag with no flats."
  (let* ((mid (/ w 2.0))
         (rail-y (* h 0.78))
         (notch-y (* h 0.34))
         (shoulder (* w 0.20))
         (pawl-half (* w 0.17)))
    (list
     ;; Rail: flat, single V notch, flat. The flats are what distinguish it at
     ;; a glance from GLYPH-SPRING, which is a continuous zigzag with none.
     (polyline (list (pt 0.0 rail-y)
                     (pt (- mid shoulder) rail-y)
                     (pt mid notch-y)
                     (pt (+ mid shoulder) rail-y)
                     (pt w rail-y)))
     ;; Solid pawl seated in the notch.
     (poly (list (pt mid (- notch-y 0.5))
                 (pt (+ mid pawl-half) 0.0)
                 (pt (- mid pawl-half) 0.0))))))

(defun glyph-blocked (at &key (up t) (length 5.0))
  "A blocked port: a stub inward from the box edge, capped with a bar.

This is the shape that tells you at a glance which ports a position shuts off."
  (let* ((dy (if up (- length) length))
         (inner (pt (pt-x at) (+ (pt-y at) dy)))
         (half 3.0))
    (list (polyline (list at inner))
          (polyline (list (pt (- (pt-x inner) half) (pt-y inner))
                          (pt (+ (pt-x inner) half) (pt-y inner)))))))

(defun glyph-arrow (from to &key (head 5.0) (filled t))
  "Flow arrow from FROM to TO with a solid head at TO.

The head is deliberately several times the stroke width -- at symbol scale an
arrow whose head is only slightly wider than its shaft reads as a plain line."
  (let* ((dx (- (pt-x to) (pt-x from)))
         (dy (- (pt-y to) (pt-y from)))
         (len (max 0.001 (sqrt (+ (* dx dx) (* dy dy)))))
         (ux (/ dx len)) (uy (/ dy len))
         ;; Perpendicular, for the two base corners of the head.
         (px (- uy)) (py ux)
         (base (pt (- (pt-x to) (* ux head)) (- (pt-y to) (* uy head))))
         (half (* head 0.5)))
    (list (polyline (list from to))
          (poly (list to
                      (pt (+ (pt-x base) (* px half)) (+ (pt-y base) (* py half)))
                      (pt (- (pt-x base) (* px half)) (- (pt-y base) (* py half))))
                :filled filled))))

(defconstant +port-stub-length+ 6.0
  "How far a port line runs outside the body. Wires attach at its far end, not
where it leaves the body, so this is also the offset between a component's
flow-line ends and its connection points.")

(defun glyph-port-stub (at &key (length +port-stub-length+) (up t))
  "Short external port line at AT, pointing up or down out of the body."
  (let ((dy (if up length (- length))))
    (list (polyline (list at (pt (pt-x at) (+ (pt-y at) dy)))))))

(defun stub-end (at &key (up t))
  "The outer end of a port stub starting at AT -- where a wire connects."
  (pt (pt-x at) (+ (pt-y at) (if up +port-stub-length+ (- +port-stub-length+)))))
