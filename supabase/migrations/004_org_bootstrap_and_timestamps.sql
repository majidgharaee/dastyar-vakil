drop policy if exists organizations_select_member on public.organizations;

create policy organizations_select_creator_or_member
on public.organizations
for select to authenticated
using (
  created_by = (select auth.uid())
  or exists (
    select 1 from public.organization_members om
    where om.organization_id = organizations.id
      and om.user_id = (select auth.uid())
  )
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public;
grant execute on function public.set_updated_at() to authenticated;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists organizations_set_updated_at on public.organizations;
create trigger organizations_set_updated_at before update on public.organizations for each row execute function public.set_updated_at();
drop trigger if exists clients_set_updated_at on public.clients;
create trigger clients_set_updated_at before update on public.clients for each row execute function public.set_updated_at();
drop trigger if exists matters_set_updated_at on public.matters;
create trigger matters_set_updated_at before update on public.matters for each row execute function public.set_updated_at();
drop trigger if exists hearings_set_updated_at on public.hearings;
create trigger hearings_set_updated_at before update on public.hearings for each row execute function public.set_updated_at();
drop trigger if exists documents_set_updated_at on public.documents;
create trigger documents_set_updated_at before update on public.documents for each row execute function public.set_updated_at();
