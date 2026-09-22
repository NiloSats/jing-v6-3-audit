// Repro: an index-floor epoch close forfeits a large unsold balance (not <=1e-6 of the pool).
// jing-buy-stx-market-spread on the v6-3 market (RV build, real rung + real market source).
import { initSimnet } from "@stacks/clarinet-sdk";
import { Cl, cvToValue, cvToString } from "@stacks/transactions";
const simnet = await initSimnet("Clarinet-jing-buy-stx-market-spread.toml");
const A = simnet.getAccounts(); const D = A.get("deployer"); const w = [...A.values()];
const [alice, bob, taker, carol] = [w[1], w[2], w[3], w[4]];
const R = "jing-buy-stx-market-spread", E = Cl.buffer(new Uint8Array(0));
const call = (fn, args, who) => cvToString(simnet.callPublicFn(R, fn, args, who).result);
const S = () => { const s = cvToValue(simnet.callReadOnlyFn(R, "get-state", [], D).result); const o = {}; for (const k of ["epoch","total-shares","unfilled-index","held-sats","resting"]) o[k] = BigInt(s[k].value); return o; };
const fmt = (o) => Object.entries(o).map(([k, v]) => `${k}=${v}`).join(" ");
const pos = (who) => { const p = cvToValue(simnet.callReadOnlyFn(R, "get-position", [Cl.principal(who)], D).result); return `shares=${p.shares.value} sbtc=${p.sbtc.value} stx=${p.stx.value}`; };
const take = (ustx) => call("rv-take", [Cl.uint(ustx), Cl.uint(15999)], taker);
// sell the pool down to about `target` sats still resting, in steps the book accepts
const sellTo = (target) => { let step = 50000000n; for (let i = 0; i < 400; i++) { const r = S().resting; if (r <= target * 13n / 10n) return; const gap = r - target; const want = gap < step ? gap : step; const res = take(want * 3200n); if (!res.startsWith("(ok")) { step = step / 2n; if (step < 1n) { console.log("  stuck", res, fmt(S())); return; } } } console.log("  sellTo gave up", fmt(S())); };

console.log("1. Alice deposits 100,000,000 sats:", call("deposit", [Cl.uint(100000000), E], alice));
sellTo(400n); let s = S();
console.log("2. pool sold down, epoch still open:", fmt(s));
console.log("   Alice:", pos(alice));
console.log("3. Bob deposits 10,000,000 sats:", call("deposit", [Cl.uint(10000000), E], bob));
s = S(); console.log("  ", fmt(s)); console.log("   Bob:", pos(bob));
const before = s.resting;
// one ordinary fill of roughly 70% of the pool
console.log("4. a taker buys ~80% of the pool:", take(before * 8n / 10n * 3200n));
s = S(); console.log("  ", fmt(s));
console.log("   still resting on the market for this rung:", s.resting.toString(), "sats (+ held", s["held-sats"].toString() + ")");
console.log("   Bob:", pos(bob), " <- unsold sBTC now reported as 0");
console.log("5. Bob withdraws everything:", call("withdraw", [Cl.uint(10000000)], bob));
console.log("   Bob claim:", call("claim", [], bob), "| Bob after:", pos(bob));
console.log("6. Carol deposits 1,000 sats into the new epoch:", call("deposit", [Cl.uint(1000), E], carol));
s = S(); console.log("  ", fmt(s));
console.log("   a taker buys 2,000,000 sats of what Bob left:", take(2000000n * 3200n));
s = S(); console.log("  ", fmt(s)); console.log("   Carol:", pos(carol));
