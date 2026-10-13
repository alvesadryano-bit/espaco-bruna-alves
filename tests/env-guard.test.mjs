import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const script = new URL('../scripts/validate-public-env.mjs', import.meta.url);
const url = 'https://example.supabase.co';
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = role => `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ role })}.signature`;

function run(key, legacyKey = '') {
  return spawnSync(process.execPath, [script.pathname], {
    encoding: 'utf8',
    env: {
      ...process.env,
      VITE_SUPABASE_URL: url,
      VITE_SUPABASE_PUBLISHABLE_KEY: key,
      VITE_SUPABASE_ANON_KEY: legacyKey,
    },
  });
}

test('accepts a publishable key', () => {
  const result = run('sb_publishable_public_test_key_1234567890');
  assert.equal(result.status, 0, result.stderr);
});

test('accepts a legacy anon JWT', () => {
  const result = run(jwt('anon'));
  assert.equal(result.status, 0, result.stderr);
});

test('rejects a service_role JWT without printing it', () => {
  const key = jwt('service_role');
  const result = run(key);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /service_role/);
  assert.doesNotMatch(`${result.stdout}${result.stderr}`, new RegExp(key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
});

test('rejects a secret key', () => {
  const result = run('sb_secret_private_test_key_1234567890');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /sb_secret/);
});

test('rejects a privileged legacy key even when a publishable key is also set', () => {
  const result = run('sb_publishable_public_test_key_1234567890', jwt('service_role'));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /VITE_SUPABASE_ANON_KEY/);
});
