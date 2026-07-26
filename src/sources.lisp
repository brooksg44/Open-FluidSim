;;;; sources.lisp -- where fluid comes from and goes back to.

(in-package #:open-fluidsim)

(defun source-geometry (component)
  "Circle with a triangle: hollow for a pneumatic supply, solid for a pump."
  (let ((filled (eq (component-domain component) :hydraulic)))
    (list (disc (pt 0.0 0.0) 9.0)
          (poly (list (pt 0.0 5.0) (pt -4.5 -2.5) (pt 4.5 -2.5)) :filled filled)
          (polyline (list (pt 0.0 9.0) (stub-end (pt 0.0 9.0)))))))

(defun single-top-port (component)
  (declare (ignore component))
  (vector (stub-end (pt 0.0 9.0))))

(defun exhaust-geometry (component)
  (declare (ignore component))
  ;; Stem down to an open triangle -- open, because it vents to atmosphere.
  (list (polyline (list (pt 0.0 10.0) (pt 0.0 4.0)))
        (polyline (list (pt -5.0 -4.0) (pt 0.0 4.0) (pt 5.0 -4.0)))))

(defun exhaust-ports (component)
  (declare (ignore component))
  (vector (pt 0.0 10.0)))

(defun reservoir-geometry (component)
  (declare (ignore component))
  ;; Open-topped tank: the ISO reservoir, drawn as three sides.
  (list (polyline (list (pt -10.0 6.0) (pt -10.0 -6.0)
                        (pt 10.0 -6.0) (pt 10.0 6.0)))
        (polyline (list (pt 0.0 6.0) (stub-end (pt 0.0 6.0))))))

(defun reservoir-ports (component)
  (declare (ignore component))
  (vector (stub-end (pt 0.0 6.0))))

(defun register-terminal (kind &key label domain geometry ports)
  (register-kind
   kind :label label :domain domain
   :make (lambda ()
           (let ((component (make-component :name label :kind kind :domain domain
                                            :state :fixed :tables (fixed-table 1))))
             (setf (component-connectors component) (make-connectors component 1))
             component))
   :ports ports
   :geometry geometry))

(register-terminal :supply :label "Supply" :domain :pneumatic
                          :geometry #'source-geometry :ports #'single-top-port)
(register-terminal :exhaust :label "Exhaust" :domain :pneumatic
                           :geometry #'exhaust-geometry :ports #'exhaust-ports)
(register-terminal :pump :label "Pump" :domain :hydraulic
                        :geometry #'source-geometry :ports #'single-top-port)
(register-terminal :reservoir :label "Reservoir" :domain :hydraulic
                             :geometry #'reservoir-geometry :ports #'reservoir-ports)

(defun make-supply (&key (name "Supply") (origin (pt 0.0 0.0)))
  (let ((c (make-component-of-kind :supply :origin origin)))
    (setf (component-name c) name) c))

(defun make-exhaust (&key (name "Exhaust") (origin (pt 0.0 0.0)))
  (let ((c (make-component-of-kind :exhaust :origin origin)))
    (setf (component-name c) name) c))
