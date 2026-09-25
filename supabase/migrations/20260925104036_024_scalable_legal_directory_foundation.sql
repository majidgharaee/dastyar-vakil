
create or replace function public.directory_normalize_text(input_text text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select nullif(
    regexp_replace(
      translate(
        replace(replace(lower(trim(input_text)), chr(8204), ' '), 'ـ', ''),
        'يىك٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
        'ییک01234567890123456789'
      ),
      '[[:space:]]+',
      ' ',
      'g'
    ),
    ''
  )
$$;

create table if not exists public.directory_groups (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fa text not null,
  normalized_name text generated always as (public.directory_normalize_text(name_fa)) stored,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (normalized_name)
);

create table if not exists public.directory_subgroups (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.directory_groups(id) on delete cascade,
  code text not null unique,
  name_fa text not null,
  normalized_name text generated always as (public.directory_normalize_text(name_fa)) stored,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, normalized_name)
);

create table if not exists public.directory_entities (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  normalized_name text generated always as (public.directory_normalize_text(canonical_name)) stored,
  status_code text not null default 'active'
    check (status_code in ('active','inactive','unknown')),
  is_public boolean not null default false,
  current_version_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.directory_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_code text not null,
  source_name text not null,
  source_version text,
  source_file_name text,
  source_file_sha256 text,
  source_csv_name text,
  source_csv_sha256 text,
  total_rows integer not null default 0 check (total_rows >= 0),
  processed_rows integer not null default 0 check (processed_rows >= 0),
  created_entities integer not null default 0 check (created_entities >= 0),
  matched_entities integer not null default 0 check (matched_entities >= 0),
  issue_rows integer not null default 0 check (issue_rows >= 0),
  status text not null default 'registered',
  metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_code, source_version, source_file_sha256)
);

create table if not exists public.directory_source_records (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.directory_import_batches(id) on delete cascade,
  row_number integer not null check (row_number > 0),
  external_id text not null,
  raw_payload jsonb not null,
  normalized_payload jsonb not null default '{}'::jsonb,
  resolved_entity_id uuid references public.directory_entities(id) on delete set null,
  resolution_status text not null default 'pending',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (batch_id, row_number),
  unique (batch_id, external_id)
);

create table if not exists public.directory_entity_versions (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.directory_entities(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  source_record_id uuid references public.directory_source_records(id) on delete set null,
  name_at_source text not null,
  province text,
  county text,
  city text,
  municipal_region text,
  jurisdiction_scope text,
  address text not null,
  normalized_address text generated always as (public.directory_normalize_text(address)) stored,
  postal_code text,
  hours_text text,
  operational_status text,
  confidence_level text not null default 'unknown'
    check (confidence_level in ('high','medium','low','unknown')),
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','source_reviewed','official_verified','needs_verification')),
  source_date_text text,
  source_name text,
  source_url text,
  map_url text,
  lawyer_use text,
  project_scope text,
  notes text,
  latitude double precision,
  longitude double precision,
  geocode_status text not null default 'search_link_only'
    check (geocode_status in ('not_geocoded','search_link_only','geocoded','verified')),
  is_current boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (entity_id, version_number),
  check (latitude is null or (latitude between -90 and 90)),
  check (longitude is null or (longitude between -180 and 180))
);

alter table public.directory_entities
  drop constraint if exists directory_entities_current_version_id_fkey;
alter table public.directory_entities
  add constraint directory_entities_current_version_id_fkey
  foreign key (current_version_id)
  references public.directory_entity_versions(id)
  on delete set null
  deferrable initially deferred;

create table if not exists public.directory_contacts (
  id uuid primary key default gen_random_uuid(),
  entity_version_id uuid not null references public.directory_entity_versions(id) on delete cascade,
  contact_type text not null
    check (contact_type in ('phone','fax','email','website','other')),
  value text not null,
  normalized_value text generated always as (public.directory_normalize_text(value)) stored,
  label text,
  is_primary boolean not null default false,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  unique (entity_version_id, contact_type, normalized_value)
);

create table if not exists public.directory_entity_classifications (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.directory_entities(id) on delete cascade,
  group_id uuid not null references public.directory_groups(id) on delete restrict,
  subgroup_id uuid references public.directory_subgroups(id) on delete restrict,
  source_record_id uuid references public.directory_source_records(id) on delete set null,
  is_primary boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (entity_id, group_id, subgroup_id)
);

create table if not exists public.directory_external_ids (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.directory_entities(id) on delete cascade,
  source_code text not null,
  external_id text not null,
  source_record_id uuid references public.directory_source_records(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (source_code, external_id)
);

create table if not exists public.directory_ingestion_issues (
  id uuid primary key default gen_random_uuid(),
  source_record_id uuid not null references public.directory_source_records(id) on delete cascade,
  severity text not null check (severity in ('info','warning','high')),
  issue_code text not null,
  field_name text,
  message text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists directory_subgroups_group_idx
  on public.directory_subgroups(group_id);
create index if not exists directory_entities_name_trgm_idx
  on public.directory_entities using gin (normalized_name extensions.gin_trgm_ops);
create index if not exists directory_entity_versions_entity_idx
  on public.directory_entity_versions(entity_id);
create unique index if not exists directory_entity_versions_one_current_idx
  on public.directory_entity_versions(entity_id)
  where is_current;
create index if not exists directory_entity_versions_city_idx
  on public.directory_entity_versions(city);
create index if not exists directory_entity_versions_confidence_idx
  on public.directory_entity_versions(confidence_level);
create index if not exists directory_entity_versions_address_trgm_idx
  on public.directory_entity_versions using gin (normalized_address extensions.gin_trgm_ops);
create index if not exists directory_contacts_version_idx
  on public.directory_contacts(entity_version_id);
create index if not exists directory_classifications_entity_idx
  on public.directory_entity_classifications(entity_id);
create index if not exists directory_classifications_group_idx
  on public.directory_entity_classifications(group_id, entity_id);
create index if not exists directory_classifications_subgroup_idx
  on public.directory_entity_classifications(subgroup_id, entity_id);
create index if not exists directory_source_records_batch_idx
  on public.directory_source_records(batch_id);
create index if not exists directory_source_records_entity_idx
  on public.directory_source_records(resolved_entity_id);
create index if not exists directory_external_ids_entity_idx
  on public.directory_external_ids(entity_id);
create index if not exists directory_issues_source_idx
  on public.directory_ingestion_issues(source_record_id);

alter table public.directory_groups enable row level security;
alter table public.directory_subgroups enable row level security;
alter table public.directory_entities enable row level security;
alter table public.directory_entity_versions enable row level security;
alter table public.directory_contacts enable row level security;
alter table public.directory_entity_classifications enable row level security;
alter table public.directory_external_ids enable row level security;
alter table public.directory_import_batches enable row level security;
alter table public.directory_source_records enable row level security;
alter table public.directory_ingestion_issues enable row level security;

revoke all on public.directory_groups from anon,authenticated;
revoke all on public.directory_subgroups from anon,authenticated;
revoke all on public.directory_entities from anon,authenticated;
revoke all on public.directory_entity_versions from anon,authenticated;
revoke all on public.directory_contacts from anon,authenticated;
revoke all on public.directory_entity_classifications from anon,authenticated;
revoke all on public.directory_external_ids from anon,authenticated;
revoke all on public.directory_import_batches from anon,authenticated;
revoke all on public.directory_source_records from anon,authenticated;
revoke all on public.directory_ingestion_issues from anon,authenticated;

grant select on public.directory_groups to anon,authenticated;
grant select on public.directory_subgroups to anon,authenticated;
grant select on public.directory_entities to anon,authenticated;
grant select on public.directory_entity_versions to anon,authenticated;
grant select on public.directory_contacts to anon,authenticated;
grant select on public.directory_entity_classifications to anon,authenticated;

grant select,insert,update,delete on public.directory_groups to service_role;
grant select,insert,update,delete on public.directory_subgroups to service_role;
grant select,insert,update,delete on public.directory_entities to service_role;
grant select,insert,update,delete on public.directory_entity_versions to service_role;
grant select,insert,update,delete on public.directory_contacts to service_role;
grant select,insert,update,delete on public.directory_entity_classifications to service_role;
grant select,insert,update,delete on public.directory_external_ids to service_role;
grant select,insert,update,delete on public.directory_import_batches to service_role;
grant select,insert,update,delete on public.directory_source_records to service_role;
grant select,insert,update,delete on public.directory_ingestion_issues to service_role;

drop policy if exists directory_groups_public_read on public.directory_groups;
create policy directory_groups_public_read
on public.directory_groups for select to anon,authenticated
using (is_active);

drop policy if exists directory_subgroups_public_read on public.directory_subgroups;
create policy directory_subgroups_public_read
on public.directory_subgroups for select to anon,authenticated
using (
  is_active and exists (
    select 1 from public.directory_groups g
    where g.id=directory_subgroups.group_id and g.is_active
  )
);

drop policy if exists directory_entities_public_read on public.directory_entities;
create policy directory_entities_public_read
on public.directory_entities for select to anon,authenticated
using (is_public);

drop policy if exists directory_versions_public_read on public.directory_entity_versions;
create policy directory_versions_public_read
on public.directory_entity_versions for select to anon,authenticated
using (
  is_current and exists (
    select 1 from public.directory_entities e
    where e.id=directory_entity_versions.entity_id and e.is_public
  )
);

drop policy if exists directory_contacts_public_read on public.directory_contacts;
create policy directory_contacts_public_read
on public.directory_contacts for select to anon,authenticated
using (
  exists (
    select 1
    from public.directory_entity_versions v
    join public.directory_entities e on e.id=v.entity_id
    where v.id=directory_contacts.entity_version_id
      and v.is_current
      and e.is_public
  )
);

drop policy if exists directory_classifications_public_read on public.directory_entity_classifications;
create policy directory_classifications_public_read
on public.directory_entity_classifications for select to anon,authenticated
using (
  exists (
    select 1 from public.directory_entities e
    where e.id=directory_entity_classifications.entity_id and e.is_public
  )
);

drop policy if exists directory_groups_service_all on public.directory_groups;
create policy directory_groups_service_all on public.directory_groups
for all to service_role using (true) with check (true);
drop policy if exists directory_subgroups_service_all on public.directory_subgroups;
create policy directory_subgroups_service_all on public.directory_subgroups
for all to service_role using (true) with check (true);
drop policy if exists directory_entities_service_all on public.directory_entities;
create policy directory_entities_service_all on public.directory_entities
for all to service_role using (true) with check (true);
drop policy if exists directory_versions_service_all on public.directory_entity_versions;
create policy directory_versions_service_all on public.directory_entity_versions
for all to service_role using (true) with check (true);
drop policy if exists directory_contacts_service_all on public.directory_contacts;
create policy directory_contacts_service_all on public.directory_contacts
for all to service_role using (true) with check (true);
drop policy if exists directory_classifications_service_all on public.directory_entity_classifications;
create policy directory_classifications_service_all on public.directory_entity_classifications
for all to service_role using (true) with check (true);
drop policy if exists directory_external_ids_service_all on public.directory_external_ids;
create policy directory_external_ids_service_all on public.directory_external_ids
for all to service_role using (true) with check (true);
drop policy if exists directory_batches_service_all on public.directory_import_batches;
create policy directory_batches_service_all on public.directory_import_batches
for all to service_role using (true) with check (true);
drop policy if exists directory_source_records_service_all on public.directory_source_records;
create policy directory_source_records_service_all on public.directory_source_records
for all to service_role using (true) with check (true);
drop policy if exists directory_issues_service_all on public.directory_ingestion_issues;
create policy directory_issues_service_all on public.directory_ingestion_issues
for all to service_role using (true) with check (true);

drop trigger if exists directory_groups_set_updated_at on public.directory_groups;
create trigger directory_groups_set_updated_at
before update on public.directory_groups
for each row execute function public.set_updated_at();

drop trigger if exists directory_subgroups_set_updated_at on public.directory_subgroups;
create trigger directory_subgroups_set_updated_at
before update on public.directory_subgroups
for each row execute function public.set_updated_at();

drop trigger if exists directory_entities_set_updated_at on public.directory_entities;
create trigger directory_entities_set_updated_at
before update on public.directory_entities
for each row execute function public.set_updated_at();

drop trigger if exists directory_batches_set_updated_at on public.directory_import_batches;
create trigger directory_batches_set_updated_at
before update on public.directory_import_batches
for each row execute function public.set_updated_at();

drop trigger if exists directory_source_records_set_updated_at on public.directory_source_records;
create trigger directory_source_records_set_updated_at
before update on public.directory_source_records
for each row execute function public.set_updated_at();

