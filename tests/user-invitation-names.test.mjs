import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL('../supabase/migrations/20261012040000_user_invitation_names.sql', import.meta.url);
const frontendUrl = new URL('../index.html', import.meta.url);
const sql = await readFile(migrationUrl, 'utf8');
const frontend = await readFile(frontendUrl, 'utf8');

test('stores the name selected by the administrator on every invitation', () => {
  assert.match(sql, /alter table public\.user_invitations[\s\S]+add column display_name text/i);
  assert.match(sql, /alter column display_name set not null/i);
  assert.match(sql, /user_invitations_display_name_check/i);
  assert.match(sql, /select nullif\(trim\(p\.display_name\), ''\)[\s\S]+p\.id = i\.professional_id/i);
  assert.match(sql, /returns table\s*\([\s\S]*display_name text[\s\S]*business_name text/i);
});

test('creates a professional automatically when no existing record is selected', () => {
  assert.match(sql, /p_display_name text[\s\S]+p_professional_id uuid default null/i);
  assert.match(sql, /if v_professional_id is null then[\s\S]+insert into public\.professionals/i);
  assert.match(sql, /insert into public\.professional_branches/i);
  assert.match(sql, /on conflict \(professional_id, branch_id\)[\s\S]+do update set active = true/i);
});

test('accepting the invitation applies the managed name to the profile and professional', () => {
  assert.match(sql, /insert into public\.profiles \(id, display_name, email\)/i);
  assert.match(sql, /on conflict \(id\) do update[\s\S]+display_name = excluded\.display_name/i);
  assert.match(sql, /set user_id = auth\.uid\(\), display_name = v_invitation\.display_name/i);
});

test('frontend asks for a name and defaults to creating a new professional', () => {
  assert.match(frontend, /name="displayName"[^>]+required/i);
  assert.match(frontend, /name="professionalMode"/i);
  assert.match(frontend, /value="new">Criar novo profissional com este nome/i);
  assert.match(frontend, /p_display_name:displayName/i);
  assert.match(frontend, /professionalMode==='existing'/i);
  assert.match(frontend, /\[hidden\]\s*\{\s*display:\s*none\s*!important;/i);
});
