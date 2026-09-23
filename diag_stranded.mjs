// Diagnostico: el invariante PROPIO del proyecto invariant-no-stranded-proceeds
// falla en cuanto el arnes alcanza la banda del suelo del indice. Aqui mido
// CUANTO queda varado y en que estado, para saber si es un hallazgo o un
// artefacto de mi envoltorio.
import { initSimnet } from "@stacks/clarinet-sdk";
import { Cl, cvToValue, cvToString } from "@stacks/transactions";
const simnet = await initSimnet("Clarinet-jing-buy-stx-market-spread.toml");
const A = simnet.getAccounts(); const D = A.get("deployer"); const w = [...A.values()];
const [alice, bob, taker] = [w[1], w[2], w[3]];
const R = "jing-buy-stx-market-spread", E = Cl.buffer(new Uint8Array(0));
const call = (fn, args, who) => cvToString(simnet.callPublicFn(R, fn, args, who).result);
const S = () => { const s = cvToValue(simnet.callReadOnlyFn(R, "get-state", [], D).result); const o = {}; for (const k of ["epoch","total-shares","unfilled-index","held-sats","resting"]) o[k] = BigInt(s[k].value); return o; };
const fmt = (o) => Object.entries(o).map(([k,v]) => `${k}=${v}`).join(" ");
const pos = (who) => cvToValue(simnet.callReadOnlyFn(R, "get-position", [Cl.principal(who)], D).result);
const stx = (who) => simnet.getAssetsMap().get("STX")?.get(who) ?? 0n;
const ACCS = w.slice(0, 10);
const varado = () => {
  const bal = stx(`${D}.${R}`) ?? 0n;
  let suma = 0n; for (const a of ACCS) suma += BigInt(pos(a).stx.value);
  return { balance: bal, reclamable: suma, varado: bal - suma };
};

console.log("1. Alice deposita 100.000.000 sats:", call("deposit", [Cl.uint(100000000), E], alice));
console.log("   estado:", fmt(S()), "| proceeds:", JSON.stringify(varado(), (k,v)=>typeof v==='bigint'?v.toString():v));
// el envoltorio propuesto, llamado como lo llamaria RV
for (let i = 0; i < 12; i++) {
  const r = call("rv-sell-down-to-floor", [Cl.uint(1n)], taker);
  const s = S();
  console.log(`   venta ${i+1}: ${r.slice(0,30)} | ${fmt(s)} | ${JSON.stringify(varado(), (k,v)=>typeof v==='bigint'?v.toString():v)}`);
  if (s["unfilled-index"] < 10000000n) break;
}
console.log("2. Alice intenta cobrar:", call("claim", [], alice));
console.log("   Alice ve:", JSON.stringify(pos(alice), (k,v)=>typeof v==='bigint'?v.toString():v));
console.log("   varado final:", JSON.stringify(varado(), (k,v)=>typeof v==='bigint'?v.toString():v));
