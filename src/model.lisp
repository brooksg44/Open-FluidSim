;;;; model.lisp -- components, connectors, and the circuit that holds them.

(in-package #:open-fluidsim)

(defstruct solenoid
  (name "Sol" :type string)
  (active nil))

(defstruct connector
  (index 0 :type fixnum)
  (owner nil)
  (pressure 0.0 :type real))

(defstruct component
  (name "" :type string)
  (kind :generic)
  (domain :pneumatic)
  (state :right)
  (origin (pt 0.0 0.0))
  (connectors #() :type simple-vector)
  (solenoids '())
  ;; How the valve behaves with no coil energised: :spring returns it to
  ;; REST-STATE, :detent leaves it wherever it was last sent.
  (hold :spring)
  (rest-state :right)
  (left-state :left)
  (right-state :right)
  ;; Electric components: the name they answer to. A coil labelled "K1"
  ;; actuates every contact labelled "K1"; a solenoid labelled "Sol 1" drives
  ;; the valve coil of that name.
  (label "")
  (energised nil)
  (pressed nil)
  ;; STATE -> simple-vector of connector indices, -1 meaning blocked. The
  ;; mapping is symmetric, so the engine can treat it as an undirected edge set.
  (tables '())
  ;; How far the body slides between positions, in symbol units.
  (shift +box-w+ :type real)
  ;; Travel of a moving part, 0.0 to 1.0. Used by cylinders for piston position.
  (travel 0.0 :type real)
  (travel-rate 1.2 :type real))

(defparameter *cylinder-kinds*
  '(:cylinder-double :cylinder-single :cylinder-double-hyd :cylinder-single-hyd)
  "Kinds that have a piston: what UPDATE-CYLINDERS drives, what the canvas
prints a travel readout for, and what a proximity switch can be mounted on.")

(defun fixed-table (n)
  "A port table for a component with no internal connections."
  (list (cons :fixed (make-array n :initial-element -1))))

(defun component-connector (component index)
  (aref (component-connectors component) index))

(defun component-table (component)
  (or (cdr (assoc (component-state component) (component-tables component)))
      (error "Component ~a has no port table for state ~s"
             (component-name component) (component-state component))))

(defstruct circuit
  (components '())
  ;; Each wire is a cons of two connectors.
  (wires '())
  ;; Connectors held at supply pressure.
  (sources '()))

(defun add-component (circuit component)
  (push component (circuit-components circuit))
  component)

(defun connect (circuit a b)
  "Wire connector A to connector B."
  (push (cons a b) (circuit-wires circuit))
  (values a b))

(defun add-source (circuit connector)
  "Hold CONNECTOR at supply pressure."
  (push connector (circuit-sources circuit))
  connector)

(defun make-connectors (component count)
  (let ((v (make-array count)))
    (dotimes (i count v)
      (setf (aref v i) (make-connector :index i :owner component)))))
