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
  "Electrical rungs driving the pneumatic circuit above.

Rung 1: +24V -> S1 -> relay coil K1 -> 0V.
Rung 2: +24V -> K1 contact -> Y1a solenoid -> 0V, so S1 extends the cylinder.
Rung 3: +24V -> S2 -> Y1b solenoid -> 0V, so S2 retracts it.

Both coils are needed for the detent to be demonstrable: a momentary tap on S1
latches the valve and the cylinder runs out and *stays* out, and it takes a tap
on S2 to send it back. With only one coil wired there is no way to reverse it,
which makes a working detent look like a stuck valve.

Returns (values circuit extend-button valve cylinder retract-button)."
  (multiple-value-bind (circuit valve cylinder) (make-demo-circuit)
    (let ((power   (make-component-of-kind :power-24v    :origin (pt 150.0 60.0)))
          (button  (make-component-of-kind :push-button  :origin (pt 150.0 30.0)))
          (coil    (make-component-of-kind :coil         :origin (pt 150.0 0.0)))
          (ground  (make-component-of-kind :common-0v    :origin (pt 150.0 -30.0)))
          (power-2 (make-component-of-kind :power-24v    :origin (pt 230.0 60.0)))
          (contact (make-component-of-kind :contact-no   :origin (pt 230.0 30.0)))
          (sol     (make-component-of-kind :solenoid-out :origin (pt 230.0 0.0)))
          (ground-2 (make-component-of-kind :common-0v   :origin (pt 230.0 -30.0)))
          (power-3 (make-component-of-kind :power-24v    :origin (pt 310.0 60.0)))
          (button-2 (make-component-of-kind :push-button :origin (pt 310.0 30.0)))
          (sol-2   (make-component-of-kind :solenoid-out :origin (pt 310.0 0.0)))
          (ground-3 (make-component-of-kind :common-0v   :origin (pt 310.0 -30.0))))
      (dolist (c (list power button coil ground power-2 contact sol ground-2
                       power-3 button-2 sol-2 ground-3))
        (add-component circuit c))
      (setf (component-label button-2) "S2")
      ;; Tie each solenoid symbol to a valve coil by tag. This is the whole
      ;; electric-to-pneumatic link: matching text, nothing more.
      (destructuring-bind (coil-a coil-b) (component-solenoids valve)
        (setf (component-label sol) (solenoid-name coil-a)
              (component-label sol-2) (solenoid-name coil-b)))
      ;; Rung 1: button energises K1.
      (connect circuit (component-connector power 0)  (component-connector button 0))
      (connect circuit (component-connector button 1) (component-connector coil 0))
      (connect circuit (component-connector coil 1)   (component-connector ground 0))
      ;; Rung 2: the K1 contact energises Sol 1.
      (connect circuit (component-connector power-2 0)  (component-connector contact 0))
      (connect circuit (component-connector contact 1)  (component-connector sol 0))
      (connect circuit (component-connector sol 1)      (component-connector ground-2 0))
      ;; Rung 3: S2 drives the other coil, so the valve can be sent back.
      (connect circuit (component-connector power-3 0)   (component-connector button-2 0))
      (connect circuit (component-connector button-2 1)  (component-connector sol-2 0))
      (connect circuit (component-connector sol-2 1)     (component-connector ground-3 0))
      (values circuit button valve cylinder button-2))))

(defun make-auto-cycle-demo-circuit ()
  "A cylinder that reciprocates on its own, from a proximity switch at each end.

Rung 1: +24V -> S1 -> prox at the retracted end -> Y1a -> 0V, so the rod goes
        out whenever it is home and S1 is made.
Rung 2: +24V -> prox at the extended end -> Y1b -> 0V, so it comes back.

Hold S1 and it cycles continuously; tap it and you get one stroke out and back.
Nothing else drives it -- the pneumatic side is reporting its own position to
the ladder, which is the whole reason the component exists.

The detent is doing real work here, and this is the circuit that shows why. A
switch is made only while the piston is within *SENSOR-BAND* of it, so for most
of every stroke *neither* coil is energised. A spring-return spool would fall
back the instant the switch that sent it dropped out, and the rod would stall
just off the end; the detent holds the spool where the switch put it, so the
stroke runs on after the switch has let go.

For the same reason the rod turns round a few percent short of each end cap
while it is cycling: a proximity switch is made as the piston *approaches* it,
not when it arrives. Release S1 and the rod does run fully home, since nothing
re-energises Y1a to interrupt it.

Note also what is *not* here: no relay, and no second button. Compare
MAKE-RELAY-DEMO-CIRCUIT, where reversing needs S2 pressed by hand.

Returns (values circuit button valve cylinder)."
  (multiple-value-bind (circuit valve cylinder) (make-demo-circuit)
    ;; Rung spacing is 40 between the switch and whatever sits above it, not the
    ;; 30 the relay demo uses: a proximity switch carries its diamond 14 units
    ;; clear of the contact, which would otherwise land on the tag of the
    ;; component above.
    (let* ((tag      (component-label cylinder))
           (power    (make-component-of-kind :power-24v   :origin (pt 150.0 100.0)))
           (button   (make-component-of-kind :push-button :origin (pt 150.0 70.0)))
           (at-home  (make-component-of-kind :sensor-no   :origin (pt 150.0 30.0)))
           (sol-a    (make-component-of-kind :solenoid-out :origin (pt 150.0 0.0)))
           (ground   (make-component-of-kind :common-0v   :origin (pt 150.0 -30.0)))
           (power-2  (make-component-of-kind :power-24v   :origin (pt 230.0 100.0)))
           (at-end   (make-component-of-kind :sensor-no   :origin (pt 230.0 30.0)))
           (sol-b    (make-component-of-kind :solenoid-out :origin (pt 230.0 0.0)))
           (ground-2 (make-component-of-kind :common-0v   :origin (pt 230.0 -30.0))))
      (dolist (c (list power button at-home sol-a ground
                       power-2 at-end sol-b ground-2))
        (add-component circuit c))
      ;; Both switches are mounted on the cylinder built above, so take its tag
      ;; rather than writing "A1" here -- the two must not be able to drift.
      (setf (component-label at-home) (format nil "~a@0" tag)
            (component-label at-end) tag)
      (destructuring-bind (coil-a coil-b) (component-solenoids valve)
        (setf (component-label sol-a) (solenoid-name coil-a)
              (component-label sol-b) (solenoid-name coil-b)))
      ;; Rung 1: out, but only from the home position.
      (connect circuit (component-connector power 0)   (component-connector button 0))
      (connect circuit (component-connector button 1)  (component-connector at-home 0))
      (connect circuit (component-connector at-home 1) (component-connector sol-a 0))
      (connect circuit (component-connector sol-a 1)   (component-connector ground 0))
      ;; Rung 2: back again, with no button in it at all.
      (connect circuit (component-connector power-2 0) (component-connector at-end 0))
      (connect circuit (component-connector at-end 1)  (component-connector sol-b 0))
      (connect circuit (component-connector sol-b 1)   (component-connector ground-2 0))
      (values circuit button valve cylinder))))
