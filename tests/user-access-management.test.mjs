import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL('../supabase/migrations/20261012030000_user_access_management.sql', import.meta.url);
const frontendUrl = new URL('../index.html', import.meta.url);
const sql = await readFile(migrationUrl, 'utf8');
const frontend = await readFile(frontendUrl, 'utf8');

const adminRpcs = [
  'create_user_invitation',
  'list_business_users',
  'revoke_user_invitation',
  'update_business_user_access',
  'remove_business_user',
];

test('creates an RLS-protected invitation table and disables additional company bootstrap', () => {
  assert.match(sql, /create table public\.user_invitations\b/i);
  assert.match(sql, /alter table public\.user_invitations enable row level security/i);
  assert.match(sql, /create policy user_invitations_admin_read[\s\S]+has_business_role/i);
  assert.match(sql, /revoke execute on function public\.create_first_business\(text, text, text\) from authenticated/i);
});

test('exposes invitation acceptance safely and validates the authenticated email', () => {
  assert.match(sql, /create or replace function public\.get_user_invitation\b/i);
  assert.match(sql, /grant execute on function public\.get_user_invitation\(uuid\) to anon, authenticated/i);
  assert.match(sql, /create or replace function public\.accept_user_invitation\b/i);
  assert.match(sql, /from auth\.users[\s\S]+v_auth_email <> lower\(v_invitation\.email\)/i);
  assert.match(sql, /grant execute on function public\.accept_user_invitation\(uuid\) to authenticated/i);
  assert.doesNotMatch(sql, /grant execute on function public\.accept_user_invitation\(uuid\) to anon/i);
});

test('keeps user administration behind authenticated admin RPCs', () => {
  for (const rpc of adminRpcs) {
    assert.match(sql, new RegExp(`create or replace function public\\.${rpc}\\b`, 'i'));
    assert.match(sql, new RegExp(`revoke all on function public\\.${rpc}[^;]+from public, anon, authenticated`, 'is'));
    assert.match(sql, new RegExp(`grant execute on function public\\.${rpc}[^;]+to authenticated`, 'is'));
  }
  assert.match(sql, /Você não pode remover o próprio acesso/i);
  assert.match(sql, /A empresa precisa manter ao menos um administrador/i);
});

test('frontend removes public signup and provides profile-based user management', () => {
  assert.doesNotMatch(frontend, /auth-mode-signup/);
  assert.doesNotMatch(frontend, /Criar empresa e continuar/);
  assert.match(frontend, /data-page="usuarios" data-admin-only="true"/);
  assert.match(frontend, /create_user_invitation/);
  assert.match(frontend, /accept_user_invitation/);
  assert.match(frontend, /Administrador · acesso completo/);
  assert.match(frontend, /Recepcionista · agenda e clientes/);
  assert.match(frontend, /Profissional · agenda própria e comissões/);
});
