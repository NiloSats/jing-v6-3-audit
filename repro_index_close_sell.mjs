// Same repro on jing-sell-stx-market-spread (rests micro-STX; takers bring sBTC).
import { initSimnet } from "@stacks/clarinet-sdk";
import { Cl, cvToValue, cvToString } from "@stacks/transactions";
const simnet = await initSimnet("Clarinet-jing-sell-stx-market-spread.toml");
const A = simnet.getAccounts(); const D = A.get("deployer"); const w = [...A.values()];
const [alice, bob, taker, carol] = [w[1], w[2], w[3], w[4]];
const R = "jing-sell-stx-market-spread", E = Cl.buffer(new Uint8Array(0));
const call = (fn, args, who) => cvToString(simnet.callPublicFn(R, fn, args, who).result);
const S = () => { const s = cvToValue(simnet.callReadOnlyFn(R, "get-state", [], D).result); const o = {}; for (const k of ["epoch","total-shares","unfilled-index","held-ustx","resting"]) o[k] = BigInt(s[k].value); return o; };
const fmt = (o) => Object.entries(o).map(([k, v]) => `${k}=${v}`).join(" ");
const pos = (who) => { const p = cvToValue(simnet.callReadOnlyFn(R, "get-position", [Cl.principal(who)], D).result); return Object.entries(p).map(([k, v]) => `${k}=${v.value}`).join(" "); };
// rv-take sends (200 + amount mod 200000) sats
const take = (sats) => call("rv-take", [Cl.uint(sats > 200n ? sats - 200n : 0n), Cl.uint(0)], taker);
const sellTo = (target) => { let step = 199000n; for (let i = 0; i < 600; i++) { const r = S().resting; if (r <= target * 13n / 10n) return; const want = (r - target) / 3300n; const a = want < step ? want : step; if (a < 201n) return; const res = take(a); if (!res.startsWith("(ok")) { step = step / 2n; if (step < 201n) { console.log("  stuck", res, fmt(S())); return; } } } console.log("  gave up", fmt(S())); };
console.log("0. mid -> 2.9e13 (under the 331.50 cap):", call("rv-set-mid", [Cl.uint(5000)], D));
console.log("1. Alice deposits 100,000 STX:", call("deposit", [Cl.uint(100000000000), E], alice));
sellTo(40000n); let s = S(); console.log("2. sold down, epoch open:", fmt(s)); console.log("   Alice:", pos(alice));
console.log("3. Bob deposits 1,000 STX:", call("deposit", [Cl.uint(1000000000), E], bob)); s = S(); console.log("  ", fmt(s)); console.log("   Bob:", pos(bob));
const before = s.resting; let n = 0;
while (S().epoch === 0n && n++ < 8) console.log("4. taker fill:", take(before / 5n / 3300n > 199000n ? 199000n : before / 5n / 3300n), fmt(S()));
s = S(); console.log("   after fills:", fmt(s)); console.log("   Bob:", pos(bob));
console.log("5. Bob withdraws:", call("withdraw", [Cl.uint(1000000000)], bob));
console.log("6. Carol deposits 0.1 STX:", call("deposit", [Cl.uint(100000), E], carol));
for (let i = 0; i < 4; i++) take(150000n); s = S(); console.log("   after more fills:", fmt(s)); console.log("   Carol:", pos(carol));
