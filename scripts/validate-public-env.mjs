// Build guard: browser bundles may contain only Supabase publishable/legacy anon keys.
const configuredKeys = [
  ['VITE_SUPABASE_PUBLISHABLE_KEY', process.env.VITE_SUPABASE_PUBLISHABLE_KEY || ''],
  ['VITE_SUPABASE_ANON_KEY', process.env.VITE_SUPABASE_ANON_KEY || ''],
].filter(([, value]) => value);
const url = process.env.VITE_SUPABASE_URL || '';

function fail(message) {
  console.error(`\n[env-guard] ${message}\n`);
  process.exit(1);
}

function decodeJwtPayload(value) {
  const parts = value.split('.');
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

function validateBrowserKey(name, key) {
  if (key.startsWith('sb_secret_')) fail(`${name} contém uma chave sb_secret. Segredos nunca podem ir para o navegador.`);
  if (key.startsWith('sb_publishable_')) return 'publishable';

  const payload = decodeJwtPayload(key);
  if (!payload) fail(`${name} não é sb_publishable_ nem um JWT legado reconhecível.`);
  if (payload.role !== 'anon') fail(`${name} contém JWT com papel "${payload.role || 'desconhecido'}"; o frontend aceita somente publishable/anon.`);
  return 'anon';
}

if (!configuredKeys.length && !url) {
  console.warn('[env-guard] Supabase não configurado; o build exibirá a tela de configuração.');
  process.exit(0);
}

if (!configuredKeys.length || !url) fail('Defina VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY em conjunto.');
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url)) fail('VITE_SUPABASE_URL não é uma URL válida de projeto Supabase.');

const types = configuredKeys.map(([name, key]) => validateBrowserKey(name, key));
if (types.includes('publishable')) console.log('[env-guard] Chave publishable validada.');
else console.warn('[env-guard] Chave anon legada validada; migre para sb_publishable_ quando possível.');
