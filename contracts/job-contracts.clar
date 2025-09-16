;; title: job-contracts
;; version: 1.0.0
;; summary: Smart contract for posting jobs, managing milestones, and tracking deliverables
;; description: Handles core job marketplace functionality including job creation, applications, and status management

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_JOB_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_STATUS (err u422))
(define-constant ERR_MILESTONE_NOT_FOUND (err u405))
(define-constant ERR_ALREADY_APPLIED (err u406))
(define-constant ERR_INVALID_FREELANCER (err u407))
(define-constant ERR_MILESTONE_ALREADY_COMPLETED (err u408))

;; job status constants
(define-constant STATUS_OPEN u0)
(define-constant STATUS_IN_PROGRESS u1)
(define-constant STATUS_COMPLETED u2)
(define-constant STATUS_CANCELLED u3)
(define-constant STATUS_DISPUTED u4)

;; milestone status constants
(define-constant MILESTONE_PENDING u0)
(define-constant MILESTONE_IN_PROGRESS u1)
(define-constant MILESTONE_COMPLETED u2)
(define-constant MILESTONE_APPROVED u3)

;; data vars
(define-data-var next-job-id uint u1)
(define-data-var total-jobs uint u0)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% fee

;; data maps
;; main job data structure
(define-map jobs uint {
    id: uint,
    title: (string-ascii 256),
    description: (string-ascii 1024),
    client: principal,
    freelancer: (optional principal),
    budget: uint,
    status: uint,
    created-at: uint,
    deadline: uint,
    escrow-funded: bool,
    total-milestones: uint
})

;; milestone tracking
(define-map milestones {job-id: uint, milestone-id: uint} {
    title: (string-ascii 256),
    description: (string-ascii 512),
    payment: uint,
    status: uint,
    deliverable-hash: (optional (string-ascii 64)),
    completed-at: (optional uint),
    approved-at: (optional uint)
})

;; job applications from freelancers
(define-map applications {job-id: uint, applicant: principal} {
    proposal: (string-ascii 512),
    bid-amount: uint,
    timeline: uint,
    applied-at: uint,
    status: uint
})

;; job category mapping
(define-map job-categories uint (string-ascii 64))

;; user reputation tracking
(define-map user-stats principal {
    jobs-completed: uint,
    jobs-posted: uint,
    total-earned: uint,
    total-spent: uint,
    reputation-score: uint
})

;; private functions
(define-private (is-valid-status (status uint))
    (or (is-eq status STATUS_OPEN)
        (is-eq status STATUS_IN_PROGRESS)
        (is-eq status STATUS_COMPLETED)
        (is-eq status STATUS_CANCELLED)
        (is-eq status STATUS_DISPUTED)))

(define-private (is-job-client (job-id uint) (user principal))
    (match (map-get? jobs job-id)
        job (is-eq (get client job) user)
        false))

(define-private (is-job-freelancer (job-id uint) (user principal))
    (match (map-get? jobs job-id)
        job (match (get freelancer job)
                freelancer (is-eq freelancer user)
                false)
        false))

(define-private (increment-job-id)
    (let ((current-id (var-get next-job-id)))
        (var-set next-job-id (+ current-id u1))
        current-id))

(define-private (update-user-stats (user principal) (jobs-completed-delta uint) (jobs-posted-delta uint) (earned-delta uint) (spent-delta uint))
    (let ((current-stats (default-to 
            {jobs-completed: u0, jobs-posted: u0, total-earned: u0, total-spent: u0, reputation-score: u100}
            (map-get? user-stats user))))
        (map-set user-stats user {
            jobs-completed: (+ (get jobs-completed current-stats) jobs-completed-delta),
            jobs-posted: (+ (get jobs-posted current-stats) jobs-posted-delta),
            total-earned: (+ (get total-earned current-stats) earned-delta),
            total-spent: (+ (get total-spent current-stats) spent-delta),
            reputation-score: (get reputation-score current-stats)
        })))

;; public functions
;; create a new job posting with milestones
(define-public (create-job (title (string-ascii 256)) 
                          (description (string-ascii 1024))
                          (budget uint)
                          (deadline uint)
                          (category (string-ascii 64))
                          (milestone-count uint))
    (let ((job-id (increment-job-id))
          (current-block stacks-block-height))
        (asserts! (> budget u0) ERR_INVALID_INPUT)
        (asserts! (> deadline current-block) ERR_INVALID_INPUT)
        (asserts! (> milestone-count u0) ERR_INVALID_INPUT)
        (asserts! (<= milestone-count u10) ERR_INVALID_INPUT) ;; max 10 milestones
        
        ;; create the job
        (map-set jobs job-id {
            id: job-id,
            title: title,
            description: description,
            client: tx-sender,
            freelancer: none,
            budget: budget,
            status: STATUS_OPEN,
            created-at: current-block,
            deadline: deadline,
            escrow-funded: false,
            total-milestones: milestone-count
        })
        
        ;; set category
        (map-set job-categories job-id category)
        
        ;; update statistics
        (update-user-stats tx-sender u0 u1 u0 u0)
        (var-set total-jobs (+ (var-get total-jobs) u1))
        
        (ok job-id)))

;; add milestone to a job (only by client)
(define-public (add-milestone (job-id uint)
                             (milestone-id uint)
                             (title (string-ascii 256))
                             (description (string-ascii 512))
                             (payment uint))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND)))
        (asserts! (is-job-client job-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status job) STATUS_OPEN) ERR_INVALID_STATUS)
        (asserts! (> payment u0) ERR_INVALID_INPUT)
        (asserts! (<= milestone-id (get total-milestones job)) ERR_INVALID_INPUT)
        
        ;; ensure milestone doesn't already exist
        (asserts! (is-none (map-get? milestones {job-id: job-id, milestone-id: milestone-id})) ERR_JOB_ALREADY_EXISTS)
        
        (map-set milestones {job-id: job-id, milestone-id: milestone-id} {
            title: title,
            description: description,
            payment: payment,
            status: MILESTONE_PENDING,
            deliverable-hash: none,
            completed-at: none,
            approved-at: none
        })
        
        (ok true)))

;; freelancer applies for a job
(define-public (apply-for-job (job-id uint)
                             (proposal (string-ascii 512))
                             (bid-amount uint)
                             (timeline uint))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND)))
        (asserts! (is-eq (get status job) STATUS_OPEN) ERR_INVALID_STATUS)
        (asserts! (not (is-eq tx-sender (get client job))) ERR_UNAUTHORIZED)
        (asserts! (> bid-amount u0) ERR_INVALID_INPUT)
        (asserts! (> timeline u0) ERR_INVALID_INPUT)
        
        ;; check if already applied
        (asserts! (is-none (map-get? applications {job-id: job-id, applicant: tx-sender})) ERR_ALREADY_APPLIED)
        
        (map-set applications {job-id: job-id, applicant: tx-sender} {
            proposal: proposal,
            bid-amount: bid-amount,
            timeline: timeline,
            applied-at: stacks-block-height,
            status: u0 ;; pending
        })
        
        (ok true)))

;; client selects a freelancer for the job
(define-public (select-freelancer (job-id uint) (freelancer principal))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND))
          (application (unwrap! (map-get? applications {job-id: job-id, applicant: freelancer}) ERR_INVALID_FREELANCER)))
        (asserts! (is-job-client job-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status job) STATUS_OPEN) ERR_INVALID_STATUS)
        
        ;; update job with selected freelancer
        (map-set jobs job-id (merge job {
            freelancer: (some freelancer),
            status: STATUS_IN_PROGRESS,
            budget: (get bid-amount application)
        }))
        
        ;; update application status
        (map-set applications {job-id: job-id, applicant: freelancer} 
                 (merge application {status: u1})) ;; accepted
        
        (ok true)))

;; freelancer submits deliverable for milestone
(define-public (submit-milestone-deliverable (job-id uint)
                                           (milestone-id uint)
                                           (deliverable-hash (string-ascii 64)))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND))
          (milestone (unwrap! (map-get? milestones {job-id: job-id, milestone-id: milestone-id}) ERR_MILESTONE_NOT_FOUND)))
        (asserts! (is-job-freelancer job-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status job) STATUS_IN_PROGRESS) ERR_INVALID_STATUS)
        (asserts! (is-eq (get status milestone) MILESTONE_PENDING) ERR_MILESTONE_ALREADY_COMPLETED)
        
        (map-set milestones {job-id: job-id, milestone-id: milestone-id}
                 (merge milestone {
                     status: MILESTONE_COMPLETED,
                     deliverable-hash: (some deliverable-hash),
                     completed-at: (some stacks-block-height)
                 }))
        
        (ok true)))

;; client approves milestone
(define-public (approve-milestone (job-id uint) (milestone-id uint))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND))
          (milestone (unwrap! (map-get? milestones {job-id: job-id, milestone-id: milestone-id}) ERR_MILESTONE_NOT_FOUND)))
        (asserts! (is-job-client job-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status milestone) MILESTONE_COMPLETED) ERR_INVALID_STATUS)
        
        (map-set milestones {job-id: job-id, milestone-id: milestone-id}
                 (merge milestone {
                     status: MILESTONE_APPROVED,
                     approved-at: (some stacks-block-height)
                 }))
        
        (ok true)))

;; mark job as completed
(define-public (complete-job (job-id uint))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND)))
        (asserts! (is-job-client job-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status job) STATUS_IN_PROGRESS) ERR_INVALID_STATUS)
        
        (map-set jobs job-id (merge job {status: STATUS_COMPLETED}))
        
        ;; update user statistics
        (match (get freelancer job)
            freelancer (update-user-stats freelancer u1 u0 (get budget job) u0)
            true)
        (update-user-stats tx-sender u0 u0 u0 (get budget job))
        
        (ok true)))

;; cancel job (only if no freelancer selected or by mutual agreement)
(define-public (cancel-job (job-id uint))
    (let ((job (unwrap! (map-get? jobs job-id) ERR_NOT_FOUND)))
        (asserts! (is-job-client job-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (or (is-eq (get status job) STATUS_OPEN)
                     (is-eq (get status job) STATUS_IN_PROGRESS)) ERR_INVALID_STATUS)
        
        (map-set jobs job-id (merge job {status: STATUS_CANCELLED}))
        (ok true)))

;; read only functions
(define-read-only (get-job (job-id uint))
    (map-get? jobs job-id))

(define-read-only (get-milestone (job-id uint) (milestone-id uint))
    (map-get? milestones {job-id: job-id, milestone-id: milestone-id}))

(define-read-only (get-application (job-id uint) (applicant principal))
    (map-get? applications {job-id: job-id, applicant: applicant}))

(define-read-only (get-user-stats (user principal))
    (map-get? user-stats user))

(define-read-only (get-total-jobs)
    (var-get total-jobs))

(define-read-only (get-next-job-id)
    (var-get next-job-id))

(define-read-only (get-platform-fee-percentage)
    (var-get platform-fee-percentage))

(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-percentage)) u10000))

