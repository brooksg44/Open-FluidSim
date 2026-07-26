;;;; library.lisp -- worked circuits.

(in-package #:open-fluidsim)

(defun make-demo-circuit ()
  "Supply -> 5/2 detented valve -> double-acting cylinder, with both exhausts.

Returns (values circuit valve cylinder). Energising Sol 1 puts the valve in
:left, which routes P to A and extends the cylinder; Sol 2 retracts it. With
both coils off the detent holds, so the cylinder stays where it was sent --
which is the whole point of a memory valve."
  (let* ((circuit   (make-circuit))
         (valve     (make-component-of-kind :valve-5-2-detented :origin (pt 0.0 0.0)))
         ;; Spread the bottom row out: at valve port spacing these would
         ;; overlap, since each symbol is wider than the gap between ports.
         (supply    (make-component-of-kind :supply  :origin (pt 12.0 -76.0)))
         (exhaust-a (make-component-of-kind :exhaust :origin (pt -34.0 -76.0)))
         (exhaust-b (make-component-of-kind :exhaust :origin (pt 58.0 -76.0)))
         (cylinder  (make-component-of-kind :cylinder-double :origin (pt -40.0 70.0))))
    (setf (component-name exhaust-a) "Exhaust A"
          (component-name exhaust-b) "Exhaust B")
    (dolist (c (list valve supply exhaust-a exhaust-b cylinder))
      (add-component circuit c))
    (connect circuit (component-connector valve 3) (component-connector supply 0))
    (connect circuit (component-connector valve 2) (component-connector exhaust-a 0))
    (connect circuit (component-connector valve 4) (component-connector exhaust-b 0))
    (connect circuit (component-connector valve 0) (component-connector cylinder 0))
    (connect circuit (component-connector valve 1) (component-connector cylinder 1))
    ;; No ADD-SOURCE needed: the supply component is a source by its kind.
    (values circuit valve cylinder)))

(defun make-relay-demo-circuit ()
  "An electrical rung driving the pneumatic circuit above.

+24V -> push button -> relay coil K1 -> 0V, and a second rung where the K1
contact feeds the Sol 1 solenoid. Pressing the button closes K1, which closes
the contact, which energises Sol 1, which shifts the valve and extends the
cylinder. Returns (values circuit button valve cylinder)."
  (multiple-value-bind (circuit valve cylinder) (make-demo-circuit)
    (let ((power   (make-component-of-kind :power-24v    :origin (pt 150.0 60.0)))
          (button  (make-component-of-kind :push-button  :origin (pt 150.0 30.0)))
          (coil    (make-component-of-kind :coil         :origin (pt 150.0 0.0)))
          (ground  (make-component-of-kind :common-0v    :origin (pt 150.0 -30.0)))
          (power-2 (make-component-of-kind :power-24v    :origin (pt 230.0 60.0)))
          (contact (make-component-of-kind :contact-no   :origin (pt 230.0 30.0)))
          (sol     (make-component-of-kind :solenoid-out :origin (pt 230.0 0.0)))
          (ground-2 (make-component-of-kind :common-0v   :origin (pt 230.0 -30.0))))
      (dolist (c (list power button coil ground power-2 contact sol ground-2))
        (add-component circuit c))
      ;; Tie the solenoid symbol to the valve's first coil by tag. This is the
      ;; whole electric-to-pneumatic link: matching text, nothing more.
      (setf (component-label sol)
            (solenoid-name (first (component-solenoids valve))))
      ;; Rung 1: button energises K1.
      (connect circuit (component-connector power 0)  (component-connector button 0))
      (connect circuit (component-connector button 1) (component-connector coil 0))
      (connect circuit (component-connector coil 1)   (component-connector ground 0))
      ;; Rung 2: the K1 contact energises Sol 1.
      (connect circuit (component-connector power-2 0)  (component-connector contact 0))
      (connect circuit (component-connector contact 1)  (component-connector sol 0))
      (connect circuit (component-connector sol 1)      (component-connector ground-2 0))
      (values circuit button valve cylinder))))
