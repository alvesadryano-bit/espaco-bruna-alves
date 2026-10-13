import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migration = await readFile(
  new URL('../supabase/migrations/20261013000000_business_theme_customization.sql', import.meta.url),
  'utf8',
);
const frontend = await readFile(new URL('../index.html', import.meta.url), 'utf8');

test('stores one validated company theme color with the current green as default', () => {
  assert.match(migration, /alter table public\.businesses[\s\S]+add column theme_primary_color text not null default '#193B35'/i);
  assert.match(migration, /check \(theme_primary_color ~ '\^#\[0-9A-F\]\{6\}\$'\)/i);
  assert.match(frontend, /const DEFAULT_THEME_COLOR='#193B35'/i);
  assert.match(frontend, /from\('businesses'\)\.select\('theme_primary_color'\)/i);
});

test('allows only an authenticated company administrator to update and audit the theme', () => {
  assert.match(migration, /create or replace function public\.update_business_theme\([\s\S]+security definer/i);
  assert.match(migration, /auth\.uid\(\) is null/i);
  assert.match(migration, /has_business_role\([\s\S]+array\['admin'\]::public\.app_role\[\]/i);
  assert.match(migration, /'business\.theme_updated'/i);
  assert.match(migration, /insert into public\.audit_logs/i);
  assert.match(migration, /revoke all on function public\.update_business_theme\(uuid, text\)[\s\S]+from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.update_business_theme\(uuid, text\)[\s\S]+to authenticated/i);
});

test('provides presets, a custom color picker, preview and company-wide save', () => {
  assert.match(frontend, /data-action="business-theme"[^>]*hidden[^>]*>[\s\S]*Personalizar cores/i);
  assert.match(frontend, /Verde clássico[\s\S]+Azul petróleo[\s\S]+Ameixa[\s\S]+Terracota/i);
  assert.match(frontend, /id="themeColorInput"[^>]+type="color"/i);
  assert.match(frontend, /id="themePreview"/i);
  assert.match(frontend, /rpc\('update_business_theme',\{p_business_id:state\.businessId,p_theme_primary_color:color\}\)/i);
  assert.match(frontend, /state\.role!==?'Administrador'/i);
});

test('normalizes custom colors, enforces readable contrast and preserves semantic colors', () => {
  assert.match(frontend, /function normalizeThemeColor[\s\S]+\^#\[0-9A-F\]\{6\}\$/i);
  assert.match(frontend, /function ensureThemeContrast/i);
  assert.match(frontend, /themeLuminance/i);
  assert.match(frontend, /\.positive\s*\{\s*color:#638a68 !important/i);
  assert.match(frontend, /\.negative\s*\{\s*color:#b97868 !important/i);
  assert.match(frontend, /\.status-pill\.service\s*\{\s*background:#fcf1e9;color:#b67e54/i);
  assert.match(frontend, /cores de sucesso, alerta e erro permanecem inalterados/i);
});
