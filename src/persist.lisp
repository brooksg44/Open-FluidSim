;;;; persist.lisp -- saving and loading circuits.
;;;;
;;;; A circuit is written as a plain s-expression, which is the whole reason
;;;; this is short: no schema, no parser, no serialisation library. The Unity
;;;; original needed a name-keyed prefab lookup and hand-rolled index fixups
;;;; to do the same job.
;;;;
;;;; Wires are stored as index quadruples rather than object references, since
;;;; connectors have no identity outside the running image. Components are
;;;; written in placement order so those indices stay meaningful.

(in-package #:open-fluidsim)

(defconstant +save-format-version+ 1)

(defparameter *circuit-file-type* "ofs")

(defun circuit-form (circuit)
  "The saved representation of CIRCUIT."
  (let* ((components (reverse (circuit-components circuit)))
         (index (make-hash-table :test #'eq)))
    (loop for component in components
          for i from 0
          do (setf (gethash component index) i))
    (list :open-fluidsim +save-format-version+
          :components
          (loop for component in components
                collect (list :kind (component-kind component)
                              :origin (list (pt-x (component-origin component))
                                            (pt-y (component-origin component)))
                              :label (component-label component)
                              :name (component-name component)
                              ;; Saved so a detented valve reloads where it was
                              ;; left, rather than snapping to its rest position.
                              :state (component-state component)
                              :travel (component-travel component)))
          :wires
          (loop for wire in (reverse (circuit-wires circuit))
                collect (list (gethash (connector-owner (car wire)) index)
                              (connector-index (car wire))
                              (gethash (connector-owner (cdr wire)) index)
                              (connector-index (cdr wire)))))))

(defun save-circuit (circuit path)
  "Write CIRCUIT to PATH. Returns the pathname written."
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
    (with-standard-io-syntax
      (let ((*package* (find-package '#:open-fluidsim))
            (*print-pretty* t)
            (*print-readably* nil))
        (write (circuit-form circuit) :stream out)
        (terpri out))))
  path)

(defun circuit-from-form (form)
  "Rebuild a circuit from the form SAVE-CIRCUIT wrote."
  (destructuring-bind (magic version &key components wires) form
    (unless (eq magic :open-fluidsim)
      (error "Not an Open-FluidSim circuit file"))
    (unless (= version +save-format-version+)
      (error "Circuit file is version ~a; this build reads version ~a"
             version +save-format-version+))
    (let ((circuit (make-circuit))
          (built (make-array (length components))))
      (loop for spec in components
            for i from 0
            do (destructuring-bind (&key kind origin label name state travel) spec
                 (let ((component (make-component-of-kind
                                   kind
                                   :origin (pt (first origin) (second origin)))))
                   (when name (setf (component-name component) name))
                   (when state (setf (component-state component) state))
                   (when travel (setf (component-travel component) travel))
                   (setf (aref built i) component)
                   (add-component circuit component)
                   (if (and label (string/= "" label))
                       ;; Through RENAME-COMPONENT so a valve's coil tags follow.
                       (rename-component component label)
                       ;; A blank tag on a kind that auto-numbers means the file
                       ;; predates that kind carrying a tag at all -- cylinders
                       ;; had none until proximity switches needed something to
                       ;; name. Number it rather than load it nameless, or a
                       ;; switch mounted on it could never find it.
                       (assign-unique-label circuit component)))))
      (dolist (wire wires)
        (destructuring-bind (a-index a-port b-index b-port) wire
          (connect circuit
                   (component-connector (aref built a-index) a-port)
                   (component-connector (aref built b-index) b-port))))
      circuit)))

(defun load-circuit (path)
  "Read a circuit from PATH."
  (with-open-file (in path :direction :input)
    (with-standard-io-syntax
      (let ((*package* (find-package '#:open-fluidsim))
            ;; Never evaluate while reading a file from disk.
            (*read-eval* nil))
        (circuit-from-form (read in))))))

(defun circuit-directory ()
  (merge-pathnames "circuits/" (user-homedir-pathname)))

(defun circuit-path (name)
  "Resolve NAME to a circuit file. A bare name lands in ~/circuits/."
  (let ((given (pathname name)))
    (if (or (pathname-directory given) (pathname-type given))
        (merge-pathnames given (make-pathname :type *circuit-file-type*))
        (merge-pathnames (make-pathname :name name :type *circuit-file-type*)
                         (circuit-directory)))))
