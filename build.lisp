;;;; build.lisp -- dump a standalone executable.
;;;;
;;;; Run from the project root:
;;;;   sbcl --noinform --disable-debugger --non-interactive --load build.lisp
;;;;
;;;; See BUILDING.md. Note that SBCL cannot cross-compile an image, so a
;;;; Windows .exe has to be produced on Windows.

(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :open-fluidsim/ui)

(defun entry ()
  (handler-case (progn (open-fluidsim.ui:run) 0)
    (error (e)
      (format *error-output* "~&open-fluidsim: ~a~%" e)
      1)))

(sb-ext:save-lisp-and-die
 #+win32 "open-fluidsim.exe" #-win32 "open-fluidsim"
 :executable t
 :toplevel #'entry
 ;; Roughly halves the image. Requires an SBCL built with core compression;
 ;; drop this line if yours rejects it.
 #+sb-core-compression :compression #+sb-core-compression t)
