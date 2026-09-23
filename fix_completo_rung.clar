;; jing-buy-stx-market-spread
;;
;; A pooled STX buy (sBTC resting, the market's x side) PEGGED to the market
;; mid on markets-sbtc-stx-jing-v6. Same pool as jing-buy-stx (one maker
;; slot, reward-per-share on two indices, read that file for the design);
;; the one difference is the order it rests. A fixed rung is a price; this
;; rung is a spread: it asks mid + spread-bps, and v6 re-evaluates that
;; against the fresh Lazer mid at every settlement (`spread-bps: (some s)`
;; on the order). No keeper, no reprice transaction, the sBTC never leaves
;; the market to follow the price. Deployed by anyone at a new spread from
;; this template. The name carries both numbers the order rests with:
;; jing-buy-stx-spread-20-floor-331-50 asks mid + 20 bps, and sits out
;; whenever that would be under 331.50 sats per STX (the floor v6 wants next
;; to a pegged ask: the price under which the peg does not fill on a mid it
;; should not trust). `initialize` takes the same two integers (u20,
;; u33150) and derives the floor in the market unit on chain, 1e18 / 33150,
;; exactly as the fixed rung derives its price; name and order agree by
;; construction. Registered in jing-ladder under side "buy-peg" against that
;; side's canonical hash (the code differs from the fixed rung, so it cannot
;; share "buy-stx"), keyed by the (spread, floor) pair packed into one uint.
;;
;; Accounting, the reward-per-share pattern on two indices:
;;   unfilled-index      what fraction of the pooled sBTC is still unsold, times
;;                   SCALE. Starts at SCALE, only ever goes down at fills.
;;   proceeds-index  micro-STX earned per share since the start, times SCALE.
;; A member holds `shares` (sats at unfilled-index SCALE). Their remaining sBTC is
;; shares * unfilled-index / SCALE; their STX is shares * (proceeds-index -
;; paid-index) / SCALE. `sync` (permissionless, run first by every action)
;; reads the contract's size on the market (live + parked) plus the sBTC it
;; holds locally, compares with what the indices predict, and folds the
;; difference in as a fill together with the STX that arrived.
;;
;; Where the sBTC sits: on the market whenever the pool is at or above the
;; market's own minimum (the market minimum), otherwise held here (`held-sats`) until a
;; deposit lifts it back. A withdrawal that would leave the market position
;; under the market minimum cancels the whole position and holds the rest (partial
;; withdrawals on the market otherwise, withdraw-token-x). Nothing held here
;; fills; that is the cost of being under the minimum.
;;
;; What passes straight through from the market: u1022 (the price crosses
;; live bids: it cannot rest, wait or use swap), u1027 (parked: deposits wait
;; for a readmit, which anyone does on the market), u1002 (settle phase:
;; withdrawals wait for the next deposit phase).
;;
;; No fee, no owner action after initialize, no reprice: a rung is a spread.

(define-constant ERR_NOT_AUTHORIZED (err u7001))
(define-constant ERR_ALREADY_INITIALIZED (err u7002))
(define-constant ERR_NOT_INITIALIZED (err u7003))
(define-constant ERR_ZERO_AMOUNT (err u7004))
(define-constant ERR_TOO_SMALL (err u7005))
(define-constant ERR_NO_POSITION (err u7006))
(define-constant ERR_INSUFFICIENT (err u7007))
(define-constant ERR_ZERO_PRICE (err u7008))
(define-constant ERR_BAD_SPREAD (err u7010))
(define-constant ERR_BAD_NAME (err u7009))
(define-constant ERR_INDEX_COLLAPSED (err u7011))

;; an epoch closes when what is left unsold, on the market plus held here, is
;; under this many sats: a walk fill is sized in whole sats so a fully taken
;; pool can keep a rounding remainder, and the market refunds a remainder under
;; its minimum back here. An absolute floor, not a fraction of the pool: the
;; remainder is a fixed size whatever the pool was (a fraction closed a small
;; pool late and a big one early). The pool is sold out, the next deposit starts
;; a fresh epoch; what is left rides into it.
(define-constant SOLD_OUT_DUST u10)

;; and the floor under the index itself. The dust test above is on an AMOUNT,
;; which leaves `unfilled-index` unbounded from below: new-index reduces to
;; actual * SCALE / total-shares, so once total-shares passes actual * SCALE the
;; index truncates to 0 while `actual` is still above the dust floor and the
;; epoch stays open. It gets there on its own, because shares are minted as
;; amount * SCALE / unfilled-index, so every sell-down and top-up cycle mints
;; more of them. At index 0 a deposit divides by zero, every withdraw is u7007
;; and sync freezes the zero, with no way back. Closing on EITHER test keeps the
;; absolute dust behaviour and restores the guarantee the index never reaches 0
;; while an epoch is open.
(define-constant SOLD_OUT_INDEX u1000000)

(define-constant MARKET .v6-market)
(define-constant LADDER .mock-jing-ladder)
(define-constant SBTC .mock-ft)
(define-constant SBTC_NAME "mock-ft")
(define-constant SIDE "buy-peg")
;; the deploy name must be NAME_PREFIX + spread + "-floor-" + the floor as named:
;; jing-buy-stx-spread-20-floor-331-50
(define-constant NAME_PREFIX "jing-buy-stx-spread-")
(define-constant GUARD_INFIX "-floor-")
;; v6 rejects a spread of 10000 bps or more (u1026)
(define-constant BPS_PRECISION u10000)
;; market price unit is micro-STX per sat times 1e10; from hundredths of a
;; sat per STX: price = 1e6 * 1e10 * 100 / cents = 1e18 / cents
(define-constant PRICE_NUMERATOR u1000000000000000000)

;; fixed-point precision of the two indices (12 decimals): fine enough that
;; no member's share rounds to nothing, small enough that shares * index *
;; SCALE stays far below uint128
(define-constant SCALE u1000000000000)
;; the market's own minimum per maker, read live: the operator can raise it
;; (set-min-token-x-deposit) and a stale constant would make the partial
;; withdraw branch call the market with a remainder it rejects (u1004)
;; literal principal on purpose: the node's read-only analysis rejects a
;; contract-call? through a constant here (clarinet accepts it, mainnet does not)
(define-read-only (min-market)
  (get min-token-x
    (contract-call? .v6-market
      get-min-deposits
    )
  )
)
;; smallest member deposit: a dust guard, not a maths need (shares are never
;; fewer than sats deposited; payouts round down by at most 1 unit)
(define-constant MIN_DEPOSIT u100)

(define-data-var initialized bool true)
(define-constant DEPLOYER tx-sender)
;; distance from mid in basis points, as named (20 -> u20); zero sits at mid
(define-data-var spread-bps uint u20)
;; the floor as named, in hundredths of a sat per STX (331.50 -> u33150)
(define-data-var floor-cents uint u33150)
;; the same floor in the market unit (1e18 / cents): what the order rests with
(define-data-var floor uint u30165912518853)
(define-data-var total-shares uint u0)
;; a sold-out pool closes its epoch: index and shares restart, old members
;; keep their claim against the epoch's final proceeds-index
(define-data-var epoch uint u0)
(define-map epoch-final-proceeds
  uint
  uint
)
(define-data-var unfilled-index uint SCALE)
(define-data-var proceeds-index uint u0)
;; sats kept in this contract, off the market (under the market minimum, or refunds)
(define-map epoch-final-unfilled uint uint)
(define-data-var reserved-sats uint u0)
(define-read-only (final-unfilled (e uint)) (default-to u0 (map-get? epoch-final-unfilled e)))
(define-data-var held-sats uint u0)
;; micro-STX balance already folded into proceeds-index
(define-data-var stx-accounted uint u0)

(define-map positions
  principal
  {
    epoch: uint,
    shares: uint,
    paid-index: uint,
  }
)

;; ---------- reads ----------

(define-read-only (get-spread-bps)
  (var-get spread-bps)
)

(define-read-only (get-floor)
  (var-get floor)
)

(define-read-only (get-floor-cents)
  (var-get floor-cents)
)

(define-read-only (get-state)
  {
    spread-bps: (var-get spread-bps),
    floor: (var-get floor),
    floor-cents: (var-get floor-cents),
    epoch: (var-get epoch),
    total-shares: (var-get total-shares),
    unfilled-index: (var-get unfilled-index),
    proceeds-index: (var-get proceeds-index),
    held-sats: (var-get held-sats),
    resting: (market-size),
    pooled: (pooled-sbtc),
  }
)

;; sBTC still unsold for `who`, and the STX they can claim, as of the last sync
(define-read-only (get-position (who principal))
  (match (map-get? positions who)
    p (if (is-eq (get epoch p) (var-get epoch))
      {
        shares: (get shares p),
        sbtc: (/ (* (get shares p) (var-get unfilled-index)) SCALE),
        stx: (/ (* (get shares p) (- (var-get proceeds-index) (get paid-index p))) SCALE),
      }
      ;; an earlier epoch: sold out, only the proceeds against its final index remain
      {
        shares: (get shares p),
        sbtc: u0,
        stx: (/ (* (get shares p) (- (final-index (get epoch p)) (get paid-index p))) SCALE),
      }
    )
    {
      shares: u0,
      sbtc: u0,
      stx: u0,
    }
  )
)

(define-read-only (final-index (e uint))
  (default-to (var-get proceeds-index) (map-get? epoch-final-proceeds e))
)

;; live + parked size of this contract on the market
(define-read-only (market-size)
  (+
    (contract-call? .v6-market
      get-token-x-deposit
      (contract-call? .v6-market
        get-current-cycle
      )
      current-contract
    )
    (contract-call? .v6-market
      get-token-x-parked current-contract
    )
  )
)

;; what the indices say is still unsold
(define-read-only (pooled-sbtc)
  (/ (* (var-get total-shares) (var-get unfilled-index)) SCALE)
)

;; ---------- lifecycle ----------

;; Once, by the deployer: the spread as named, then register.
(define-public (initialize
    (bps uint)
    (cents uint)
  )
  (begin
    (asserts! (is-eq tx-sender DEPLOYER) ERR_NOT_AUTHORIZED)
    (asserts! (not (var-get initialized)) ERR_ALREADY_INITIALIZED)
    (asserts! (< bps BPS_PRECISION) ERR_BAD_SPREAD)
    (asserts! (> cents u0) ERR_ZERO_PRICE)
    (asserts! (is-eq (own-name) (expected-name bps cents)) ERR_BAD_NAME)
    (let ((p (/ PRICE_NUMERATOR cents)))
      (var-set spread-bps bps)
      (var-set floor-cents cents)
      (var-set floor p)
      (var-set initialized true)
      ;; the ladder keys one rung per (side, value): the (spread, floor) pair
      ;; packed into one uint so two rungs can share a spread at different
      ;; floors; the market-price slot logs the floor in the market unit, as the
      ;; fixed rung logs its price
      (contract-call? LADDER register SIDE (+ (* cents BPS_PRECISION) bps) p)
    )
  )
)

;; ---------- sync ----------

;; Fold the market's state into the indices. Fills shrink the market size and
;; put STX here; refunds (dust, cancel) move sBTC from the market to here.
;; `actual` = market size + sats held here; `recorded` = what the indices last knew.
;; A shortfall is a fill: unfilled-index scales down by actual/recorded and every
;; new micro-STX is spread per share.
(define-public (sync)
  (let (
      (shares (var-get total-shares))
      (local (unwrap-panic (contract-call? SBTC get-balance current-contract)))
      (bruto (+ (market-size) local))
      (actual (if (> bruto (var-get reserved-sats)) (- bruto (var-get reserved-sats)) u0))
      (recorded (pooled-sbtc))
      (stx-now (stx-get-balance current-contract))
      (gained (- stx-now (var-get stx-accounted)))
    )
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    (var-set held-sats local)
    (if (is-eq shares u0)
      (begin
        ;; nobody in: nothing to attribute, just keep the STX watermark
        (var-set stx-accounted stx-now)
        (ok true)
      )
      (let (
          (new-index (if (and (< actual recorded) (> recorded u0))
            (/ (* (var-get unfilled-index) actual) recorded)
            (var-get unfilled-index)
          ))
          (new-proceeds (if (> gained u0)
            (+ (var-get proceeds-index) (/ (* gained SCALE) shares))
            (var-get proceeds-index)
          ))
          (current-epoch (var-get epoch))
        )
        (var-set unfilled-index new-index)
        (var-set proceeds-index new-proceeds)
        (var-set stx-accounted stx-now)
        ;; sold out (down to sub-sat dust): close the epoch, restart the pool.
        ;; Dust still resting rides into the next epoch as a gift.
        (and
          (or (< actual SOLD_OUT_DUST) (< new-index SOLD_OUT_INDEX))
          (begin
            (map-set epoch-final-proceeds current-epoch new-proceeds)
            (map-set epoch-final-unfilled current-epoch new-index)
            (var-set reserved-sats (+ (var-get reserved-sats) actual))
            (is-ok (contract-call? LADDER log-epoch-closed current-epoch new-proceeds))
            (var-set epoch (+ current-epoch u1))
            (var-set total-shares u0)
            (var-set unfilled-index SCALE)
          )
        )
        (ok true)
      )
    )
  )
)

;; ---------- member actions ----------

;; Join the rung with `amount` sats. Goes to the market when the pool is at
;; or above the market minimum (pushing along anything held), else waits here.
(define-public (deposit
    (amount uint)
    (update (buff 8192))
  )
  (let (
      (member tx-sender)
    )
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    (asserts! (>= amount MIN_DEPOSIT) ERR_TOO_SMALL)
    (try! (sync))
    ;; Belt and braces on the share mint below, which divides by this index.
    ;; `sync` just closed the epoch and reset the index to SCALE if it had
    ;; fallen under SOLD_OUT_INDEX, so this holds by construction. It is
    ;; written down because the one thing that can go wrong at that mint is
    ;; UNRECOVERABLE rather than merely wrong - a zero index means deposit
    ;; divides by zero, every withdraw is ERR_INSUFFICIENT and nothing can
    ;; reset it - and because this whole class began with a guarantee in
    ;; `sync` quietly losing its enforcement. A named refusal beats a
    ;; DivisionByZero, and this assert fails loudly if that ever happens again.
    (asserts! (>= (var-get unfilled-index) SOLD_OUT_INDEX) ERR_INDEX_COLLAPSED)
    (let ((paid (try! (settle-proceeds member))))
      (try! (contract-call? SBTC transfer amount member current-contract none))
      (let (
          (to-push (+ amount (var-get held-sats)))
          (shares (/ (* amount SCALE) (var-get unfilled-index)))
          (pos (position-of member))
          (epo (var-get epoch))
        )
        ;; the market's minimum is on the whole position (live + parked + new);
        ;; the market's deposit takes a parked position back by itself (a free
        ;; slot, else the smallest maker is bumped when the combined size is
        ;; bigger); if it refuses (queue full, crossing, stale update) the
        ;; funds are held here instead of aborting for every member
        (if (and
            (>= (+ to-push (market-size)) (min-market))
            (is-ok (push-to-market to-push update))
          )
          (var-set held-sats u0)
          (var-set held-sats to-push)
        )
        (map-set positions member {
          epoch: epo,
          shares: (+ (get shares pos) shares),
          paid-index: (var-get proceeds-index),
        })
        (var-set total-shares (+ (var-get total-shares) shares))
        ;; the log is best effort: a member's funds never hang on a print
        (is-ok (contract-call? LADDER log-deposit member amount shares epo
          (is-eq (var-get held-sats) u0) (var-get held-sats)
        ))
        (ok { amount: amount, shares: shares, epoch: epo,
          stx-paid: paid, sbtc-paid: u0 })
      )
    )
  )
)

;; Take `amount` of your unsold sats back (and your STX). Comes from what is
;; held here first, then from the market by partial withdrawal; if that would
;; leave the market position under the market minimum the whole position is cancelled
;; and the rest held here for the others.
;; Push what this contract holds onto the market. Sponsor-friendly deposits:
;; a member's `deposit` with an empty update (0x00) needs no oracle read from
;; the member; when the market needs a price the funds are held here, and
;; any keeper pushes them later with a fresh update. (ok true) when pushed,
;; (ok false) when there is nothing to push, the pool is under the market
;; minimum, or the market refuses (the funds stay held).
(define-public (push (update (buff 8192)))
  (begin
    (asserts! (var-get initialized) ERR_NOT_INITIALIZED)
    (try! (sync))
    (let (
        (to-push (var-get held-sats))
        (pushed (and
          (> to-push u0)
          (>= (+ to-push (market-size)) (min-market))
          (is-ok (push-to-market to-push update))
        ))
      )
      (if pushed
        (var-set held-sats u0)
        true
      )
      (is-ok (contract-call? LADDER log-push tx-sender to-push pushed (var-get held-sats)))
      (ok pushed)
    )
  )
)

(define-public (withdraw (amount uint))
  (let (
      (member tx-sender)
      (pos (unwrap! (map-get? positions member) ERR_NO_POSITION))
    )
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (try! (sync))
    (let ((paid (try! (settle-proceeds member))))
      ;; an old-epoch member was paid out and deleted by settle-proceeds
      (asserts! (is-some (map-get? positions member)) ERR_NO_POSITION)
      (let (
          (fi (var-get unfilled-index))
          (mine (/ (* (get shares pos) fi) SCALE))
          ;; round the burn UP: a floor here paid `amount` for fewer shares than
          ;; it is worth once fi < SCALE, so 1-sat withdraws drained the others
          (shares-out (if (>= amount mine)
            (get shares pos)
            (/ (+ (* amount SCALE) (- fi u1)) fi)
          ))
          (take (if (>= amount mine)
            mine
            amount
          ))
          (epo (var-get epoch))
        )
        (asserts! (> take u0) ERR_INSUFFICIENT)
        (try! (pull-to-held-sats take))
        (try! (as-contract? ((with-ft SBTC SBTC_NAME take))
          (try! (contract-call? SBTC transfer take current-contract member none))
        ))
        (var-set held-sats (- (var-get held-sats) take))
        (if (is-eq shares-out (get shares pos))
          (map-delete positions member)
          (map-set positions member {
            epoch: epo,
            shares: (- (get shares pos) shares-out),
            paid-index: (var-get proceeds-index),
          })
        )
        (var-set total-shares (- (var-get total-shares) shares-out))
        (is-ok (contract-call? LADDER log-withdraw member take shares-out epo
          (var-get held-sats)
        ))
        (ok { stx: paid, sbtc: take })
      )
    )
  )
)

;; STX from fills only; the sBTC keeps resting.
(define-public (claim)
  (begin
    (asserts! (is-some (map-get? positions tx-sender)) ERR_NO_POSITION)
    (try! (sync))
    (let ((paid (try! (settle-proceeds tx-sender))))
      (is-ok (contract-call? LADDER log-claim tx-sender paid (var-get epoch)))
      (ok { stx: paid, sbtc: u0 })
    )
  )
)

;; ---------- private ----------

;; this contract's own name, from its principal
(define-private (own-name)
  (default-to "" (get name (unwrap-panic (principal-destruct? current-contract))))
)

;; "jing-buy-stx-spread-20-floor-331-50" for (u20, u33150): the spread in
;; basis points, then the floor as whole sats, dash, two-digit hundredths
(define-private (expected-name
    (bps uint)
    (cents uint)
  )
  (let (
      (whole (int-to-ascii (/ cents u100)))
      (frac (mod cents u100))
      (frac-str (if (< frac u10)
        (concat "0" (int-to-ascii frac))
        (int-to-ascii frac)
      ))
    )
    (concat
      (concat (concat (concat NAME_PREFIX (int-to-ascii bps)) GUARD_INFIX) whole)
      (concat "-" frac-str)
    )
  )
)

(define-private (position-of (who principal))
  (default-to {
    epoch: (var-get epoch),
    shares: u0,
    paid-index: (var-get proceeds-index),
  }
    (map-get? positions who)
  )
)

;; Pay `who` the STX their shares earned since their paid-index, then move
;; the mark. Called after sync by every member action.
(define-private (settle-proceeds (who principal))
  (match (map-get? positions who)
    pos (let (
        (current (is-eq (get epoch pos) (var-get epoch)))
        (upto (if current
          (var-get proceeds-index)
          (final-index (get epoch pos))
        ))
        (owed (/ (* (get shares pos) (- upto (get paid-index pos))) SCALE))
      )
      (and
        (> owed u0)
        (try! (as-contract? ((with-stx owed))
          (try! (stx-transfer? owed current-contract who))
        ))
      )
      (var-set stx-accounted (- (var-get stx-accounted) owed))
      ;; NUEVO: al miembro de una epoca cerrada se le devuelve su parte NO VENDIDA,
      ;; que antes se regalaba a la epoca siguiente.
      (and (not current)
        (let ((mios (/ (* (get shares pos) (final-unfilled (get epoch pos))) SCALE)))
          (and (> mios u0)
            (begin
              (try! (pull-to-held-sats mios))
              (try! (as-contract? ((with-ft SBTC SBTC_NAME mios))
                (try! (contract-call? SBTC transfer mios current-contract who none))
              ))
              (var-set held-sats (- (var-get held-sats) mios))
              (var-set reserved-sats (if (> (var-get reserved-sats) mios) (- (var-get reserved-sats) mios) u0))
              true))))
      (if current
        (map-set positions who (merge pos { paid-index: upto }))
        (map-delete positions who)
      )
      (ok owed)
    )
    (ok u0)
  )
)

;; Make sure `held-sats` covers `amount`: partial-withdraw the gap from the market,
;; or cancel the whole market position when the remainder would sit under
;; the market minimum.
;; One attempt to push the pool onto the market. Its own function so the
;; try! returns from here, not from deposit: a refusal is a value the caller
;; can read (is-ok) and answer by holding, while the market's own state rolls
;; back with the failed call. A parked position is taken back by the market
;; inside this same deposit (free slot, else bump on the combined size).
(define-private (push-to-market
    (to-push uint)
    (update (buff 8192))
  )
  (as-contract? ((with-ft SBTC SBTC_NAME to-push))
    (try! (contract-call? MARKET deposit-token-x to-push (var-get floor) (some (var-get spread-bps)) update SBTC SBTC_NAME))
  )
)

(define-private (pull-to-held-sats (amount uint))
  (let ((have (var-get held-sats)))
    (if (>= have amount)
      (ok true)
      (let (
          (gap (- amount have))
          (on-market (market-size))
        )
        (asserts! (>= on-market gap) ERR_INSUFFICIENT)
        (if (>= (- on-market gap) (min-market))
          (begin
            (try! (as-contract? ()
              (try! (contract-call? MARKET withdraw-token-x gap SBTC SBTC_NAME))
            ))
            (var-set held-sats (+ have gap))
            (ok true)
          )
          (let ((refunded (try! (as-contract? ()
              (try! (contract-call? MARKET cancel-token-x-deposit SBTC SBTC_NAME))
            ))))
            (var-set held-sats (+ have refunded))
            (ok true)
          )
        )
      )
    )
  )
)


;; ============================================================================
;; RENDEZVOUS INVARIANTS for jing-buy-stx-market-spread (pooled pegged buy rung on markets v6)
;; ============================================================================
;; Append-only block; tests/rv/build.sh section 2f binds the rung to the v6
;; fuzz market (`.v6-market`, settle live through the mock Lazer oracle),
;; the mock ladder, the mock RFQ oracle and one mock-ft for sBTC and wstx,
;; and pre-initializes it at 331.50 sats per STX as the floor, 20 bps. RV fuzzes the
;; rung's member actions (deposit, withdraw, claim, push, sync); the rv-*
;; wrappers below play the rest of the market around it: the mid moves,
;; the opposite side rests and takes, competitors crowd the rung's side,
;; settlements run. Every wrapper that moves the market ends with `sync`
;; so the rung's view is current when the invariants read it.
;;
;; Mirrored file: the six rungs share this block up to the side (x / y),
;; the resting asset and the order they rest. Edit all six together.
;; ============================================================================

(define-map context (string-ascii 100) { called: uint })

(define-public (update-context (function-name (string-ascii 100)) (called uint))
  (ok (map-set context function-name { called: called })))

(define-constant RV-ACCOUNTS (list
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
  'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5
  'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG
  'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC
  'ST2NEB84ASENDXKYGJPQW86YXQCEFEX2ZQPG87ND
  'ST2REHHS5J3CERCRBEPMGH7921Q6PYKAADT7JP2VB
  'ST3AM1A56AK2C1XAFJ4115ZSV26EB49BVQ10MGCS0
  'ST3PF13W7Z0RRM42A8VZRVFQ75SV1K26RXEP8YGKJ
  'ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDGNV5N7R21XCP
  'STNHKEPYEPJ8ET55ZZ0M5A34J0R3N5FM2CMMMAZ6))

;; same price band as the market target: [2.4e13, 4.0e13) in the market
;; unit, 250.00 to 416.67 sats per STX, around the rung's 331.50
(define-constant RV-MID-BASE u24000000000000)
(define-constant RV-MID-STEPS u16000)
(define-constant RV-MID-STEP u1000000000)

(define-private (rv-price (raw uint))
  (+ RV-MID-BASE (* (mod raw RV-MID-STEPS) RV-MID-STEP)))

;; ---------------------------------------------------------------------------
;; wrappers: the market around the rung
;; ---------------------------------------------------------------------------

(define-public (rv-set-mid (raw uint))
  (contract-call? .mock-lazer-oracle set-mid (rv-price raw)))

(define-public (rv-unpause-market)
  (contract-call? .v6-market rv-unpause))

;; a resting STX bid from the sender
(define-public (rv-bid (amount uint) (limit uint))
  (contract-call? .v6-market deposit-token-y amount (rv-price limit) none 0x
    .mock-ft "mock-ft"))

;; a resting sBTC ask from the sender
(define-public (rv-ask (amount uint) (limit uint))
  (contract-call? .v6-market deposit-token-x amount (rv-price limit) none 0x
    .mock-ft "mock-ft"))

(define-public (rv-cancel-bid)
  (contract-call? .v6-market cancel-token-y-deposit .mock-ft "mock-ft"))

(define-public (rv-cancel-ask)
  (contract-call? .v6-market cancel-token-x-deposit .mock-ft "mock-ft"))

(define-public (rv-settle)
  (begin
    (try! (contract-call? .v6-market settle-with-refresh 0x .mock-ft "mock-ft"
      .mock-ft "mock-ft"))
    (sync)))

;; a taker on the opposite side of the rung
(define-public (rv-take (amount uint) (limit uint))
  (begin
    (try! (contract-call? .v6-market swap amount (rv-price limit) 0x
      .mock-ft "mock-ft" .mock-ft "mock-ft" false))
    (sync)))

;; ---------------------------------------------------------------------------
;; readers
;; ---------------------------------------------------------------------------

(define-private (rv-current-shares (a principal) (acc uint))
  (match (map-get? positions a)
    p (if (is-eq (get epoch p) (var-get epoch)) (+ acc (get shares p)) acc)
    acc))

(define-private (rv-unsold-fold (a principal) (acc uint))
  (+ acc (get sbtc (get-position a))))

(define-private (rv-proceeds-fold (a principal) (acc uint))
  (+ acc (get stx (get-position a))))

(define-private (rv-paid-ahead (a principal))
  (match (map-get? positions a)
    p (and (is-eq (get epoch p) (var-get epoch))
           (> (get paid-index p) (var-get proceeds-index)))
    false))

(define-private (rv-local)
  (unwrap-panic (contract-call? .mock-ft get-balance current-contract)))

(define-private (rv-proceeds-balance)
  (stx-get-balance current-contract))

;; ============================================================================
;; 1: what the rung holds off the market equals what it says it holds.
;; sync sets held from the balance; deposit, withdraw and push keep them
;; together. Drift here means an amount moved without the counter.
;; ============================================================================

(define-read-only (invariant-held-eq-local)
  (is-eq (var-get held-sats) (rv-local)))

;; ============================================================================
;; 2: the proceeds watermark equals the proceeds balance. sync sets it,
;; settle-proceeds moves it down by exactly what it pays.
;; ============================================================================

(define-read-only (invariant-accounted-eq-balance)
  (is-eq (var-get stx-accounted) (rv-proceeds-balance)))

;; ============================================================================
;; 3: total shares equal the sum of the current epoch's member shares. A
;; closed epoch's members keep their rows (with their old epoch) and are
;; not counted.
;; ============================================================================

(define-read-only (invariant-total-shares-eq-sum)
  (is-eq (var-get total-shares) (fold rv-current-shares RV-ACCOUNTS u0)))

;; ============================================================================
;; 4-5: SOLVENCY of the unsold side. What the indices say is pooled never
;; exceeds what is actually resting plus held, and the members' claims on
;; it never exceed the pool.
;; ============================================================================

(define-read-only (invariant-pooled-le-actual)
  (<= (pooled-sbtc) (+ (market-size) (var-get held-sats))))

(define-read-only (invariant-members-unsold-le-pooled)
  (<= (fold rv-unsold-fold RV-ACCOUNTS u0) (pooled-sbtc)))

;; ============================================================================
;; 6: SOLVENCY of the proceeds side. Every member's claimable proceeds
;; (current epoch against the live index, closed epochs against their
;; final index) fit in the balance.
;; ============================================================================

(define-read-only (invariant-members-proceeds-le-balance)
  (<= (fold rv-proceeds-fold RV-ACCOUNTS u0) (rv-proceeds-balance)))

;; ============================================================================
;; 7-8: the indices. unfilled-index only ever comes down from SCALE and an
;; open epoch with shares holds at least SOLD_OUT_DUST (under it, sync has
;; closed the epoch and restarted);
;; no member's paid mark is ahead of the proceeds index.
;; ============================================================================

(define-read-only (invariant-unfilled-index-bounds)
  (and (<= (var-get unfilled-index) SCALE)
       ;; An OPEN epoch that still has shares must sit above BOTH floors. The
       ;; dust bound alone is on an amount and leaves the index unbounded below:
       ;; new-index is actual * SCALE / total-shares, so a growing total-shares
       ;; truncates it to 0 while the amount is still above dust, and at 0 a
       ;; deposit divides by zero and every withdraw is u7007, permanently.
       ;; This conjunct is the one that fails on that path.
       (or (is-eq (var-get total-shares) u0)
           (and (>= (+ (market-size) (rv-local)) SOLD_OUT_DUST)
                (>= (var-get unfilled-index) SOLD_OUT_INDEX)))))

(define-read-only (invariant-paid-index-le-proceeds)
  (is-eq (len (filter rv-paid-ahead RV-ACCOUNTS)) u0))

;; ============================================================================
;; 9: the order the rung rests with is the one it was deployed for. The
;; market may roll, park or partially fill it; it never reprices it.
;; ============================================================================

(define-read-only (invariant-resting-order-is-the-rung)
  (or (is-eq (market-size) u0)
      (let ((o (contract-call? .v6-market get-token-x-order current-contract)))
        (and (is-eq (get limit o) (var-get floor)) (is-eq (get spread-bps o) (some (var-get spread-bps)))))))

;; ============================================================================
;; 10: the rung is live or parked on the market, never both (the market's
;; own invariants check this for accounts; they are not evaluated here).
;; ============================================================================

(define-read-only (invariant-rung-never-live-and-parked)
  (not (and
    (> (contract-call? .v6-market get-token-x-deposit
         (contract-call? .v6-market get-current-cycle) current-contract) u0)
    (> (contract-call? .v6-market get-token-x-parked current-contract) u0))))

;; ============================================================================
;; 11-12: a closed epoch's final index never runs ahead of the live one
;; (old members are paid against it); the rung holds no order row on the
;; market without a position (mirror of the market's stale-order check).
;; ============================================================================

(define-read-only (invariant-closed-epoch-index-le-live)
  (or (is-eq (var-get epoch) u0)
      (<= (final-index (- (var-get epoch) u1)) (var-get proceeds-index))))

(define-read-only (invariant-rung-no-stale-order)
  (or (> (market-size) u0)
      (is-eq (contract-call? .v6-market get-token-x-limit current-contract) u0)))

;; ============================================================================
;; PROPERTY TESTS (`rv . <rung> test`): the two anti-drain promises of the
;; pool. (ok true) passes, (ok false) discards, (err) or a panic fails.
;; ============================================================================

;; P1: DEPOSIT THEN WITHDRAW IT ALL never takes more out of the pool than
;; went in: the pool's assets (held here + resting on the market) after
;; are at least what they were before (the share-burn rounding class the
;; ladder bounty found). Measured on the pool, not the member: the mock
;; token mints a fresh wallet on its first transfer. A failure encodes the
;; shortfall: 9100000000 + (before - after).
(define-public (test-deposit-withdraw-no-drain (amount uint))
  (let (
      (amt (+ MIN_DEPOSIT (mod amount u1000000)))
      (before (+ (unwrap-panic (contract-call? .mock-ft get-balance current-contract)) (market-size)))
    )
    (match (deposit amt 0x)
      d (match (withdraw amt)
          w (let ((after (+ (unwrap-panic (contract-call? .mock-ft get-balance current-contract)) (market-size))))
              (if (>= after before) (ok true) (err (+ u9100000000 (- before after)))))
          e (ok false))
      e (ok false))))

;; P2: A WITHDRAWAL NEVER PAYS MORE THAN THE POSITION SHOWED before the call
;; (sync only ever shrinks the unsold side).
(define-public (test-withdraw-le-position (amount uint))
  (let (
      (pos (get sbtc (get-position tx-sender)))
      (before (unwrap-panic (contract-call? .mock-ft get-balance tx-sender)))
    )
    (if (is-eq pos u0)
      (ok false)
      (match (withdraw (+ u1 (mod amount u1000000)))
        w (if (<= (- (unwrap-panic (contract-call? .mock-ft get-balance tx-sender)) before) pos) (ok true) (err u9102))
        e (ok false)))))

;; drivers for test mode: the market around the rung (RV only calls
;; test-* functions there)
(define-public (test-drive-deposit (amount uint))
  (match (deposit (+ MIN_DEPOSIT (mod amount u1000000)) 0x) r (ok true) e (ok false)))
(define-public (test-drive-bid (amount uint) (limit uint))
  (match (rv-bid amount limit) r (ok true) e (ok false)))
(define-public (test-drive-ask (amount uint) (limit uint))
  (match (rv-ask amount limit) r (ok true) e (ok false)))
(define-public (test-drive-settle)
  (match (rv-settle) r (ok true) e (ok false)))
(define-public (test-drive-take (amount uint) (limit uint))
  (match (rv-take amount limit) r (ok true) e (ok false)))
(define-public (test-drive-set-mid (raw uint))
  (match (rv-set-mid raw) r (ok true) e (ok false)))
(define-public (test-drive-push)
  (match (push 0x) r (ok true) e (ok false)))
(define-public (test-drive-claim)
  (match (claim) r (ok true) e (ok false)))

;; ============================================================================
;; 13: a seated rung (a band seat on the ladder) is never parked. The market
;; checks this for accounts; its invariants are not evaluated in a rung run.
;; ============================================================================

(define-read-only (invariant-seated-never-parked)
  (or (not (contract-call? .mock-jing-ladder is-band-x current-contract))
      (is-eq (contract-call? .v6-market get-token-x-parked current-contract) u0)))

;; ============================================================================
;; 14: NO STRANDED PROCEEDS. What the rung holds in proceeds beyond the sum
;; of every member's claim (the live index for the current epoch, the final
;; index for a closed one) is rounding dust only: at most one unit per
;; member action (deposit, withdraw and claim each settle proceeds once,
;; and each settlement floors; the mock ladder counts the actions from the
;; rung's own logs). Two earlier bounds were wrong, per member and per
;; account per epoch, each replayed step by step with tests/rv/_replay.mjs. A credit against the wrong share count, or a
;; closed epoch that dropped a claim, is thousands of units, far above it.
;; ============================================================================

(define-private (rv-member-count (a principal) (acc uint))
  (if (is-some (map-get? positions a)) (+ acc u1) acc))

(define-read-only (invariant-no-stranded-proceeds)
  (<= (- (stx-get-balance current-contract) (fold rv-proceeds-fold RV-ACCOUNTS u0))
      (+ u1 (contract-call? .mock-jing-ladder get-action-count current-contract))))

;; P4: SYNC IS IDEMPOTENT. The reward-per-share fold every action runs
;; first: run it, snapshot, run it again, nothing moved.
(define-public (test-sync-idempotent)
  (match (sync)
    a (let (
        (i1 (var-get unfilled-index))
        (p1 (var-get proceeds-index))
        (h1 (var-get held-sats))
        (w1 (var-get stx-accounted))
        (e1 (var-get epoch))
        (t1 (var-get total-shares))
      )
      (match (sync)
        b (if (and
            (is-eq i1 (var-get unfilled-index))
            (is-eq p1 (var-get proceeds-index))
            (is-eq h1 (var-get held-sats))
            (is-eq w1 (var-get stx-accounted))
            (is-eq e1 (var-get epoch))
            (is-eq t1 (var-get total-shares)))
          (ok true)
          (err u9104))
        e (ok false)))
    e (ok false)))

;; P5: CLAIM IS IDEMPOTENT. A second claim in the same state pays nothing
;; and leaves the paid mark where the first put it.
(define-public (test-claim-idempotent)
  (match (claim)
    a (let (
        (bal (rv-proceeds-balance))
        (mark (get paid-index (default-to { epoch: u0, shares: u0, paid-index: u0 } (map-get? positions tx-sender))))
      )
      (match (claim)
        b (if (and (is-eq bal (rv-proceeds-balance))
                   (is-eq mark (get paid-index (default-to { epoch: u0, shares: u0, paid-index: u0 } (map-get? positions tx-sender)))))
          (ok true)
          (err u9105))
        e (ok false)))
    e (ok false)))

;; ============================================================================
;; 15: THE RUNG WAS NEVER MINTED. The mock token mints a sender short of a
;; transfer; a contract that gets minted tried to pay more sBTC than it held.
;; For the rung that is an insolvency the mint would otherwise hide.
;; ============================================================================

(define-read-only (invariant-rung-never-minted)
  (is-eq (contract-call? .mock-ft get-minted current-contract) u0))

;; Rich receipts must match actual transfers and the final accounting state.
(define-public (test-deposit-receipt (raw uint))
  (let ((amount (+ MIN_DEPOSIT (mod raw u1000000)))
        (before (stx-get-balance tx-sender)))
    (match (deposit amount 0x)
      receipt (if (and
          (is-eq (get amount receipt) amount)
          (is-eq (get shares receipt) (/ (* amount SCALE) (var-get unfilled-index)))
          (is-eq (get epoch receipt) (var-get epoch))
          (is-eq (get sbtc-paid receipt) u0)
          (is-eq (get stx-paid receipt) (- (stx-get-balance tx-sender) before)))
        (ok true) (err u9110))
      error (ok false))))

(define-public (test-withdraw-receipt (raw uint))
  (let ((amount (+ u1 (mod raw u1000000)))
        (stx-before (stx-get-balance tx-sender))
        (sbtc-before (unwrap-panic (contract-call? .mock-ft get-balance tx-sender))))
    (match (withdraw amount)
      receipt (if (and
          (is-eq (get stx receipt) (- (stx-get-balance tx-sender) stx-before))
          (is-eq (get sbtc receipt) (- (unwrap-panic (contract-call? .mock-ft get-balance tx-sender)) sbtc-before))
          (<= (get sbtc receipt) amount))
        (ok true) (err u9111))
      error (ok false))))

(define-public (test-claim-receipt)
  (let ((stx-before (stx-get-balance tx-sender))
        (sbtc-before (unwrap-panic (contract-call? .mock-ft get-balance tx-sender))))
    (match (claim)
      receipt (if (and
          (is-eq (get stx receipt) (- (stx-get-balance tx-sender) stx-before))
          (is-eq (get sbtc receipt) (- (unwrap-panic (contract-call? .mock-ft get-balance tx-sender)) sbtc-before)))
        (ok true) (err u9112))
      error (ok false))))
