;;;; engine.lisp -- actuator logic and pressure propagation.
;;;;
;;;; The Unity original propagated by recursive callback (RespondToSignal ->
;;;; SpreadSignal -> RespondToSignal ...), which made cycles in the circuit a
;;;; hazard and the order of evaluation hard to reason about. Here propagation
;;;; is a plain flood fill over an undirected graph whose edges are the wires
;;;; plus each component's internal connections for its current state, so
;;;; loops are handled by the visited set and the result is order-independent.

(in-package #:open-fluidsim)

(defun energise (solenoid) (setf (solenoid-active solenoid) t))
(defun de-energise (solenoid) (setf (solenoid-active solenoid) nil))

(defun pressurised-p (connector)
  (> (connector-pressure connector) 0.0))

(defun update-actuators (circuit)
  "Advance every component's position from its actuator states.

A detented valve holds its last commanded position when both solenoids are off
-- and when both are on. That behaviour is the *absence* of an else branch
here: nothing resets the state, so it persists."
  (dolist (component (circuit-components circuit))
    (let ((solenoids (component-solenoids component)))
      (when (= 2 (length solenoids))
        (let ((left (first solenoids))
              (right (second solenoids)))
          (cond ((and (solenoid-active left) (not (solenoid-active right)))
                 (setf (component-state component) :left))
                ((and (solenoid-active right) (not (solenoid-active left)))
                 (setf (component-state component) :right))
                ;; Both off or both on: the detent holds. Deliberately no clause.
                (t nil)))))))

(defun internal-neighbours (connector)
  "Connectors joined to CONNECTOR inside its own component, at the current state."
  (let* ((owner (connector-owner connector)))
    (when owner
      (let* ((table (component-table owner))
             (target (aref table (connector-index connector))))
        (when (>= target 0)
          (list (component-connector owner target)))))))

(defun wire-neighbours (circuit connector)
  "Connectors wired externally to CONNECTOR."
  (let ((result '()))
    (dolist (wire (circuit-wires circuit) result)
      (cond ((eq (car wire) connector) (push (cdr wire) result))
            ((eq (cdr wire) connector) (push (car wire) result))))))

(defun source-connectors (circuit)
  "Every connector held at supply pressure.

Any :SUPPLY component counts as a source by virtue of being one, so dropping a
supply onto the canvas pressurises the circuit with no extra bookkeeping.
CIRCUIT-SOURCES remains for marking an arbitrary connector live by hand."
  (remove-duplicates
   (append (circuit-sources circuit)
           (loop for component in (circuit-components circuit)
                 when (eq (component-kind component) :supply)
                   collect (component-connector component 0)))))

(defun propagate (circuit &key (supply 1.0))
  "Flood supply pressure through the circuit; return the set of live connectors."
  (dolist (component (circuit-components circuit))
    (loop for c across (component-connectors component)
          do (setf (connector-pressure c) 0.0)))
  (let ((visited (make-hash-table :test #'eq))
        (queue (source-connectors circuit)))
    (dolist (source queue) (setf (gethash source visited) t))
    (loop while queue
          for connector = (pop queue)
          do (setf (connector-pressure connector) supply)
             (dolist (next (append (internal-neighbours connector)
                                   (wire-neighbours circuit connector)))
               (unless (gethash next visited)
                 (setf (gethash next visited) t)
                 (push next queue))))
    visited))

(defun update-cylinders (circuit dt)
  "Drive piston travel from the pressure at each cylinder's two ports.

With neither port pressurised the piston holds position rather than drifting,
so a detented valve parked between commands leaves the cylinder where it was."
  (dolist (component (circuit-components circuit))
    (when (eq (component-kind component) :cylinder-double-acting)
      (let* ((cap (component-connector component 0))
             (rod (component-connector component 1))
             (travel (component-travel component))
             (target (cond ((and (pressurised-p cap) (not (pressurised-p rod))) 1.0)
                           ((and (pressurised-p rod) (not (pressurised-p cap))) 0.0)
                           (t travel)))
             (step (* (component-travel-rate component) dt))
             (delta (- target travel)))
        (setf (component-travel component)
              (cond ((<= (abs delta) step) target)
                    ((plusp delta) (+ travel step))
                    (t (- travel step))))))))

(defun step-simulation (circuit &key (supply 1.0) (dt 1/60))
  "One simulation step: settle valve positions, propagate pressure, then move
pistons. Cylinders move from the pressures this step just computed, so there
is no one-frame lag between a valve shifting and the cylinder responding."
  (update-actuators circuit)
  (prog1 (propagate circuit :supply supply)
    (update-cylinders circuit dt)))
