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

;;; Where circuits live.
;;;
;;; Two kinds of directory, and the difference is the whole design: one place
;;; the user's own work is written, and a search path of read-only places the
;;; examples might be sitting. Saving an example therefore lands a copy in the
;;; user's directory instead of editing what shipped with the program.

(defun %getenv (name)
  "The environment variable NAME, or NIL. The only place the core cares which
implementation it is running on."
  (declare (ignorable name))
  #+sbcl (sb-ext:posix-getenv name)
  #+ccl (ccl:getenv name)
  #+(or ecl clisp) (ext:getenv name)
  #-(or sbcl ccl ecl clisp) nil)

(defun %as-directory (namestring)
  "NAMESTRING as a directory pathname, whether or not it ends in a separator."
  (let ((p (pathname namestring)))
    (if (pathname-name p)
        (make-pathname :directory (append (or (pathname-directory p) '(:relative))
                                          (list (file-namestring p)))
                       :name nil :type nil :defaults p)
        p)))

(defun source-circuit-directory ()
  "The examples that ship in the source tree, beside src/.

Asked of ASDF at runtime rather than worked out from *COMPILE-FILE-TRUENAME*,
which points into the fasl cache and not at the sources. Kept at arm's length
through FIND-SYMBOL so the core still loads where ASDF is absent, and returns
NIL rather than erroring in a dumped image whose build tree is long gone."
  (let* ((package (find-package '#:asdf))
         (f (and package (find-symbol "SYSTEM-RELATIVE-PATHNAME" package))))
    (when (and f (fboundp f))
      (ignore-errors (funcall f "open-fluidsim" "circuits/")))))

(defun executable-circuit-directory ()
  "circuits/ beside the running executable: how a dumped image finds the
examples that shipped with it. Meaningless when running from source, where it
points next to the Lisp binary and finds nothing."
  #+sbcl (merge-pathnames "circuits/"
                          (make-pathname :name nil :type nil
                                         :defaults (pathname sb-ext:*runtime-pathname*)))
  #-sbcl nil)

(defun circuit-directory ()
  "Where a bare name is saved: the place each platform's users look for their
own documents. Override with the OPEN_FLUIDSIM_CIRCUITS environment variable."
  (let ((override (%getenv "OPEN_FLUIDSIM_CIRCUITS")))
    (if (and override (string/= "" override))
        (%as-directory override)
        (merge-pathnames #+win32 "Documents/Open-FluidSim/"
                         #+darwin "Documents/Open-FluidSim/"
                         #-(or win32 darwin) ".local/share/open-fluidsim/"
                         (user-homedir-pathname)))))

(defun circuit-search-path ()
  "Directories a bare name is looked for in, writable one first.

~/circuits/ stays on the list because that is where saves landed before this
existed; dropping it would strand anything already written there."
  (remove-duplicates
   (remove nil (list (circuit-directory)
                     (merge-pathnames "circuits/" (user-homedir-pathname))
                     (executable-circuit-directory)
                     (source-circuit-directory)))
   :test #'equal :from-end t))

(defun %bare-name (name)
  "NAME as a bare circuit name, or NIL when it names a location instead.
A typed-in \"Auto Cycle.ofs\" is still a bare name -- the extension is ours."
  (let ((given (pathname name)))
    (cond ((pathname-directory given) nil)
          ((null (pathname-type given)) (pathname-name given))
          ((string-equal (pathname-type given) *circuit-file-type*)
           (pathname-name given))
          (t nil))))

(defun circuit-path (name)
  "Resolve NAME to the file a save should write. A bare name lands in
CIRCUIT-DIRECTORY; anything with a directory in it is taken literally."
  (let ((bare (%bare-name name)))
    (if bare
        (merge-pathnames (make-pathname :name bare :type *circuit-file-type*)
                         (circuit-directory))
        (merge-pathnames (pathname name)
                         (make-pathname :type *circuit-file-type*)))))

(defun circuit-files (&optional (directory nil directoryp))
  "The circuit files in DIRECTORY, or across the whole search path."
  (loop for dir in (if directoryp (list directory) (circuit-search-path))
        append (directory (make-pathname :name :wild :type *circuit-file-type*
                                         :defaults dir))))

(defun list-circuits ()
  "Names a bare name could reach, nearest first. A name in the user's own
directory shadows an example of the same name, and is listed once."
  (let ((names '()))
    (dolist (file (circuit-files) (nreverse names))
      (pushnew (pathname-name file) names :test #'string-equal))))

(defun find-circuit-file (name)
  "Resolve NAME for loading: the first existing file it matches along the search
path. NIL when nothing matches -- the caller has better things to say about
that than an unhandled file error."
  (let ((bare (%bare-name name)))
    (if (null bare)
        (probe-file (circuit-path name))
        (or (loop for dir in (circuit-search-path)
                  thereis (probe-file (make-pathname :name bare
                                                     :type *circuit-file-type*
                                                     :defaults dir)))
            ;; Second pass, ignoring case: the examples have capitals and spaces
            ;; in their names, and Linux will not forgive a typo that Windows
            ;; and macOS would both have let through.
            (find bare (circuit-files) :key #'pathname-name :test #'string-equal)))))
