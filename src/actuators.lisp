;;;; actuators.lisp -- cylinders.

(in-package #:open-fluidsim)

(defconstant +cylinder-length+ 80.0)
(defconstant +cylinder-half-h+ 16.0)

(defun cylinder-geometry (component)
  (let* ((travel (component-travel component))
         (h +cylinder-half-h+)
         (piston-x (+ 14.0 (* travel 52.0)))
         (single (= 1 (length (component-connectors component)))))
    (append
     (list (box 0.0 (- h) +cylinder-length+ (* 2 h))
           (polyline (list (pt piston-x (- h)) (pt piston-x h)) :width 2.5)
           (polyline (list (pt piston-x 0.0) (pt (+ +cylinder-length+ 30.0) 0.0))
                     :width 2.5))
     ;; A single-acting cylinder carries its return spring on the rod side.
     (when single
       (translate-ops (glyph-spring :w 30.0 :h (* 1.6 h) :coils 4)
                      (- +cylinder-length+ 34.0) (* -0.8 h)))
     (glyph-port-stub (pt 10.0 (- h)) :up nil)
     (unless single
       (glyph-port-stub (pt 70.0 (- h)) :up nil))
     ;; The tag, below the barrel and clear of the port stubs. Worth the ink
     ;; because it is what a proximity switch names to find this cylinder.
     (list (caption (pt 0.0 (- (+ h 8.0))) (component-label component) :size 6)))))

(defun cylinder-ports (component)
  (if (= 1 (length (component-connectors component)))
      (vector (stub-end (pt 10.0 (- +cylinder-half-h+)) :up nil))
      (vector (stub-end (pt 10.0 (- +cylinder-half-h+)) :up nil)
              (stub-end (pt 70.0 (- +cylinder-half-h+)) :up nil))))

(defun register-cylinder (kind &key label domain ports)
  (register-kind
   kind
   :label label :domain domain
   ;; Cylinders are auto-numbered A1, A2... so a proximity switch has something
   ;; to name. Before this they carried no tag at all and there was no way to
   ;; say which cylinder a switch was mounted on.
   :label-prefix "A"
   :make (lambda ()
           (let ((component (make-component :name label :kind kind :domain domain
                                            :state :fixed
                                            :tables (fixed-table ports))))
             (setf (component-connectors component)
                   (make-connectors component ports))
             component))
   :ports #'cylinder-ports
   :geometry #'cylinder-geometry))

(register-cylinder :cylinder-double :label "Cylinder" :domain :pneumatic :ports 2)
(register-cylinder :cylinder-single :label "Single Acting" :domain :pneumatic :ports 1)
(register-cylinder :cylinder-double-hyd :label "Cylinder" :domain :hydraulic :ports 2)
(register-cylinder :cylinder-single-hyd :label "Single Acting" :domain :hydraulic :ports 1)

(defun make-cylinder (&key (name "Cylinder") (origin (pt 0.0 0.0)))
  (let ((component (make-component-of-kind :cylinder-double :origin origin)))
    (setf (component-name component) name)
    component))
