# Running the reproductions

1. Clone `Rapha-btc/jing-contracts-v3` at `6bf0470` and `npm install`.
2. Copy `build-v63.mjs` and `build-rung.mjs` from this repo into `tests/rv/`, then:
   ```
   node tests/rv/build-v63.mjs                                  # market from markets-sbtc-stx-jing-v6-3-formatted.clar
   node tests/rv/build-rung.mjs jing-buy-stx-market-spread
   node tests/rv/build-rung.mjs jing-sell-stx-market-spread
   ```
   (Node ports of `tests/rv/build.sh` sections 2d/2f; the only additions are the v6-3 and ladder-v1 principals.)
3. Set the real price in the two builds (finding 2): replace `u30165912518853695` with `u30165912518853` in the `floor` / `cap` data-var of `tests/rv/.build/jing-{buy,sell}-stx-market-spread.clar`. On Windows, make sure the .clar files have LF line endings.
4. `node repro_index_close.mjs`, `node repro_index_close_sell.mjs` from the repo root.
5. `fix_check.mjs` expects the patch in REPORT.md applied to the buy build.
