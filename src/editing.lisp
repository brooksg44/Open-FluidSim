;;;; editing.lisp -- operations an editor needs: what is under the cursor,
;;;; and how to add, move and remove things.
;;;;
;;;; Deliberately renderer-free. Hit testing works in model coordinates, so the
;;;; UI converts screen to model once and everything here stays testable
;;;; without opening a window.

(in-package #:open-fluidsim)

(defparameter *palette*
  '((:supply                    . "Supply")
    (:exhaust                   . "Exhaust")
    (:valve-5-2-double-solenoid . "5/2 Detented")
    (:cylinder-double-acting    . "Cylinder"))
  "Component kinds offered by the palette, in display order.")

(defun make-component-of-kind (kind &key (origin (pt 0.0 0.0)))
  "Construct a component by kind. The palette places components through this,
so a new kind becomes available by adding one clause."
  (ecase kind
    (:supply                    (make-supply :origin origin))
    (:exhaust                   (make-exhaust :origin origin))
    (:valve-5-2-double-solenoid (make-valve-5-2-double-solenoid :origin origin))
    (:cylinder-double-acting    (make-cylinder :origin origin))))

(defun component-bounds (component)
  (ops-bounds (component-world-geometry component)))

(defun point-in-component-p (component x y &key (slack 3.0))
  (multiple-value-bind (min-x min-y max-x max-y) (component-bounds component)
    (and min-x
         (<= (- min-x slack) x (+ max-x slack))
         (<= (- min-y slack) y (+ max-y slack)))))

(defun component-at (circuit x y)
  "Topmost component whose bounds contain the point, or NIL.

Components are consed on, so the list runs newest first -- which is also
drawing order, so FIND-IF picks what the user sees on top."
  (find-if (lambda (component) (point-in-component-p component x y))
           (circuit-components circuit)))

(defun connector-at (circuit x y &key (radius 5.0))
  "Connector within RADIUS of the point, or NIL."
  (dolist (component (circuit-components circuit))
    (dotimes (index (length (component-connectors component)))
      (let* ((p (component-port-position component index))
             (dx (- x (pt-x p)))
             (dy (- y (pt-y p))))
        (when (<= (+ (* dx dx) (* dy dy)) (* radius radius))
          (return-from connector-at (component-connector component index))))))
  nil)

(defun move-component (component x y)
  (setf (component-origin component) (pt x y))
  component)

(defun wire-between (circuit a b)
  "The existing wire joining A and B, in either direction, or NIL."
  (find-if (lambda (wire)
             (or (and (eq (car wire) a) (eq (cdr wire) b))
                 (and (eq (car wire) b) (eq (cdr wire) a))))
           (circuit-wires circuit)))

(defun toggle-wire (circuit a b)
  "Connect A and B, or disconnect them if already joined. Returns :connected,
:disconnected, or NIL when the pair is not wireable."
  (cond ((or (null a) (null b) (eq a b)) nil)
        ;; Two ports of the same component would be a wire to itself.
        ((eq (connector-owner a) (connector-owner b)) nil)
        (t (let ((existing (wire-between circuit a b)))
             (cond (existing
                    (setf (circuit-wires circuit)
                          (remove existing (circuit-wires circuit)))
                    :disconnected)
                   (t (connect circuit a b)
                      :connected))))))

(defun remove-component (circuit component)
  "Remove COMPONENT and every wire attached to it."
  (flet ((attached-p (connector) (eq (connector-owner connector) component)))
    (setf (circuit-components circuit)
          (remove component (circuit-components circuit))
          (circuit-wires circuit)
          (remove-if (lambda (wire)
                       (or (attached-p (car wire)) (attached-p (cdr wire))))
                     (circuit-wires circuit))
          (circuit-sources circuit)
          (remove-if #'attached-p (circuit-sources circuit))))
  component)

(defun clear-circuit (circuit)
  (setf (circuit-components circuit) '()
        (circuit-wires circuit) '()
        (circuit-sources circuit) '())
  circuit)
