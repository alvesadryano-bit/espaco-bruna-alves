begin;

alter table public.user_invitations
  add column display_name text;

update public.user_invitations i
set display_name = coalesce(
  (
    select nullif(trim(p.display_name), '')
    from public.professionals p
    where p.id = i.professional_id
      and p.business_id = i.business_id
  ),
  case
    when char_length(trim(replace(replace(split_part(i.email, '@', 1), '.', ' '), '_', ' '))) >= 2
      then initcap(trim(replace(replace(split_part(i.email, '@', 1), '.', ' '), '_', ' ')))
    else 'Usuário convidado'
  end
)
where i.display_name is null;

alter table public.user_invitations
  alter column display_name set not null;

alter table public.user_invitations
  add constraint user_invitations_display_name_check
  check (char_length(trim(display_name)) between 2 and 100);

-- O retorno passa a incluir o nome definido pela administração.
revoke all on function public.get_user_invitation(uuid) from public, anon, authenticated;
drop function public.get_user_invitation(uuid);

create function public.get_user_invitation(p_token uuid)
returns table (
  invitation_id uuid,
  display_name text,
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
  select i.id, i.display_name, i.email, i.role, b.name, i.expires_at
  from public.user_invitations i
  join public.businesses b on b.id = i.business_id
  where i.token = p_token
    and i.accepted_at is null
    and i.revoked_at is null
    and i.expires_at > now()
  limit 1;
$$;

-- A assinatura inclui o nome. Profissional sem ID existente é criado automaticamente.
revoke all on function public.create_user_invitation(uuid, text, public.app_role, uuid, uuid) from public, anon, authenticated;
drop function public.create_user_invitation(uuid, text, public.app_role, uuid, uuid);

create function public.create_user_invitation(
  p_business_id uuid,
  p_display_name text,
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
  v_display_name text := trim(coalesce(p_display_name, ''));
  v_email text := lower(trim(coalesce(p_email, '')));
  v_professional_id uuid := p_professional_id;
  v_created_professional boolean := false;
  v_invitation public.user_invitations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória' using errcode = '28000';
  end if;
  if not public.has_business_role(p_business_id, array['admin']::public.app_role[], null) then
    raise exception 'Somente administradores podem convidar usuários' using errcode = '42501';
  end if;
  if char_length(v_display_name) not between 2 and 100 then
    raise exception 'Informe o nome completo da pessoa' using errcode = '22023';
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
    if p_branch_id is null then
      raise exception 'Selecione a unidade do profissional' using errcode = '22023';
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

  if p_role = 'professional' then
    if v_professional_id is null then
      insert into public.professionals (business_id, display_name, active)
      values (p_business_id, v_display_name, true)
      returning id into v_professional_id;
      v_created_professional := true;
    else
      if exists (
        select 1 from public.user_invitations i
        where i.business_id = p_business_id
          and i.professional_id = v_professional_id
          and i.accepted_at is null
          and i.revoked_at is null
      ) then
        raise exception 'Este profissional já possui um convite pendente' using errcode = '23505';
      end if;
      perform 1
      from public.professionals p
      where p.id = v_professional_id
        and p.business_id = p_business_id
        and p.active
        and p.user_id is null;
      if not found then
        raise exception 'Profissional inválido ou já vinculado a outro acesso' using errcode = '23505';
      end if;
    end if;

    insert into public.professional_branches (
      business_id, professional_id, branch_id, active
    ) values (
      p_business_id, v_professional_id, p_branch_id, true
    )
    on conflict (professional_id, branch_id)
    do update set active = true;
  else
    v_professional_id := null;
  end if;

  insert into public.user_invitations (
    business_id, display_name, email, role, branch_id, professional_id, created_by
  ) values (
    p_business_id,
    v_display_name,
    v_email,
    p_role,
    case when p_role = 'admin' then null else p_branch_id end,
    v_professional_id,
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
      'display_name', v_invitation.display_name,
      'email', v_invitation.email,
      'role', v_invitation.role,
      'branch_id', v_invitation.branch_id,
      'professional_id', v_invitation.professional_id,
      'professional_created', v_created_professional,
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

  insert into public.profiles (id, display_name, email)
  values (auth.uid(), v_invitation.display_name, v_auth_email)
  on conflict (id) do update
    set display_name = excluded.display_name,
        email = excluded.email,
        updated_at = now();

  if v_invitation.professional_id is not null then
    update public.professionals
    set user_id = auth.uid(), display_name = v_invitation.display_name
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
    jsonb_build_object(
      'display_name', v_invitation.display_name,
      'role', v_invitation.role,
      'invitation_id', v_invitation.id
    )
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
    i.display_name,
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

revoke all on function public.get_user_invitation(uuid) from public, anon, authenticated;
revoke all on function public.create_user_invitation(uuid, text, text, public.app_role, uuid, uuid) from public, anon, authenticated;
revoke all on function public.accept_user_invitation(uuid) from public, anon, authenticated;
revoke all on function public.list_business_users(uuid) from public, anon, authenticated;

grant execute on function public.get_user_invitation(uuid) to anon, authenticated;
grant execute on function public.create_user_invitation(uuid, text, text, public.app_role, uuid, uuid) to authenticated;
grant execute on function public.accept_user_invitation(uuid) to authenticated;
grant execute on function public.list_business_users(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
