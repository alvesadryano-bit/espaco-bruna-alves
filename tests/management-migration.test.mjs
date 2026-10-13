import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL('../supabase/migrations/20261012020000_management_modules.sql', import.meta.url);
const sql = await readFile(migrationUrl, 'utf8');

const requiredTables = [
  'products',
  'branch_product_stock',
  'stock_movements',
  'checkouts',
  'checkout_items',
  'checkout_payments',
  'expenses',
  'commission_entries',
  'commission_payouts',
];

const requiredRpcs = [
  'create_inventory_product',
  'record_stock_movement',
  'upsert_commission_rule',
  'close_appointment_checkout',
  'record_expense',
  'pay_commissions',
];

test('defines every management table with RLS enabled', () => {
  for (const table of requiredTables) {
    assert.match(sql, new RegExp(`create table public\\.${table}\\b`, 'i'), `missing table ${table}`);
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, 'i'), `missing RLS for ${table}`);
  }
});

test('exposes mutations only through authenticated RPCs', () => {
  for (const rpc of requiredRpcs) {
    assert.match(sql, new RegExp(`create or replace function public\\.${rpc}\\b`, 'i'), `missing RPC ${rpc}`);
    assert.match(sql, new RegExp(`grant execute on function public\\.${rpc}[^;]+to authenticated`, 'is'), `missing authenticated grant for ${rpc}`);
    assert.match(sql, new RegExp(`revoke all on function public\\.${rpc}[^;]+from public, anon`, 'is'), `missing public revoke for ${rpc}`);
  }
});

test('revokes direct writes before granting read access', () => {
  assert.match(sql, /revoke all on public\.products[\s\S]+from anon, authenticated;/i);
  assert.match(sql, /grant select on public\.products[\s\S]+to authenticated;/i);
});
