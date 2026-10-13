begin;

-- Convites administrados pela própria plataforma. Nenhuma chave privilegiada vai para o navegador.
create table public.user_invitations (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  email text not null,
  role public.app_role not null,
  branch_id uuid,
  professional_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  accepted_user_id uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (professional_id, business_id) references public.professionals(id, business_id) on delete cascade,
  constraint user_invitations_email_check check (
    email = lower(trim(email))
    and email ~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$'
  ),
  constraint user_invitations_role_scope_check check (
    (role = 'admin' and branch_id is null and professional_id is null)
    or (role = 'receptionist' and branch_id is not null and professional_id is null)
    or (role = 'professional' and branch_id is not null and professional_id is not null)
  ),
  constraint user_invitations_acceptance_check check (
    (accepted_at is null and accepted_user_id is null)
    or (accepted_at is not null and accepted_user_id is not null)
  )
);

create index user_invitations_business_status_idx
  on public.user_invitations (business_id, created_at desc);
create index user_invitations_email_idx
  on public.user_invitations (lower(email));
create unique index user_invitations_pending_email_unique
  on public.user_invitations (business_id, lower(email))
  where accepted_at is null and revoked_at is null;
create unique index user_invitations_pending_professional_unique
  on public.user_invitations (business_id, professional_id)
  where professional_id is not null and accepted_at is null and revoked_at is null;

alter table public.user_invitations enable row level security;

create policy user_invitations_admin_read
  on public.user_invitations
  for select
  to authenticated
  using (public.has_business_role(business_id, array['admin']::public.app_role[], null));

-- Este projeto é de uma única empresa. A empresa inicial já existe e novas contas entram por convite.
revoke execute on function public.create_first_business(text, text, text) from authenticated;

create or replace function public.get_user_invitation(p_token uuid)
returns table (
  invitation_id uuid,
  email text,
  role public.app_role,
  business_name text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.email, i.role, b.name, i.expires_at
  from public.user_invitations i
  join public.businesses b on b.id = i.business_id
  where i.token = p_token
    and i.accepted_at is null
    and i.revoked_at is null
    and i.expires_at > now()
  limit 1;
$$;

create or replace function public.create_user_invitation(
  p_business_id uuid,
  p_email text,
  p_role public.app_role,
  p_branch_id uuid default null,
  p_professional_id uuid default null
)
returns table (
  invitation_id uuid,
  invitation_token uuid,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_invitation public.user_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória' using errcode = '28000';
  end if;
  if not public.has_business_role(p_business_id, array['admin']::public.app_role[], null) then
    raise exception 'Somente administradores podem convidar usuários' using errcode = '42501';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'Informe um e-mail válido' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.business_memberships m
    join public.profiles p on p.id = m.user_id
    where m.business_id = p_business_id and lower(p.email) = v_email
  ) then
    raise exception 'Este e-mail já possui acesso à empresa' using errcode = '23505';
  end if;

  if p_role = 'admin' then
    if p_branch_id is not null or p_professional_id is not null then
      raise exception 'Administrador não deve ser limitado a uma unidade ou profissional' using errcode = '22023';
    end if;
  elsif p_role = 'receptionist' then
    if p_branch_id is null or p_professional_id is not null then
      raise exception 'Selecione a unidade da recepcionista' using errcode = '22023';
    end if;
  elsif p_role = 'professional' then
    if p_branch_id is null or p_professional_id is null then
      raise exception 'Selecione a unidade e o profissional' using errcode = '22023';
    end if;
  end if;

  if p_branch_id is not null and not exists (
    select 1 from public.branches b
    where b.id = p_branch_id and b.business_id = p_business_id and b.active
  ) then
    raise exception 'Unidade inválida ou inativa' using errcode = '22023';
  end if;

  update public.user_invitations i
  set revoked_at = now(), updated_at = now()
  where i.business_id = p_business_id
    and i.accepted_at is null
    and i.revoked_at is null
    and (i.expires_at <= now() or lower(i.email) = v_email);

  if p_professional_id is not null then
    if exists (
      select 1 from public.user_invitations i
      where i.business_id = p_business_id
        and i.professional_id = p_professional_id
        and i.accepted_at is null
        and i.revoked_at is null
    ) then
      raise exception 'Este profissional já possui um convite pendente' using errcode = '23505';
    end if;
    perform 1
    from public.professionals p
    where p.id = p_professional_id
      and p.business_id = p_business_id
      and p.active
      and p.user_id is null;
    if not found then
      raise exception 'Profissional inválido ou já vinculado a outro acesso' using errcode = '23505';
    end if;
  end if;

  insert into public.user_invitations (
    business_id, email, role, branch_id, professional_id, created_by
  ) values (
    p_business_id,
    v_email,
    p_role,
    case when p_role = 'admin' then null else p_branch_id end,
    case when p_role = 'professional' then p_professional_id else null end,
    auth.uid()
  )
  returning * into v_invitation;

  insert into public.audit_logs (
    business_id, user_id, action, entity_type, entity_id, after_data
  ) values (
    p_business_id,
    auth.uid(),
    'access.invitation_created',
    'user_invitation',
    v_invitation.id,
    jsonb_build_object(
      'email', v_invitation.email,
      'role', v_invitation.role,
      'branch_id', v_invitation.branch_id,
      'professional_id', v_invitation.professional_id,
      'expires_at', v_invitation.expires_at
    )
  );

  return query select v_invitation.id, v_invitation.token, v_invitation.expires_at;
end;
$$;

create or replace function public.accept_user_invitation(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation public.user_invitations%rowtype;
  v_auth_email text;
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória' using errcode = '28000';
  end if;

  select * into v_invitation
  from public.user_invitations i
  where i.token = p_token
  for update;

  if not found then
    raise exception 'Convite não encontrado' using errcode = 'P0002';
  end if;
  if v_invitation.revoked_at is not null then
    raise exception 'Este convite foi revogado' using errcode = '42501';
  end if;
  if v_invitation.accepted_at is not null then
    raise exception 'Este convite já foi utilizado' using errcode = '23505';
  end if;
  if v_invitation.expires_at <= now() then
    raise exception 'Este convite expirou' using errcode = '22023';
  end if;

  select lower(email) into v_auth_email
  from auth.users
  where id = auth.uid();

  if v_auth_email is null or v_auth_email <> lower(v_invitation.email) then
    raise exception 'Entre com o mesmo e-mail informado no convite' using errcode = '42501';
  end if;
  if exists (select 1 from public.business_memberships m where m.user_id = auth.uid()) then
    raise exception 'Esta conta já está vinculada a uma empresa' using errcode = '23505';
  end if;

  if v_invitation.professional_id is not null then
    perform 1
    from public.professionals p
    where p.id = v_invitation.professional_id
      and p.business_id = v_invitation.business_id
      and (p.user_id is null or p.user_id = auth.uid())
    for update;
    if not found then
      raise exception 'O profissional deste convite já está vinculado' using errcode = '23505';
    end if;
  end if;

  insert into public.business_memberships (
    business_id, user_id, role, branch_id, professional_id
  ) values (
    v_invitation.business_id,
    auth.uid(),
    v_invitation.role,
    v_invitation.branch_id,
    v_invitation.professional_id
  )
  returning id into v_membership_id;

  if v_invitation.professional_id is not null then
    update public.professionals
    set user_id = auth.uid()
    where id = v_invitation.professional_id
      and business_id = v_invitation.business_id;
  end if;

  update public.user_invitations
  set accepted_user_id = auth.uid(), accepted_at = now(), updated_at = now()
  where id = v_invitation.id;

  insert into public.audit_logs (
    business_id, user_id, action, entity_type, entity_id, after_data
  ) values (
    v_invitation.business_id,
    auth.uid(),
    'access.invitation_accepted',
    'business_membership',
    v_membership_id,
    jsonb_build_object('role', v_invitation.role, 'invitation_id', v_invitation.id)
  );

  return v_invitation.business_id;
end;
$$;

create or replace function public.list_business_users(p_business_id uuid)
returns table (
  record_type text,
  record_id uuid,
  user_id uuid,
  display_name text,
  email text,
  role public.app_role,
  branch_id uuid,
  branch_name text,
  professional_id uuid,
  professional_name text,
  status text,
  invitation_token uuid,
  created_at timestamptz,
  expires_at timestamptz,
  is_current_user boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória' using errcode = '28000';
  end if;
  if not public.has_business_role(p_business_id, array['admin']::public.app_role[], null) then
    raise exception 'Somente administradores podem visualizar usuários' using errcode = '42501';
  end if;

  return query
  select
    'member'::text,
    m.id,
    m.user_id,
    coalesce(nullif(p.display_name, ''), split_part(coalesce(p.email, ''), '@', 1)),
    coalesce(p.email, ''),
    m.role,
    m.branch_id,
    b.name,
    m.professional_id,
    pro.display_name,
    'active'::text,
    null::uuid,
    m.created_at,
    null::timestamptz,
    m.user_id = auth.uid()
  from public.business_memberships m
  left join public.profiles p on p.id = m.user_id
  left join public.branches b on b.id = m.branch_id and b.business_id = m.business_id
  left join public.professionals pro on pro.id = m.professional_id and pro.business_id = m.business_id
  where m.business_id = p_business_id

  union all

  select
    'invitation'::text,
    i.id,
    null::uuid,
    ''::text,
    i.email,
    i.role,
    i.branch_id,
    b.name,
    i.professional_id,
    pro.display_name,
    case when i.expires_at <= now() then 'expired' else 'pending' end,
    i.token,
    i.created_at,
    i.expires_at,
    false
  from public.user_invitations i
  left join public.branches b on b.id = i.branch_id and b.business_id = i.business_id
  left join public.professionals pro on pro.id = i.professional_id and pro.business_id = i.business_id
  where i.business_id = p_business_id
    and i.accepted_at is null
    and i.revoked_at is null

  order by 1, 13;
end;
$$;

create or replace function public.revoke_user_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation public.user_invitations%rowtype;
begin
  select * into v_invitation
  from public.user_invitations i
  where i.id = p_invitation_id
  for update;

  if not found then
    raise exception 'Convite não encontrado' using errcode = 'P0002';
  end if;
  if not public.has_business_role(v_invitation.business_id, array['admin']::public.app_role[], null) then
    raise exception 'Somente administradores podem revogar convites' using errcode = '42501';
  end if;
  if v_invitation.accepted_at is not null then
    raise exception 'O convite já foi utilizado' using errcode = '23505';
  end if;

  update public.user_invitations
  set revoked_at = coalesce(revoked_at, now()), updated_at = now()
  where id = p_invitation_id;

  insert into public.audit_logs (
    business_id, user_id, action, entity_type, entity_id, before_data
  ) values (
    v_invitation.business_id,
    auth.uid(),
    'access.invitation_revoked',
    'user_invitation',
    v_invitation.id,
    jsonb_build_object('email', v_invitation.email, 'role', v_invitation.role)
  );
end;
$$;

create or replace function public.update_business_user_access(
  p_membership_id uuid,
  p_role public.app_role,
  p_branch_id uuid default null,
  p_professional_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership public.business_memberships%rowtype;
  v_admin_count integer;
begin
  select * into v_membership
  from public.business_memberships m
  where m.id = p_membership_id
  for update;

  if not found then
    raise exception 'Acesso não encontrado' using errcode = 'P0002';
  end if;
  if not public.has_business_role(v_membership.business_id, array['admin']::public.app_role[], null) then
    raise exception 'Somente administradores podem alterar acessos' using errcode = '42501';
  end if;

  if v_membership.role = 'admin' and p_role <> 'admin' then
    select count(*) into v_admin_count
    from public.business_memberships m
    where m.business_id = v_membership.business_id and m.role = 'admin';
    if v_admin_count <= 1 then
      raise exception 'A empresa precisa manter ao menos um administrador' using errcode = '23514';
    end if;
  end if;

  if p_role = 'admin' then
    if p_branch_id is not null or p_professional_id is not null then
      raise exception 'Administrador não deve ser limitado a uma unidade ou profissional' using errcode = '22023';
    end if;
  elsif p_role = 'receptionist' then
    if p_branch_id is null or p_professional_id is not null then
      raise exception 'Selecione a unidade da recepcionista' using errcode = '22023';
    end if;
  elsif p_role = 'professional' then
    if p_branch_id is null or p_professional_id is null then
      raise exception 'Selecione a unidade e o profissional' using errcode = '22023';
    end if;
  end if;

  if p_branch_id is not null and not exists (
    select 1 from public.branches b
    where b.id = p_branch_id
      and b.business_id = v_membership.business_id
      and b.active
  ) then
    raise exception 'Unidade inválida ou inativa' using errcode = '22023';
  end if;

  if p_professional_id is not null then
    if p_professional_id is distinct from v_membership.professional_id and exists (
      select 1 from public.user_invitations i
      where i.business_id = v_membership.business_id
        and i.professional_id = p_professional_id
        and i.accepted_at is null
        and i.revoked_at is null
        and i.expires_at > now()
    ) then
      raise exception 'Este profissional já possui um convite pendente' using errcode = '23505';
    end if;
    perform 1
    from public.professionals p
    where p.id = p_professional_id
      and p.business_id = v_membership.business_id
      and p.active
      and (p.user_id is null or p.user_id = v_membership.user_id)
    for update;
    if not found then
      raise exception 'Profissional inválido ou já vinculado a outro acesso' using errcode = '23505';
    end if;
  end if;

  if v_membership.professional_id is not null
     and (p_role <> 'professional' or v_membership.professional_id <> p_professional_id) then
    update public.professionals
    set user_id = null
    where id = v_membership.professional_id
      and business_id = v_membership.business_id
      and user_id = v_membership.user_id;
  end if;

  update public.business_memberships
  set role = p_role,
      branch_id = case when p_role = 'admin' then null else p_branch_id end,
      professional_id = case when p_role = 'professional' then p_professional_id else null end
  where id = p_membership_id;

  if p_role = 'professional' then
    update public.professionals
    set user_id = v_membership.user_id
    where id = p_professional_id
      and business_id = v_membership.business_id;
  end if;

  insert into public.audit_logs (
    business_id, user_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    v_membership.business_id,
    auth.uid(),
    'access.membership_updated',
    'business_membership',
    p_membership_id,
    jsonb_build_object(
      'role', v_membership.role,
      'branch_id', v_membership.branch_id,
      'professional_id', v_membership.professional_id
    ),
    jsonb_build_object(
      'role', p_role,
      'branch_id', case when p_role = 'admin' then null else p_branch_id end,
      'professional_id', case when p_role = 'professional' then p_professional_id else null end
    )
  );

  return p_membership_id;
end;
$$;

create or replace function public.remove_business_user(p_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membership public.business_memberships%rowtype;
  v_admin_count integer;
begin
  select * into v_membership
  from public.business_memberships m
  where m.id = p_membership_id
  for update;

  if not found then
    raise exception 'Acesso não encontrado' using errcode = 'P0002';
  end if;
  if not public.has_business_role(v_membership.business_id, array['admin']::public.app_role[], null) then
    raise exception 'Somente administradores podem remover acessos' using errcode = '42501';
  end if;
  if v_membership.user_id = auth.uid() then
    raise exception 'Você não pode remover o próprio acesso' using errcode = '23514';
  end if;

  if v_membership.role = 'admin' then
    select count(*) into v_admin_count
    from public.business_memberships m
    where m.business_id = v_membership.business_id and m.role = 'admin';
    if v_admin_count <= 1 then
      raise exception 'A empresa precisa manter ao menos um administrador' using errcode = '23514';
    end if;
  end if;

  delete from public.business_memberships where id = p_membership_id;

  if v_membership.professional_id is not null then
    update public.professionals
    set user_id = null
    where id = v_membership.professional_id
      and business_id = v_membership.business_id
      and user_id = v_membership.user_id;
  end if;

  insert into public.audit_logs (
    business_id, user_id, action, entity_type, entity_id, before_data
  ) values (
    v_membership.business_id,
    auth.uid(),
    'access.membership_removed',
    'business_membership',
    p_membership_id,
    jsonb_build_object(
      'removed_user_id', v_membership.user_id,
      'role', v_membership.role,
      'branch_id', v_membership.branch_id,
      'professional_id', v_membership.professional_id
    )
  );
end;
$$;

revoke all on table public.user_invitations from anon, authenticated;
grant select on table public.user_invitations to authenticated;

revoke all on function public.get_user_invitation(uuid) from public, anon, authenticated;
revoke all on function public.create_user_invitation(uuid, text, public.app_role, uuid, uuid) from public, anon, authenticated;
revoke all on function public.accept_user_invitation(uuid) from public, anon, authenticated;
revoke all on function public.list_business_users(uuid) from public, anon, authenticated;
revoke all on function public.revoke_user_invitation(uuid) from public, anon, authenticated;
revoke all on function public.update_business_user_access(uuid, public.app_role, uuid, uuid) from public, anon, authenticated;
revoke all on function public.remove_business_user(uuid) from public, anon, authenticated;

grant execute on function public.get_user_invitation(uuid) to anon, authenticated;
grant execute on function public.create_user_invitation(uuid, text, public.app_role, uuid, uuid) to authenticated;
grant execute on function public.accept_user_invitation(uuid) to authenticated;
grant execute on function public.list_business_users(uuid) to authenticated;
grant execute on function public.revoke_user_invitation(uuid) to authenticated;
grant execute on function public.update_business_user_access(uuid, public.app_role, uuid, uuid) to authenticated;
grant execute on function public.remove_business_user(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
