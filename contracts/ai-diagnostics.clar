;; AI Diagnostic Assistance Contract
;; Provides AI-powered diagnostic support to healthcare providers

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-PROVIDER (err u201))
(define-constant ERR-INVALID-REQUEST (err u202))
(define-constant ERR-REQUEST-NOT-FOUND (err u203))
(define-constant ERR-INVALID-RATING (err u204))
(define-constant ERR-ALREADY-RATED (err u205))

;; Data Variables
(define-data-var request-counter uint u0)
(define-data-var ai-model-version (string-ascii 20) "v1.0")

;; Data Maps
(define-map healthcare-providers
  { provider-id: principal }
  {
    name: (string-ascii 100),
    specialty: (string-ascii 50),
    license-number: (string-ascii 20),
    institution: (string-ascii 100),
    is-verified: bool,
    diagnostic-requests: uint,
    accuracy-score: uint
  }
)

(define-map diagnostic-requests
  { request-id: uint }
  {
    provider-id: principal,
    patient-symptoms: (string-ascii 500),
    patient-age: uint,
    patient-gender: (string-ascii 10),
    medical-history: (string-ascii 300),
    test-results: (optional (string-ascii 300)),
    ai-diagnosis: (optional (string-ascii 200)),
    confidence-score: (optional uint),
    timestamp: uint,
    status: (string-ascii 20)
  }
)

(define-map diagnosis-feedback
  { request-id: uint }
  {
    provider-id: principal,
    accuracy-rating: uint,
    clinical-outcome: (string-ascii 200),
    feedback-notes: (optional (string-ascii 300)),
    timestamp: uint
  }
)

(define-map ai-model-performance
  { model-version: (string-ascii 20) }
  {
    total-requests: uint,
    accurate-diagnoses: uint,
    average-confidence: uint,
    last-updated: uint
  }
)

;; Public Functions

;; Register healthcare provider
(define-public (register-provider (name (string-ascii 100)) (specialty (string-ascii 50)) (license-number (string-ascii 20)) (institution (string-ascii 100)))
  (begin
    (asserts! (> (len name) u0) ERR-INVALID-PROVIDER)
    (asserts! (> (len specialty) u0) ERR-INVALID-PROVIDER)
    (asserts! (> (len license-number) u0) ERR-INVALID-PROVIDER)
    (ok (map-set healthcare-providers
      { provider-id: tx-sender }
      {
        name: name,
        specialty: specialty,
        license-number: license-number,
        institution: institution,
        is-verified: false,
        diagnostic-requests: u0,
        accuracy-score: u0
      }
    ))
  )
)

;; Verify healthcare provider (admin only)
(define-public (verify-provider (provider-id principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (match (map-get? healthcare-providers { provider-id: provider-id })
      provider-data (ok (map-set healthcare-providers
        { provider-id: provider-id }
        (merge provider-data { is-verified: true })
      ))
      ERR-INVALID-PROVIDER
    )
  )
)

;; Submit diagnostic request
(define-public (submit-diagnostic-request
  (patient-symptoms (string-ascii 500))
  (patient-age uint)
  (patient-gender (string-ascii 10))
  (medical-history (string-ascii 300))
  (test-results (optional (string-ascii 300))))
  (let
    (
      (request-id (+ (var-get request-counter) u1))
      (provider-data (unwrap! (map-get? healthcare-providers { provider-id: tx-sender }) ERR-INVALID-PROVIDER))
    )
    (asserts! (get is-verified provider-data) ERR-NOT-AUTHORIZED)
    (asserts! (> (len patient-symptoms) u0) ERR-INVALID-REQUEST)
    (asserts! (> patient-age u0) ERR-INVALID-REQUEST)
    (asserts! (< patient-age u150) ERR-INVALID-REQUEST)

    (var-set request-counter request-id)

    ;; Update provider request count
    (map-set healthcare-providers
      { provider-id: tx-sender }
      (merge provider-data { diagnostic-requests: (+ (get diagnostic-requests provider-data) u1) })
    )

    (ok (map-set diagnostic-requests
      { request-id: request-id }
      {
        provider-id: tx-sender,
        patient-symptoms: patient-symptoms,
        patient-age: patient-age,
        patient-gender: patient-gender,
        medical-history: medical-history,
        test-results: test-results,
        ai-diagnosis: none,
        confidence-score: none,
        timestamp: block-height,
        status: "pending"
      }
    ))
  )
)

;; AI system provides diagnosis (admin only - simulates AI response)
(define-public (provide-ai-diagnosis (request-id uint) (diagnosis (string-ascii 200)) (confidence-score uint))
  (let
    (
      (request-data (unwrap! (map-get? diagnostic-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request-data) "pending") ERR-INVALID-REQUEST)
    (asserts! (> (len diagnosis) u0) ERR-INVALID-REQUEST)
    (asserts! (<= confidence-score u100) ERR-INVALID-REQUEST)

    (ok (map-set diagnostic-requests
      { request-id: request-id }
      (merge request-data {
        ai-diagnosis: (some diagnosis),
        confidence-score: (some confidence-score),
        status: "completed"
      })
    ))
  )
)

;; Provider submits feedback on AI diagnosis accuracy
(define-public (submit-diagnosis-feedback (request-id uint) (accuracy-rating uint) (clinical-outcome (string-ascii 200)) (feedback-notes (optional (string-ascii 300))))
  (let
    (
      (request-data (unwrap! (map-get? diagnostic-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (existing-feedback (map-get? diagnosis-feedback { request-id: request-id }))
    )
    (asserts! (is-eq tx-sender (get provider-id request-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request-data) "completed") ERR-INVALID-REQUEST)
    (asserts! (<= accuracy-rating u5) ERR-INVALID-RATING)
    (asserts! (> accuracy-rating u0) ERR-INVALID-RATING)
    (asserts! (is-none existing-feedback) ERR-ALREADY-RATED)

    ;; Update provider accuracy score
    (let
      (
        (provider-data (unwrap-panic (map-get? healthcare-providers { provider-id: tx-sender })))
        (current-score (get accuracy-score provider-data))
        (request-count (get diagnostic-requests provider-data))
        (new-score (/ (+ (* current-score (- request-count u1)) (* accuracy-rating u20)) request-count))
      )
      (map-set healthcare-providers
        { provider-id: tx-sender }
        (merge provider-data { accuracy-score: new-score })
      )
    )

    (ok (map-set diagnosis-feedback
      { request-id: request-id }
      {
        provider-id: tx-sender,
        accuracy-rating: accuracy-rating,
        clinical-outcome: clinical-outcome,
        feedback-notes: feedback-notes,
        timestamp: block-height
      }
    ))
  )
)

;; Update AI model version (admin only)
(define-public (update-ai-model (new-version (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-version) u0) ERR-INVALID-REQUEST)
    (ok (var-set ai-model-version new-version))
  )
)

;; Read-only functions

(define-read-only (get-provider (provider-id principal))
  (map-get? healthcare-providers { provider-id: provider-id })
)

(define-read-only (get-diagnostic-request (request-id uint))
  (map-get? diagnostic-requests { request-id: request-id })
)

(define-read-only (get-diagnosis-feedback (request-id uint))
  (map-get? diagnosis-feedback { request-id: request-id })
)

(define-read-only (get-request-counter)
  (var-get request-counter)
)

(define-read-only (get-ai-model-version)
  (var-get ai-model-version)
)

(define-read-only (get-model-performance (model-version (string-ascii 20)))
  (map-get? ai-model-performance { model-version: model-version })
)
