// Port a Node del pipeline python3 de tests/rv/build.sh, solo para
// markets-sbtc-stx-jing-v6 (la maquina de auditoria no tiene python3).
// Aplica las mismas sustituciones, en el mismo orden, y concatena las
// invariantes. Salida: tests/rv/.build/markets-sbtc-stx-jing-v6.clar
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const SRC = 'contracts/markets-sbtc-stx-jing-v6-3-formatted.clar';
const INV = 'tests/rv/markets-sbtc-stx-jing-v6.invariants.clar';
const OUT = 'tests/rv/.build/markets-sbtc-stx-jing-v6.clar';

let text = readFileSync(SRC, 'utf8');
const rep = (a, b) => { text = text.split(a).join(b); };

// 1. trait SIP-010 local
rep("(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)",
    '(use-trait ft-trait .sip-010-trait.sip-010-trait)');

// 2d. especifico de markets-sbtc-stx-jing-v6
rep('.jing-core-v5', '.mock-jing-core');
rep("'SPMV5HDZ4EMB8XY7HAYT3XW0DF7DZ4E8XEG2J1T8.pyth-lazer-oracle", '.mock-lazer-oracle');
rep("'SPMV5HDZ4EMB8XY7HAYT3XW0DF7DZ4E8XEG2J1T8.pyth-lazer-decoder-v1", '.mock-lazer-oracle');
rep('.jing-ladder-v1', '.mock-jing-ladder'); rep('.jing-ladder', '.mock-jing-ladder');
rep('(define-constant MAX_DEPOSITORS u50)', '(define-constant MAX_DEPOSITORS u6)');
rep('(define-data-var seats-per-side uint u10)', '(define-data-var seats-per-side uint u2)');
rep('(define-data-var distance-slots uint u10)', '(define-data-var distance-slots uint u2)');
rep('(define-data-var treasury principal tx-sender)', '(define-data-var treasury principal .mock-jing-ladder)');
rep('(define-data-var feed-id-x uint u0)', '(define-data-var feed-id-x uint u1)');
rep('(define-data-var feed-id-y uint u0)', '(define-data-var feed-id-y uint u45)');
rep('(define-data-var min-token-y-deposit uint u0)', '(define-data-var min-token-y-deposit uint u10000)');
rep('(define-data-var min-token-x-deposit uint u0)', '(define-data-var min-token-x-deposit uint u100)');

// 2. mock-jing-core generico (no toca ".mock-jing-core": el caracter previo es '-')
rep('.jing-core-v3', '.mock-jing-core');
rep('.jing-core-v2', '.mock-jing-core');
rep('.jing-core', '.mock-jing-core');

// 3. tokens pre-inicializados al mock
rep('(define-data-var token-x principal SAINT)', '(define-data-var token-x principal .mock-ft)');
rep('(define-data-var token-y principal SAINT)', '(define-data-var token-y principal .mock-ft)');

// 4. saltar el gate de initialize()
rep('(define-data-var initialized bool false)', '(define-data-var initialized bool true)');

// 6. reescrituras genericas de vault (aqui no-ops salvo las de nombre)
rep("'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token", '.mock-ft');
rep("'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2", '.mock-ft');
rep('.markets-sbtc-usdcx-jing', '.mock-jing-market');
rep('.markets-sbtc-stx-jing', '.mock-jing-market');
rep('.jing-vault-auth', '.mock-jing-vault-auth');

text += '\n\n' + readFileSync(INV, 'utf8');

mkdirSync('tests/rv/.build', { recursive: true });
writeFileSync(OUT, text);
console.log('escrito', OUT, text.length, 'bytes');
for (const probe of ['MAX_DEPOSITORS u6', 'seats-per-side uint u2', 'mock-jing-ladder', 'rv-band-y']) {
  console.log(text.includes(probe) ? 'OK  ' : 'FALTA', probe);
}
