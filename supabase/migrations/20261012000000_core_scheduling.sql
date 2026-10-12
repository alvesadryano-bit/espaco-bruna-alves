-- Esquema inicial do Espaço Bruna Alves para Supabase (PostgreSQL).
-- RLS é a fronteira de autorização: a chave anon pode estar no navegador; a service_role nunca.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create type public.app_role as enum ('admin', 'professional', 'receptionist');
create type public.appointment_status as enum ('scheduled', 'confirmed', 'in_service', 'completed', 'no_show', 'cancelled');
create type public.waitlist_status as enum ('waiting', 'scheduled', 'cancelled');
create type public.commission_rule_type as enum ('percent', 'fixed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  email text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(new.email, ''), '@', 1)),
    new.email
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 140),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  timezone text not null default 'America/Sao_Paulo',
  currency char(3) not null default 'BRL',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  timezone text not null default 'America/Sao_Paulo',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, name),
  unique (id, business_id)
);

create table public.professionals (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, business_id)
);
create unique index professionals_user_business_unique
  on public.professionals (business_id, user_id) where user_id is not null;

create table public.business_memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  branch_id uuid,
  professional_id uuid,
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete cascade,
  check ((role = 'professional' and professional_id is not null) or (role <> 'professional' and professional_id is null))
);
create unique index business_membership_scope_unique
  on public.business_memberships (business_id, user_id, role, coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index business_memberships_user_idx on public.business_memberships (user_id, business_id);

create table public.professional_branches (
  business_id uuid not null references public.businesses(id) on delete cascade,
  professional_id uuid not null,
  branch_id uuid not null,
  active boolean not null default true,
  primary key (professional_id, branch_id),
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete cascade,
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  description text,
  duration_minutes integer not null check (duration_minutes between 5 and 1440),
  default_price numeric(12,2) not null check (default_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name),
  unique (id, business_id)
);

create table public.professional_services (
  business_id uuid not null references public.businesses(id) on delete cascade,
  professional_id uuid not null,
  service_id uuid not null,
  active boolean not null default true,
  primary key (professional_id, service_id),
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete cascade,
  foreign key (service_id, business_id) references public.services(id, business_id) on delete cascade
);

create table public.service_commission_rules (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  service_id uuid not null,
  professional_id uuid,
  rule_type public.commission_rule_type not null,
  value numeric(10,4) not null check (value >= 0),
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  created_at timestamptz not null default now(),
  foreign key (service_id, business_id) references public.services(id, business_id) on delete cascade,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete cascade,
  check (valid_to is null or valid_to > valid_from),
  check (rule_type <> 'percent' or value <= 100)
);
create index service_commission_lookup_idx on public.service_commission_rules (business_id, service_id, professional_id, valid_from desc);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 140),
  phone_e164 text not null,
  email text,
  birth_date date,
  notes text,
  marketing_opt_in boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, phone_e164),
  unique (id, business_id)
);
create index clients_business_name_idx on public.clients (business_id, lower(name));

create table public.client_consents (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid not null,
  purpose text not null check (purpose in ('marketing', 'whatsapp', 'sms', 'photo')),
  channel text,
  granted boolean not null,
  captured_at timestamptz not null default now(),
  captured_by uuid default auth.uid() references auth.users(id) on delete set null,
  revoked_at timestamptz,
  foreign key (client_id, business_id) references public.clients(id, business_id) on delete cascade
);

create table public.client_allergies (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid not null,
  allergen text not null,
  severity text,
  notes text,
  created_at timestamptz not null default now(),
  foreign key (client_id, business_id) references public.clients(id, business_id) on delete cascade
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  client_id uuid not null,
  status public.appointment_status not null default 'scheduled',
  source text not null default 'staff',
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete restrict,
  foreign key (client_id, business_id) references public.clients(id, business_id) on delete restrict,
  unique (id, business_id, branch_id)
);
create index appointments_branch_created_idx on public.appointments (business_id, branch_id, created_at desc);
create index appointments_client_idx on public.appointments (business_id, client_id, created_at desc);

create table public.appointment_services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  appointment_id uuid not null,
  service_id uuid not null,
  professional_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.appointment_status not null default 'scheduled',
  duration_snapshot integer not null,
  price_snapshot numeric(12,2) not null,
  commission_type_snapshot public.commission_rule_type,
  commission_value_snapshot numeric(10,4),
  created_at timestamptz not null default now(),
  foreign key (appointment_id, business_id, branch_id) references public.appointments(id, business_id, branch_id) on delete cascade,
  foreign key (service_id, business_id) references public.services(id, business_id) on delete restrict,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete restrict,
  unique (id, business_id),
  check (ends_at > starts_at),
  check (duration_snapshot > 0),
  check (price_snapshot >= 0)
);
create index appointment_services_calendar_idx on public.appointment_services (business_id, branch_id, professional_id, starts_at);
-- btree_gist foi instalado no schema extensions; incluí-lo explicitamente no caminho para resolver gist_uuid_ops.
set search_path to public, extensions;
alter table public.appointment_services
  add constraint appointment_services_no_professional_overlap
  exclude using gist (
    professional_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('scheduled', 'confirmed', 'in_service'));
reset search_path;

create table public.professional_time_blocks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  branch_id uuid not null,
  professional_id uuid not null,
  block_type text not null check (block_type in ('break', 'day_off', 'leave', 'other')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete cascade,
  check (ends_at > starts_at)
);
create index professional_time_blocks_calendar_idx on public.professional_time_blocks (professional_id, starts_at, ends_at);

create table public.waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  client_id uuid not null,
  service_id uuid not null,
  preferred_professional_id uuid,
  time_preference text not null default 'any' check (time_preference in ('any', 'morning', 'afternoon', 'evening')),
  status public.waitlist_status not null default 'waiting',
  notes text,
  scheduled_appointment_id uuid,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (client_id, business_id) references public.clients(id, business_id) on delete cascade,
  foreign key (service_id, business_id) references public.services(id, business_id) on delete restrict,
  foreign key (preferred_professional_id, business_id) references public.professionals(id, business_id) on delete restrict,
  foreign key (scheduled_appointment_id, business_id, branch_id) references public.appointments(id, business_id, branch_id) on delete restrict,
  check (status <> 'scheduled' or scheduled_appointment_id is not null)
);
create index waitlist_branch_status_idx on public.waitlist_entries (business_id, branch_id, status, created_at);

create table public.client_formula_records (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid not null,
  appointment_service_id uuid,
  formula_notes text not null,
  performed_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  foreign key (client_id, business_id) references public.clients(id, business_id) on delete cascade,
  foreign key (appointment_service_id, business_id) references public.appointment_services(id, business_id) on delete restrict
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default now()
);
create index audit_logs_business_time_idx on public.audit_logs (business_id, occurred_at desc);

-- Helpers de autorização: SECURITY DEFINER evita recursão das policies de memberships.
create or replace function public.has_business_role(p_business_id uuid, p_roles public.app_role[], p_branch_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_memberships m
    where m.business_id = p_business_id
      and m.user_id = auth.uid()
      and m.role = any(p_roles)
      and (m.branch_id is null or (p_branch_id is not null and m.branch_id = p_branch_id))
  );
$$;

create or replace function public.has_any_business_role(p_business_id uuid, p_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_memberships m
    where m.business_id = p_business_id and m.user_id = auth.uid() and m.role = any(p_roles)
  );
$$;

create or replace function public.can_read_appointment(p_business_id uuid, p_branch_id uuid, p_appointment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_business_role(p_business_id, array['admin','receptionist']::public.app_role[], p_branch_id)
    or exists (
      select 1
      from public.appointment_services s
      join public.business_memberships m
        on m.business_id = s.business_id
       and m.professional_id = s.professional_id
       and m.user_id = auth.uid()
       and m.role = 'professional'
      where s.business_id = p_business_id
        and s.branch_id = p_branch_id
        and s.appointment_id = p_appointment_id
        and (m.branch_id is null or m.branch_id = p_branch_id)
    );
$$;

create or replace function public.can_read_client(p_business_id uuid, p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_memberships m
    where m.business_id = p_business_id and m.user_id = auth.uid()
      and m.role = 'admin' and m.branch_id is null
  )
  or exists (
    select 1
    from public.appointments a
    join public.business_memberships m on m.business_id = a.business_id and m.user_id = auth.uid()
    where a.business_id = p_business_id and a.client_id = p_client_id
      and m.role in ('admin','receptionist')
      and (m.branch_id is null or m.branch_id = a.branch_id)
  )
  or exists (
    select 1
    from public.appointments a
    join public.appointment_services s on s.appointment_id = a.id and s.business_id = a.business_id
    join public.business_memberships m
      on m.business_id = s.business_id
     and m.professional_id = s.professional_id
     and m.user_id = auth.uid()
     and m.role = 'professional'
    where a.business_id = p_business_id and a.client_id = p_client_id
      and (m.branch_id is null or m.branch_id = a.branch_id)
  );
$$;

create or replace function public.create_first_business(p_name text, p_slug text, p_branch_name text default 'Unidade principal')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_branch_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  if exists (select 1 from public.business_memberships m where m.user_id = auth.uid()) then
    raise exception 'Este usuário já está vinculado a uma empresa' using errcode = '23505';
  end if;
  insert into public.businesses (owner_user_id, name, slug)
  values (auth.uid(), trim(p_name), lower(trim(p_slug)))
  returning id into v_business_id;
  insert into public.branches (business_id, name)
  values (v_business_id, coalesce(nullif(trim(p_branch_name), ''), 'Unidade principal'))
  returning id into v_branch_id;
  insert into public.business_memberships (business_id, user_id, role, branch_id)
  values (v_business_id, auth.uid(), 'admin', null);
  return v_business_id;
end;
$$;

create or replace function public.schedule_waitlist_entry(
  p_waitlist_entry_id uuid,
  p_professional_id uuid,
  p_starts_at timestamptz,
  p_service_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_waitlist public.waitlist_entries%rowtype;
  v_service public.services%rowtype;
  v_ends_at timestamptz;
  v_appointment_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select * into v_waitlist
  from public.waitlist_entries w
  where w.id = p_waitlist_entry_id and w.status = 'waiting'
  for update;
  if not found then raise exception 'A cliente não está mais na fila' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_waitlist.business_id, array['admin','receptionist']::public.app_role[], v_waitlist.branch_id) then
    raise exception 'Sem permissão para agendar nesta unidade' using errcode = '42501';
  end if;
  if p_starts_at is null or p_starts_at <= now() then
    raise exception 'O horário precisa ser futuro' using errcode = '22007';
  end if;
  select * into v_service
  from public.services s
  where s.id = coalesce(p_service_id, v_waitlist.service_id)
    and s.business_id = v_waitlist.business_id and s.active;
  if not found then raise exception 'Serviço não encontrado ou inativo' using errcode = 'P0002'; end if;
  if not exists (
    select 1 from public.professionals p
    join public.professional_branches pb on pb.professional_id = p.id and pb.business_id = p.business_id
    join public.professional_services ps on ps.professional_id = p.id and ps.business_id = p.business_id
    where p.id = p_professional_id and p.business_id = v_waitlist.business_id and p.active
      and pb.branch_id = v_waitlist.branch_id and pb.active
      and ps.service_id = v_service.id and ps.active
  ) then
    raise exception 'Profissional não habilitado para este serviço/unidade' using errcode = '22023';
  end if;
  v_ends_at := p_starts_at + make_interval(mins => v_service.duration_minutes);
  if exists (
    select 1 from public.professional_time_blocks b
    where b.professional_id = p_professional_id and b.branch_id = v_waitlist.branch_id
      and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts_at, v_ends_at, '[)')
  ) then
    raise exception 'Horário bloqueado para este profissional' using errcode = '23P01';
  end if;
  insert into public.appointments (business_id, branch_id, client_id, status, source, notes, created_by)
  values (v_waitlist.business_id, v_waitlist.branch_id, v_waitlist.client_id, 'scheduled', 'kanban', v_waitlist.notes, auth.uid())
  returning id into v_appointment_id;
  insert into public.appointment_services (business_id, branch_id, appointment_id, service_id, professional_id, starts_at, ends_at, status, duration_snapshot, price_snapshot)
  values (v_waitlist.business_id, v_waitlist.branch_id, v_appointment_id, v_service.id, p_professional_id, p_starts_at, v_ends_at, 'scheduled', v_service.duration_minutes, v_service.default_price);
  update public.waitlist_entries
  set status = 'scheduled', scheduled_appointment_id = v_appointment_id, service_id = v_service.id, updated_at = now()
  where id = v_waitlist.id;
  return v_appointment_id;
end;
$$;

create or replace function public.create_appointment(
  p_branch_id uuid,
  p_client_id uuid,
  p_service_id uuid,
  p_professional_id uuid,
  p_starts_at timestamptz,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_service public.services%rowtype;
  v_ends_at timestamptz;
  v_appointment_id uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select b.business_id into v_business_id from public.branches b where b.id = p_branch_id and b.active;
  if not found then raise exception 'Unidade não encontrada ou inativa' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin','receptionist']::public.app_role[], p_branch_id) then
    raise exception 'Sem permissão para agendar nesta unidade' using errcode = '42501';
  end if;
  if p_starts_at is null or p_starts_at <= now() then raise exception 'O horário precisa ser futuro' using errcode = '22007'; end if;
  if not exists (select 1 from public.clients c where c.id = p_client_id and c.business_id = v_business_id) then
    raise exception 'Cliente não encontrada nesta empresa' using errcode = 'P0002';
  end if;
  select s.* into v_service from public.services s
  where s.id = p_service_id and s.business_id = v_business_id and s.active;
  if not found then raise exception 'Serviço não encontrado ou inativo' using errcode = 'P0002'; end if;
  if not exists (
    select 1 from public.professionals p
    join public.professional_branches pb on pb.professional_id = p.id and pb.business_id = p.business_id
    join public.professional_services ps on ps.professional_id = p.id and ps.business_id = p.business_id
    where p.id = p_professional_id and p.business_id = v_business_id and p.active
      and pb.branch_id = p_branch_id and pb.active and ps.service_id = v_service.id and ps.active
  ) then raise exception 'Profissional não habilitado para este serviço/unidade' using errcode = '22023'; end if;
  v_ends_at := p_starts_at + make_interval(mins => v_service.duration_minutes);
  if exists (
    select 1 from public.professional_time_blocks b
    where b.professional_id = p_professional_id and b.branch_id = p_branch_id
      and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts_at, v_ends_at, '[)')
  ) then raise exception 'Horário bloqueado para este profissional' using errcode = '23P01'; end if;
  insert into public.appointments (business_id, branch_id, client_id, status, source, notes, created_by)
  values (v_business_id, p_branch_id, p_client_id, 'scheduled', 'staff', nullif(trim(p_notes), ''), auth.uid())
  returning id into v_appointment_id;
  insert into public.appointment_services (business_id, branch_id, appointment_id, service_id, professional_id, starts_at, ends_at, status, duration_snapshot, price_snapshot)
  values (v_business_id, p_branch_id, v_appointment_id, v_service.id, p_professional_id, p_starts_at, v_ends_at, 'scheduled', v_service.duration_minutes, v_service.default_price);
  return v_appointment_id;
end;
$$;

create or replace function public.move_appointment(p_appointment_id uuid, p_new_starts_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_branch_id uuid;
  v_status public.appointment_status;
  v_old_start timestamptz;
  v_shift interval;
begin
  if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode = '28000'; end if;
  select a.business_id, a.branch_id, a.status into v_business_id, v_branch_id, v_status
  from public.appointments a where a.id = p_appointment_id;
  if not found then raise exception 'Agendamento não encontrado' using errcode = 'P0002'; end if;
  if not public.has_business_role(v_business_id, array['admin','receptionist']::public.app_role[], v_branch_id) then
    raise exception 'Sem permissão para reagendar nesta unidade' using errcode = '42501';
  end if;
  if v_status in ('completed','no_show','cancelled') then raise exception 'Este atendimento não pode ser movido' using errcode = '22023'; end if;
  if p_new_starts_at is null or p_new_starts_at <= now() then raise exception 'O novo horário precisa ser futuro' using errcode = '22007'; end if;
  select min(s.starts_at) into v_old_start from public.appointment_services s where s.appointment_id = p_appointment_id;
  if v_old_start is null then raise exception 'Agendamento sem serviço vinculado' using errcode = 'P0002'; end if;
  v_shift := p_new_starts_at - v_old_start;
  if exists (
    select 1 from public.appointment_services s
    join public.professional_time_blocks b on b.professional_id = s.professional_id and b.branch_id = s.branch_id
    where s.appointment_id = p_appointment_id
      and tstzrange(s.starts_at + v_shift, s.ends_at + v_shift, '[)') && tstzrange(b.starts_at, b.ends_at, '[)')
  ) then raise exception 'O novo horário conflita com um bloqueio' using errcode = '23P01'; end if;
  update public.appointment_services set starts_at = starts_at + v_shift, ends_at = ends_at + v_shift where appointment_id = p_appointment_id;
  update public.appointments set updated_at = now() where id = p_appointment_id;
  return p_appointment_id;
end;
$$;

-- Row Level Security: toda regra abaixo continua valendo mesmo com a chave anon no navegador.
alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.branches enable row level security;
alter table public.professionals enable row level security;
alter table public.business_memberships enable row level security;
alter table public.professional_branches enable row level security;
alter table public.services enable row level security;
alter table public.professional_services enable row level security;
alter table public.service_commission_rules enable row level security;
alter table public.clients enable row level security;
alter table public.client_consents enable row level security;
alter table public.client_allergies enable row level security;
alter table public.appointments enable row level security;
alter table public.appointment_services enable row level security;
alter table public.professional_time_blocks enable row level security;
alter table public.waitlist_entries enable row level security;
alter table public.client_formula_records enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_read_self on public.profiles for select to authenticated using (id = auth.uid());
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy businesses_read_member on public.businesses for select to authenticated using (public.has_any_business_role(id, array['admin','professional','receptionist']::public.app_role[]));
create policy businesses_update_admin on public.businesses for update to authenticated using (public.has_business_role(id, array['admin']::public.app_role[], null)) with check (public.has_business_role(id, array['admin']::public.app_role[], null));

create policy branches_read_member on public.branches for select to authenticated using (public.has_business_role(business_id, array['admin','professional','receptionist']::public.app_role[], id));
create policy branches_insert_admin on public.branches for insert to authenticated with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));
create policy branches_update_admin on public.branches for update to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));

create policy professionals_read_team on public.professionals for select to authenticated using (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], null)
  or exists (
    select 1 from public.professional_branches pb
    where pb.business_id = professionals.business_id and pb.professional_id = professionals.id
      and public.has_business_role(pb.business_id, array['admin','receptionist']::public.app_role[], pb.branch_id)
  )
  or user_id = auth.uid()
  or exists (select 1 from public.business_memberships m where m.business_id = professionals.business_id and m.user_id = auth.uid() and m.professional_id = professionals.id and m.role = 'professional')
);
create policy professionals_manage_admin on public.professionals for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));

create policy memberships_read_self_or_admin on public.business_memberships for select to authenticated using (
  user_id = auth.uid() or public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)
);
create policy memberships_manage_admin on public.business_memberships for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], branch_id));

create policy professional_branches_read_team on public.professional_branches for select to authenticated using (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id)
  or exists (select 1 from public.business_memberships m where m.business_id = professional_branches.business_id and m.user_id = auth.uid() and m.professional_id = professional_branches.professional_id and m.role = 'professional' and (m.branch_id is null or m.branch_id = professional_branches.branch_id))
);
create policy professional_branches_manage_admin on public.professional_branches for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));

create policy services_read_member on public.services for select to authenticated using (public.has_any_business_role(business_id, array['admin','professional','receptionist']::public.app_role[]));
create policy services_manage_admin on public.services for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));

create policy professional_services_read_team on public.professional_services for select to authenticated using (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], null)
  or exists (
    select 1 from public.professional_branches pb
    where pb.business_id = professional_services.business_id and pb.professional_id = professional_services.professional_id
      and public.has_business_role(pb.business_id, array['admin','receptionist']::public.app_role[], pb.branch_id)
  )
  or exists (select 1 from public.business_memberships m where m.business_id = professional_services.business_id and m.user_id = auth.uid() and m.professional_id = professional_services.professional_id and m.role = 'professional')
);
create policy professional_services_manage_admin on public.professional_services for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));

create policy commission_rules_admin_only on public.service_commission_rules for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], null));

create policy clients_read_scoped on public.clients for select to authenticated using (public.can_read_client(business_id, id));
create policy clients_insert_frontdesk on public.clients for insert to authenticated with check (
  public.has_any_business_role(business_id, array['admin','receptionist']::public.app_role[])
  and created_by = auth.uid()
);
create policy clients_update_scoped_frontdesk on public.clients for update to authenticated using (
  public.can_read_client(business_id, id) and public.has_any_business_role(business_id, array['admin','receptionist']::public.app_role[])
) with check (
  public.can_read_client(business_id, id) and public.has_any_business_role(business_id, array['admin','receptionist']::public.app_role[])
);

create policy client_consents_read_scoped on public.client_consents for select to authenticated using (public.can_read_client(business_id, client_id));
create policy client_consents_manage_frontdesk on public.client_consents for all to authenticated using (
  public.can_read_client(business_id, client_id) and public.has_any_business_role(business_id, array['admin','receptionist']::public.app_role[])
) with check (
  public.can_read_client(business_id, client_id) and public.has_any_business_role(business_id, array['admin','receptionist']::public.app_role[])
);

create policy client_allergies_read_scoped on public.client_allergies for select to authenticated using (public.can_read_client(business_id, client_id));
create policy client_allergies_write_member on public.client_allergies for all to authenticated using (public.can_read_client(business_id, client_id) and public.has_any_business_role(business_id, array['admin','professional','receptionist']::public.app_role[])) with check (public.can_read_client(business_id, client_id) and public.has_any_business_role(business_id, array['admin','professional','receptionist']::public.app_role[]));

create policy appointments_read_scoped on public.appointments for select to authenticated using (public.can_read_appointment(business_id, branch_id, id));
create policy appointment_services_read_scoped on public.appointment_services for select to authenticated using (public.can_read_appointment(business_id, branch_id, appointment_id));
-- Gravações e reagendamentos passam por RPC transacional; não expor INSERT/UPDATE direto ao navegador.

create policy time_blocks_read_scoped on public.professional_time_blocks for select to authenticated using (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id)
  or exists (select 1 from public.business_memberships m where m.business_id = professional_time_blocks.business_id and m.user_id = auth.uid() and m.professional_id = professional_time_blocks.professional_id and m.role = 'professional' and (m.branch_id is null or m.branch_id = professional_time_blocks.branch_id))
);
create policy time_blocks_manage_admin on public.professional_time_blocks for all to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], branch_id)) with check (public.has_business_role(business_id, array['admin']::public.app_role[], branch_id));

create policy waitlist_read_frontdesk on public.waitlist_entries for select to authenticated using (public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id));
create policy waitlist_create_frontdesk on public.waitlist_entries for insert to authenticated with check (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id)
  and created_by = auth.uid()
);
create policy waitlist_update_frontdesk on public.waitlist_entries for update to authenticated
using (public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id))
with check (
  public.has_business_role(business_id, array['admin','receptionist']::public.app_role[], branch_id)
  and (
    status <> 'scheduled'
    or exists (
      select 1 from public.appointments a
      where a.id = waitlist_entries.scheduled_appointment_id
        and a.business_id = waitlist_entries.business_id
        and a.branch_id = waitlist_entries.branch_id
        and a.client_id = waitlist_entries.client_id
    )
  )
);

create policy formulas_read_scoped on public.client_formula_records for select to authenticated using (public.can_read_client(business_id, client_id));
create policy formulas_write_member on public.client_formula_records for all to authenticated using (public.can_read_client(business_id, client_id) and public.has_any_business_role(business_id, array['admin','professional']::public.app_role[])) with check (public.can_read_client(business_id, client_id) and public.has_any_business_role(business_id, array['admin','professional']::public.app_role[]));

create policy audit_logs_admin_read on public.audit_logs for select to authenticated using (public.has_business_role(business_id, array['admin']::public.app_role[], null));

-- Supabase authenticated role receives only table privileges; RLS policies above define row scope.
grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, update on public.businesses to authenticated;
grant select, insert, update on public.branches to authenticated;
grant select, insert, update, delete on public.professionals, public.business_memberships, public.professional_branches to authenticated;
grant select, insert, update, delete on public.services, public.professional_services, public.service_commission_rules to authenticated;
grant select, insert, update on public.clients, public.client_consents, public.client_allergies, public.client_formula_records to authenticated;
grant select on public.appointments, public.appointment_services to authenticated;
grant select, insert, update on public.professional_time_blocks, public.waitlist_entries to authenticated;
grant select on public.audit_logs to authenticated;

grant execute on function public.has_business_role(uuid, public.app_role[], uuid) to authenticated;
grant execute on function public.has_any_business_role(uuid, public.app_role[]) to authenticated;
grant execute on function public.can_read_appointment(uuid, uuid, uuid) to authenticated;
grant execute on function public.can_read_client(uuid, uuid) to authenticated;
grant execute on function public.create_first_business(text, text, text) to authenticated;
grant execute on function public.create_appointment(uuid, uuid, uuid, uuid, timestamptz, text) to authenticated;
grant execute on function public.move_appointment(uuid, timestamptz) to authenticated;
grant execute on function public.schedule_waitlist_entry(uuid, uuid, timestamptz, uuid) to authenticated;
revoke all on function public.create_first_business(text, text, text) from public, anon;
revoke all on function public.create_appointment(uuid, uuid, uuid, uuid, timestamptz, text) from public, anon;
revoke all on function public.move_appointment(uuid, timestamptz) from public, anon;
revoke all on function public.schedule_waitlist_entry(uuid, uuid, timestamptz, uuid) from public, anon;
