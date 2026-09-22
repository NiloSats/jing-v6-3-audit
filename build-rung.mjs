// Port a Node de la seccion 2f del pipeline python3 de tests/rv/build.sh,
// para los rungs jing-buy/sell-stx-core-spread.
//   node tests/rv/build-rung.mjs jing-buy-stx-core-spread
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const name = process.argv[2] || 'jing-buy-stx-core-spread';
const SRC = `contracts/${name}.clar`;
const INV = `tests/rv/${name}.invariants.clar`;
const OUT = `tests/rv/.build/${name}.clar`;

let text = readFileSync(SRC, 'utf8');
const rep = (a, b) => { text = text.split(a).join(b); };

// 1. trait local
rep("(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)",
    '(use-trait ft-trait .sip-010-trait.sip-010-trait)');

// 2f. los rungs agrupados
rep("'SPV9K21TBFAK4KNRJXF5DFP8N7W46G4V9RCJDC22.markets-sbtc-stx-jing-v6-3", '.v6-market');
rep("'SPV9K21TBFAK4KNRJXF5DFP8N7W46G4V9RCJDC22.jing-ladder-v1", '.mock-jing-ladder');
rep("'SPV9K21TBFAK4KNRJXF5DFP8N7W46G4V9RCJDC22.markets-sbtc-stx-jing-v6", '.v6-market');
rep("'SPV9K21TBFAK4KNRJXF5DFP8N7W46G4V9RCJDC22.jing-ladder", '.mock-jing-ladder');
rep("'SPV9K21TBFAK4KNRJXF5DFP8N7W46G4V9RCJDC22.rfq-sbtc-stx-jing-v2-3", '.mock-rfq-oracle');
rep("'SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4.sbtc-token", '.mock-ft');
rep("'SM1793C4R5PZ4NS4VQ4WMP7SKKYVH8JZEWSZ9HCCR.token-stx-v-1-2", '.mock-ft');
rep('(define-constant SBTC_NAME "sbtc-token")', '(define-constant SBTC_NAME "mock-ft")');
rep('(define-constant WSTX_NAME "wstx")', '(define-constant WSTX_NAME "mock-ft")');
rep('(define-data-var initialized bool false)', '(define-data-var initialized bool true)');
rep('(define-data-var price uint u0)', '(define-data-var price uint u30165912518853695)');
rep('(define-data-var sats-per-stx-cents uint u0)', '(define-data-var sats-per-stx-cents uint u33150)');
rep('(define-data-var spread-bps uint u0)', '(define-data-var spread-bps uint u20)');
rep('(define-data-var floor-cents uint u0)', '(define-data-var floor-cents uint u33150)');
rep('(define-data-var cap-cents uint u0)', '(define-data-var cap-cents uint u33150)');
rep('(define-data-var floor uint u0)', '(define-data-var floor uint u30165912518853695)');
rep('(define-data-var cap uint u0)', '(define-data-var cap uint u30165912518853695)');

// 2. mock-jing-core generico
rep('.jing-core-v5', '.mock-jing-core');
rep('.jing-core-v3', '.mock-jing-core');
rep('.jing-core-v2', '.mock-jing-core');
rep('.jing-core', '.mock-jing-core');

text += '\n\n' + readFileSync(INV, 'utf8');

mkdirSync('tests/rv/.build', { recursive: true });
writeFileSync(OUT, text);
console.log('escrito', OUT, text.length, 'bytes');
