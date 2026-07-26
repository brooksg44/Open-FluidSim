;;;; library.lisp -- concrete components and a worked circuit.
;;;;
;;;; Each component kind supplies two things: COMPONENT-PORTS, the positions
;;;; where wires attach, and COMPONENT-GEOMETRY, the drawing operations for its
;;;; current state. Both are in the component's local frame; the renderer
;;;; offsets by COMPONENT-ORIGIN. Adding a component means adding two clauses.

(in-package #:open-fluidsim)

;;; ------------------------------------------------------------------
;;; 5/2 valve, solenoid at each end, detent instead of a return spring
;;; ------------------------------------------------------------------
;;;
;;; Port indices match the Unity original: 0 top-left (A), 1 top-right (B),
;;; 2 bottom-left (exhaust), 3 bottom-middle (P, supply), 4 bottom-right
;;; (exhaust). Ports are fixed; the body slides behind them.

;;; Two related sets of points, and the distinction matters:
;;;
;;;   *VALVE-5-2-PORTS*  where the internal flow lines meet the box edge. The
;;;                      arrows terminate here and the port stubs start here.
;;;   the connection points   the far end of those stubs, where wires attach.
;;;
;;; Putting them at the box edge instead would leave every wire ending part
;;; way along a line that then carries on past it.

(defparameter *valve-5-2-ports*
  (vector (pt 6.0   10.0)               ; 0  A
          (pt 18.0  10.0)               ; 1  B
          (pt 4.0  -10.0)               ; 2  exhaust
          (pt 12.0 -10.0)               ; 3  P (supply)
          (pt 20.0 -10.0)))             ; 4  exhaust

(defparameter *valve-5-2-connection-points*
  (map 'vector (lambda (p) (stub-end p :up (plusp (pt-y p)))) *valve-5-2-ports*)
  "Where wires attach: the outer end of each port stub.")

(defparameter *valve-5-2-tables*
  '((:left  . #(3 4 -1 0 1))
    (:right . #(2 3 0 1 -1)))
  "Internal connections per position; -1 is blocked. Symmetric by construction.")

(defparameter *valve-5-2-flows*
  '((:left  . ((3 . 0) (1 . 4)))
    (:right . ((3 . 1) (0 . 2))))
  "The same connections, oriented for drawing flow arrows.")

(defun make-valve-5-2-double-solenoid (&key (name "5/2 Valve (Detented)")
                                            (origin (pt 0.0 0.0)))
  (let ((component (make-component :name name
                                   :kind :valve-5-2-double-solenoid
                                   :state :right
                                   :origin origin
                                   :tables *valve-5-2-tables*
                                   :shift +box-w+
                                   :solenoids (list (make-solenoid :name "Sol 1")
                                                    (make-solenoid :name "Sol 2")))))
    (setf (component-connectors component) (make-connectors component 5))
    component))

(defun valve-body-arrows (state dx)
  "Flow arrows for STATE, drawn in a body box offset by DX."
  (let ((flows (cdr (assoc state *valve-5-2-flows*)))
        (ops '()))
    ;; Arrows run the full distance between port positions, so they terminate
    ;; exactly on the box edge where the external stub begins. Do not inset
    ;; them: an internal line that stops short of its port reads as unconnected.
    (dolist (flow flows (nreverse ops))
      (let ((from (aref *valve-5-2-ports* (car flow)))
            (to   (aref *valve-5-2-ports* (cdr flow))))
        (dolist (op (glyph-arrow (pt (+ (pt-x from) dx) (pt-y from))
                                 (pt (+ (pt-x to) dx) (pt-y to))))
          (push op ops))))))

(defun valve-geometry (component)
  "The body and its actuators slide as a unit; the port stubs stay put.

Actuator order follows the original symbol set: the powered solenoid sits
against the body and the detent goes outboard of it, in the position a return
spring occupies on a spring-centred valve."
  (let* ((state (component-state component))
         (slide (if (eq state :left) (component-shift component) 0.0))
         (base (- (/ +box-h+ 2)))          ; actuators sit on the body baseline
         (body '()))
    (push (box (- +box-w+) base +box-w+ +box-h+) body)
    (dolist (op (valve-body-arrows :left (- +box-w+))) (push op body))
    (push (box 0.0 base +box-w+ +box-h+) body)
    (dolist (op (valve-body-arrows :right 0.0)) (push op body))
    (setf body (nreverse body))
    (let ((left-sol  (translate-ops (glyph-solenoid) (- (+ +box-w+ 14.0)) base))
          (right-sol (translate-ops (glyph-solenoid) +box-w+ base))
          ;; The detent stacks directly above the left solenoid, sharing its
          ;; column so both glyphs touch the position box.
          (detent    (translate-ops (glyph-detent) (- (+ +box-w+ 14.0))
                                    (+ base +actuator-h+)))
          (stubs '()))
      (dotimes (i 5)
        (let ((p (aref *valve-5-2-ports* i)))
          (dolist (op (glyph-port-stub p :up (> (pt-y p) 0)))
            (push op stubs))))
      (append (translate-ops (append body left-sol right-sol detent) slide 0.0)
              stubs))))

;;; ------------------------------------------------------------------
;;; Supply and exhaust
;;; ------------------------------------------------------------------

(defun make-supply (&key (name "Supply") (origin (pt 0.0 0.0)))
  "Compressed air source. Its single port is held at supply pressure."
  (let ((component (make-component :name name :kind :supply :state :fixed
                                   :origin origin :tables (fixed-table 1))))
    (setf (component-connectors component) (make-connectors component 1))
    component))

(defun supply-geometry (component)
  (declare (ignore component))
  (list (disc (pt 0.0 0.0) 9.0)                       ; outline circle
        (poly (list (pt 0.0 5.0) (pt -4.5 -2.5) (pt 4.5 -2.5)))
        (polyline (list (pt 0.0 9.0) (stub-end (pt 0.0 9.0))))))

(defun make-exhaust (&key (name "Exhaust") (origin (pt 0.0 0.0)))
  "Vent to atmosphere."
  (let ((component (make-component :name name :kind :exhaust :state :fixed
                                   :origin origin :tables (fixed-table 1))))
    (setf (component-connectors component) (make-connectors component 1))
    component))

(defun exhaust-geometry (component)
  (declare (ignore component))
  ;; Stem down from the port to an open triangle -- open, because it vents.
  (list (polyline (list (pt 0.0 10.0) (pt 0.0 4.0)))
        (polyline (list (pt -5.0 -4.0) (pt 0.0 4.0) (pt 5.0 -4.0)))))

;;; ------------------------------------------------------------------
;;; Double-acting cylinder
;;; ------------------------------------------------------------------

(defconstant +cylinder-length+ 80.0)
(defconstant +cylinder-half-h+ 16.0)

(defun make-cylinder (&key (name "Cylinder") (origin (pt 0.0 0.0)))
  "Double-acting cylinder. Port 0 is the cap end (extends), port 1 the rod end."
  (let ((component (make-component :name name :kind :cylinder-double-acting
                                   :state :fixed :origin origin
                                   :tables (fixed-table 2))))
    (setf (component-connectors component) (make-connectors component 2))
    component))

(defun cylinder-geometry (component)
  (let* ((travel (component-travel component))
         (h +cylinder-half-h+)
         (piston-x (+ 14.0 (* travel 52.0))))
    (append
     (list (box 0.0 (- h) +cylinder-length+ (* 2 h))
           ;; Piston face.
           (polyline (list (pt piston-x (- h)) (pt piston-x h)) :width 2.5)
           ;; Rod, out through the right-hand end cap.
           (polyline (list (pt piston-x 0.0) (pt (+ +cylinder-length+ 30.0) 0.0))
                     :width 2.5))
     ;; Port stubs, down out of the barrel at each end.
     (glyph-port-stub (pt 10.0 (- h)) :up nil)
     (glyph-port-stub (pt 70.0 (- h)) :up nil))))

;;; ------------------------------------------------------------------
;;; Dispatch
;;; ------------------------------------------------------------------

(defun component-ports (component)
  "Vector of local attachment points, indexed like the component's connectors."
  (ecase (component-kind component)
    (:valve-5-2-double-solenoid *valve-5-2-connection-points*)
    (:supply   (vector (stub-end (pt 0.0 9.0))))
    (:exhaust  (vector (pt 0.0 10.0)))
    (:cylinder-double-acting
     (vector (stub-end (pt 10.0 (- +cylinder-half-h+)) :up nil)
             (stub-end (pt 70.0 (- +cylinder-half-h+)) :up nil)))))

(defun component-port-position (component index)
  "World position of port INDEX."
  (pt+ (component-origin component) (aref (component-ports component) index)))

(defun connector-position (connector)
  (component-port-position (connector-owner connector)
                           (connector-index connector)))

(defun component-geometry (component)
  "Drawing operations in the component's local frame."
  (ecase (component-kind component)
    (:valve-5-2-double-solenoid (valve-geometry component))
    (:supply (supply-geometry component))
    (:exhaust (exhaust-geometry component))
    (:cylinder-double-acting (cylinder-geometry component))))

(defun component-world-geometry (component)
  (let ((origin (component-origin component)))
    (translate-ops (component-geometry component) (pt-x origin) (pt-y origin))))

(defun circuit-bounds (circuit)
  "Extent of everything drawn, as (values min-x min-y max-x max-y).

Returns NIL for an empty circuit. Used to fit the view to the drawing, so a
renderer never has to guess a zoom level."
  (ops-bounds (mapcan #'component-world-geometry (circuit-components circuit))))

;;; ------------------------------------------------------------------
;;; A worked circuit
;;; ------------------------------------------------------------------

(defun make-demo-circuit ()
  "Supply -> 5/2 detented valve -> double-acting cylinder, with both exhausts.

Returns (values circuit valve cylinder). Energising Sol 1 puts the valve in
:left, which routes P to A and extends the cylinder; Sol 2 retracts it. With
both coils off the detent holds, so the cylinder stays where it was sent --
which is the whole point of a memory valve."
  (let* ((circuit  (make-circuit))
         (valve    (make-valve-5-2-double-solenoid :origin (pt 0.0 0.0)))
         ;; Spread the three bottom components out: at valve port spacing they
         ;; would overlap each other, since each symbol is wider than 12 units.
         (supply   (make-supply   :origin (pt 12.0 -76.0)))
         (exhaust-a (make-exhaust :origin (pt -34.0 -76.0) :name "Exhaust A"))
         (exhaust-b (make-exhaust :origin (pt 58.0  -76.0) :name "Exhaust B"))
         (cylinder (make-cylinder :origin (pt -40.0 70.0))))
    (dolist (c (list valve supply exhaust-a exhaust-b cylinder))
      (add-component circuit c))
    (connect circuit (component-connector valve 3) (component-connector supply 0))
    (connect circuit (component-connector valve 2) (component-connector exhaust-a 0))
    (connect circuit (component-connector valve 4) (component-connector exhaust-b 0))
    (connect circuit (component-connector valve 0) (component-connector cylinder 0))
    (connect circuit (component-connector valve 1) (component-connector cylinder 1))
    ;; No ADD-SOURCE needed: the supply component is a source by its kind.
    (values circuit valve cylinder)))
