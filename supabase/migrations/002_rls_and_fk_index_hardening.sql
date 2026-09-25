drop policy if exists organization_members_select_member on public.organization_members;

create policy organization_members_select_self on public.organization_members
for select to authenticated
using (user_id = (select auth.uid()));

create policy organization_members_insert_initial_owner on public.organization_members
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and role = 'owner'
  and exists (
    select 1 from public.organizations o
    where o.id = organization_members.organization_id
      and o.created_by = (select auth.uid())
  )
);

create policy profiles_insert_self on public.profiles
for insert to authenticated
with check (id = (select auth.uid()));

create index if not exists organizations_created_by_idx on public.organizations(created_by);
create index if not exists clients_created_by_idx on public.clients(created_by);
create index if not exists matters_created_by_idx on public.matters(created_by);
create index if not exists hearings_created_by_idx on public.hearings(created_by);
create index if not exists matter_clients_client_idx on public.matter_clients(client_id);
create index if not exists documents_owner_user_idx on public.documents(owner_user_id);
create index if not exists documents_client_idx on public.documents(client_id);
create index if not exists documents_current_version_idx on public.documents(current_version_id);
create index if not exists document_versions_created_by_idx on public.document_versions(created_by);
