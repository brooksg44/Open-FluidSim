;;;; engine.lisp -- actuator logic and propagation.
;;;;
;;;; The Unity original propagated by recursive callback (RespondToSignal ->
;;;; SpreadSignal -> RespondToSignal ...), which made cycles in the circuit a
;;;; hazard and the order of evaluation hard to reason about. Here propagation
;;;; is a flood fill over an undirected graph whose edges are the wires plus
;;;; each component's internal connections for its current state, so loops are
;;;; handled by the visited set and the result is order-independent.
;;;;
;;;; Fluid and electric circuits use the same code: a wire is a wire, and a
;;;; contact that is open blocks exactly like a valve port that is shut.

(in-package #:open-fluidsim)

(defun energise (solenoid) (setf (solenoid-active solenoid) t))
(defun de-energise (solenoid) (setf (solenoid-active solenoid) nil))

(defun pressurised-p (connector)
  (> (connector-pressure connector) 0.0))

(defun internal-neighbours (connector)
  "Connectors joined to CONNECTOR inside its own component, at the current state."
  (let ((owner (connector-owner connector)))
    (when owner
      (let* ((table (component-table owner))
             (target (aref table (connector-index connector))))
        (when (>= target 0)
          (list (component-connector owner target)))))))

(defun wire-neighbours (circuit connector)
  (let ((result '()))
    (dolist (wire (circuit-wires circuit) result)
      (cond ((eq (car wire) connector) (push (cdr wire) result))
            ((eq (cdr wire) connector) (push (car wire) result))))))

(defun flood (circuit start)
  "Connectors reachable from START, as a hash table used as a set."
  (let ((visited (make-hash-table :test #'eq))
        (queue (copy-list start)))
    (dolist (connector queue) (setf (gethash connector visited) t))
    (loop while queue
          for connector = (pop queue)
          do (dolist (next (append (internal-neighbours connector)
                                   (wire-neighbours circuit connector)))
               (unless (gethash next visited)
                 (setf (gethash next visited) t)
                 (push next queue))))
    visited))

(defun source-connectors (circuit)
  "Every connector held at supply potential.

A :SUPPLY, :PUMP or :POWER-24V component is a source by virtue of being one,
so dropping one onto the canvas energises the circuit with no extra
bookkeeping. CIRCUIT-SOURCES remains for marking a connector live by hand."
  (remove-duplicates
   (append (circuit-sources circuit)
           (loop for component in (circuit-components circuit)
                 when (member (component-kind component) '(:supply :pump :power-24v))
                   collect (component-connector component 0)))))

(defun return-connectors (circuit)
  "Connectors that complete a circuit back to 0V."
  (loop for component in (circuit-components circuit)
        when (eq (component-kind component) :common-0v)
          collect (component-connector component 0)))

(defun propagate (circuit &key (supply 1.0))
  "Flood supply through the circuit; return the set of live connectors."
  (dolist (component (circuit-components circuit))
    (loop for c across (component-connectors component)
          do (setf (connector-pressure c) 0.0)))
  (let ((live (flood circuit (source-connectors circuit))))
    (maphash (lambda (connector present)
               (declare (ignore present))
               (setf (connector-pressure connector) supply))
             live)
    live))

;;; ------------------------------------------------------------------
;;; Actuators
;;; ------------------------------------------------------------------

(defun update-valves (circuit)
  "Advance every valve's position from its coils.

A spring-return valve falls back to its rest position when nothing is
energised. A detented valve holds where it was last sent -- and that behaviour
is the *absence* of a clause here: nothing resets the state, so it persists."
  (dolist (component (circuit-components circuit))
    (let ((solenoids (component-solenoids component)))
      (case (length solenoids)
        (1 (setf (component-state component)
                 (if (solenoid-active (first solenoids))
                     (component-left-state component)
                     (component-rest-state component))))
        (2 (let ((left (solenoid-active (first solenoids)))
                 (right (solenoid-active (second solenoids))))
             (cond ((and left (not right))
                    (setf (component-state component) (component-left-state component)))
                   ((and right (not left))
                    (setf (component-state component) (component-right-state component)))
                   ((eq (component-hold component) :spring)
                    (setf (component-state component) (component-rest-state component)))
                   ;; Detent: both off or both on, hold position. No clause.
                   (t nil))))))))

(defun update-cylinders (circuit dt)
  "Drive piston travel from the pressure at each cylinder's ports.

With nothing pressurised a double-acting piston holds position rather than
drifting, so a detented valve parked between commands leaves it where it was.
A single-acting cylinder is spring-returned and falls back instead."
  (dolist (component (circuit-components circuit))
    (when (member (component-kind component) *cylinder-kinds*)
      (let* ((connectors (component-connectors component))
             (single (= 1 (length connectors)))
             (cap (component-connector component 0))
             (rod (unless single (component-connector component 1)))
             (travel (component-travel component))
             (target (cond (single (if (pressurised-p cap) 1.0 0.0))
                           ((and (pressurised-p cap) (not (pressurised-p rod))) 1.0)
                           ((and (pressurised-p rod) (not (pressurised-p cap))) 0.0)
                           (t travel)))
             (step (* (component-travel-rate component) dt))
             (delta (- target travel)))
        (setf (component-travel component)
              (cond ((<= (abs delta) step) target)
                    ((plusp delta) (+ travel step))
                    (t (- travel step))))))))

(defun step-simulation (circuit &key (supply 1.0) (dt 1/60))
  "One simulation step.

Propagation runs twice: once so the electrical side can see which coils are
energised, and again after the valves have moved, so the fluid paths reflect
their new positions within the same step rather than a frame later."
  (propagate circuit :supply supply)
  (update-electric circuit)
  (update-valves circuit)
  (prog1 (propagate circuit :supply supply)
    (update-cylinders circuit dt)))
