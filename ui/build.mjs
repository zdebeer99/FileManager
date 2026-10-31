// Builds the Elm UI into ui/dist. Usage: node ui/build.mjs [--dev]
// --dev skips --optimize and minification so Debug.log works and builds are faster.

import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { transformSync } from 'esbuild';

const ui = dirname(fileURLToPath(import.meta.url));
const dist = join(ui, 'dist');
const dev = process.argv.includes('--dev');
const isWindows = process.platform === 'win32';

mkdirSync(dist, { recursive: true });

const elm = join(ui, '..', 'node_modules', '.bin', isWindows ? 'elm.cmd' : 'elm');
const elmOut = join(dist, 'elm.js');
execFileSync(elm, ['make', 'src/Main.elm', ...(dev ? [] : ['--optimize']), '--output', elmOut], {
  cwd: ui,
  stdio: 'inherit',
  shell: isWindows,
});

if (!dev) {
  // Elm's curried helpers are pure, which lets esbuild drop unused code.
  const pure = ['F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9'];
  const result = transformSync(readFileSync(elmOut, 'utf8'), { minify: true, pure, target: 'es2020' });
  writeFileSync(elmOut, result.code);
}

for (const file of ['index.html', 'styles.css', 'bridge.js']) {
  copyFileSync(join(ui, 'static', file), join(dist, file));
}

console.log(`UI built (${dev ? 'dev' : 'release'}) -> ${dist}`);
