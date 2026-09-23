// Construye un peldano para RV como tests/rv/build.sh (seccion 2f), con el
// floor/cap real (hallazgo 2), el envoltorio que alcanza la banda del suelo
// del indice y el invariante propuesto.
//   node nilo/build-inv.mjs jing-buy-stx-market-spread [--sin-invariante] [--con-arreglo]
import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const name = process.argv[2] || 'jing-buy-stx-market-spread';
const conInv = !process.argv.includes('--sin-invariante');
const conFix = process.argv.includes('--con-arreglo');
execSync(`node nilo/build-rung.mjs ${name}`, { stdio: 'inherit' });
const OUT = `tests/rv/.build/${name}.clar`;
let t = readFileSync(OUT, 'utf8');

// hallazgo 2: el precio del arnes esta 1000x por encima del real 1e18/33150
if (!t.includes('u30165912518853695')) throw new Error('no encontre el floor/cap del arnes');
t = t.split('u30165912518853695').join('u30165912518853');

if (conFix) {
  // Arreglo A del informe: no acunar en la cola de la epoca, y reiniciar el
  // indice cuando se va el ultimo miembro.
  const ancla = '(asserts! (>= (var-get unfilled-index) SOLD_OUT_INDEX) ERR_INDEX_COLLAPSED)';
  const dec = '(var-set total-shares (- (var-get total-shares) shares-out))';
  const cst = '(define-constant ERR_INDEX_COLLAPSED (err u7011))';
  for (const [a, q] of [[ancla, 'assert de deposit'], [dec, 'decremento de total-shares'], [cst, 'constante de error']]) {
    if (!t.includes(a)) throw new Error('no encontre el ' + q);
  }
  t = t.split(ancla).join(ancla + '\n    (asserts! (>= (var-get unfilled-index) MINT_FLOOR) ERR_POOL_TAIL)');
  t = t.split(dec).join(dec + '\n        (and (is-eq (var-get total-shares) u0)\n          (begin (var-set epoch (+ (var-get epoch) u1)) (var-set unfilled-index SCALE)))');
  t = t.replace(cst, cst + '\n(define-constant MINT_FLOOR u1000000000)\n(define-constant ERR_POOL_TAIL (err u7012))');
}

if (conInv) t += '\n' + readFileSync('nilo/envoltorio_cierre.clar', 'utf8')
                  + '\n' + readFileSync('nilo/invariante_cierre.clar', 'utf8');
writeFileSync(OUT, t.replace(/\r\n/g, '\n'));
console.log(`${OUT}: floor real, invariante=${conInv}, arreglo=${conFix}, ${t.length} bytes`);
