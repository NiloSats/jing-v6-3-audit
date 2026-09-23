
;; ============================================================================
;; PROPOSED: NOTHING RESTS WITHOUT AN OWNER (the mirror of 4)
;; ============================================================================
;; Invariant 4 (invariant-pooled-le-actual) pins one direction: the accounting
;; never claims more inventory than the rung really has. That is solvency, and
;; it holds even when the pool forgets whose the inventory is.
;;
;; This is the other direction. What the rung actually has -- resting on the
;; market plus held off it -- must be covered by what the accounting says is
;; pooled, because pooled-sbtc is total-shares * unfilled-index / SCALE and a
;; member's claim is a slice of exactly that. Inventory above it belongs to
;; nobody: get-position reports it as 0 for every member, withdraw cannot
;; reach it, and its proceeds land in the next epoch's index.
;;
;; The slack is derived, not chosen:
;;   SOLD_OUT_DUST          sync is allowed to close on (< actual SOLD_OUT_DUST),
;;                          so up to DUST-1 sats may be legitimately abandoned.
;;   total-shares / SCALE   sync sets new-index = actual * SCALE / total-shares
;;                          with a floor division, so pooled understates actual
;;                          by at most one index step, which is that many sats.
;; Anything above that slack is inventory with no owner.
;;
;; Why the existing block cannot see it: invariant-unfilled-index-bounds asks
;; its question only of an OPEN epoch -- its first disjunct is
;; (is-eq (var-get total-shares) u0), which is exactly the state an epoch close
;; produces. The close is the one moment the suite excuses.
;; ============================================================================

(define-read-only (invariant-actual-le-pooled)
  (<= (+ (market-size) (rv-local))
      (+ (pooled-sbtc) SOLD_OUT_DUST (/ (var-get total-shares) SCALE))))
