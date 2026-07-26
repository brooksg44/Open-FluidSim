;;;; package.lisp

(defpackage #:open-fluidsim
  (:nicknames #:ofs)
  (:use #:cl)
  (:export
   ;; geometry
   #:pt #:pt-x #:pt-y #:pt+ #:pt- #:pt-scale
   ;; drawing operations (backend-agnostic)
   #:polyline #:polyline-points #:polyline-width
   #:poly #:poly-points #:poly-filled
   #:disc #:disc-center #:disc-radius #:disc-filled
   #:box #:box-x #:box-y #:box-w #:box-h #:box-width
   #:caption #:caption-pos #:caption-text #:caption-size
   #:translate-ops #:ops-bounds
   ;; glyphs
   #:glyph-solenoid #:glyph-spring #:glyph-detent #:glyph-arrow #:glyph-port-stub
   #:stub-end #:+box-w+ #:+box-h+ #:+actuator-h+ #:+port-stub-length+
   ;; model
   #:connector #:make-connector #:connector-index #:connector-owner #:connector-pressure
   #:component #:make-component #:component-name #:component-kind #:component-state
   #:component-connectors #:component-solenoids #:component-tables #:component-origin
   #:component-connector #:component-shift #:component-travel #:component-travel-rate
   #:component-domain #:component-hold #:component-rest-state #:component-label
   #:component-energised #:component-pressed #:component-table #:fixed-table
   ;; registry
   #:register-kind #:kind-info #:kind-label #:kind-domain #:all-kinds
   #:kinds-in-domain #:domains #:palette-for-domain
   #:solenoid #:make-solenoid #:solenoid-name #:solenoid-active
   #:circuit #:make-circuit #:circuit-components #:circuit-wires #:circuit-sources
   #:add-component #:connect #:add-source
   ;; engine
   #:update-cylinders #:propagate #:step-simulation
   #:pressurised-p #:energise #:de-energise #:source-connectors
   #:return-connectors #:grounded-connectors #:flood #:update-valves
   #:update-electric
   ;; editing
   #:make-component-of-kind #:component-bounds #:point-in-component-p
   #:component-at #:connector-at #:move-component #:wire-between #:toggle-wire
   #:remove-component #:clear-circuit
   ;; persistence
   #:save-circuit #:load-circuit #:circuit-path #:circuit-directory
   #:circuit-form #:circuit-from-form
   ;; library
   #:make-valve-5-2-double-solenoid #:make-supply #:make-exhaust #:make-cylinder
   #:make-demo-circuit #:make-relay-demo-circuit #:solenoid-name
   #:rename-component #:assign-unique-label #:refresh-solenoid-tags
   #:component-ports #:component-port-position #:connector-position
   #:component-geometry #:component-world-geometry #:valve-geometry
   #:circuit-bounds))
