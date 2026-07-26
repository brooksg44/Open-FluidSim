;;;; package.lisp -- raylib front-end.

(defpackage #:open-fluidsim.ui
  (:nicknames #:ofs.ui)
  (:use #:cl)
  (:local-nicknames (#:ofs #:open-fluidsim)
                    (#:rl #:raylib)
                    (#:v #:3d-vectors))
  (:export #:run))
