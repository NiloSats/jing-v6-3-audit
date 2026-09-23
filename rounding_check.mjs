// Borde del redondeo en withdraw: quemar participaciones redondea HACIA ARRIBA.
// ¿Puede quemarse más de lo que se tiene (aborto) o menos de lo debido (robo a los demás)?
import { initSimnet } from "@stacks/clarinet-sdk";
import { Cl, cvToValue, cvToString } from "@stacks/transactions";
const simnet = await initSimnet("Clarinet-jing-buy-stx-market-spread.toml");
const A = simnet.getAccounts(); const D = A.get("deployer"); const w = [...A.values()];
const [alice, bob, taker] = [w[1], w[2], w[3]];
const R = "jing-buy-stx-market-spread", E = Cl.buffer(new Uint8Array(0));
const call = (fn, args, who) => cvToString(simnet.callPublicFn(R, fn, args, who).result);
const S = () => { const s = cvToValue(simnet.callReadOnlyFn(R, "get-state", [], D).result); const o={}; for (const k of ["epoch","total-shares","unfilled-index","held-sats","resting","pooled"]) o[k]=BigInt(s[k].value); return o; };
const pos = (who) => { const p = cvToValue(simnet.callReadOnlyFn(R, "get-position", [Cl.principal(who)], D).result); return { shares: BigInt(p.shares.value), sbtc: BigInt(p.sbtc.value) }; };
const take = (ustx) => call("rv-take", [Cl.uint(ustx), Cl.uint(15999)], taker);
call("deposit", [Cl.uint(10000000), E], alice);
call("deposit", [Cl.uint(3000000), E], bob);
// una venta parcial para que el índice deje de ser redondo
take(4000000n * 3200n);
console.log("estado tras la venta:", Object.entries(S()).map(([k,v])=>k+"="+v).join(" "));
const antes = pos(bob), aliceAntes = pos(alice);
console.log("Bob antes:", antes.shares, "participaciones,", antes.sbtc, "sats");
// retirar TODO menos 1 sat: el peor caso para el redondeo
const objetivo = antes.sbtc - 1n;
console.log(`Bob retira ${objetivo} (todo menos 1):`, call("withdraw", [Cl.uint(objetivo)], bob).slice(0, 60));
const despues = pos(bob), aliceDespues = pos(alice);
console.log("Bob después:", despues.shares, "participaciones,", despues.sbtc, "sats");
console.log("quemadas:", antes.shares - despues.shares, "| lo justo sería ceil:", (objetivo * 1000000000000n + (S()["unfilled-index"] - 1n)) / S()["unfilled-index"]);
console.log("Alice antes:", aliceAntes.sbtc, "-> después:", aliceDespues.sbtc, "| diferencia:", aliceDespues.sbtc - aliceAntes.sbtc, "(debe ser 0 o positiva: nadie puede robarle)");
// ahora 1 sat, el caso que rompió la versión anterior
console.log("Bob retira 1 sat:", call("withdraw", [Cl.uint(1)], bob).slice(0, 60));
const fin = pos(bob); console.log("Bob final:", fin.shares, "participaciones,", fin.sbtc, "sats | Alice:", pos(alice).sbtc);
