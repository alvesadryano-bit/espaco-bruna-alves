-- Módulos operacionais: estoque, fechamento financeiro e comissões.
-- Aplicar uma única vez após 20261012010000_frontdesk_client_visibility.sql.

begin;

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 140),
  sku text not null check (char_length(trim(sku)) between 1 and 60),
  product_type text not null check (product_type in ('internal', 'retail')),
  unit text not null check (char_length(trim(unit)) between 1 and 20),
  minimum_stock numeric(14,3) not null default 0 check (minimum_stock >= 0),
  cost_price numeric(12,4) not null default 0 check (cost_price >= 0),
  sale_price numeric(12,2) check (sale_price is null or sale_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id)
);
create unique index products_business_sku_unique on public.products (business_id, upper(sku));
create index products_business_active_idx on public.products (business_id, active, name);

create table public.branch_product_stock (
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  average_cost numeric(12,4) not null default 0 check (average_cost >= 0),
  updated_at timestamptz not null default now(),
  primary key (branch_id, product_id),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (product_id, business_id) references public.products(id, business_id) on delete cascade
);
create index branch_product_stock_low_idx on public.branch_product_stock (business_id, branch_id, quantity);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  movement_type text not null check (movement_type in ('purchase', 'consumption', 'sale', 'loss', 'return', 'adjustment')),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  balance_after numeric(14,3) not null check (balance_after >= 0),
  unit_cost numeric(12,4) check (unit_cost is null or unit_cost >= 0),
  reason text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (product_id, business_id) references public.products(id, business_id) on delete restrict
);
create index stock_movements_branch_time_idx on public.stock_movements (business_id, branch_id, created_at desc);
create index stock_movements_product_time_idx on public.stock_movements (product_id, created_at desc);

create table public.checkouts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  appointment_id uuid not null,
  client_id uuid not null,
  status text not null default 'paid' check (status in ('paid', 'voided')),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null check (total >= 0),
  notes text,
  closed_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (appointment_id, business_id, branch_id) references public.appointments(id, business_id, branch_id) on delete restrict,
  foreign key (client_id, business_id) references public.clients(id, business_id) on delete restrict,
  unique (id, business_id, branch_id)
);
create unique index checkouts_one_active_per_appointment_idx on public.checkouts (appointment_id) where status = 'paid';
create index checkouts_branch_closed_idx on public.checkouts (business_id, branch_id, closed_at desc);

create table public.checkout_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  checkout_id uuid not null,
  appointment_service_id uuid not null,
  service_id uuid not null,
  professional_id uuid not null,
  description text not null,
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  foreign key (checkout_id, business_id, branch_id) references public.checkouts(id, business_id, branch_id) on delete cascade,
  foreign key (appointment_service_id, business_id) references public.appointment_services(id, business_id) on delete restrict,
  foreign key (service_id, business_id) references public.services(id, business_id) on delete restrict,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete restrict,
  unique (checkout_id, appointment_service_id),
  unique (id, business_id, branch_id)
);
create index checkout_items_professional_idx on public.checkout_items (business_id, professional_id, created_at desc);

create table public.checkout_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  checkout_id uuid not null,
  payment_method text not null check (payment_method in ('pix', 'credit_card', 'debit_card', 'cash', 'bank_transfer', 'other')),
  amount numeric(12,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  foreign key (checkout_id, business_id, branch_id) references public.checkouts(id, business_id, branch_id) on delete cascade
);
create index checkout_payments_branch_time_idx on public.checkout_payments (business_id, branch_id, created_at desc);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  description text not null check (char_length(trim(description)) between 2 and 180),
  category text not null check (char_length(trim(category)) between 2 and 80),
  amount numeric(12,2) not null check (amount > 0),
  status text not null default 'paid' check (status in ('pending', 'paid', 'cancelled')),
  due_date date,
  paid_at timestamptz,
  payment_method text check (payment_method is null or payment_method in ('pix', 'credit_card', 'debit_card', 'cash', 'bank_transfer', 'other')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  check ((status = 'paid' and paid_at is not null) or status <> 'paid')
);
create index expenses_branch_date_idx on public.expenses (business_id, branch_id, paid_at desc, due_date desc);

create table public.commission_payouts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  professional_id uuid not null,
  amount numeric(12,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('pix', 'bank_transfer', 'cash', 'other')),
  notes text,
  paid_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete restrict,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete restrict,
  unique (id, business_id, branch_id)
);
create index commission_payouts_professional_time_idx on public.commission_payouts (business_id, professional_id, paid_at desc);

create table public.commission_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  checkout_item_id uuid not null,
  professional_id uuid not null,
  service_id uuid not null,
  commission_rule_id uuid references public.service_commission_rules(id) on delete set null,
  rule_type public.commission_rule_type not null,
  base_amount numeric(12,2) not null check (base_amount >= 0),
  rule_value numeric(10,4) not null check (rule_value >= 0),
  amount numeric(12,2) not null check (amount >= 0),
  status text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  payout_id uuid,
  generated_at timestamptz not null default now(),
  paid_at timestamptz,
  foreign key (checkout_item_id, business_id, branch_id) references public.checkout_items(id, business_id, branch_id) on delete restrict,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete restrict,
  foreign key (service_id, business_id) references public.services(id, business_id) on delete restrict,
  foreign key (payout_id, business_id, branch_id) references public.commission_payouts(id, business_id, branch_id) on delete restrict,
  unique (checkout_item_id)
);
create index commission_entries_status_idx on public.commission_entries (business_id, branch_id, professional_id, status, generated_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger products_touch_updated_at before update on public.products
for each row execute procedure public.touch_updated_at();
create trigger checkouts_touch_updated_at before update on public.checkouts
for each row execute procedure public.touch_updated_at();
create trigger expenses_touch_updated_at before update on public.expenses
for each row execute procedure public.touch_updated_at();

create or replace function public.create_inventory_product(
  p_branch_id uuid,
  p_name text,
  p_sku text,
  p_product_type text,
  p_unit text,
  p_minimum_stock numeric default 0,
  p_cost_price numeric default 0,
  p_sale_price numeric default null,
  p_initial_quantity numeric default 0
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_product_id uuid;
  v_initial numeric(14,3) := coalesce(p_initial_quantity, 0);
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select b.business_id into v_business_id from public.branches b where b.id = p_branch_id and b.active;
  if not found then raise exception 'Unidade não encontrada ou inativa' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin']::public.app_role[], p_branch_id) then
    raise exception 'Sem permissão para gerenciar o estoque desta unidade' using errcode = '42501';
  end if;
  if p_product_type not in ('internal', 'retail') then raise exception 'Tipo de produto inválido' using errcode = '22023'; end if;
  if v_initial < 0 or coalesce(p_minimum_stock, 0) < 0 or coalesce(p_cost_price, 0) < 0 then
    raise exception 'Quantidade, mínimo e custo não podem ser negativos' using errcode = '22023';
  end if;
  insert into public.products (business_id, name, sku, product_type, unit, minimum_stock, cost_price, sale_price)
  values (v_business_id, trim(p_name), upper(trim(p_sku)), p_product_type, trim(p_unit), coalesce(p_minimum_stock, 0), coalesce(p_cost_price, 0), p_sale_price)
  returning id into v_product_id;
  insert into public.branch_product_stock (business_id, branch_id, product_id, quantity, average_cost)
  values (v_business_id, p_branch_id, v_product_id, v_initial, coalesce(p_cost_price, 0));
  if v_initial > 0 then
    insert into public.stock_movements (business_id, branch_id, product_id, movement_type, quantity_delta, balance_after, unit_cost, reason, created_by)
    values (v_business_id, p_branch_id, v_product_id, 'purchase', v_initial, v_initial, coalesce(p_cost_price, 0), 'Estoque inicial', auth.uid());
  end if;
  insert into public.audit_logs (business_id, user_id, action, entity_type, entity_id, after_data)
  values (v_business_id, auth.uid(), 'inventory.product_created', 'product', v_product_id, jsonb_build_object('branch_id', p_branch_id, 'initial_quantity', v_initial));
  return v_product_id;
end;
$$;

create or replace function public.record_stock_movement(
  p_branch_id uuid,
  p_product_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_unit_cost numeric default null,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_stock public.branch_product_stock%rowtype;
  v_new_quantity numeric(14,3);
  v_new_average numeric(12,4);
  v_movement_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select b.business_id into v_business_id from public.branches b where b.id = p_branch_id and b.active;
  if not found then raise exception 'Unidade não encontrada ou inativa' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin']::public.app_role[], p_branch_id) then
    raise exception 'Sem permissão para movimentar o estoque desta unidade' using errcode = '42501';
  end if;
  if p_movement_type not in ('purchase', 'consumption', 'sale', 'loss', 'return', 'adjustment') then
    raise exception 'Tipo de movimentação inválido' using errcode = '22023';
  end if;
  if p_quantity_delta is null or p_quantity_delta = 0 then raise exception 'A quantidade da movimentação não pode ser zero' using errcode = '22023'; end if;
  if p_movement_type in ('purchase', 'return') and p_quantity_delta < 0 then raise exception 'Entradas precisam ter quantidade positiva' using errcode = '22023'; end if;
  if p_movement_type in ('consumption', 'sale', 'loss') and p_quantity_delta > 0 then raise exception 'Saídas precisam ter quantidade negativa' using errcode = '22023'; end if;
  if p_unit_cost is not null and p_unit_cost < 0 then raise exception 'Custo unitário inválido' using errcode = '22023'; end if;
  if not exists (select 1 from public.products p where p.id = p_product_id and p.business_id = v_business_id and p.active) then
    raise exception 'Produto não encontrado ou inativo' using errcode = 'P0002';
  end if;
  insert into public.branch_product_stock (business_id, branch_id, product_id, quantity, average_cost)
  values (v_business_id, p_branch_id, p_product_id, 0, 0)
  on conflict (branch_id, product_id) do nothing;
  select * into v_stock from public.branch_product_stock s
  where s.branch_id = p_branch_id and s.product_id = p_product_id for update;
  v_new_quantity := v_stock.quantity + p_quantity_delta;
  if v_new_quantity < 0 then raise exception 'Saldo insuficiente: disponível %', v_stock.quantity using errcode = '22023'; end if;
  v_new_average := v_stock.average_cost;
  if p_quantity_delta > 0 and p_unit_cost is not null then
    if v_new_quantity = 0 then v_new_average := p_unit_cost;
    else v_new_average := round(((v_stock.quantity * v_stock.average_cost) + (p_quantity_delta * p_unit_cost)) / v_new_quantity, 4); end if;
  end if;
  update public.branch_product_stock set quantity = v_new_quantity, average_cost = v_new_average, updated_at = now()
  where branch_id = p_branch_id and product_id = p_product_id;
  update public.products set cost_price = v_new_average where id = p_product_id and p_quantity_delta > 0 and p_unit_cost is not null;
  insert into public.stock_movements (business_id, branch_id, product_id, movement_type, quantity_delta, balance_after, unit_cost, reason, created_by)
  values (v_business_id, p_branch_id, p_product_id, p_movement_type, p_quantity_delta, v_new_quantity, p_unit_cost, nullif(trim(p_reason), ''), auth.uid())
  returning id into v_movement_id;
  insert into public.audit_logs (business_id, user_id, action, entity_type, entity_id, after_data)
  values (v_business_id, auth.uid(), 'inventory.stock_moved', 'stock_movement', v_movement_id, jsonb_build_object('branch_id', p_branch_id, 'product_id', p_product_id, 'delta', p_quantity_delta, 'balance', v_new_quantity));
  return v_movement_id;
end;
$$;

create or replace function public.upsert_commission_rule(
  p_service_id uuid,
  p_professional_id uuid,
  p_rule_type public.commission_rule_type,
  p_value numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_rule_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select s.business_id into v_business_id from public.services s where s.id = p_service_id and s.active;
  if not found then raise exception 'Serviço não encontrado ou inativo' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin']::public.app_role[], null) then
    raise exception 'Sem permissão para configurar comissões' using errcode = '42501';
  end if;
  if p_value is null or p_value < 0 or (p_rule_type = 'percent' and p_value > 100) then
    raise exception 'Valor de comissão inválido' using errcode = '22023';
  end if;
  if p_professional_id is not null and not exists (
    select 1 from public.professionals p where p.id = p_professional_id and p.business_id = v_business_id and p.active
  ) then raise exception 'Profissional não encontrado ou inativo' using errcode = 'P0002'; end if;
  update public.service_commission_rules r set valid_to = now()
  where r.business_id = v_business_id and r.service_id = p_service_id
    and r.professional_id is not distinct from p_professional_id and r.valid_to is null;
  insert into public.service_commission_rules (business_id, service_id, professional_id, rule_type, value, valid_from)
  values (v_business_id, p_service_id, p_professional_id, p_rule_type, p_value, now())
  returning id into v_rule_id;
  insert into public.audit_logs (business_id, user_id, action, entity_type, entity_id, after_data)
  values (v_business_id, auth.uid(), 'commission.rule_set', 'service_commission_rule', v_rule_id, jsonb_build_object('service_id', p_service_id, 'professional_id', p_professional_id, 'rule_type', p_rule_type, 'value', p_value));
  return v_rule_id;
end;
$$;

create or replace function public.close_appointment_checkout(
  p_appointment_id uuid,
  p_discount numeric default 0,
  p_payments jsonb default '[]'::jsonb,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_appointment public.appointments%rowtype;
  v_subtotal numeric(12,2);
  v_discount numeric(12,2) := coalesce(p_discount, 0);
  v_total numeric(12,2);
  v_payment_total numeric(12,2) := 0;
  v_payment jsonb;
  v_method text;
  v_amount numeric(12,2);
  v_checkout_id uuid;
  v_item_id uuid;
  v_line record;
  v_rule public.service_commission_rules%rowtype;
  v_commission_base numeric(12,2);
  v_commission_amount numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select * into v_appointment from public.appointments a where a.id = p_appointment_id for update;
  if not found then raise exception 'Agendamento não encontrado' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_appointment.business_id, array['admin','receptionist']::public.app_role[], v_appointment.branch_id) then
    raise exception 'Sem permissão para fechar esta comanda' using errcode = '42501';
  end if;
  if v_appointment.status in ('completed', 'no_show', 'cancelled') then raise exception 'Este atendimento não pode ser fechado' using errcode = '22023'; end if;
  if exists (select 1 from public.checkouts c where c.appointment_id = p_appointment_id and c.status = 'paid') then
    raise exception 'Este atendimento já possui uma comanda paga' using errcode = '23505';
  end if;
  select coalesce(round(sum(s.price_snapshot), 2), 0) into v_subtotal
  from public.appointment_services s where s.appointment_id = p_appointment_id and s.status not in ('cancelled', 'no_show');
  if v_subtotal <= 0 then raise exception 'O atendimento não possui serviços cobrables' using errcode = '22023'; end if;
  if v_discount < 0 or v_discount >= v_subtotal then raise exception 'O desconto deve ser menor que o subtotal' using errcode = '22023'; end if;
  v_total := round(v_subtotal - v_discount, 2);
  if jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'Informe ao menos uma forma de pagamento' using errcode = '22023'; end if;
  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    v_method := v_payment ->> 'method';
    v_amount := round((v_payment ->> 'amount')::numeric, 2);
    if v_method not in ('pix', 'credit_card', 'debit_card', 'cash', 'bank_transfer', 'other') or v_amount <= 0 then
      raise exception 'Forma ou valor de pagamento inválido' using errcode = '22023';
    end if;
    v_payment_total := v_payment_total + v_amount;
  end loop;
  if abs(v_payment_total - v_total) > 0.009 then raise exception 'A soma dos pagamentos precisa ser igual ao total da comanda' using errcode = '22023'; end if;
  insert into public.checkouts (business_id, branch_id, appointment_id, client_id, subtotal, discount, total, notes, created_by)
  values (v_appointment.business_id, v_appointment.branch_id, v_appointment.id, v_appointment.client_id, v_subtotal, v_discount, v_total, nullif(trim(p_notes), ''), auth.uid())
  returning id into v_checkout_id;
  for v_line in
    select s.*, sv.name as service_name
    from public.appointment_services s
    join public.services sv on sv.id = s.service_id and sv.business_id = s.business_id
    where s.appointment_id = p_appointment_id and s.status not in ('cancelled', 'no_show')
    order by s.starts_at
  loop
    insert into public.checkout_items (business_id, branch_id, checkout_id, appointment_service_id, service_id, professional_id, description, quantity, unit_price, line_total)
    values (v_appointment.business_id, v_appointment.branch_id, v_checkout_id, v_line.id, v_line.service_id, v_line.professional_id, v_line.service_name, 1, v_line.price_snapshot, v_line.price_snapshot)
    returning id into v_item_id;
    select r.* into v_rule
    from public.service_commission_rules r
    where r.business_id = v_appointment.business_id and r.service_id = v_line.service_id
      and (r.professional_id = v_line.professional_id or r.professional_id is null)
      and r.valid_from <= now() and (r.valid_to is null or r.valid_to > now())
    order by (r.professional_id is not null) desc, r.valid_from desc
    limit 1;
    if found then
      v_commission_base := round(v_line.price_snapshot * case when v_subtotal = 0 then 0 else v_total / v_subtotal end, 2);
      v_commission_amount := case when v_rule.rule_type = 'percent'
        then round(v_commission_base * v_rule.value / 100, 2)
        else round(least(v_rule.value, v_commission_base), 2)
      end;
      if v_commission_amount > 0 then
        insert into public.commission_entries (business_id, branch_id, checkout_item_id, professional_id, service_id, commission_rule_id, rule_type, base_amount, rule_value, amount)
        values (v_appointment.business_id, v_appointment.branch_id, v_item_id, v_line.professional_id, v_line.service_id, v_rule.id, v_rule.rule_type, v_commission_base, v_rule.value, v_commission_amount);
      end if;
      update public.appointment_services set commission_type_snapshot = v_rule.rule_type, commission_value_snapshot = v_rule.value where id = v_line.id;
    end if;
  end loop;
  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    insert into public.checkout_payments (business_id, branch_id, checkout_id, payment_method, amount)
    values (v_appointment.business_id, v_appointment.branch_id, v_checkout_id, v_payment ->> 'method', round((v_payment ->> 'amount')::numeric, 2));
  end loop;
  update public.appointment_services set status = 'completed' where appointment_id = p_appointment_id and status not in ('cancelled', 'no_show');
  update public.appointments set status = 'completed', updated_at = now() where id = p_appointment_id;
  insert into public.audit_logs (business_id, user_id, action, entity_type, entity_id, after_data)
  values (v_appointment.business_id, auth.uid(), 'finance.checkout_closed', 'checkout', v_checkout_id, jsonb_build_object('branch_id', v_appointment.branch_id, 'appointment_id', p_appointment_id, 'total', v_total));
  return v_checkout_id;
end;
$$;

create or replace function public.record_expense(
  p_branch_id uuid,
  p_description text,
  p_category text,
  p_amount numeric,
  p_payment_method text,
  p_paid_at timestamptz default now(),
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_expense_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select b.business_id into v_business_id from public.branches b where b.id = p_branch_id and b.active;
  if not found then raise exception 'Unidade não encontrada ou inativa' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin']::public.app_role[], p_branch_id) then
    raise exception 'Sem permissão para registrar despesas nesta unidade' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Valor da despesa inválido' using errcode = '22023'; end if;
  if p_payment_method not in ('pix', 'credit_card', 'debit_card', 'cash', 'bank_transfer', 'other') then raise exception 'Forma de pagamento inválida' using errcode = '22023'; end if;
  insert into public.expenses (business_id, branch_id, description, category, amount, status, paid_at, payment_method, notes, created_by)
  values (v_business_id, p_branch_id, trim(p_description), trim(p_category), round(p_amount, 2), 'paid', coalesce(p_paid_at, now()), p_payment_method, nullif(trim(p_notes), ''), auth.uid())
  returning id into v_expense_id;
  insert into public.audit_logs (business_id, user_id, action, entity_type, entity_id, after_data)
  values (v_business_id, auth.uid(), 'finance.expense_recorded', 'expense', v_expense_id, jsonb_build_object('branch_id', p_branch_id, 'amount', round(p_amount, 2)));
  return v_expense_id;
end;
$$;

create or replace function public.pay_commissions(
  p_branch_id uuid,
  p_professional_id uuid,
  p_entry_ids uuid[],
  p_payment_method text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_amount numeric(12,2);
  v_selected_count integer;
  v_requested_count integer;
  v_payout_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select b.business_id into v_business_id from public.branches b where b.id = p_branch_id and b.active;
  if not found then raise exception 'Unidade não encontrada ou inativa' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin']::public.app_role[], p_branch_id) then
    raise exception 'Sem permissão para registrar repasses nesta unidade' using errcode = '42501';
  end if;
  if p_payment_method not in ('pix', 'bank_transfer', 'cash', 'other') then raise exception 'Forma de pagamento inválida' using errcode = '22023'; end if;
  v_requested_count := coalesce(cardinality(p_entry_ids), 0);
  if v_requested_count = 0 then raise exception 'Selecione ao menos uma comissão pendente' using errcode = '22023'; end if;
  perform 1 from public.commission_entries e
  where e.id = any(p_entry_ids) and e.business_id = v_business_id and e.branch_id = p_branch_id
    and e.professional_id = p_professional_id and e.status = 'pending'
  for update;
  select count(*), coalesce(round(sum(e.amount), 2), 0) into v_selected_count, v_amount
  from public.commission_entries e
  where e.id = any(p_entry_ids) and e.business_id = v_business_id and e.branch_id = p_branch_id
    and e.professional_id = p_professional_id and e.status = 'pending';
  if v_selected_count <> v_requested_count or v_amount <= 0 then raise exception 'Há comissões inválidas, já pagas ou de outro profissional' using errcode = '22023'; end if;
  insert into public.commission_payouts (business_id, branch_id, professional_id, amount, payment_method, notes, created_by)
  values (v_business_id, p_branch_id, p_professional_id, v_amount, p_payment_method, nullif(trim(p_notes), ''), auth.uid())
  returning id into v_payout_id;
  update public.commission_entries set status = 'paid', payout_id = v_payout_id, paid_at = now()
  where id = any(p_entry_ids);
  insert into public.audit_logs (business_id, user_id, action, entity_type, entity_id, after_data)
  values (v_business_id, auth.uid(), 'commission.payout_recorded', 'commission_payout', v_payout_id, jsonb_build_object('branch_id', p_branch_id, 'professional_id', p_professional_id, 'amount', v_amount));
  return v_payout_id;
end;
$$;

alter table public.products enable row level security;
alter table public.branch_product_stock enable row level security;
alter table public.stock_movements enable row level security;
alter table public.checkouts enable row level security;
alter table public.checkout_items enable row level security;
alter table public.checkout_payments enable row level security;
alter table public.expenses enable row level security;
alter table public.commission_payouts enable row level security;
alter table public.commission_entries enable row level security;

create policy products_read_member on public.products for select to authenticated using (
  public.has_any_business_role(business_id, array['admin','professional','receptionist']::public.app_role[])
);
create policy products_manage_admin on public.products for all to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], null)
) with check (
  public.has_business_role(business_id, array['admin']::public.app_role[], null)
);

create policy branch_stock_read_admin on public.branch_product_stock for select to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
);
create policy branch_stock_manage_admin on public.branch_product_stock for all to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
) with check (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
);

create policy stock_movements_read_admin on public.stock_movements for select to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
);

create policy checkouts_read_frontdesk on public.checkouts for select to authenticated using (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id)
);
create policy checkout_items_read_frontdesk on public.checkout_items for select to authenticated using (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id)
);
create policy checkout_payments_read_admin on public.checkout_payments for select to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
);
create policy expenses_read_admin on public.expenses for select to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
);

create policy commission_payouts_read_scoped on public.commission_payouts for select to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
  or exists (
    select 1 from public.business_memberships m
    where m.business_id = commission_payouts.business_id and m.user_id = auth.uid()
      and m.role = 'professional' and m.professional_id = commission_payouts.professional_id
      and (m.branch_id is null or m.branch_id = commission_payouts.branch_id)
  )
);
create policy commission_entries_read_scoped on public.commission_entries for select to authenticated using (
  public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
  or exists (
    select 1 from public.business_memberships m
    where m.business_id = commission_entries.business_id and m.user_id = auth.uid()
      and m.role = 'professional' and m.professional_id = commission_entries.professional_id
      and (m.branch_id is null or m.branch_id = commission_entries.branch_id)
  )
);

revoke all on public.products, public.branch_product_stock, public.stock_movements from anon, authenticated;
revoke all on public.checkouts, public.checkout_items, public.checkout_payments, public.expenses from anon, authenticated;
revoke all on public.commission_payouts, public.commission_entries from anon, authenticated;

grant select on public.products, public.branch_product_stock, public.stock_movements to authenticated;
grant select on public.checkouts, public.checkout_items, public.checkout_payments, public.expenses to authenticated;
grant select on public.commission_payouts, public.commission_entries to authenticated;

grant execute on function public.create_inventory_product(uuid, text, text, text, text, numeric, numeric, numeric, numeric) to authenticated;
grant execute on function public.record_stock_movement(uuid, uuid, text, numeric, numeric, text) to authenticated;
grant execute on function public.upsert_commission_rule(uuid, uuid, public.commission_rule_type, numeric) to authenticated;
grant execute on function public.close_appointment_checkout(uuid, numeric, jsonb, text) to authenticated;
grant execute on function public.record_expense(uuid, text, text, numeric, text, timestamptz, text) to authenticated;
grant execute on function public.pay_commissions(uuid, uuid, uuid[], text, text) to authenticated;

revoke all on function public.create_inventory_product(uuid, text, text, text, text, numeric, numeric, numeric, numeric) from public, anon;
revoke all on function public.record_stock_movement(uuid, uuid, text, numeric, numeric, text) from public, anon;
revoke all on function public.upsert_commission_rule(uuid, uuid, public.commission_rule_type, numeric) from public, anon;
revoke all on function public.close_appointment_checkout(uuid, numeric, jsonb, text) from public, anon;
revoke all on function public.record_expense(uuid, text, text, numeric, text, timestamptz, text) from public, anon;
revoke all on function public.pay_commissions(uuid, uuid, uuid[], text, text) from public, anon;

commit;
