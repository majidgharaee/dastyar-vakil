create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','lawyer','assistant','viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  full_name text not null,
  national_id text,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.matters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  title text not null,
  case_number text,
  court_name text,
  status text not null default 'open',
  description text,
  opened_at date,
  closed_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.matter_clients (
  matter_id uuid not null references public.matters(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  relation_type text not null default 'client',
  created_at timestamptz not null default now(),
  primary key (matter_id, client_id)
);

create table public.hearings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  matter_id uuid references public.matters(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  starts_at timestamptz not null,
  court_name text,
  branch_name text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id),
  client_id uuid references public.clients(id) on delete set null,
  matter_id uuid references public.matters(id) on delete set null,
  document_type text not null,
  title text,
  original_filename text not null,
  confidentiality text not null default 'private'
    check (confidentiality in ('private','organization','public')),
  processing_status text not null default 'pending'
    check (processing_status in ('pending','processing','ready','failed')),
  current_version_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  storage_provider text not null default 'supabase',
  storage_bucket text not null,
  storage_key text not null,
  sha256 text not null,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  mime_type text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (document_id, version_number),
  unique (storage_provider, storage_bucket, storage_key)
);

alter table public.documents
  add constraint documents_current_version_fk
  foreign key (current_version_id) references public.document_versions(id)
  deferrable initially deferred;

create table public.document_chunks (
  id uuid primary key default gen_random_uuid(),
  document_version_id uuid not null references public.document_versions(id) on delete cascade,
  chunk_index integer not null check (chunk_index >= 0),
  content text not null,
  page_from integer,
  page_to integer,
  metadata jsonb not null default '{}'::jsonb,
  embedding extensions.vector(3072),
  created_at timestamptz not null default now(),
  unique (document_version_id, chunk_index)
);

create index organization_members_user_idx on public.organization_members(user_id);
create index clients_org_idx on public.clients(organization_id);
create index matters_org_idx on public.matters(organization_id);
create index hearings_org_idx on public.hearings(organization_id);
create index hearings_matter_idx on public.hearings(matter_id);
create index documents_org_idx on public.documents(organization_id);
create index documents_matter_idx on public.documents(matter_id);
create index document_versions_document_idx on public.document_versions(document_id);
create index document_chunks_version_idx on public.document_chunks(document_version_id);
create index document_chunks_content_fts_idx on public.document_chunks using gin (to_tsvector('simple', content));

alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.clients enable row level security;
alter table public.matters enable row level security;
alter table public.matter_clients enable row level security;
alter table public.hearings enable row level security;
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.document_chunks enable row level security;

create policy profiles_select_self on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update_self on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy organizations_select_member on public.organizations for select to authenticated using (exists (select 1 from public.organization_members om where om.organization_id = organizations.id and om.user_id = (select auth.uid())));
create policy organizations_insert_creator on public.organizations for insert to authenticated with check (created_by = (select auth.uid()));

create policy organization_members_select_member on public.organization_members
for select to authenticated
using (exists (
  select 1 from public.organization_members me
  where me.organization_id = organization_members.organization_id
    and me.user_id = (select auth.uid())
));

create policy clients_member_all on public.clients for all to authenticated
using (exists (select 1 from public.organization_members om where om.organization_id = clients.organization_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.organization_members om where om.organization_id = clients.organization_id and om.user_id = (select auth.uid())));

create policy matters_member_all on public.matters for all to authenticated
using (exists (select 1 from public.organization_members om where om.organization_id = matters.organization_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.organization_members om where om.organization_id = matters.organization_id and om.user_id = (select auth.uid())));

create policy matter_clients_member_all on public.matter_clients for all to authenticated
using (exists (select 1 from public.matters m join public.organization_members om on om.organization_id = m.organization_id where m.id = matter_clients.matter_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.matters m join public.organization_members om on om.organization_id = m.organization_id where m.id = matter_clients.matter_id and om.user_id = (select auth.uid())));

create policy hearings_member_all on public.hearings for all to authenticated
using (exists (select 1 from public.organization_members om where om.organization_id = hearings.organization_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.organization_members om where om.organization_id = hearings.organization_id and om.user_id = (select auth.uid())));

create policy documents_member_all on public.documents for all to authenticated
using (exists (select 1 from public.organization_members om where om.organization_id = documents.organization_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.organization_members om where om.organization_id = documents.organization_id and om.user_id = (select auth.uid())));

create policy document_versions_member_all on public.document_versions for all to authenticated
using (exists (select 1 from public.documents d join public.organization_members om on om.organization_id = d.organization_id where d.id = document_versions.document_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.documents d join public.organization_members om on om.organization_id = d.organization_id where d.id = document_versions.document_id and om.user_id = (select auth.uid())));

create policy document_chunks_member_all on public.document_chunks for all to authenticated
using (exists (select 1 from public.document_versions dv join public.documents d on d.id = dv.document_id join public.organization_members om on om.organization_id = d.organization_id where dv.id = document_chunks.document_version_id and om.user_id = (select auth.uid())))
with check (exists (select 1 from public.document_versions dv join public.documents d on d.id = dv.document_id join public.organization_members om on om.organization_id = d.organization_id where dv.id = document_chunks.document_version_id and om.user_id = (select auth.uid())));

grant select, insert, update, delete on public.profiles, public.organizations, public.organization_members, public.clients, public.matters, public.matter_clients, public.hearings, public.documents, public.document_versions, public.document_chunks to authenticated;
