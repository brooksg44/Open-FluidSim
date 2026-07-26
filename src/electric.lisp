;;;; electric.lisp -- the electrical side: rails, contacts, buttons, coils.
;;;;
;;;; Electric components reuse the fluid engine. A wire is a wire, and an open
;;;; contact blocks exactly like a shut valve port, so the same flood fill
;;;; serves both. What differs is energisation: a coil is only energised when
;;;; current can reach it from +24V *and* return from it to 0V, which needs a
;;;; flood from each rail rather than one.
;;;;
;;;; Components are linked by LABEL rather than by an explicit reference: a
;;;; coil labelled "K1" actuates every contact labelled "K1", and a solenoid
;;;; labelled "Sol 1" drives the valve coil of that name.

(in-package #:open-fluidsim)

(defparameter *lead* 12.0 "Half-width of an inline electric symbol.")

(defun inline-ports (component)
  (declare (ignore component))
  (vector (pt (- *lead*) 0.0) (pt *lead* 0.0)))

(defun leads ()
  (list (polyline (list (pt (- *lead*) 0.0) (pt -4.0 0.0)))
        (polyline (list (pt 4.0 0.0) (pt *lead* 0.0)))))

(defun contact-geometry (component)
  "Two contact faces, bridged by a bar when closed. NC types carry a slash."
  (let ((closed (eq (component-state component) :closed))
        (nc (member (component-kind component)
                    '(:contact-nc :push-button-closed :sensor-nc))))
    (append
     (leads)
     (list (polyline (list (pt -4.0 -5.0) (pt -4.0 5.0)))
           (polyline (list (pt 4.0 -5.0) (pt 4.0 5.0))))
     (when closed
       (list (polyline (list (pt -4.0 0.0) (pt 4.0 0.0)) :width 2.0)))
     (when nc
       (list (polyline (list (pt -7.0 -7.0) (pt 7.0 7.0)))))
     ;; Button cap for the pushbutton variants.
     (when (member (component-kind component)
                   '(:push-button :push-button-closed))
       (list (polyline (list (pt 0.0 5.0) (pt 0.0 11.0)))
             (polyline (list (pt -5.0 11.0) (pt 5.0 11.0)) :width 2.0)))
     ;; Label, so linked pairs can be told apart.
     (list (caption (pt -7.0 -13.0) (component-label component) :size 5)))))

(defun coil-geometry (component)
  (append
   (leads)
   (list (box -8.0 -6.0 16.0 12.0))
   ;; A solenoid gets the diagonal that marks a powered actuator.
   (when (eq (component-kind component) :solenoid-out)
     (list (polyline (list (pt -6.0 -4.0) (pt 6.0 4.0)))))
   (list (caption (pt -7.0 -14.0) (component-label component) :size 5))))

(defun rail-geometry (component)
  (let* ((top (eq (component-kind component) :power-24v))
         (y (if top 6.0 -6.0)))
    (list (polyline (list (pt -12.0 y) (pt 12.0 y)) :width 2.0)
          (polyline (list (pt 0.0 y) (pt 0.0 0.0)))
          (caption (pt -9.0 (if top 15.0 -10.0))
                   (if top "+24V" "0V") :size 5))))

(defun rail-ports (component)
  (declare (ignore component))
  (vector (pt 0.0 0.0)))

;;; ------------------------------------------------------------------
;;; Registration
;;; ------------------------------------------------------------------

(defun register-electric (kind &key label ports geometry (connectors 2)
                                    (state :open) (label-default "") prefix)
  (register-kind
   kind :label label :domain :electric :label-prefix prefix
   :make (lambda ()
           (let ((component (make-component :name label :kind kind
                                            :domain :electric
                                            :state state
                                            :label label-default
                                            :tables (electric-tables state))))
             (setf (component-connectors component)
                   (make-connectors component connectors))
             component))
   :ports ports
   :geometry geometry))

(defun electric-tables (state)
  (declare (ignore state))
  ;; All states are always present; COMPONENT-STATE selects between them.
  ;;
  ;; :LOAD is a coil, and it deliberately does *not* conduct. A coil is a load,
  ;; not a wire, and letting the flood pass through one is wrong in a way that
  ;; bites immediately: with two coils sharing a common return bus to 0V --
  ;; ordinary wiring -- energising the first would carry "live" through it,
  ;; along the bus and back up through the second, so both would read as
  ;; energised. On a double-solenoid valve that means both coils on at once,
  ;; the detent holds, and the valve never shifts.
  '((:closed . #(1 0))
    (:open   . #(-1 -1))
    (:load   . #(-1 -1))
    (:fixed  . #(-1))))

(register-electric :power-24v :label "+24V" :connectors 1 :state :fixed
                              :ports #'rail-ports :geometry #'rail-geometry)
(register-electric :common-0v :label "0V" :connectors 1 :state :fixed
                              :ports #'rail-ports :geometry #'rail-geometry)
(register-electric :push-button :label "Push Button" :state :open
                                :label-default "S1" :prefix "S"
                                :ports #'inline-ports :geometry #'contact-geometry)
(register-electric :push-button-closed :label "Push Button (NC)" :state :closed
                                       :label-default "S2" :prefix "S"
                                       :ports #'inline-ports :geometry #'contact-geometry)
(register-electric :contact-no :label "Contact (NO)" :state :open
                               :label-default "K1"
                               :ports #'inline-ports :geometry #'contact-geometry)
(register-electric :contact-nc :label "Contact (NC)" :state :closed
                               :label-default "K1"
                               :ports #'inline-ports :geometry #'contact-geometry)
(register-electric :coil :label "Relay Coil" :state :load
                         :label-default "K1" :prefix "K"
                         :ports #'inline-ports :geometry #'coil-geometry)
(register-electric :solenoid-out :label "Solenoid" :state :load
                                 :label-default "Sol 1"
                                 :ports #'inline-ports :geometry #'coil-geometry)

;;; ------------------------------------------------------------------
;;; Behaviour
;;; ------------------------------------------------------------------

(defun coil-kind-p (kind) (member kind '(:coil :solenoid-out)))

(defun grounded-connectors (circuit)
  "Connectors with a path back to 0V, as a set, or NIL if nothing is grounded.

Since a coil does not conduct, its return leg is not reachable from a supply
rail and so never counts as live. Without this it would be indistinguishable
from an unwired terminal, and a correctly wired circuit would look broken."
  (let ((returns (return-connectors circuit)))
    (when returns (flood circuit returns))))

(defun update-electric (circuit)
  "Energise coils, actuate contacts, and drive valve solenoids.

A coil needs current in and current out, so it is energised only when one of
its terminals is reachable from a source rail and the other from 0V. Wiring a
coil to +24V alone leaves it dead, as it should."
  (let* ((live (flood circuit (source-connectors circuit)))
         (returns (return-connectors circuit))
         (grounded (and returns (flood circuit returns))))
    ;; 1. Coils and solenoids.
    (dolist (component (circuit-components circuit))
      (when (coil-kind-p (component-kind component))
        (let ((a (component-connector component 0))
              (b (component-connector component 1)))
          (setf (component-energised component)
                (and grounded
                     (or (and (gethash a live) (gethash b grounded))
                         (and (gethash b live) (gethash a grounded)))
                     t)))))
    ;; 2. Contacts follow the coil that shares their label; buttons follow the
    ;;    pointer. Both resolve to open or closed.
    (flet ((coil-live-p (label)
             (some (lambda (c) (and (eq (component-kind c) :coil)
                                    (string= label (component-label c))
                                    (component-energised c)))
                   (circuit-components circuit))))
      (dolist (component (circuit-components circuit))
        (let ((closed
                (case (component-kind component)
                  (:contact-no (coil-live-p (component-label component)))
                  (:contact-nc (not (coil-live-p (component-label component))))
                  (:push-button (component-pressed component))
                  (:push-button-closed (not (component-pressed component)))
                  (t nil))))
          (when (member (component-kind component)
                        '(:contact-no :contact-nc :push-button :push-button-closed))
            (setf (component-state component) (if closed :closed :open))))))
    ;; 3. Solenoid symbols drive the valve coil carrying the same tag.
    ;;
    ;; The table records every tag that has a solenoid symbol, whether or not
    ;; it is currently energised. Collecting only the energised ones would mean
    ;; that when the last one drops out there is nothing left to switch the
    ;; valve coils off, and a spring-return valve would stay shifted forever.
    (let ((tags (make-hash-table :test #'equal)))
      (dolist (component (circuit-components circuit))
        (when (eq (component-kind component) :solenoid-out)
          (setf (gethash (component-label component) tags)
                ;; Several symbols may share a tag; any one of them drives it.
                (or (gethash (component-label component) tags)
                    (component-energised component)))))
      (dolist (component (circuit-components circuit))
        (dolist (solenoid (component-solenoids component))
          (multiple-value-bind (energised present)
              (gethash (solenoid-name solenoid) tags)
            ;; A coil with no matching symbol is left alone, so the keyboard
            ;; keeps control of valves that have not been wired up yet.
            (when present
              (setf (solenoid-active solenoid) (and energised t)))))))))
