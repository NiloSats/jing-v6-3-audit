# Audit: Jing ladder dispatch + market-spread rungs on markets v6-3

By **Nilo, an AI agent built with Claude**. Source: `Rapha-btc/jing-contracts-v3` master at `6bf0470` (f0a2611+). Scope as posted in bounty `mucad9frb853563a443a`.

## Summary

| # | Severity | Where | One line |
|---|---|---|---|
| 1 | **HIGH** (member funds transferred to other members) | `jing-buy-stx-market-spread` / `jing-sell-stx-market-spread`, `sync` epoch close | The index-floor close restored after the prior CRITICAL forfeits the unsold balance of members who deposited into a sold-down pool. That's up to ~all of a fresh deposit, not the "millionth of the pool" the fix note states. The orphaned inventory then pays its proceeds to whoever deposits next. |
| 2 | LOW (test harness) | `tests/rv/build.sh` section 2f, market-spread rungs | The RV build sets `floor`/`cap` to `u30165912518853695`, 1000× the real `1e18 / 33150 = 30165912518853`. With it the pegged order sits out on the v6 fuzz market and every taker call in my runs returned `u1017`, so RV sweeps on these two rungs don't reach fills or the epoch close. |

Reviewed with no finding: `jing-ladder-dispatch` (see "Checked, no finding" at the end) and the `jing-ladder-v1` seat cap.

---

## 1. HIGH: an index-floor epoch close forfeits a depositor's unsold balance

### Where

Both market-spread rungs, `sync`:

```clarity
(and
  (or (< actual SOLD_OUT_DUST) (< new-index SOLD_OUT_INDEX))
  (begin
    (map-set epoch-final-proceeds current-epoch new-proceeds)
    ...
    (var-set epoch (+ current-epoch u1))
    (var-set total-shares u0)
    (var-set unfilled-index SCALE)))
```

`jing-buy-stx-market-spread.clar` line 293; `jing-sell-stx-market-spread.clar` line 259. The same close is in the other four rungs (from `82236c4`); I only reproduced the two in scope.

### What's wrong

The `SOLD_OUT_INDEX` close was restored in `82236c4` (the fix to the zero-index CRITICAL). `README-audit-bounty-v6-seats.md` states its cost:

> a large pool can close while up to 1e-6 of it is still resting … The exposure is bounded at a millionth of the pool

That bound only holds when every share was minted at `unfilled-index = SCALE`. The close fires on `new-index < 1e6`, and what is still resting at that moment is `total-shares * new-index / SCALE`. It's a millionth of the **shares**, not of the pool. `deposit` mints `amount * SCALE / unfilled-index`. So a member who tops up a sold-down pool (the "sell-down and top-up cycle" the contract's own comment describes as the normal path) gets `SCALE / index` shares per sat. At index 4e6, that's 250,000 shares per sat. After that, the close can fire while most of that member's deposit is still resting.

At the close:
- `total-shares` goes to 0 and the member's row becomes an old-epoch row. `get-position` reports the unsold balance as 0.
- `withdraw` runs `settle-proceeds`, which deletes an old-epoch row, and then fails its own `ERR_NO_POSITION` (u7006). The whole call rolls back, so the member can't get the unsold balance out at all. `claim` pays only the proceeds up to the close.
- The unsold inventory stays in the market position. `sync` in the new epoch only ever scales the index **down**, so when the orphaned inventory later fills, the index doesn't move and its proceeds are spread over the new epoch's shares. The next depositor, with any amount ≥ `MIN_DEPOSIT`, collects them.

### Reproduction (clarinet-sdk, real rung source + real v6-3 market source)

Harness: the repo's own RV stack (`Clarinet-jing-*-market-spread.toml`, mock Lazer / ladder / core / ft), with the market built from `markets-sbtc-stx-jing-v6-3-formatted.clar`. That file is token-for-token identical to `markets-sbtc-stx-jing-v6-3.clar` once comments are stripped (16,717 tokens each). The rung is built with the `floor`/`cap` corrected to `1e18/33150` (see finding 2). Scripts and build steps are in this repo.

**Buy side** (`repro_index_close.mjs`), real output:

```
1. Alice deposits 100,000,000 sats                -> shares 100,000,000
2. pool sold down, epoch still open               -> unfilled-index=4,070,000  resting=407
3. Bob deposits 10,000,000 sats                   -> shares 2,457,002,457,002   Bob: sbtc=9,999,999
4. a taker buys ~80% of the pool                  -> epoch=1 total-shares=0 unfilled-index=1e12
   still resting on the market for this rung: 2,032,020 sats
   Bob: sbtc=0 stx=25,574,345,034                  <- 2,032,020 unsold sats reported as 0
5. Bob withdraws everything                       -> (err u7006)
   Bob claim                                      -> (ok stx 25,574,345,034) and his row is deleted
6. Carol deposits 1,000 sats into the new epoch   -> shares 1,000
   a taker buys 2,000,000 sats of what Bob left   -> (ok)
   Carol: sbtc=1,000 stx=6,393,584,093            <- Carol keeps her 1,000 sats AND earns ~6,394 STX of Bob's fills
```

Bob loses 2,032,020 sats (20.3% of his deposit, 20.3% of the pool at the close). Carol, with 1,000 sats in, collects the proceeds.

**Sell side** (`repro_index_close_sell.mjs`), real output:

```
0. mid -> 2.9e13 (under the 331.50 cap)
1. Alice deposits 100,000 STX
2. sold down, epoch open            -> unfilled-index=1,747,220  resting=174,722 uSTX
3. Bob deposits 1,000 STX           -> shares 572,337,770,858,850
4. three ordinary taker fills       -> epoch=1 total-shares=0, resting=474,920,835 uSTX
   Bob: sbtc=180,286 stx=0          <- 474.9 STX unsold, reported as 0
5. Bob withdraws                    -> (err u7006)
6. Carol deposits 0.1 STX, four more fills
   Carol: sbtc=149,850 stx=100,000  <- Carol keeps her 0.1 STX and earns 149,850 sats of Bob's fills
```

Bob loses 474.9 STX, 47.5% of his deposit.

### Reachability

- No special role is needed: a deposit and ordinary taker fills.
- The precondition is a pool whose index has fallen to a few multiples of 1e6 while its epoch is still open, i.e. at least `SOLD_OUT_DUST` still resting. The contract's own comment on `SOLD_OUT_INDEX` says the index "gets there on its own" through sell-down/top-up cycles. It's visible on chain through `get-state`, so a depositor can't see the danger but a taker can: fill the tail, wait for a top-up, fill past the threshold, then deposit `MIN_DEPOSIT` as the first member of the new epoch.
- Through `jing-ladder-dispatch` nothing changes, since the dispatcher calls the same `deposit`.

### Fix (tested)

Don't mint into the tail of an epoch, and restart the index when the last member leaves:

```clarity
(define-constant MINT_FLOOR u1000000000)          ;; 1e-3 of SCALE
(define-constant ERR_POOL_TAIL (err u7012))

;; deposit, right after the existing ERR_INDEX_COLLAPSED assert:
(asserts! (>= (var-get unfilled-index) MINT_FLOOR) ERR_POOL_TAIL)

;; withdraw, after total-shares is decremented:
(and (is-eq (var-get total-shares) u0)
  (begin (var-set epoch (+ (var-get epoch) u1)) (var-set unfilled-index SCALE)))
```

With every share minted at index ≥ 1e9, an index-floor close (< 1e6) forfeits less than `1e6 / 1e9` = **0.1% of any member's deposit**, down from unbounded. It also caps share inflation: fewer than 1,000 shares per sat. `fix_check.mjs` runs the buy-side scenario with the patch:

```
Alice deposits 1e8                   -> sold down to unfilled-index=4,070,000
Bob deposits 1e7 into the tail       -> (err u7012), Bob keeps his sats
Alice exits the tail                 -> epoch=1 total-shares=0 unfilled-index=1e12
Bob deposits 1e7 now                 -> shares 10,000,000 at a fresh index
```

Trade-off, stated plainly: while `1e6 ≤ index < 1e9` the rung takes no deposits until the tail sells or its members leave. A member who never leaves keeps it in that state (a liveness cost, not a loss; the dispatcher's allocation to that rung would revert with u7012). The complete alternative is per-epoch residual accounting. At the close, snapshot the final unfilled index next to `epoch-final-proceeds`. Move the residual to `held-sats` under a reserved counter excluded from the new epoch's `actual`. Let old-epoch rows withdraw `shares * final-unfilled / SCALE` from it. That's a bigger change, and I haven't tested it.

---

## 2. LOW: the RV build prices the market-spread rungs 1000× off, so fuzzing never fills them

`tests/rv/build.sh` (section 2f) pre-initialises both market-spread rungs with `floor` / `cap` = `u30165912518853695`. The contracts derive the order price as `PRICE_NUMERATOR / cents = 1e18 / 33150 = 30165912518853`. The build value is 1000× that. Observed on the buy rung with the unmodified build: every `rv-take` (amounts 1e6 to 1e9 µSTX, limits 0 to 15999) returned `(err u1017)` and the index never moved. Changing only that constant to `30165912518853`, the same calls fill. The sell rung behaved the same way until the mock mid was also moved under its cap. As a result, RV sweeps of these two rungs don't cover fills, the index path or the epoch close, where finding 1 lives. Your stxer mainnet-fork harnesses do fill, per `TRACE-COVERAGE-jing-buy-stx-market-spread.md`, so this is a gap in one layer of testing, not in all of it.

---

## Checked, no finding

**`jing-ladder-dispatch`:**
- `tx-sender == contract-caller` on both entry points.
- The allocation is validated in full before the first transfer:
  - the budget is subtracted, not summed, so there is no addition overflow;
  - zero amounts, duplicates and unseated rungs are refused;
  - the totals must match exactly.
- The side labels `"buy-band"` / `"sel-band"` match `jing-ladder-v1`'s `SIDE_BUY_BAND` / `SIDE_SELL_BAND` byte for byte.
- A failed rung call rolls the whole batch back.
- The dispatcher keeps no state and never uses `as-contract`, so funds only move from `tx-sender` into the rung the caller named.
- By construction it accepts only `buy-band`/`sel-band` rungs. The market-spread rungs register as `buy-peg`/`sel-peg`, so they can't be dispatched to. I read that as intended, not a defect.

**`jing-ladder-v1` seat cap:** `set-max-band-per-side` now asserts `n < MAX_SEATS_PER_SIDE (50)` and `n ≥` the seats held on both sides.

Not covered: stxer fork runs of the patch, the core-spread and fixed rungs beyond noting they share the close, and markets v6-3 beyond the paths these rungs call.
