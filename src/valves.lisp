;;;; valves.lisp -- directional control valves, built from a specification.
;;;;
;;;; Every valve in the library is the same drawing: N position boxes side by
;;;; side, flow arrows inside each, actuators on the ends, and fixed external
;;;; ports the body slides behind. Only the port layout, the connection tables
;;;; and the actuators differ. So they are data, and one geometry function
;;;; draws all of them -- 2/2, 3/2, 5/2 and 5/3, pneumatic and hydraulic.

(in-package #:open-fluidsim)

(defstruct valve-spec
  ports                                 ; flow-line ends, within box [0,+box-w+]
  states                                ; left-to-right order of position boxes
  tables                                ; state -> vector of targets, -1 blocked
  flows                                 ; state -> list of (from . to) for arrows
  rest                                  ; position with no coil energised
  (hold :spring)                        ; :spring returns to REST, :detent holds
  left-actuators                        ; inner to outer, e.g. (:solenoid :spring)
  right-actuators
  left-overlay)                         ; drawn above the inner left actuator

(defvar *valve-specs* (make-hash-table :test #'eq))

(defun valve-spec (kind)
  (or (gethash kind *valve-specs*)
      (error "No valve specification for ~s" kind)))

;;; ------------------------------------------------------------------
;;; Port layouts
;;; ------------------------------------------------------------------

(defparameter *ports-2-2*
  (vector (pt 12.0 10.0)                ; 0  A
          (pt 12.0 -10.0)))             ; 1  P

(defparameter *ports-3-2*
  (vector (pt 12.0 10.0)                ; 0  A
          (pt 6.0 -10.0)                ; 1  P
          (pt 18.0 -10.0)))             ; 2  R

(defparameter *ports-5-2*
  (vector (pt 6.0   10.0)               ; 0  A
          (pt 18.0  10.0)               ; 1  B
          (pt 4.0  -10.0)               ; 2  R
          (pt 12.0 -10.0)               ; 3  P
          (pt 20.0 -10.0)))             ; 4  S

;; Kept for the tests that predate the parametric rewrite.
(defparameter *valve-5-2-ports* *ports-5-2*)

;;; ------------------------------------------------------------------
;;; Geometry
;;; ------------------------------------------------------------------

(defun valve-box-ops (spec state dx filled)
  "Arrows and blocked-port marks for STATE, in a box offset by DX."
  (let ((table (cdr (assoc state (valve-spec-tables spec))))
        (flows (cdr (assoc state (valve-spec-flows spec))))
        (ports (valve-spec-ports spec))
        (ops '()))
    (dolist (flow flows)
      (let ((from (aref ports (car flow)))
            (to   (aref ports (cdr flow))))
        (dolist (op (glyph-arrow (pt (+ (pt-x from) dx) (pt-y from))
                                 (pt (+ (pt-x to) dx) (pt-y to))
                                 :filled filled))
          (push op ops))))
    ;; Anything the table blocks gets a capped stub instead of an arrow.
    (dotimes (index (length ports))
      (when (minusp (aref table index))
        (let ((p (aref ports index)))
          (dolist (op (glyph-blocked (pt (+ (pt-x p) dx) (pt-y p))
                                     :up (plusp (pt-y p))))
            (push op ops)))))
    (nreverse ops)))

(defun actuator-stack-ops (actuators outward-sign body-edge base)
  "Glyphs for one end of a valve, laid out from the body outward.

OUTWARD-SIGN is -1 for the left end and +1 for the right."
  (let ((ops '())
        (x body-edge))
    (dolist (actuator actuators (nreverse ops))
      (let ((left-edge (if (minusp outward-sign) (- x 14.0) x)))
        (dolist (op (ecase actuator
                      (:solenoid (translate-ops (glyph-solenoid) left-edge base))
                      (:spring   (translate-ops (glyph-spring) left-edge base))
                      (:detent   (translate-ops (glyph-detent) left-edge base))))
          (push op ops))
        (incf x (* outward-sign 14.0))))))

(defun valve-geometry-from-spec (component)
  (let* ((spec (valve-spec (component-kind component)))
         (states (valve-spec-states spec))
         (index (or (position (component-state component) states) 0))
         (count (length states))
         (filled (eq (component-domain component) :hydraulic))
         (half-h (- (/ +box-h+ 2)))
         (body-left (* (- index) +box-w+))
         (body-right (* (- count index) +box-w+))
         (ops '()))
    ;; Position boxes, the current one aligned to [0, +box-w+].
    (loop for state in states
          for j from 0
          for dx = (* (- j index) +box-w+)
          do (push (box dx half-h +box-w+ +box-h+) ops)
             (dolist (op (valve-box-ops spec state dx filled)) (push op ops)))
    (setf ops (nreverse ops))
    (append
     ops
     (actuator-stack-ops (valve-spec-left-actuators spec) -1 body-left half-h)
     (actuator-stack-ops (valve-spec-right-actuators spec) +1 body-right half-h)
     ;; The overlay -- a detent -- stacks above the inner left actuator.
     (when (valve-spec-left-overlay spec)
       (translate-ops (glyph-detent) (- body-left 14.0) (+ half-h +actuator-h+)))
     (valve-tag-captions component body-left body-right half-h)
     ;; External stubs stay put while the body slides.
     (loop for p across (valve-spec-ports spec)
           append (glyph-port-stub p :up (plusp (pt-y p)))))))

(defun refresh-solenoid-tags (component)
  "Name each valve coil after the valve's label: Y1 gives Y1a and Y1b.

Without this every valve would call its coils the same thing, and one electric
solenoid symbol would drive all of them at once."
  (loop for solenoid in (component-solenoids component)
        for suffix across "ab"
        do (setf (solenoid-name solenoid)
                 (format nil "~a~a" (component-label component) suffix)))
  component)

(defun valve-tag-captions (component body-left body-right base)
  "The coil tags, printed under the actuator they belong to."
  (let ((solenoids (component-solenoids component))
        (y (- base 7.0)))
    (append
     (when (first solenoids)
       (list (caption (pt (- body-left 14.0) y)
                      (solenoid-name (first solenoids)) :size 5)))
     (when (second solenoids)
       (list (caption (pt body-right y)
                      (solenoid-name (second solenoids)) :size 5))))))

(defun valve-connection-points (component)
  (map 'vector (lambda (p) (stub-end p :up (plusp (pt-y p))))
       (valve-spec-ports (valve-spec (component-kind component)))))

;;; ------------------------------------------------------------------
;;; Registration
;;; ------------------------------------------------------------------

(defun count-solenoids (spec)
  (+ (count :solenoid (valve-spec-left-actuators spec))
     (count :solenoid (valve-spec-right-actuators spec))))

(defun register-valve (kind &key label domain spec)
  (setf (gethash kind *valve-specs*) spec)
  (register-kind
   kind
   :label label
   :domain domain
   :make (lambda ()
           (let* ((solenoid-count (count-solenoids spec))
                  (component
                    (make-component
                     :name label
                     :kind kind
                     :domain domain
                     :state (valve-spec-rest spec)
                     :tables (valve-spec-tables spec)
                     :hold (valve-spec-hold spec)
                     :rest-state (valve-spec-rest spec)
                     :left-state (first (valve-spec-states spec))
                     :right-state (car (last (valve-spec-states spec)))
                     :solenoids (loop for i from 1 to solenoid-count
                                      collect (make-solenoid
                                               :name (format nil "Sol ~d" i))))))
             (setf (component-connectors component)
                   (make-connectors component (length (valve-spec-ports spec))))
             component))
   :label-prefix "Y"
   :ports #'valve-connection-points
   :geometry #'valve-geometry-from-spec))

(macrolet ((both-domains (base-kind label &body spec-form)
             ;; Pneumatic and hydraulic valves differ only in arrow fill and
             ;; which palette tab they appear under, so register them together.
             `(progn
                (register-valve ,base-kind :label ,label :domain :pneumatic
                                           :spec (progn ,@spec-form))
                (register-valve ,(intern (format nil "~a-HYD" base-kind) :keyword)
                                :label ,label :domain :hydraulic
                                :spec (progn ,@spec-form)))))

  (both-domains :valve-2-2 "2/2 Valve"
    (make-valve-spec
     :ports *ports-2-2*
     :states '(:open :closed)
     :tables '((:open . #(1 0)) (:closed . #(-1 -1)))
     :flows '((:open . ((1 . 0))) (:closed . ()))
     :rest :closed
     :left-actuators '(:solenoid)
     :right-actuators '(:spring)))

  (both-domains :valve-3-2 "3/2 Valve"
    (make-valve-spec
     :ports *ports-3-2*
     :states '(:open :closed)
     :tables '((:open . #(1 0 -1)) (:closed . #(2 -1 0)))
     :flows '((:open . ((1 . 0))) (:closed . ((0 . 2))))
     :rest :closed
     :left-actuators '(:solenoid)
     :right-actuators '(:spring)))

  (both-domains :valve-5-2 "5/2 Valve"
    (make-valve-spec
     :ports *ports-5-2*
     :states '(:left :right)
     :tables '((:left . #(3 4 -1 0 1)) (:right . #(2 3 0 1 -1)))
     :flows '((:left . ((3 . 0) (1 . 4))) (:right . ((3 . 1) (0 . 2))))
     :rest :right
     :left-actuators '(:solenoid)
     :right-actuators '(:spring)))

  (both-domains :valve-5-2-double "5/2 Double Sol"
    (make-valve-spec
     :ports *ports-5-2*
     :states '(:left :right)
     :tables '((:left . #(3 4 -1 0 1)) (:right . #(2 3 0 1 -1)))
     :flows '((:left . ((3 . 0) (1 . 4))) (:right . ((3 . 1) (0 . 2))))
     :rest :right
     :left-actuators '(:solenoid :spring)
     :right-actuators '(:solenoid :spring)))

  (both-domains :valve-5-2-detented "5/2 Detented"
    (make-valve-spec
     :ports *ports-5-2*
     :states '(:left :right)
     :tables '((:left . #(3 4 -1 0 1)) (:right . #(2 3 0 1 -1)))
     :flows '((:left . ((3 . 0) (1 . 4))) (:right . ((3 . 1) (0 . 2))))
     :rest :right
     :hold :detent
     :left-actuators '(:solenoid)
     :right-actuators '(:solenoid)
     :left-overlay :detent))

  (both-domains :valve-5-3 "5/3 Closed Centre"
    (make-valve-spec
     :ports *ports-5-2*
     :states '(:left :middle :right)
     :tables '((:left . #(3 4 -1 0 1))
               (:middle . #(-1 -1 -1 -1 -1))
               (:right . #(2 3 0 1 -1)))
     :flows '((:left . ((3 . 0) (1 . 4)))
              (:middle . ())
              (:right . ((3 . 1) (0 . 2))))
     :rest :middle
     :left-actuators '(:solenoid :spring)
     :right-actuators '(:solenoid :spring))))

(defun make-valve-5-2-double-solenoid (&key (name "5/2 Detented")
                                            (origin (pt 0.0 0.0)))
  "The detented 5/2, kept as a named constructor for existing callers."
  (let ((component (make-component-of-kind :valve-5-2-detented :origin origin)))
    (setf (component-name component) name)
    component))
