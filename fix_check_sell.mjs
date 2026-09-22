// Sell side: same scenario as repro_index_close_sell.mjs with the MINT_FLOOR patch applied.
import { initSimnet } from "@stacks/clarinet-sdk";
import { Cl, cvToValue, cvToString } from "@stacks/transactions";
const simnet = await initSimnet("Clarinet-jing-sell-stx-market-spread.toml");
const A = simnet.getAccounts(); const D = A.get("deployer"); const w = [...A.values()];
const [alice, bob, taker] = [w[1], w[2], w[3]];
const R = "jing-sell-stx-market-spread", E = Cl.buffer(new Uint8Array(0));
const call = (fn, args, who) => cvToString(simnet.callPublicFn(R, fn, args, who).result);
const S = () => { const s = cvToValue(simnet.callReadOnlyFn(R, "get-state", [], D).result); const o = {}; for (const k of ["epoch","total-shares","unfilled-index","held-ustx","resting"]) o[k] = BigInt(s[k].value); return o; };
const fmt = (o) => Object.entries(o).map(([k, v]) => `${k}=${v}`).join(" ");
const take = (sats) => call("rv-take", [Cl.uint(sats > 200n ? sats - 200n : 0n), Cl.uint(0)], taker);
const sellTo = (target) => { let step = 199000n; for (let i = 0; i < 600; i++) { const r = S().resting; if (r <= target * 13n / 10n) return; const want = (r - target) / 3300n; const a = want < step ? want : step; if (a < 201n) return; const res = take(a); if (!res.startsWith("(ok")) { step = step / 2n; if (step < 201n) return; } } };
console.log("mid -> 2.9e13:", call("rv-set-mid", [Cl.uint(5000)], D));
console.log("Alice deposits 100,000 STX:", call("deposit", [Cl.uint(100000000000), E], alice)); sellTo(40000n); console.log(fmt(S()));
console.log("Bob deposits 1,000 STX into the tail:", call("deposit", [Cl.uint(1000000000), E], bob), " <- refused, Bob keeps his STX");
console.log("Alice exits the tail:", call("withdraw", [Cl.uint(100000000000)], alice)); console.log(fmt(S()));
console.log("Bob deposits 1,000 STX now:", call("deposit", [Cl.uint(1000000000), E], bob)); console.log(fmt(S()));
