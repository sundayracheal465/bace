
(define-constant ERR-NOT-FOUND u404)
(define-constant ERR-NOT-EXPIRED u100)
(define-constant ERR-ALREADY-SETTLED u409)
(define-constant ERR-UNAUTHORIZED u401)
(define-constant ERR-ORACLE-MISSING u402)
(define-constant ERR-ORACLE-STALE u403)
(define-constant ERR-FUTURE-BLOCK u405)
(define-constant ERR-ESCROW-INCOMPLETE u406)
(define-constant ERR-BAD-AMOUNT u407)
(define-constant ERR-ESCROW-EXCESS u408)
(define-constant ERR-ORACLE-PRESENT u410)

(define-constant STATUS-SETTLED u1)
(define-constant STATUS-REFUNDED u2)

(define-constant EMPTY-ESCROW {long-escrow: u0, short-escrow: u0})

(define-data-var oracle-admin principal tx-sender)
(define-data-var oracle-max-delay uint u144)

(define-map positions
    uint
    (tuple
        (expiration-block uint)
        (strike-price uint)
        (payout uint)
        (long-holder principal)
        (short-holder principal)
    )
)

(define-map escrows
    uint
    (tuple
        (long-escrow uint)
        (short-escrow uint)
    )
)

(define-map settlements
    uint
    (tuple
        (status uint)
        (settled-at uint)
        (oracle-value (optional uint))
        (winner (optional principal))
    )
)

(define-map oracle-fees
    uint
    (tuple
        (avg-fee uint)
        (reported-at uint)
        (reporter principal)
    )
)

(define-read-only (get-oracle-fee (block uint))
    (match (map-get? oracle-fees block)
        oracle
            (begin
                (asserts! (>= (get reported-at oracle) block) (err ERR-ORACLE-STALE))
                (asserts! (<= (get reported-at oracle) (+ block (var-get oracle-max-delay))) (err ERR-ORACLE-STALE))
                (ok (get avg-fee oracle))
            )
        (err ERR-ORACLE-MISSING)
    )
)

(define-public (set-oracle-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-admin)) (err ERR-UNAUTHORIZED))
        (var-set oracle-admin new-admin)
        (ok true)
    )
)

(define-public (set-oracle-max-delay (new-delay uint))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-admin)) (err ERR-UNAUTHORIZED))
        (asserts! (> new-delay u0) (err ERR-BAD-AMOUNT))
        (var-set oracle-max-delay new-delay)
        (ok true)
    )
)

(define-public (report-fee (block uint) (avg-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-admin)) (err ERR-UNAUTHORIZED))
        (asserts! (<= block burn-block-height) (err ERR-FUTURE-BLOCK))
        (map-set oracle-fees block {avg-fee: avg-fee, reported-at: burn-block-height, reporter: tx-sender})
        (ok true)
    )
)

(define-public (fund-escrow (position-id uint) (amount uint))
    (let ((pos (unwrap! (map-get? positions position-id) (err ERR-NOT-FOUND))))
        (begin
            (asserts! (is-none (map-get? settlements position-id)) (err ERR-ALREADY-SETTLED))
            (asserts! (> amount u0) (err ERR-BAD-AMOUNT))
            (asserts!
                (or (is-eq tx-sender (get long-holder pos)) (is-eq tx-sender (get short-holder pos)))
                (err ERR-UNAUTHORIZED)
            )
            (let ((escrow (default-to EMPTY-ESCROW (map-get? escrows position-id))))
                (let ((total (+ (get long-escrow escrow) (get short-escrow escrow))))
                    (asserts! (<= (+ total amount) (get payout pos)) (err ERR-ESCROW-EXCESS))
                    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                    (if (is-eq tx-sender (get long-holder pos))
                        (map-set escrows position-id {long-escrow: (+ (get long-escrow escrow) amount), short-escrow: (get short-escrow escrow)})
                        (map-set escrows position-id {long-escrow: (get long-escrow escrow), short-escrow: (+ (get short-escrow escrow) amount)})
                    )
                    (ok true)
                )
            )
        )
    )
)

(define-public (refund-position (position-id uint))
    (let ((pos (unwrap! (map-get? positions position-id) (err ERR-NOT-FOUND))))
        (begin
            (asserts! (is-none (map-get? settlements position-id)) (err ERR-ALREADY-SETTLED))
            (asserts! (>= burn-block-height (get expiration-block pos)) (err ERR-NOT-EXPIRED))
            (let ((escrow (default-to EMPTY-ESCROW (map-get? escrows position-id))))
                (let ((long-amt (get long-escrow escrow)) (short-amt (get short-escrow escrow)))
                    (asserts! (or (> long-amt u0) (> short-amt u0)) (err ERR-ESCROW-INCOMPLETE))
                    (match (get-oracle-fee (get expiration-block pos))
                        fee (err ERR-ORACLE-PRESENT)
                        err-code
                            (begin
                                (if (> long-amt u0)
                                    (try! (as-contract (stx-transfer? long-amt tx-sender (get long-holder pos))))
                                    true
                                )
                                (if (> short-amt u0)
                                    (try! (as-contract (stx-transfer? short-amt tx-sender (get short-holder pos))))
                                    true
                                )
                                (map-set settlements position-id {status: STATUS-REFUNDED, settled-at: burn-block-height, oracle-value: none, winner: none})
                                (map-delete escrows position-id)
                                (ok true)
                            )
                    )
                )
            )
        )
    )
)

(define-public (settle-position (position-id uint))
    (let (
        (pos (unwrap! (map-get? positions position-id) (err ERR-NOT-FOUND)))
        (expiration (get expiration-block pos))
    )
        (begin
            (asserts! (is-none (map-get? settlements position-id)) (err ERR-ALREADY-SETTLED))
            (asserts! (>= burn-block-height expiration) (err ERR-NOT-EXPIRED))
            (let ((escrow (default-to EMPTY-ESCROW (map-get? escrows position-id))))
                (let ((total (+ (get long-escrow escrow) (get short-escrow escrow))))
                    (asserts! (is-eq total (get payout pos)) (err ERR-ESCROW-INCOMPLETE))
                    (let ((avg-fee (try! (get-oracle-fee expiration))))
                        (let ((winner (if (> avg-fee (get strike-price pos))
                                            (get long-holder pos)
                                            (get short-holder pos))))
                            (as-contract (try! (stx-transfer? (get payout pos) tx-sender winner)))
                            (map-set settlements position-id {status: STATUS-SETTLED, settled-at: burn-block-height, oracle-value: (some avg-fee), winner: (some winner)})
                            (map-delete escrows position-id)
                            (ok true)
                        )
                    )
                )
            )
        )
    )
)
