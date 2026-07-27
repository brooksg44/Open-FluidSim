;;;; open-fluidsim.asd

(asdf:defsystem "open-fluidsim"
  :description "Fluid power circuit simulator: component model, signal propagation, and backend-agnostic ISO 1219 symbol geometry."
  :author "Gregory Brooks <brooksg44@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ()                        ; core is deliberately dependency-free
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "geometry")
                             (:file "glyphs")
                             (:file "model")
                             (:file "engine")
                             (:file "registry")
                             (:file "valves")
                             (:file "actuators")
                             (:file "sources")
                             (:file "electric")
                             (:file "library")
                             (:file "editing")
                             (:file "persist")))))

;; The renderer is a separate system so the core stays loadable, testable and
;; portable without dragging in a foreign library.
(asdf:defsystem "open-fluidsim/ui"
  :description "raylib front-end for open-fluidsim."
  :author "Gregory Brooks <brooksg44@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("open-fluidsim" "cl-raylib" "3d-vectors")
  :serial t
  :components ((:module "ui"
                :components ((:file "package")
                             (:file "raylib-bool")
                             (:file "render")
                             (:file "palette")
                             (:file "app")))))

(asdf:defsystem "open-fluidsim/tests"
  :description "FiveAM test suite for open-fluidsim."
  :depends-on ("open-fluidsim" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "tests"))))
  :perform (test-op (op c)
             (uiop:symbol-call :fiveam :run!
                               (uiop:find-symbol* '#:open-fluidsim :open-fluidsim/tests))))
