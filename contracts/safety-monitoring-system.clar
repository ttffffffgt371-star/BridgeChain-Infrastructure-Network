;; Safety Monitoring System Contract
;; Monitor bridge conditions using sensors and coordinate maintenance to prevent structural failures

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-UNAUTHORIZED (err u203))
(define-constant ERR-INVALID-THRESHOLD (err u204))
(define-constant ERR-INVALID-PRIORITY (err u205))
(define-constant ERR-SYSTEM-INACTIVE (err u206))
(define-constant ERR-SENSOR-OFFLINE (err u207))

;; Alert Priority Levels
(define-constant PRIORITY-LOW u1)
(define-constant PRIORITY-MEDIUM u2)
(define-constant PRIORITY-HIGH u3)
(define-constant PRIORITY-CRITICAL u4)

;; Sensor Status
(define-constant SENSOR-ACTIVE "active")
(define-constant SENSOR-OFFLINE "offline")
(define-constant SENSOR-MAINTENANCE "maintenance")

;; Data Variables
(define-data-var monitoring-active bool true)
(define-data-var alert-counter uint u0)
(define-data-var sensor-counter uint u0)
(define-data-var maintenance-request-counter uint u0)

;; Sensor Network Registry
(define-map sensors
  { sensor-id: uint }
  {
    bridge-id: uint,
    sensor-type: (string-ascii 32),
    location: (string-ascii 64),
    installation-date: uint,
    last-reading: uint,
    status: (string-ascii 16),
    operator: principal,
    calibration-date: uint
  }
)

;; Safety Thresholds Configuration
(define-map safety-thresholds
  { bridge-id: uint, threshold-type: (string-ascii 32) }
  {
    warning-level: uint,
    critical-level: uint,
    measurement-unit: (string-ascii 16),
    set-by: principal,
    last-updated: uint
  }
)

;; Real-time Sensor Readings
(define-map sensor-readings
  { sensor-id: uint, reading-id: uint }
  {
    timestamp: uint,
    value: uint,
    status: (string-ascii 16),
    alert-triggered: bool,
    recorded-by: principal
  }
)

;; Sensor Reading Counter
(define-map sensor-reading-counters
  { sensor-id: uint }
  { counter: uint }
)

;; Alert System
(define-map safety-alerts
  { alert-id: uint }
  {
    bridge-id: uint,
    sensor-id: uint,
    alert-type: (string-ascii 32),
    priority: uint,
    description: (string-ascii 256),
    triggered-at: uint,
    resolved-at: (optional uint),
    resolved-by: (optional principal),
    status: (string-ascii 16)
  }
)

;; Maintenance Requests
(define-map maintenance-requests
  { request-id: uint }
  {
    bridge-id: uint,
    alert-id: (optional uint),
    request-type: (string-ascii 32),
    priority: uint,
    description: (string-ascii 256),
    requested-by: principal,
    requested-at: uint,
    assigned-to: (optional principal),
    status: (string-ascii 16),
    estimated-cost: uint
  }
)

;; Emergency Contacts
(define-map emergency-contacts
  { bridge-id: uint, contact-type: (string-ascii 32) }
  {
    contact-info: (string-ascii 128),
    active: bool,
    last-notified: uint
  }
)

;; Public Functions

;; Register new sensor
(define-public (register-sensor
    (bridge-id uint)
    (sensor-type (string-ascii 32))
    (location (string-ascii 64)))
  (let
    (
      (sensor-id (+ (var-get sensor-counter) u1))
      (current-block burn-block-height)
    )
    (asserts! (var-get monitoring-active) ERR-SYSTEM-INACTIVE)
    
    (map-set sensors
      { sensor-id: sensor-id }
      {
        bridge-id: bridge-id,
        sensor-type: sensor-type,
        location: location,
        installation-date: current-block,
        last-reading: current-block,
        status: SENSOR-ACTIVE,
        operator: tx-sender,
        calibration-date: current-block
      }
    )
    
    (map-set sensor-reading-counters { sensor-id: sensor-id } { counter: u0 })
    (var-set sensor-counter sensor-id)
    (ok sensor-id)
  )
)

;; Set safety thresholds for a bridge
(define-public (set-safety-threshold
    (bridge-id uint)
    (threshold-type (string-ascii 32))
    (warning-level uint)
    (critical-level uint)
    (measurement-unit (string-ascii 16)))
  (let
    (
      (current-block burn-block-height)
    )
    (asserts! (> critical-level warning-level) ERR-INVALID-THRESHOLD)
    
    (map-set safety-thresholds
      { bridge-id: bridge-id, threshold-type: threshold-type }
      {
        warning-level: warning-level,
        critical-level: critical-level,
        measurement-unit: measurement-unit,
        set-by: tx-sender,
        last-updated: current-block
      }
    )
    (ok true)
  )
)

;; Record sensor reading and check for alerts
(define-public (record-sensor-reading
    (sensor-id uint)
    (reading-value uint))
  (let
    (
      (sensor-data (unwrap! (map-get? sensors { sensor-id: sensor-id }) ERR-NOT-FOUND))
      (reading-counter (default-to u0 (get counter (map-get? sensor-reading-counters { sensor-id: sensor-id }))))
      (new-reading-id (+ reading-counter u1))
      (current-block burn-block-height)
      (bridge-id (get bridge-id sensor-data))
    )
    (asserts! (is-eq (get status sensor-data) SENSOR-ACTIVE) ERR-SENSOR-OFFLINE)
    
    ;; Record the reading
    (map-set sensor-readings
      { sensor-id: sensor-id, reading-id: new-reading-id }
      {
        timestamp: current-block,
        value: reading-value,
        status: "normal",
        alert-triggered: false,
        recorded-by: tx-sender
      }
    )
    
    ;; Update sensor last reading timestamp
    (map-set sensors
      { sensor-id: sensor-id }
      (merge sensor-data { last-reading: current-block })
    )
    
    (map-set sensor-reading-counters { sensor-id: sensor-id } { counter: new-reading-id })
    
    ;; Check thresholds and trigger alerts if necessary
    (try! (check-and-trigger-alert sensor-id bridge-id reading-value))
    
    (ok new-reading-id)
  )
)

;; Trigger safety alert
(define-public (trigger-manual-alert
    (bridge-id uint)
    (alert-type (string-ascii 32))
    (priority uint)
    (description (string-ascii 256)))
  (let
    (
      (alert-id (+ (var-get alert-counter) u1))
      (current-block burn-block-height)
    )
    (asserts! (<= priority PRIORITY-CRITICAL) ERR-INVALID-PRIORITY)
    (asserts! (>= priority PRIORITY-LOW) ERR-INVALID-PRIORITY)
    
    (map-set safety-alerts
      { alert-id: alert-id }
      {
        bridge-id: bridge-id,
        sensor-id: u0,
        alert-type: alert-type,
        priority: priority,
        description: description,
        triggered-at: current-block,
        resolved-at: none,
        resolved-by: none,
        status: "active"
      }
    )
    
    (var-set alert-counter alert-id)
    (ok alert-id)
  )
)

;; Resolve safety alert
(define-public (resolve-alert (alert-id uint) (resolution-notes (string-ascii 256)))
  (let
    (
      (alert-data (unwrap! (map-get? safety-alerts { alert-id: alert-id }) ERR-NOT-FOUND))
      (current-block burn-block-height)
    )
    (asserts! (is-eq (get status alert-data) "active") ERR-NOT-FOUND)
    
    (map-set safety-alerts
      { alert-id: alert-id }
      (merge alert-data {
        resolved-at: (some current-block),
        resolved-by: (some tx-sender),
        status: "resolved"
      })
    )
    (ok true)
  )
)

;; Create maintenance request
(define-public (create-maintenance-request
    (bridge-id uint)
    (request-type (string-ascii 32))
    (priority uint)
    (description (string-ascii 256))
    (estimated-cost uint))
  (let
    (
      (request-id (+ (var-get maintenance-request-counter) u1))
      (current-block burn-block-height)
    )
    (asserts! (<= priority PRIORITY-CRITICAL) ERR-INVALID-PRIORITY)
    (asserts! (>= priority PRIORITY-LOW) ERR-INVALID-PRIORITY)
    
    (map-set maintenance-requests
      { request-id: request-id }
      {
        bridge-id: bridge-id,
        alert-id: none,
        request-type: request-type,
        priority: priority,
        description: description,
        requested-by: tx-sender,
        requested-at: current-block,
        assigned-to: none,
        status: "pending",
        estimated-cost: estimated-cost
      }
    )
    
    (var-set maintenance-request-counter request-id)
    (ok request-id)
  )
)

;; Assign maintenance request
(define-public (assign-maintenance-request (request-id uint) (assigned-to principal))
  (let
    (
      (request-data (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (is-eq (get status request-data) "pending") ERR-NOT-FOUND)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request-data {
        assigned-to: (some assigned-to),
        status: "assigned"
      })
    )
    (ok true)
  )
)

;; Update sensor status
(define-public (update-sensor-status (sensor-id uint) (new-status (string-ascii 16)))
  (let
    (
      (sensor-data (unwrap! (map-get? sensors { sensor-id: sensor-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get operator sensor-data)) ERR-UNAUTHORIZED)
    
    (map-set sensors
      { sensor-id: sensor-id }
      (merge sensor-data { status: new-status })
    )
    (ok true)
  )
)

;; Emergency system shutdown
(define-public (emergency-shutdown)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set monitoring-active false)
    (ok true)
  )
)

;; Private Functions

;; Check thresholds and trigger alert if necessary
(define-private (check-and-trigger-alert (sensor-id uint) (bridge-id uint) (reading-value uint))
  (let
    (
      (sensor-data (unwrap! (map-get? sensors { sensor-id: sensor-id }) ERR-NOT-FOUND))
      (threshold-data (map-get? safety-thresholds { bridge-id: bridge-id, threshold-type: (get sensor-type sensor-data) }))
    )
    (match threshold-data
      thresholds
      (if (>= reading-value (get critical-level thresholds))
        (trigger-threshold-alert sensor-id bridge-id "critical" reading-value)
        (if (>= reading-value (get warning-level thresholds))
          (trigger-threshold-alert sensor-id bridge-id "warning" reading-value)
          (ok u0)
        )
      )
      (ok u0)
    )
  )
)

;; Trigger threshold-based alert
(define-private (trigger-threshold-alert (sensor-id uint) (bridge-id uint) (alert-level (string-ascii 16)) (reading-value uint))
  (let
    (
      (alert-id (+ (var-get alert-counter) u1))
      (current-block burn-block-height)
      (priority (if (is-eq alert-level "critical") PRIORITY-CRITICAL PRIORITY-MEDIUM))
    )
    (map-set safety-alerts
      { alert-id: alert-id }
      {
        bridge-id: bridge-id,
        sensor-id: sensor-id,
        alert-type: "threshold-exceeded",
        priority: priority,
        description: "Sensor reading exceeded safety threshold",
        triggered-at: current-block,
        resolved-at: none,
        resolved-by: none,
        status: "active"
      }
    )
    
    (var-set alert-counter alert-id)
    (ok alert-id)
  )
)

;; Read Only Functions

;; Get sensor information
(define-read-only (get-sensor-info (sensor-id uint))
  (map-get? sensors { sensor-id: sensor-id })
)

;; Get latest sensor reading
(define-read-only (get-latest-sensor-reading (sensor-id uint))
  (let
    (
      (reading-counter (default-to u0 (get counter (map-get? sensor-reading-counters { sensor-id: sensor-id }))))
    )
    (if (> reading-counter u0)
      (map-get? sensor-readings { sensor-id: sensor-id, reading-id: reading-counter })
      none
    )
  )
)

;; Get safety threshold
(define-read-only (get-safety-threshold (bridge-id uint) (threshold-type (string-ascii 32)))
  (map-get? safety-thresholds { bridge-id: bridge-id, threshold-type: threshold-type })
)

;; Get alert information
(define-read-only (get-alert-info (alert-id uint))
  (map-get? safety-alerts { alert-id: alert-id })
)

;; Get maintenance request
(define-read-only (get-maintenance-request (request-id uint))
  (map-get? maintenance-requests { request-id: request-id })
)

;; Get system status
(define-read-only (get-system-status)
  {
    monitoring-active: (var-get monitoring-active),
    total-sensors: (var-get sensor-counter),
    total-alerts: (var-get alert-counter),
    total-maintenance-requests: (var-get maintenance-request-counter),
    owner: CONTRACT-OWNER
  }
)

;; Get bridge monitoring summary
(define-read-only (get-bridge-monitoring-summary (bridge-id uint))
  (ok {
    bridge-id: bridge-id,
    monitoring-active: (var-get monitoring-active),
    last-check: burn-block-height
  })
)

