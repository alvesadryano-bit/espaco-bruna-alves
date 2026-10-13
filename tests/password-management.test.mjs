import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const frontend = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const readme = await readFile(new URL('../README.md', import.meta.url), 'utf8');

test('offers self-service password recovery from the login screen', () => {
  assert.match(frontend, /data-action="auth-forgot-password">Esqueci minha senha/i);
  assert.match(frontend, /id="passwordRecoveryRequestForm"/i);
  assert.match(frontend, /resetPasswordForEmail\(email,\{redirectTo:passwordResetRedirect\(\)\}\)/i);
  assert.match(frontend, /password-reset=1/i);
  assert.match(frontend, /view==='recovery-sent'/i);
});

test('forces the recovery link through a new-password screen before loading the workspace', () => {
  assert.match(frontend, /event==='PASSWORD_RECOVERY'/i);
  assert.match(frontend, /localStorage\.setItem\('passwordRecoveryPending','1'\)/i);
  assert.match(frontend, /recoveryContext\|\|state\.passwordRecovery[\s\S]+renderAuthGate\('password-reset'\)/i);
  assert.match(frontend, /id="passwordResetForm"/i);
  assert.match(frontend, /auth\.updateUser\(\{password\}\)/i);
  assert.match(frontend, /clearPasswordRecoveryContext\(\)[\s\S]+loadAuthenticatedWorkspace/i);
});

test('lets an authenticated user change their own password after checking the current password', () => {
  assert.match(frontend, /data-action="auth-change-password"[^>]*>[^<]*<span>[^<]*<\/span>Alterar minha senha/i);
  assert.match(frontend, /id="changeOwnPasswordForm"/i);
  assert.match(frontend, /signInWithPassword\(\{email,password:currentPassword\}\)/i);
  assert.match(frontend, /updateUser\(\{password\}\)/i);
  assert.match(frontend, /Escolha uma senha diferente da atual/i);
});

test('lets an administrator send the official reset link without setting another user password', () => {
  assert.match(frontend, /data-action="send-user-password-reset"/i);
  assert.match(frontend, /id="adminPasswordResetForm"/i);
  assert.match(frontend, /resetPasswordForEmail\(member\.email,\{redirectTo:passwordResetRedirect\(\)\}\)/i);
  assert.doesNotMatch(frontend, /\.auth\.admin\./i);
  assert.doesNotMatch(frontend, /service_role/i);
  assert.match(readme, /A administradora nunca vê nem escolhe a nova senha/i);
});
