
;; ============================================================================
;; PROPOSED WRAPPER (sell side): aim the sell-down at the index floor
;; ============================================================================
;; Mirror of the buy-side block. Two differences forced by this side:
;;   - the rung rests token-y (micro-STX), so the taker pays token-x (sats):
;;     sats = micro-STX * cap-cents / 1e8 at 331.50 sats per STX.
;;   - rv-take folds its argument into (+ u200 (mod amount u200000)), which caps
;;     a single take at about 200,200 sats. That cap is fine for the fuzz walk
;;     but it cannot express "take the gap", so this wrapper calls swap directly
;;     with the amount it computed and syncs exactly as rv-take does.
;; Everything it reaches is reachable in production: a taker picks the amount.
;; ============================================================================

(define-public (rv-sell-down-to-floor (raw uint))
  (let (
      (target (+ SOLD_OUT_INDEX (* (mod raw u9) SOLD_OUT_INDEX)))
      (resting (+ (market-size) (rv-local)))
      (keep (/ (* (var-get total-shares) target) SCALE))
      (cents (var-get cap-cents))
    )
    (asserts! (> (var-get total-shares) u0) (err u9200))
    (asserts! (> cents u0) (err u9201))
    (asserts! (> resting keep) (err u9202))
    ;; el mercado rechaza un llenado parcial (ERR_PARTIAL_FILL, u1017): el resto
    ;; tiene que quedar por debajo de su minimo. Lo que esta EN MANO no se puede
    ;; llenar, asi que la toma se acota a lo que hay puesto en el mercado.
    (let ((hueco (- resting keep)) (enMercado (market-size)))
      (asserts! (> enMercado u0) (err u9203))
      (try! (contract-call? .v6-market swap
              (/ (* (if (< hueco enMercado) hueco enMercado) cents) u100000000)
              (rv-price u15999) 0x .mock-ft "mock-ft" .mock-ft "mock-ft" true))
      (sync))))
