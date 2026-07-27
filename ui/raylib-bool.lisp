;;;; raylib-bool.lisp -- read raylib's booleans at the width C returns them.
;;;;
;;;; raylib's `bool` is <stdbool.h>'s: one byte. cl-raylib declares these
;;;; functions to CFFI as :boolean, whose base type is :int, so four bytes are
;;;; read where one was returned. The x64 ABI leaves the upper bits of the
;;;; return register undefined, and raylib's own MSVC build leaves garbage in
;;;; them: measured on Windows with no button held, IsMouseButtonDown came back
;;;; as 0x00F0C000 -- low byte 0, which CFFI reported as true because the whole
;;;; int was non-zero. The canvas then panned every frame and every frame
;;;; registered a fresh click, so the editor looked stuck in a pan gesture and
;;;; clicking did nothing you could see.
;;;;
;;;; The clang build used on macOS happens to zero-extend, which is why this
;;;; never showed up there. So bind the entry points ourselves and read exactly
;;;; the one byte C promises -- correct on every platform, not a Windows patch.
;;;;
;;;; Only IsMouseButtonDown and IsMouseButtonPressed were observed corrupt, but
;;;; the mistake is in the declaration rather than in those two functions, so
;;;; every predicate the editor depends on is bound here.

(in-package #:open-fluidsim.ui)

(cffi:defctype rl-bool (:boolean :char)
  "C99 bool: one byte, whatever CFFI's :boolean would have assumed.")

;; The enum types are internal to cl-raylib, hence the double colons. Worth it
;; to keep the keyword arguments at the call sites.
(cffi:defcfun ("IsMouseButtonDown" mouse-button-down-p) rl-bool
  "Is BUTTON being held this frame?"
  (button raylib::mousebutton))

(cffi:defcfun ("IsMouseButtonPressed" mouse-button-pressed-p) rl-bool
  "Did BUTTON go down this frame?"
  (button raylib::mousebutton))

(cffi:defcfun ("IsKeyPressed" key-pressed-p) rl-bool
  "Did KEY go down this frame?"
  (key raylib::keyboardkey))

(cffi:defcfun ("IsWindowResized" window-resized-p) rl-bool
  "Was the window resized last frame?")

(cffi:defcfun ("WindowShouldClose" window-should-close-p) rl-bool
  "Has the user asked to close the window?")
