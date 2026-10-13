begin;

-- Uma única cor-base gera a paleta visual da empresa no frontend.
alter table public.businesses
  add column theme_primary_color text not null default '#193B35';

alter table public.businesses
  add constraint businesses_theme_primary_color_format
  check (theme_primary_color ~ '^#[0-9A-F]{6}$');

comment on column public.businesses.theme_primary_color is
  'Cor hexadecimal base da identidade visual compartilhada pela empresa.';

create or replace function public.update_business_theme(
  p_business_id uuid,
  p_theme_primary_color text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_color text := upper(trim(coalesce(p_theme_primary_color, '')));
  v_previous_color text;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória' using errcode = '28000';
  end if;

  if not public.has_business_role(
    p_business_id,
    array['admin']::public.app_role[],
    null
  ) then
    raise exception 'Somente administradores podem personalizar as cores da empresa'
      using errcode = '42501';
  end if;

  if v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'Cor em formato inválido' using errcode = '22023';
  end if;

  select b.theme_primary_color
    into v_previous_color
  from public.businesses b
  where b.id = p_business_id
  for update;

  if not found then
    raise exception 'Empresa não encontrada' using errcode = 'P0002';
  end if;

  if v_previous_color is distinct from v_color then
    update public.businesses
    set theme_primary_color = v_color,
        updated_at = now()
    where id = p_business_id;

    insert into public.audit_logs (
      business_id,
      user_id,
      action,
      entity_type,
      entity_id,
      before_data,
      after_data
    ) values (
      p_business_id,
      auth.uid(),
      'business.theme_updated',
      'business',
      p_business_id,
      jsonb_build_object('theme_primary_color', v_previous_color),
      jsonb_build_object('theme_primary_color', v_color)
    );
  end if;

  return v_color;
end;
$$;

revoke all on function public.update_business_theme(uuid, text)
  from public, anon, authenticated;
grant execute on function public.update_business_theme(uuid, text)
  to authenticated;

commit;
