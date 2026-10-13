import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const frontendUrl = new URL('../index.html', import.meta.url);
const frontend = await readFile(frontendUrl, 'utf8');

test('uses the approved moderate typography scale in the main interface', () => {
  assert.match(frontend, /\.nav-link\s*\{[^}]*font-size:13\.8px/i);
  assert.match(frontend, /\.page-subtitle\s*\{[^}]*font-size:12\.7px/i);
  assert.match(frontend, /\.metric-label\s*\{[^}]*font-size:11\.5px/i);
  assert.match(frontend, /\.data-table td\s*\{[^}]*font-size:10\.4px/i);
  assert.match(frontend, /\.form-field input,[^{]+\{[^}]*font-size:11\.5px/i);
});

test('does not leave interface text below the new eight-pixel floor', () => {
  const sizes = [...frontend.matchAll(/font-size:\s*([0-9.]+)px/gi)].map(match => Number(match[1]));
  assert.ok(sizes.length > 100, 'expected the complete inline stylesheet');
  assert.equal(sizes.filter(size => size < 8).length, 0);
});
