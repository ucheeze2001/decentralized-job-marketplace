;; title: escrow-payments
;; version: 1.0.0
;; summary: Smart contract to hold funds until successful completion of work
;; description: Manages payment security and automated releases for the decentralized job marketplace

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_ESCROW_ALREADY_EXISTS (err u409))
(define-constant ERR_ESCROW_NOT_FUNDED (err u410))
(define-constant ERR_PAYMENT_ALREADY_RELEASED (err u411))
(define-constant ERR_INVALID_STATUS (err u422))
(define-constant ERR_DISPUTE_ACTIVE (err u412))
(define-constant ERR_INSUFFICIENT_BALANCE (err u413))
(define-constant ERR_REFUND_NOT_ALLOWED (err u414))
(define-constant ERR_MILESTONE_NOT_APPROVED (err u415))

;; escrow status constants
(define-constant ESCROW_PENDING u0)
(define-constant ESCROW_FUNDED u1)
(define-constant ESCROW_COMPLETED u2)
(define-constant ESCROW_DISPUTED u3)
(define-constant ESCROW_REFUNDED u4)

;; payment status constants
(define-constant PAYMENT_PENDING u0)
(define-constant PAYMENT_RELEASED u1)
(define-constant PAYMENT_DISPUTED u2)

;; dispute status constants
(define-constant DISPUTE_NONE u0)
(define-constant DISPUTE_CLIENT_INITIATED u1)
(define-constant DISPUTE_FREELANCER_INITIATED u2)
(define-constant DISPUTE_RESOLVED u3)

;; data vars
(define-data-var next-escrow-id uint u1)
(define-data-var total-escrows uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5%
(define-data-var dispute-resolution-fee uint u100000) ;; 100 STX
(define-data-var total-platform-fees uint u0)

;; data maps
;; main escrow data structure
(define-map escrows uint {
    job-id: uint,
    client: principal,
    freelancer: (optional principal),
    total-amount: uint,
    amount-deposited: uint,
    amount-released: uint,
    status: uint,
    created-at: uint,
    funded-at: (optional uint),
    completed-at: (optional uint),
    dispute-status: uint,
    arbitrator: (optional principal)
})

;; milestone payment tracking
(define-map milestone-payments {escrow-id: uint, milestone-id: uint} {
    amount: uint,
    status: uint,
    released-at: (optional uint),
    release-tx: (optional (string-ascii 64))
})

;; dispute records
(define-map disputes uint {
    escrow-id: uint,
    initiated-by: principal,
    reason: (string-ascii 512),
    evidence: (optional (string-ascii 256)),
    created-at: uint,
    resolved-at: (optional uint),
    resolution: (optional (string-ascii 512)),
    arbitrator-decision: (optional uint)
})

;; emergency pause mechanism
(define-map emergency-pause bool bool)

;; authorized arbitrators
(define-map arbitrators principal bool)

;; private functions
(define-private (is-contract-paused)
    (default-to false (map-get? emergency-pause true)))

(define-private (is-authorized-arbitrator (arbitrator principal))
    (default-to false (map-get? arbitrators arbitrator)))

(define-private (increment-escrow-id)
    (let ((current-id (var-get next-escrow-id)))
        (var-set next-escrow-id (+ current-id u1))
        current-id))

(define-private (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000))

(define-private (is-escrow-client (escrow-id uint) (user principal))
    (match (map-get? escrows escrow-id)
        escrow (is-eq (get client escrow) user)
        false))

(define-private (is-escrow-freelancer (escrow-id uint) (user principal))
    (match (map-get? escrows escrow-id)
        escrow (match (get freelancer escrow)
                freelancer (is-eq freelancer user)
                false)
        false))

(define-private (is-valid-escrow-status (status uint))
    (or (is-eq status ESCROW_PENDING)
        (is-eq status ESCROW_FUNDED)
        (is-eq status ESCROW_COMPLETED)
        (is-eq status ESCROW_DISPUTED)
        (is-eq status ESCROW_REFUNDED)))

;; public functions
;; create new escrow for a job
(define-public (create-escrow (job-id uint) (total-amount uint) (freelancer (optional principal)))
    (let ((escrow-id (increment-escrow-id)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (> total-amount u0) ERR_INVALID_INPUT)
        
        ;; create escrow record
        (map-set escrows escrow-id {
            job-id: job-id,
            client: tx-sender,
            freelancer: freelancer,
            total-amount: total-amount,
            amount-deposited: u0,
            amount-released: u0,
            status: ESCROW_PENDING,
            created-at: stacks-block-height,
            funded-at: none,
            completed-at: none,
            dispute-status: DISPUTE_NONE,
            arbitrator: none
        })
        
        (var-set total-escrows (+ (var-get total-escrows) u1))
        (ok escrow-id)))

;; fund escrow with STX
(define-public (fund-escrow (escrow-id uint))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-escrow-client escrow-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status escrow) ESCROW_PENDING) ERR_INVALID_STATUS)
        
        ;; transfer STX to contract
        (try! (stx-transfer? (get total-amount escrow) tx-sender (as-contract tx-sender)))
        
        ;; update escrow status
        (map-set escrows escrow-id (merge escrow {
            amount-deposited: (get total-amount escrow),
            status: ESCROW_FUNDED,
            funded-at: (some stacks-block-height)
        }))
        
        (ok true)))

;; add milestone payment to escrow
(define-public (add-milestone-payment (escrow-id uint) (milestone-id uint) (amount uint))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-escrow-client escrow-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status escrow) ESCROW_FUNDED) ERR_ESCROW_NOT_FUNDED)
        (asserts! (> amount u0) ERR_INVALID_INPUT)
        
        ;; ensure milestone payment doesn't already exist
        (asserts! (is-none (map-get? milestone-payments {escrow-id: escrow-id, milestone-id: milestone-id})) ERR_ESCROW_ALREADY_EXISTS)
        
        (map-set milestone-payments {escrow-id: escrow-id, milestone-id: milestone-id} {
            amount: amount,
            status: PAYMENT_PENDING,
            released-at: none,
            release-tx: none
        })
        
        (ok true)))

;; release milestone payment to freelancer
(define-public (release-milestone-payment (escrow-id uint) (milestone-id uint))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND))
          (milestone-payment (unwrap! (map-get? milestone-payments {escrow-id: escrow-id, milestone-id: milestone-id}) ERR_NOT_FOUND))
          (freelancer (unwrap! (get freelancer escrow) ERR_NOT_FOUND))
          (payment-amount (get amount milestone-payment))
          (platform-fee (calculate-platform-fee payment-amount))
          (net-payment (- payment-amount platform-fee)))
        
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-escrow-client escrow-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status escrow) ESCROW_FUNDED) ERR_ESCROW_NOT_FUNDED)
        (asserts! (is-eq (get status milestone-payment) PAYMENT_PENDING) ERR_PAYMENT_ALREADY_RELEASED)
        (asserts! (is-eq (get dispute-status escrow) DISPUTE_NONE) ERR_DISPUTE_ACTIVE)
        
        ;; check sufficient balance
        (asserts! (<= payment-amount (- (get amount-deposited escrow) (get amount-released escrow))) ERR_INSUFFICIENT_BALANCE)
        
        ;; transfer payment to freelancer (minus platform fee)
        (try! (as-contract (stx-transfer? net-payment tx-sender freelancer)))
        
        ;; collect platform fee
        (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
        
        ;; update milestone payment status
        (map-set milestone-payments {escrow-id: escrow-id, milestone-id: milestone-id}
                 (merge milestone-payment {
                     status: PAYMENT_RELEASED,
                     released-at: (some stacks-block-height)
                 }))
        
        ;; update escrow released amount
        (map-set escrows escrow-id (merge escrow {
            amount-released: (+ (get amount-released escrow) payment-amount)
        }))
        
        (ok net-payment)))

;; initiate dispute
(define-public (initiate-dispute (escrow-id uint) (reason (string-ascii 512)) (evidence (optional (string-ascii 256))))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (or (is-escrow-client escrow-id tx-sender) 
                     (is-escrow-freelancer escrow-id tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get dispute-status escrow) DISPUTE_NONE) ERR_DISPUTE_ACTIVE)
        
        (let ((dispute-type (if (is-escrow-client escrow-id tx-sender) 
                               DISPUTE_CLIENT_INITIATED 
                               DISPUTE_FREELANCER_INITIATED)))
            
            ;; create dispute record
            (map-set disputes escrow-id {
                escrow-id: escrow-id,
                initiated-by: tx-sender,
                reason: reason,
                evidence: evidence,
                created-at: stacks-block-height,
                resolved-at: none,
                resolution: none,
                arbitrator-decision: none
            })
            
            ;; update escrow status
            (map-set escrows escrow-id (merge escrow {
                status: ESCROW_DISPUTED,
                dispute-status: dispute-type
            }))
            
            (ok true))))

;; resolve dispute (arbitrator only)
(define-public (resolve-dispute (escrow-id uint) 
                               (resolution (string-ascii 512))
                               (client-percentage uint)
                               (freelancer-percentage uint))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND))
          (dispute (unwrap! (map-get? disputes escrow-id) ERR_NOT_FOUND)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-authorized-arbitrator tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status escrow) ESCROW_DISPUTED) ERR_INVALID_STATUS)
        (asserts! (is-eq (+ client-percentage freelancer-percentage) u100) ERR_INVALID_INPUT)
        
        (let ((total-disputed-amount (- (get amount-deposited escrow) (get amount-released escrow)))
              (client-share (/ (* total-disputed-amount client-percentage) u100))
              (freelancer-share (/ (* total-disputed-amount freelancer-percentage) u100))
              (freelancer (unwrap! (get freelancer escrow) ERR_NOT_FOUND)))
            
            ;; transfer client share back to client
            (if (> client-share u0)
                (try! (as-contract (stx-transfer? client-share tx-sender (get client escrow))))
                true)
            
            ;; transfer freelancer share to freelancer
            (if (> freelancer-share u0)
                (try! (as-contract (stx-transfer? freelancer-share tx-sender freelancer)))
                true)
            
            ;; update dispute record
            (map-set disputes escrow-id (merge dispute {
                resolved-at: (some stacks-block-height),
                resolution: (some resolution),
                arbitrator-decision: (some u1)
            }))
            
            ;; update escrow status
            (map-set escrows escrow-id (merge escrow {
                status: ESCROW_COMPLETED,
                dispute-status: DISPUTE_RESOLVED,
                completed-at: (some stacks-block-height),
                arbitrator: (some tx-sender)
            }))
            
            (ok true))))

;; complete escrow (when all payments released)
(define-public (complete-escrow (escrow-id uint))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-escrow-client escrow-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status escrow) ESCROW_FUNDED) ERR_INVALID_STATUS)
        (asserts! (is-eq (get amount-deposited escrow) (get amount-released escrow)) ERR_INSUFFICIENT_BALANCE)
        
        (map-set escrows escrow-id (merge escrow {
            status: ESCROW_COMPLETED,
            completed-at: (some stacks-block-height)
        }))
        
        (ok true)))

;; emergency refund (only if no payments made)
(define-public (emergency-refund (escrow-id uint))
    (let ((escrow (unwrap! (map-get? escrows escrow-id) ERR_NOT_FOUND)))
        (asserts! (not (is-contract-paused)) ERR_UNAUTHORIZED)
        (asserts! (is-escrow-client escrow-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status escrow) ESCROW_FUNDED) ERR_INVALID_STATUS)
        (asserts! (is-eq (get amount-released escrow) u0) ERR_REFUND_NOT_ALLOWED)
        (asserts! (is-eq (get dispute-status escrow) DISPUTE_NONE) ERR_DISPUTE_ACTIVE)
        
        ;; refund full amount to client
        (try! (as-contract (stx-transfer? (get amount-deposited escrow) tx-sender (get client escrow))))
        
        ;; update escrow status
        (map-set escrows escrow-id (merge escrow {
            status: ESCROW_REFUNDED
        }))
        
        (ok true)))

;; admin functions
;; add authorized arbitrator (contract owner only)
(define-public (add-arbitrator (arbitrator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set arbitrators arbitrator true)
        (ok true)))

;; remove arbitrator (contract owner only)
(define-public (remove-arbitrator (arbitrator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete arbitrators arbitrator)
        (ok true)))

;; emergency pause (contract owner only)
(define-public (set-emergency-pause (paused bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set emergency-pause true paused)
        (ok true)))

;; withdraw platform fees (contract owner only)
(define-public (withdraw-platform-fees (recipient principal))
    (let ((fee-amount (var-get total-platform-fees)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> fee-amount u0) ERR_INSUFFICIENT_FUNDS)
        
        (try! (as-contract (stx-transfer? fee-amount tx-sender recipient)))
        (var-set total-platform-fees u0)
        (ok fee-amount)))

;; read only functions
(define-read-only (get-escrow (escrow-id uint))
    (map-get? escrows escrow-id))

(define-read-only (get-milestone-payment (escrow-id uint) (milestone-id uint))
    (map-get? milestone-payments {escrow-id: escrow-id, milestone-id: milestone-id}))

(define-read-only (get-dispute (escrow-id uint))
    (map-get? disputes escrow-id))

(define-read-only (get-total-escrows)
    (var-get total-escrows))

(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate))

(define-read-only (get-total-platform-fees)
    (var-get total-platform-fees))

(define-read-only (is-arbitrator (user principal))
    (is-authorized-arbitrator user))

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender)))

