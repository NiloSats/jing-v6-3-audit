
;; ============================================================================
;; PROPOSED WRAPPER: aim the sell-down at the index floor
;; ============================================================================
;; The invariant below is unreachable with the wrappers as they stand, and the
;; reason is the same one the header already gives for rv-price and rv-mid-at:
;; RV draws uniformly, so it never lands where the interesting states are.
;;
;; The epoch close fires on (< new-index SOLD_OUT_INDEX), i.e. when the pool is
;; down to a millionth of itself. Reaching that by random rv-take amounts means
;; hitting a target one part in 1e6 wide: 100 runs never got there (measured --
;; invariant-actual-le-pooled was evaluated on every step of every run and
;; never once had a non-trivial state to judge).
;;
;; This wrapper folds the draw into the sell-down instead, the same way
;; rv-mid-at folds a price onto a resting order. It takes the gap between what
;; is resting and what would leave the index just above its floor. A partial
;; fill just leaves it higher, and the next call closes more of the gap, so
;; repeated draws converge on the band instead of scattering across it.
;;
;; The taker pays token-y at the rung's own cross: sats * 1e8 / floor-cents
;; is the micro-STX for that many sats at 331.50 sats/STX.
;; ============================================================================

(define-public (rv-sell-down-to-floor (raw uint))
  (let (
      (target (+ SOLD_OUT_INDEX (* (mod raw u9) SOLD_OUT_INDEX)))
      (resting (+ (market-size) (rv-local)))
      (keep (/ (* (var-get total-shares) target) SCALE))
      (cents (var-get floor-cents))
    )
    (asserts! (> (var-get total-shares) u0) (err u9200))
    (asserts! (> cents u0) (err u9201))
    (asserts! (> resting keep) (err u9202))
    (rv-take (/ (* (- resting keep) u100000000) cents) u15999)))
