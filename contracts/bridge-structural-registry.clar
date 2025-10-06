;; Bridge Structural Registry Contract
;; Map and register bridges with structural health data, load capacity, and inspection schedules

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-CAPACITY (err u103))
(define-constant ERR-UNAUTHORIZED (err u104))
(define-constant ERR-INVALID-HEALTH-SCORE (err u105))
(define-constant MAX-HEALTH-SCORE u100)
(define-constant MIN-HEALTH-SCORE u0)

;; Data Variables
(define-data-var bridge-counter uint u0)
(define-data-var contract-active bool true)

;; Bridge Structure Definition
(define-map bridges
  { bridge-id: uint }
  {
    name: (string-ascii 64),
    location: (string-ascii 128),
    bridge-type: (string-ascii 32),
    construction-year: uint,
    load-capacity: uint,
    current-health-score: uint,
    last-inspection: uint,
    next-inspection: uint,
    inspector-address: principal,
    status: (string-ascii 16),
    registration-block: uint,
    owner: principal
  }
)

;; Inspector Registry
(define-map authorized-inspectors
  { inspector: principal }
  {
    name: (string-ascii 64),
    certification: (string-ascii 32),
    active: bool,
    total-inspections: uint
  }
)

;; Inspection History
(define-map inspection-records
  { bridge-id: uint, inspection-id: uint }
  {
    inspector: principal,
    inspection-date: uint,
    health-score: uint,
    notes: (string-ascii 256),
    recommendations: (string-ascii 256)
  }
)

;; Bridge to Inspection Counter Mapping
(define-map bridge-inspection-counters
  { bridge-id: uint }
  { counter: uint }
)

;; Maintenance Records
(define-map maintenance-records
  { bridge-id: uint, maintenance-id: uint }
  {
    maintenance-date: uint,
    maintenance-type: (string-ascii 32),
    cost: uint,
    contractor: (string-ascii 64),
    performed-by: principal
  }
)

;; Bridge to Maintenance Counter Mapping
(define-map bridge-maintenance-counters
  { bridge-id: uint }
  { counter: uint }
)

;; Public Functions

;; Register a new bridge
(define-public (register-bridge 
    (name (string-ascii 64))
    (location (string-ascii 128))
    (bridge-type (string-ascii 32))
    (construction-year uint)
    (load-capacity uint)
    (initial-health-score uint))
  (let 
    (
      (bridge-id (+ (var-get bridge-counter) u1))
      (current-block burn-block-height)
    )
    (asserts! (var-get contract-active) ERR-OWNER-ONLY)
    (asserts! (> load-capacity u0) ERR-INVALID-CAPACITY)
    (asserts! (<= initial-health-score MAX-HEALTH-SCORE) ERR-INVALID-HEALTH-SCORE)
    (asserts! (>= initial-health-score MIN-HEALTH-SCORE) ERR-INVALID-HEALTH-SCORE)
    
    (map-set bridges
      { bridge-id: bridge-id }
      {
        name: name,
        location: location,
        bridge-type: bridge-type,
        construction-year: construction-year,
        load-capacity: load-capacity,
        current-health-score: initial-health-score,
        last-inspection: current-block,
        next-inspection: (+ current-block u2016),
        inspector-address: tx-sender,
        status: "active",
        registration-block: current-block,
        owner: tx-sender
      }
    )
    
    (map-set bridge-inspection-counters { bridge-id: bridge-id } { counter: u0 })
    (map-set bridge-maintenance-counters { bridge-id: bridge-id } { counter: u0 })
    
    (var-set bridge-counter bridge-id)
    (ok bridge-id)
  )
)

;; Add authorized inspector
(define-public (add-inspector 
    (inspector principal)
    (name (string-ascii 64))
    (certification (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (map-set authorized-inspectors
      { inspector: inspector }
      {
        name: name,
        certification: certification,
        active: true,
        total-inspections: u0
      }
    )
    (ok true)
  )
)

;; Update bridge health score after inspection
(define-public (update-health-score 
    (bridge-id uint)
    (new-health-score uint)
    (inspection-notes (string-ascii 256))
    (recommendations (string-ascii 256)))
  (let 
    (
      (bridge-data (unwrap! (map-get? bridges { bridge-id: bridge-id }) ERR-NOT-FOUND))
      (inspector-data (unwrap! (map-get? authorized-inspectors { inspector: tx-sender }) ERR-UNAUTHORIZED))
      (inspection-counter (default-to u0 (get counter (map-get? bridge-inspection-counters { bridge-id: bridge-id }))))
      (new-inspection-id (+ inspection-counter u1))
      (current-block burn-block-height)
    )
    (asserts! (get active inspector-data) ERR-UNAUTHORIZED)
    (asserts! (<= new-health-score MAX-HEALTH-SCORE) ERR-INVALID-HEALTH-SCORE)
    (asserts! (>= new-health-score MIN-HEALTH-SCORE) ERR-INVALID-HEALTH-SCORE)
    
    (map-set bridges
      { bridge-id: bridge-id }
      (merge bridge-data {
        current-health-score: new-health-score,
        last-inspection: current-block,
        next-inspection: (+ current-block u2016),
        inspector-address: tx-sender
      })
    )
    
    (map-set inspection-records
      { bridge-id: bridge-id, inspection-id: new-inspection-id }
      {
        inspector: tx-sender,
        inspection-date: current-block,
        health-score: new-health-score,
        notes: inspection-notes,
        recommendations: recommendations
      }
    )
    
    (map-set bridge-inspection-counters { bridge-id: bridge-id } { counter: new-inspection-id })
    (map-set authorized-inspectors
      { inspector: tx-sender }
      (merge inspector-data { total-inspections: (+ (get total-inspections inspector-data) u1) })
    )
    
    (ok new-inspection-id)
  )
)

;; Record maintenance activity
(define-public (record-maintenance 
    (bridge-id uint)
    (maintenance-type (string-ascii 32))
    (cost uint)
    (contractor (string-ascii 64)))
  (let 
    (
      (bridge-data (unwrap! (map-get? bridges { bridge-id: bridge-id }) ERR-NOT-FOUND))
      (maintenance-counter (default-to u0 (get counter (map-get? bridge-maintenance-counters { bridge-id: bridge-id }))))
      (new-maintenance-id (+ maintenance-counter u1))
      (current-block burn-block-height)
    )
    (asserts! (is-eq tx-sender (get owner bridge-data)) ERR-UNAUTHORIZED)
    
    (map-set maintenance-records
      { bridge-id: bridge-id, maintenance-id: new-maintenance-id }
      {
        maintenance-date: current-block,
        maintenance-type: maintenance-type,
        cost: cost,
        contractor: contractor,
        performed-by: tx-sender
      }
    )
    
    (map-set bridge-maintenance-counters { bridge-id: bridge-id } { counter: new-maintenance-id })
    (ok new-maintenance-id)
  )
)

;; Update bridge status
(define-public (update-bridge-status (bridge-id uint) (new-status (string-ascii 16)))
  (let 
    (
      (bridge-data (unwrap! (map-get? bridges { bridge-id: bridge-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner bridge-data)) ERR-UNAUTHORIZED)
    
    (map-set bridges
      { bridge-id: bridge-id }
      (merge bridge-data { status: new-status })
    )
    (ok true)
  )
)

;; Emergency contract shutdown
(define-public (emergency-shutdown)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-active false)
    (ok true)
  )
)

;; Read Only Functions

;; Get bridge information
(define-read-only (get-bridge-info (bridge-id uint))
  (map-get? bridges { bridge-id: bridge-id })
)

;; Get inspector information
(define-read-only (get-inspector-info (inspector principal))
  (map-get? authorized-inspectors { inspector: inspector })
)

;; Get inspection record
(define-read-only (get-inspection-record (bridge-id uint) (inspection-id uint))
  (map-get? inspection-records { bridge-id: bridge-id, inspection-id: inspection-id })
)

;; Get maintenance record
(define-read-only (get-maintenance-record (bridge-id uint) (maintenance-id uint))
  (map-get? maintenance-records { bridge-id: bridge-id, maintenance-id: maintenance-id })
)

;; Get total bridge count
(define-read-only (get-bridge-count)
  (var-get bridge-counter)
)

;; Get contract status
(define-read-only (get-contract-status)
  {
    active: (var-get contract-active),
    total-bridges: (var-get bridge-counter),
    owner: CONTRACT-OWNER
  }
)

;; Check if bridge needs inspection
(define-read-only (needs-inspection (bridge-id uint))
  (match (map-get? bridges { bridge-id: bridge-id })
    bridge-data (ok (>= burn-block-height (get next-inspection bridge-data)))
    ERR-NOT-FOUND
  )
)

;; Get bridge health status
(define-read-only (get-bridge-health-status (bridge-id uint))
  (match (map-get? bridges { bridge-id: bridge-id })
    bridge-data 
    (ok {
      bridge-id: bridge-id,
      health-score: (get current-health-score bridge-data),
      status: (get status bridge-data),
      last-inspection: (get last-inspection bridge-data),
      needs-attention: (< (get current-health-score bridge-data) u60)
    })
    ERR-NOT-FOUND
  )
)

