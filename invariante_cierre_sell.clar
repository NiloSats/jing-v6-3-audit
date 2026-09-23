
;; ============================================================================
;; PROPOSED (sell side): NOTHING RESTS WITHOUT AN OWNER (the mirror of 4)
;; ============================================================================
;; Same statement as the buy-side block, in this side's units. Invariant 4 pins
;; "the accounting never claims more than the rung has"; this pins the other
;; direction, "the rung never has more than the accounting can assign to
;; somebody". Slack derived the same way: SOLD_OUT_DUST because sync may close
;; on (< actual SOLD_OUT_DUST), and total-shares / SCALE for the floor division
;; in new-index.
;; ============================================================================

(define-read-only (invariant-actual-le-pooled)
  (<= (+ (market-size) (rv-local))
      (+ (pooled-stx) SOLD_OUT_DUST (/ (var-get total-shares) SCALE))))
