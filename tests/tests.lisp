;;;; tests.lisp

(defpackage #:open-fluidsim/tests
  (:use #:cl #:fiveam)
  (:local-nicknames (#:ofs #:open-fluidsim))
  (:export #:open-fluidsim))

(in-package #:open-fluidsim/tests)

(def-suite open-fluidsim :description "Core model, detent behaviour and propagation.")
(in-suite open-fluidsim)

(defun fresh-circuit ()
  "A valve with its P port held at supply pressure."
  (let ((valve (ofs:make-valve-5-2-double-solenoid))
        (circuit (ofs:make-circuit)))
    (ofs:add-component circuit valve)
    (ofs:add-source circuit (ofs:component-connector valve 3))
    (values circuit valve)))

(test starts-in-right-position
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (ofs:step-simulation circuit)
    (is (eq :right (ofs:component-state valve)))))

(test solenoid-one-shifts-left
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (ofs:energise (first (ofs:component-solenoids valve)))
    (ofs:step-simulation circuit)
    (is (eq :left (ofs:component-state valve)))))

(test detent-holds-when-both-coils-released
  ;; The defining property: a spring-return valve would snap back here.
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (let ((sol-1 (first (ofs:component-solenoids valve))))
      (ofs:energise sol-1)
      (ofs:step-simulation circuit)
      (is (eq :left (ofs:component-state valve)))
      (ofs:de-energise sol-1)
      (ofs:step-simulation circuit)
      (is (eq :left (ofs:component-state valve)) "detent must hold after release")
      ;; And keeps holding across further steps.
      (dotimes (i 5) (ofs:step-simulation circuit))
      (is (eq :left (ofs:component-state valve))))))

(test detent-holds-when-both-coils-energised
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (destructuring-bind (sol-1 sol-2) (ofs:component-solenoids valve)
      (ofs:energise sol-1)
      (ofs:step-simulation circuit)
      (ofs:energise sol-2)
      (ofs:step-simulation circuit)
      (is (eq :left (ofs:component-state valve))
          "both coils on is ambiguous, so the detent should hold"))))

(test right-position-routes-supply-to-port-1
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (ofs:step-simulation circuit)
    (is (ofs:pressurised-p (ofs:component-connector valve 1)))
    (is (not (ofs:pressurised-p (ofs:component-connector valve 0))))))

(test left-position-routes-supply-to-port-0
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (ofs:energise (first (ofs:component-solenoids valve)))
    (ofs:step-simulation circuit)
    (is (ofs:pressurised-p (ofs:component-connector valve 0)))
    (is (not (ofs:pressurised-p (ofs:component-connector valve 1))))))

(test blocked-port-stays-dead
  ;; In the right position, index 4 is blocked (-1 in the table).
  (multiple-value-bind (circuit valve) (fresh-circuit)
    (ofs:step-simulation circuit)
    (is (not (ofs:pressurised-p (ofs:component-connector valve 4))))))

;;; The worked circuit: supply -> valve -> cylinder, with exhausts.

(defun settle (circuit &key (steps 120) (dt 1/60))
  "Run enough steps for a cylinder to complete its travel."
  (dotimes (i steps) (ofs:step-simulation circuit :dt dt)))

(test demo-circuit-wires-up
  (multiple-value-bind (circuit valve cylinder) (ofs:make-demo-circuit)
    (is (= 5 (length (ofs:circuit-components circuit))))
    (is (= 5 (length (ofs:circuit-wires circuit))))
    (is (eq :valve-5-2-detented (ofs:component-kind valve)))
    (is (eq :cylinder-double (ofs:component-kind cylinder)))))

(test supply-reaches-the-cylinder
  ;; In the rest position P routes to B, so the rod-end port is live and the
  ;; cap-end port is not.
  (multiple-value-bind (circuit valve cylinder) (ofs:make-demo-circuit)
    (declare (ignore valve))
    (ofs:step-simulation circuit)
    (is (ofs:pressurised-p (ofs:component-connector cylinder 1)))
    (is (not (ofs:pressurised-p (ofs:component-connector cylinder 0))))))

(test cylinder-extends-and-retracts
  (multiple-value-bind (circuit valve cylinder) (ofs:make-demo-circuit)
    (destructuring-bind (sol-1 sol-2) (ofs:component-solenoids valve)
      (settle circuit)
      (is (= 0.0 (ofs:component-travel cylinder)) "starts retracted")
      (ofs:energise sol-1)
      (settle circuit)
      (is (= 1.0 (ofs:component-travel cylinder)) "Sol 1 extends it")
      (ofs:de-energise sol-1)
      (ofs:energise sol-2)
      (settle circuit)
      (is (= 0.0 (ofs:component-travel cylinder)) "Sol 2 retracts it"))))

(test cylinder-holds-when-detent-holds
  ;; Release the coil mid-stroke: the valve keeps its position, so the
  ;; cylinder carries on rather than stopping or reversing. Then confirm it
  ;; stays extended indefinitely with both coils off.
  (multiple-value-bind (circuit valve cylinder) (ofs:make-demo-circuit)
    (let ((sol-1 (first (ofs:component-solenoids valve))))
      (ofs:energise sol-1)
      (settle circuit :steps 10)
      (ofs:de-energise sol-1)
      (settle circuit)
      (is (eq :left (ofs:component-state valve)) "detent holds the valve")
      (is (= 1.0 (ofs:component-travel cylinder))
          "cylinder completes its stroke with no coil energised")
      (settle circuit :steps 300)
      (is (= 1.0 (ofs:component-travel cylinder)) "and stays there"))))

(test every-component-has-geometry-and-ports
  ;; Guards the ECASE dispatch: a component kind added without both clauses
  ;; would signal here rather than at draw time.
  (multiple-value-bind (circuit valve cylinder) (ofs:make-demo-circuit)
    (declare (ignore valve cylinder))
    (dolist (component (ofs:circuit-components circuit))
      (is (plusp (length (ofs:component-world-geometry component)))
          "~a produced no geometry" (ofs:component-name component))
      (is (= (length (ofs:component-ports component))
             (length (ofs:component-connectors component)))
          "~a: port count does not match connector count"
          (ofs:component-name component)))))

;;; Editing operations, which the palette and canvas gestures are built on.

(test every-registered-kind-is-usable
  ;; Everything in the registry reaches a palette tab, so a kind that cannot be
  ;; built, positioned or drawn would fail at click time. Catch it here.
  (dolist (kind (ofs:all-kinds))
    (let ((component (ofs:make-component-of-kind kind)))
      (is (eq kind (ofs:component-kind component)))
      (is (plusp (length (ofs:component-world-geometry component)))
          "~a produced no geometry" kind)
      (is (= (length (ofs:component-ports component))
             (length (ofs:component-connectors component)))
          "~a: port count does not match connector count" kind)
      ;; Its current state must have a port table, or propagation will error.
      (is (= (length (ofs:component-table component))
             (length (ofs:component-connectors component)))
          "~a: port table does not match connector count" kind))))

(test every-domain-has-components
  (dolist (domain (ofs:domains))
    (is (plusp (length (ofs:palette-for-domain domain)))
        "domain ~a has no components" domain)))

;;; The electrical side.

(defun find-kind (circuit kind)
  (find kind (ofs:circuit-components circuit) :key #'ofs:component-kind))

(defun make-circuit-with-spring-valve ()
  "+24V -> button -> solenoid symbol -> 0V, tagged to a 3/2 spring-return valve."
  (let* ((circuit (ofs:make-circuit))
         (valve  (ofs:add-component circuit (ofs:make-component-of-kind :valve-3-2)))
         (power  (ofs:add-component circuit (ofs:make-component-of-kind :power-24v)))
         (button (ofs:add-component circuit (ofs:make-component-of-kind :push-button)))
         (sol    (ofs:add-component circuit (ofs:make-component-of-kind :solenoid-out)))
         (ground (ofs:add-component circuit (ofs:make-component-of-kind :common-0v))))
    (ofs:assign-unique-label circuit valve)
    (ofs:rename-component sol (ofs:solenoid-name (first (ofs:component-solenoids valve))))
    (ofs:connect circuit (ofs:component-connector power 0) (ofs:component-connector button 0))
    (ofs:connect circuit (ofs:component-connector button 1) (ofs:component-connector sol 0))
    (ofs:connect circuit (ofs:component-connector sol 1) (ofs:component-connector ground 0))
    circuit))

(test a-coil-needs-both-a-supply-and-a-return
  ;; Wired to +24V alone the coil is dead; it takes a path back to 0V.
  (let* ((circuit (ofs:make-circuit))
         (power (ofs:add-component circuit (ofs:make-component-of-kind :power-24v)))
         (coil (ofs:add-component circuit (ofs:make-component-of-kind :coil)))
         (ground (ofs:add-component circuit (ofs:make-component-of-kind :common-0v))))
    (ofs:connect circuit (ofs:component-connector power 0)
                 (ofs:component-connector coil 0))
    (ofs:step-simulation circuit)
    (is (not (ofs:component-energised coil)) "no return path yet")
    (ofs:connect circuit (ofs:component-connector coil 1)
                 (ofs:component-connector ground 0))
    (ofs:step-simulation circuit)
    (is (ofs:component-energised coil) "closed circuit should energise it")))

(test relay-chain-drives-the-cylinder
  ;; Button -> K1 coil -> K1 contact -> Sol 1 -> valve -> cylinder.
  (multiple-value-bind (circuit button valve cylinder) (ofs:make-relay-demo-circuit)
    (let ((coil (find-kind circuit :coil))
          (contact (find-kind circuit :contact-no)))
      (settle circuit :steps 5)
      (is (not (ofs:component-energised coil)) "idle with the button released")
      (is (eq :open (ofs:component-state contact)))
      (is (eq :right (ofs:component-state valve)))
      ;; Press and hold.
      (setf (ofs:component-pressed button) t)
      (settle circuit)
      (is (ofs:component-energised coil) "button energises K1")
      (is (eq :closed (ofs:component-state contact)) "K1 closes its contact")
      (is (eq :left (ofs:component-state valve)) "Sol 1 shifts the valve")
      (is (= 1.0 (ofs:component-travel cylinder)) "and the cylinder extends")
      ;; Release: the coil drops out, but the valve detent holds.
      (setf (ofs:component-pressed button) nil)
      (settle circuit)
      (is (not (ofs:component-energised coil)))
      (is (eq :left (ofs:component-state valve))
          "detented valve keeps its position after the coil drops out")
      (is (= 1.0 (ofs:component-travel cylinder))))))

(test spring-return-valve-drops-out-when-its-solenoid-does
  ;; Regression: collecting only the *energised* solenoid tags meant that when
  ;; the last one dropped out there was nothing left to switch the valve coil
  ;; off, so a spring-return valve stayed shifted forever.
  (let* ((circuit (make-circuit-with-spring-valve))
         (valve (find-kind circuit :valve-3-2))
         (button (find-kind circuit :push-button)))
    (settle circuit :steps 5)
    (is (eq :closed (ofs:component-state valve)) "starts in its spring position")
    (setf (ofs:component-pressed button) t)
    (settle circuit :steps 5)
    (is (eq :open (ofs:component-state valve)) "solenoid shifts it")
    (setf (ofs:component-pressed button) nil)
    (settle circuit :steps 5)
    (is (eq :closed (ofs:component-state valve))
        "spring must return it once the solenoid drops out")))

(test coils-sharing-a-return-bus-energise-independently
  ;; Regression, from a real circuit: two solenoid coils whose returns tie
  ;; together on the way to 0V -- ordinary wiring. Coils used to conduct, so
  ;; the live flood ran through Y1a, along the shared return and back up
  ;; through Y1b, energising both. On a detented valve that means both coils
  ;; on at once, so the detent held and pressing S1 did nothing.
  (let* ((circuit (ofs:make-circuit))
         (valve (ofs:add-component circuit (ofs:make-component-of-kind
                                            :valve-5-2-detented)))
         (power (ofs:add-component circuit (ofs:make-component-of-kind :power-24v)))
         (s1 (ofs:add-component circuit (ofs:make-component-of-kind :push-button)))
         (s2 (ofs:add-component circuit (ofs:make-component-of-kind :push-button)))
         (y1a (ofs:add-component circuit (ofs:make-component-of-kind :solenoid-out)))
         (y1b (ofs:add-component circuit (ofs:make-component-of-kind :solenoid-out)))
         (gnd (ofs:add-component circuit (ofs:make-component-of-kind :common-0v))))
    (ofs:assign-unique-label circuit valve)
    (destructuring-bind (coil-a coil-b) (ofs:component-solenoids valve)
      (ofs:rename-component y1a (ofs:solenoid-name coil-a))
      (ofs:rename-component y1b (ofs:solenoid-name coil-b)))
    (ofs:connect circuit (ofs:component-connector power 0) (ofs:component-connector s1 0))
    (ofs:connect circuit (ofs:component-connector power 0) (ofs:component-connector s2 0))
    (ofs:connect circuit (ofs:component-connector s1 1) (ofs:component-connector y1a 0))
    (ofs:connect circuit (ofs:component-connector s2 1) (ofs:component-connector y1b 0))
    ;; The shared return bus.
    (ofs:connect circuit (ofs:component-connector y1a 1) (ofs:component-connector y1b 1))
    (ofs:connect circuit (ofs:component-connector y1b 1) (ofs:component-connector gnd 0))
    (settle circuit :steps 5)
    (is (not (ofs:component-energised y1a)))
    (is (not (ofs:component-energised y1b)))
    ;; Press S1: only Y1a may energise, and the valve must shift.
    (setf (ofs:component-pressed s1) t)
    (settle circuit :steps 5)
    (is (ofs:component-energised y1a) "S1 should energise Y1a")
    (is (not (ofs:component-energised y1b))
        "Y1b shares only a return with Y1a and must stay dead")
    (is (eq :left (ofs:component-state valve)) "the valve must actually shift")
    ;; And the other button drives the other way.
    (setf (ofs:component-pressed s1) nil
          (ofs:component-pressed s2) t)
    (settle circuit :steps 5)
    (is (not (ofs:component-energised y1a)))
    (is (ofs:component-energised y1b))
    (is (eq :right (ofs:component-state valve)))))

(test coil-tags-are-unique-per-valve
  ;; Two valves must not answer to the same solenoid symbol.
  (let* ((circuit (ofs:make-circuit))
         (a (ofs:add-component circuit (ofs:make-component-of-kind :valve-3-2)))
         (b (ofs:add-component circuit (ofs:make-component-of-kind :valve-3-2))))
    (ofs:assign-unique-label circuit a)
    (ofs:assign-unique-label circuit b)
    (is (string/= (ofs:component-label a) (ofs:component-label b)))
    (is (string/= (ofs:solenoid-name (first (ofs:component-solenoids a)))
                  (ofs:solenoid-name (first (ofs:component-solenoids b))))
        "coil tags must differ, or one symbol drives both valves")))

(test retagging-a-valve-retags-its-coils
  (let ((valve (ofs:make-component-of-kind :valve-5-2-detented)))
    (ofs:rename-component valve "Y7")
    (is (equal '("Y7a" "Y7b")
               (mapcar #'ofs:solenoid-name (ofs:component-solenoids valve))))))

(test normally-closed-contact-opens-when-energised
  (let* ((circuit (ofs:make-circuit))
         (power (ofs:add-component circuit (ofs:make-component-of-kind :power-24v)))
         (coil (ofs:add-component circuit (ofs:make-component-of-kind :coil)))
         (ground (ofs:add-component circuit (ofs:make-component-of-kind :common-0v)))
         (contact (ofs:add-component circuit (ofs:make-component-of-kind :contact-nc))))
    (ofs:connect circuit (ofs:component-connector power 0) (ofs:component-connector coil 0))
    (ofs:connect circuit (ofs:component-connector coil 1) (ofs:component-connector ground 0))
    (ofs:step-simulation circuit)
    (is (ofs:component-energised coil))
    (is (eq :open (ofs:component-state contact))
        "an NC contact sharing the coil's label should open")))

;;; Saving and loading.

(defun temp-circuit-path (name)
  (merge-pathnames (format nil "open-fluidsim-test-~a.ofs" name)
                   #p"/tmp/"))

(test save-and-load-round-trips
  (multiple-value-bind (circuit s1 valve cylinder) (ofs:make-relay-demo-circuit)
    (declare (ignore cylinder))
    ;; Put the circuit in a non-default state first, so the test would notice
    ;; if loading silently reset everything to rest.
    (setf (ofs:component-pressed s1) t)
    (settle circuit)
    (setf (ofs:component-pressed s1) nil)
    (settle circuit)
    (is (eq :left (ofs:component-state valve)))
    (let ((path (temp-circuit-path "roundtrip")))
      (ofs:save-circuit circuit path)
      (is (probe-file path) "the file should exist")
      (let ((back (ofs:load-circuit path)))
        (is (= (length (ofs:circuit-components circuit))
               (length (ofs:circuit-components back))))
        (is (= (length (ofs:circuit-wires circuit))
               (length (ofs:circuit-wires back))))
        (let ((restored (find :valve-5-2-detented (ofs:circuit-components back)
                              :key #'ofs:component-kind)))
          (is (eq :left (ofs:component-state restored))
              "a detented valve must reload where it was left, not at rest")
          (is (string= "Y1" (ofs:component-label restored)))
          (is (equal '("Y1a" "Y1b")
                     (mapcar #'ofs:solenoid-name (ofs:component-solenoids restored)))
              "coil tags must survive the round trip, or links break")))
      (delete-file path))))

(test a-loaded-circuit-still-simulates
  ;; Wires are stored as indices, so a mistake there would produce a circuit
  ;; that loads but conducts nothing.
  (multiple-value-bind (circuit s1 valve cylinder) (ofs:make-relay-demo-circuit)
    (declare (ignore s1 valve cylinder))
    (let ((path (temp-circuit-path "simulates")))
      (ofs:save-circuit circuit path)
      (let* ((back (ofs:load-circuit path))
             (valve (find :valve-5-2-detented (ofs:circuit-components back)
                          :key #'ofs:component-kind))
             (cyl (find :cylinder-double (ofs:circuit-components back)
                        :key #'ofs:component-kind))
             (button (find-if (lambda (c)
                                (and (eq :push-button (ofs:component-kind c))
                                     (string= "S1" (ofs:component-label c))))
                              (ofs:circuit-components back))))
        (is (not (null button)) "S1 should have survived the round trip")
        (setf (ofs:component-pressed button) t)
        (settle back)
        (is (eq :left (ofs:component-state valve))
            "the reloaded circuit should still shift its valve")
        (is (= 1.0 (ofs:component-travel cyl))
            "and still drive its cylinder"))
      (delete-file path))))

(test loading-rejects-a-foreign-file
  (let ((path (temp-circuit-path "foreign")))
    (with-open-file (out path :direction :output :if-exists :supersede)
      (write-line "(:something-else 1 :components nil :wires nil)" out))
    (signals error (ofs:load-circuit path))
    (delete-file path)))

(test bare-names-resolve-to-the-circuit-directory
  (let ((path (ofs:circuit-path "demo")))
    (is (string= "demo" (pathname-name path)))
    (is (string= "ofs" (pathname-type path))))
  ;; An explicit path is left alone apart from gaining the type.
  (is (string= "elsewhere" (pathname-name (ofs:circuit-path "/tmp/elsewhere")))))

;;; The demo circuit must be operable in both directions.

(test demo-circuit-can-extend-and-retract
  ;; Regression: with only one solenoid symbol wired there was no way to send
  ;; the detented valve back, which made a working detent look like a stuck
  ;; valve.
  (multiple-value-bind (circuit s1 valve cylinder s2) (ofs:make-relay-demo-circuit)
    (is (not (null s2)) "the demo needs a second button to retract")
    (settle circuit :steps 5)
    ;; Momentary tap: the detent should latch and the stroke complete.
    (setf (ofs:component-pressed s1) t)
    (settle circuit :steps 6)
    (setf (ofs:component-pressed s1) nil)
    (settle circuit)
    (is (eq :left (ofs:component-state valve)) "detent latches after a tap")
    (is (= 1.0 (ofs:component-travel cylinder)) "and the stroke completes")
    ;; The other button must send it back.
    (setf (ofs:component-pressed s2) t)
    (settle circuit :steps 6)
    (setf (ofs:component-pressed s2) nil)
    (settle circuit)
    (is (eq :right (ofs:component-state valve)) "S2 latches it the other way")
    (is (= 0.0 (ofs:component-travel cylinder)) "and it retracts")))

(test hit-testing-finds-components-and-ports
  (let* ((circuit (ofs:make-circuit))
         (valve (ofs:add-component circuit (ofs:make-component-of-kind
                                            :valve-5-2-detented))))
    (is (eq valve (ofs:component-at circuit 12.0 0.0)))
    (is (null (ofs:component-at circuit 900.0 900.0)))
    (let ((p (ofs:component-port-position valve 3)))
      (is (eq (ofs:component-connector valve 3)
              (ofs:connector-at circuit (ofs:pt-x p) (ofs:pt-y p)))))
    (is (null (ofs:connector-at circuit 500.0 500.0)))))

(test wiring-toggles
  (let* ((circuit (ofs:make-circuit))
         (valve (ofs:add-component circuit (ofs:make-component-of-kind
                                            :valve-5-2-detented)))
         (supply (ofs:add-component circuit (ofs:make-component-of-kind :supply)))
         (a (ofs:component-connector valve 3))
         (b (ofs:component-connector supply 0)))
    (is (eq :connected (ofs:toggle-wire circuit a b)))
    (is (= 1 (length (ofs:circuit-wires circuit))))
    (is (eq :disconnected (ofs:toggle-wire circuit a b)) "clicking again unwires")
    (is (= 0 (length (ofs:circuit-wires circuit))))
    ;; Two ports of one component would be a wire to itself.
    (is (null (ofs:toggle-wire circuit
                               (ofs:component-connector valve 0)
                               (ofs:component-connector valve 1))))
    (is (null (ofs:toggle-wire circuit a a)))))

(test removing-a-component-takes-its-wires
  (multiple-value-bind (circuit valve cylinder) (ofs:make-demo-circuit)
    (declare (ignore valve))
    (let ((wires-before (length (ofs:circuit-wires circuit))))
      (ofs:remove-component circuit cylinder)
      ;; Valve, supply and two exhausts remain.
      (is (= 4 (length (ofs:circuit-components circuit))))
      (is (< (length (ofs:circuit-wires circuit)) wires-before)
          "the cylinder's two wires should be gone")
      (is (notany (lambda (wire)
                    (or (eq (ofs:connector-owner (car wire)) cylinder)
                        (eq (ofs:connector-owner (cdr wire)) cylinder)))
                  (ofs:circuit-wires circuit))
          "no wire may reference a removed component"))))

(test a-placed-supply-pressurises-without-add-source
  ;; The editor has no way to call ADD-SOURCE, so :SUPPLY components must
  ;; become sources by virtue of their kind.
  (let* ((circuit (ofs:make-circuit))
         (supply (ofs:add-component circuit (ofs:make-component-of-kind :supply))))
    (is (null (ofs:circuit-sources circuit)) "nothing registered by hand")
    (ofs:propagate circuit)
    (is (ofs:pressurised-p (ofs:component-connector supply 0)))))

(test connection-points-sit-at-the-outer-end-of-port-stubs
  ;; A wire must meet the far end of the port line, not the point where that
  ;; line leaves the body with the drawn stub carrying on past it.
  (let ((valve (ofs:make-valve-5-2-double-solenoid)))
    (dotimes (index 5)
      (let ((flow (aref ofs::*valve-5-2-ports* index))
            (connection (aref (ofs:component-ports valve) index)))
        (is (= (ofs:pt-x flow) (ofs:pt-x connection))
            "port ~a: stub must be vertical" index)
        (is (= (abs (- (ofs:pt-y connection) (ofs:pt-y flow)))
               ofs:+port-stub-length+)
            "port ~a: connection point should be one stub length out" index)
        (is (> (abs (ofs:pt-y connection)) (abs (ofs:pt-y flow)))
            "port ~a: connection point must be outboard, not inboard" index)))))

(test geometry-shifts-with-position
  (let ((valve (ofs:make-valve-5-2-double-solenoid)))
    (flet ((left-edge (component)
             (multiple-value-bind (min-x) (ofs:ops-bounds (ofs:component-world-geometry component))
               min-x)))
      (let ((before (left-edge valve)))
        (setf (ofs:component-state valve) :left)
        (let ((after (left-edge valve)))
          (is (> after before) "body must slide right when shifted to :left"))))))
