;;;; registry.lisp -- the table of component kinds.
;;;;
;;;; Every kind registers three functions: how to build one, where its wires
;;;; attach, and how to draw it. Dispatch is a hash lookup rather than an
;;;; ECASE, so a new component is added by calling REGISTER-KIND in whichever
;;;; file it belongs to -- no central list to keep in step.

(in-package #:open-fluidsim)

(defstruct kind-info
  kind label domain make ports geometry
  ;; Prefix for auto-numbered tags ("K" -> K1, K2...). NIL means the kind
  ;; refers to something else's tag, so its registered default is kept.
  label-prefix)

(defvar *kinds* (make-hash-table :test #'eq))
(defvar *kind-order* '()
  "Registration order, reversed. Drives palette layout.")

(defun register-kind (kind &key label domain make ports geometry label-prefix)
  (unless (gethash kind *kinds*)
    (push kind *kind-order*))
  (setf (gethash kind *kinds*)
        (make-kind-info :kind kind :label label :domain domain
                        :make make :ports ports :geometry geometry
                        :label-prefix label-prefix))
  kind)

(defun kind-info (kind)
  (or (gethash kind *kinds*)
      (error "Unknown component kind ~s" kind)))

(defun kind-label (kind) (kind-info-label (kind-info kind)))
(defun kind-domain (kind) (kind-info-domain (kind-info kind)))

(defun all-kinds ()
  (reverse *kind-order*))

(defun kinds-in-domain (domain)
  (remove-if-not (lambda (kind) (eq domain (kind-domain kind))) (all-kinds)))

(defun domains ()
  '(:electric :pneumatic :hydraulic))

(defun make-component-of-kind (kind &key (origin (pt 0.0 0.0)))
  "Construct a component by kind. The palette places components through this."
  (let ((component (funcall (kind-info-make (kind-info kind)))))
    (setf (component-kind component) kind
          (component-domain component) (kind-domain kind)
          (component-origin component) origin)
    (when (string= "" (component-name component))
      (setf (component-name component) (kind-label kind)))
    (let ((prefix (kind-info-label-prefix (kind-info kind))))
      (when (and prefix (string= "" (component-label component)))
        (setf (component-label component) (format nil "~a1" prefix))))
    ;; Valve coils take their tags from the valve's label.
    (when (component-solenoids component)
      (refresh-solenoid-tags component))
    component))

(defun component-ports (component)
  "Vector of local attachment points, indexed like the component's connectors."
  (funcall (kind-info-ports (kind-info (component-kind component))) component))

(defun component-geometry (component)
  "Drawing operations in the component's local frame."
  (funcall (kind-info-geometry (kind-info (component-kind component))) component))

(defun component-port-position (component index)
  "World position of port INDEX."
  (pt+ (component-origin component) (aref (component-ports component) index)))

(defun connector-position (connector)
  (component-port-position (connector-owner connector)
                           (connector-index connector)))

(defun component-world-geometry (component)
  (let ((origin (component-origin component)))
    (translate-ops (component-geometry component) (pt-x origin) (pt-y origin))))

(defun circuit-bounds (circuit)
  "Extent of everything drawn, as (values min-x min-y max-x max-y).

Returns NIL for an empty circuit. Used to fit the view to the drawing, so a
renderer never has to guess a zoom level."
  (ops-bounds (mapcan #'component-world-geometry (circuit-components circuit))))
