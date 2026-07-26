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
    (is (eq :valve-5-2-double-solenoid (ofs:component-kind valve)))
    (is (eq :cylinder-double-acting (ofs:component-kind cylinder)))))

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

(test every-palette-kind-is-constructible
  ;; If a kind reaches the palette without a MAKE-COMPONENT-OF-KIND clause,
  ;; clicking it would fail at placement time. Catch it here instead.
  (dolist (entry ofs:*palette*)
    (let ((component (ofs:make-component-of-kind (car entry))))
      (is (eq (car entry) (ofs:component-kind component)))
      (is (plusp (length (ofs:component-world-geometry component)))))))

(test hit-testing-finds-components-and-ports
  (let* ((circuit (ofs:make-circuit))
         (valve (ofs:add-component circuit (ofs:make-component-of-kind
                                            :valve-5-2-double-solenoid))))
    (is (eq valve (ofs:component-at circuit 12.0 0.0)))
    (is (null (ofs:component-at circuit 900.0 900.0)))
    (let ((p (ofs:component-port-position valve 3)))
      (is (eq (ofs:component-connector valve 3)
              (ofs:connector-at circuit (ofs:pt-x p) (ofs:pt-y p)))))
    (is (null (ofs:connector-at circuit 500.0 500.0)))))

(test wiring-toggles
  (let* ((circuit (ofs:make-circuit))
         (valve (ofs:add-component circuit (ofs:make-component-of-kind
                                            :valve-5-2-double-solenoid)))
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
             (multiple-value-bind (min-x) (ofs:ops-bounds (ofs:valve-geometry component))
               min-x)))
      (let ((before (left-edge valve)))
        (setf (ofs:component-state valve) :left)
        (let ((after (left-edge valve)))
          (is (> after before) "body must slide right when shifted to :left"))))))
