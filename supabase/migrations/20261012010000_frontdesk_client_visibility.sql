-- Correção de escopo para clientes da recepção e fechamento das permissões RPC.
-- Aplicar uma única vez, depois de 20261012000000_core_scheduling.sql.

create or replace function public.can_read_client(p_business_id uuid, p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1 from public.business_memberships m
      where m.business_id = p_business_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
        and m.branch_id is null
    )
    or exists (
      select 1
      from public.business_memberships m
      where m.business_id = p_business_id
        and m.user_id = auth.uid()
        and m.role in ('admin', 'receptionist')
        and (
          m.branch_id is null
          or exists (
            select 1 from public.appointments a
            where a.business_id = p_business_id
              and a.client_id = p_client_id
              and a.branch_id = m.branch_id
          )
          or exists (
            select 1 from public.clients c
            where c.business_id = p_business_id
              and c.id = p_client_id
              and c.created_by = auth.uid()
          )
          or exists (
            select 1 from public.waitlist_entries w
            where w.business_id = p_business_id
              and w.client_id = p_client_id
              and w.branch_id = m.branch_id
          )
        )
    )
    or exists (
      select 1
      from public.appointments a
      join public.appointment_services s
        on s.appointment_id = a.id and s.business_id = a.business_id
      join public.business_memberships m
        on m.business_id = s.business_id
       and m.professional_id = s.professional_id
       and m.user_id = auth.uid()
       and m.role = 'professional'
      where a.business_id = p_business_id
        and a.client_id = p_client_id
        and (m.branch_id is null or m.branch_id = a.branch_id)
    );
$$;

-- SECURITY DEFINER RPCs seguem indisponíveis a anon/PUBLIC; só sessões autenticadas as executam.
revoke all on function public.schedule_waitlist_entry(uuid, uuid, timestamptz, uuid) from public, anon;
revoke all on function public.move_appointment(uuid, timestamptz) from public, anon;
grant execute on function public.schedule_waitlist_entry(uuid, uuid, timestamptz, uuid) to authenticated;
grant execute on function public.move_appointment(uuid, timestamptz) to authenticated;
