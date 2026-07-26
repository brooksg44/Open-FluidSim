;;;; palette.lisp -- the component palette down the left edge.
;;;;
;;;; Entries draw the component's own geometry through DRAW-OPS-FITTED, so a
;;;; palette entry cannot drift out of sync with the thing it places. The Unity
;;;; original kept a separate thumbnail sprite per component and they had to be
;;;; maintained in parallel.

(in-package #:open-fluidsim.ui)

(defparameter *hud-height* 72
  "Vertical space reserved for the HUD across the top of the window.")

(defparameter *palette-width* 148)
(defparameter *palette-entry-height* 76)
(defparameter *palette-gap* 6)

(defvar *palette-previews* (make-hash-table :test #'eq)
  "One prototype component per kind, built lazily, used only for drawing.")

(defun palette-preview (kind)
  (or (gethash kind *palette-previews*)
      (setf (gethash kind *palette-previews*)
            (ofs:make-component-of-kind kind))))

(defparameter *tab-height* 24)

(defun tab-rect (index)
  (let ((w (floor *palette-width* (length (ofs:domains)))))
    (values (* index w) *hud-height* w *tab-height*)))

(defun palette-domain-at (screen-x screen-y)
  "The domain tab under the given screen point, or NIL."
  (loop for domain in (ofs:domains)
        for index from 0
        do (multiple-value-bind (x y w h) (tab-rect index)
             (when (and (<= x screen-x (+ x w)) (<= y screen-y (+ y h)))
               (return domain)))))

(defvar *palette-scroll* 0
  "How far the entry list is scrolled down, in pixels.

A global rather than editor state, like *PALETTE-PREVIEWS* above: there is one
palette, so there is one scroll position, and threading it through every entry
function would buy nothing.")

(defun palette-entries-top ()
  (+ *hud-height* *tab-height* *palette-gap*))

(defun palette-entry-pitch ()
  (+ *palette-entry-height* *palette-gap*))

(defun palette-max-scroll (domain)
  "How far the list can travel: zero when every entry already fits."
  (max 0 (- (* (length (ofs:palette-for-domain domain)) (palette-entry-pitch))
            (- (rl:get-screen-height) (palette-entries-top)))))

(defun scroll-palette (domain amount)
  "Scroll the list by AMOUNT pixels, clamped. Call with 0 to re-clamp after the
window is resized or the tab changes, either of which can shorten the list."
  (setf *palette-scroll*
        (max 0 (min (palette-max-scroll domain) (+ *palette-scroll* amount)))))

(defun palette-entry-rect (index)
  "Screen rectangle of palette entry INDEX, as (values x y w h)."
  (values *palette-gap*
          (- (+ (palette-entries-top) (* index (palette-entry-pitch)))
             *palette-scroll*)
          (- *palette-width* (* 2 *palette-gap*))
          *palette-entry-height*))

(defun palette-kind-at (domain screen-x screen-y)
  "The component kind under the given screen point, or NIL."
  (when (and (< screen-x *palette-width*)
             ;; Scrolled entries pass under the tab strip; a click up there
             ;; belongs to the tabs, not to whatever happens to be sliding by.
             (>= screen-y (palette-entries-top)))
    (loop for (kind . nil) in (ofs:palette-for-domain domain)
          for index from 0
          do (multiple-value-bind (x y w h) (palette-entry-rect index)
               (when (and (<= x screen-x (+ x w))
                          (<= y screen-y (+ y h)))
                 (return kind))))))

(defun in-palette-p (screen-x)
  (< screen-x *palette-width*))

(defun domain-label (domain)
  (ecase domain (:electric "Elec") (:pneumatic "Pneu") (:hydraulic "Hyd")))

(defun draw-palette-scrollbar (domain)
  "A thumb down the right edge, drawn only when the list actually overflows.

Without it there is nothing to say the list continues past the bottom of the
window, and an entry you cannot see is an entry you cannot place."
  (let ((travel (palette-max-scroll domain)))
    (when (plusp travel)
      (let* ((top (palette-entries-top))
             (track (- (rl:get-screen-height) top))
             (thumb (max 20 (round (* track (/ track (+ track travel))))))
             (y (+ top (round (* (- track thumb) (/ *palette-scroll* travel))))))
        (rl:draw-rectangle (- *palette-width* 5) top 3 track :gray)
        (rl:draw-rectangle (- *palette-width* 5) y 3 thumb :darkgray)))))

(defun draw-palette (domain selected-kind)
  ;; Re-clamp first: a resize or a tab change can shorten the list under a
  ;; scroll position that was legal when it was set.
  (scroll-palette domain 0)
  (let ((height (rl:get-screen-height)))
    (rl:draw-rectangle 0 *hud-height* *palette-width* (- height *hud-height*)
                       :lightgray))
  (loop for (kind . label) in (ofs:palette-for-domain domain)
        for index from 0
        do (multiple-value-bind (x y w h) (palette-entry-rect index)
             ;; Skip anything wholly outside the visible band, in either
             ;; direction -- scrolling puts entries above it as well as below.
             (when (and (< y (rl:get-screen-height))
                        (> (+ y h) (palette-entries-top)))
               (let ((chosen (eq kind selected-kind)))
                 (rl:draw-rectangle x y w h (if chosen :beige :raywhite))
                 (rl:draw-rectangle-lines x y w h (if chosen :maroon :gray))
                 ;; The symbol itself, leaving a strip at the bottom for the name.
                 (draw-ops-fitted (ofs:component-world-geometry (palette-preview kind))
                                  x y w (- h 14))
                 (rl:draw-text label (+ x 5) (+ y h -13) 10 :darkgray)))))
  (draw-palette-scrollbar domain)
  ;; Tabs last, so an entry scrolled up under the strip is covered by it
  ;; rather than painted over it.
  (loop for d in (ofs:domains)
        for index from 0
        do (multiple-value-bind (x y w h) (tab-rect index)
             (let ((current (eq d domain)))
               (rl:draw-rectangle x y w h (if current :raywhite :gray))
               (rl:draw-rectangle-lines x y w h :darkgray)
               (rl:draw-text (domain-label d) (+ x 8) (+ y 6) 11
                             (if current :maroon :raywhite))))))
