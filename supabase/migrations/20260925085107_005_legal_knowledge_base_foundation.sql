
create extension if not exists pg_trgm with schema extensions;

create or replace function public.legal_normalize_text(input_text text)
returns text
language sql
immutable
parallel safe
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

create table public.legal_authority_types (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_unit_types (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_relation_types (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  inverse_code text references public.legal_relation_types(code),
  is_directional boolean not null default true,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_content_statuses (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table public.legal_verification_statuses (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table public.legal_publication_statuses (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table public.legal_effect_statuses (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table public.legal_version_types (
  code text primary key,
  name_fa text not null,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
);

create table public.legal_jurisdictions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fa text not null,
  name_en text,
  parent_id uuid references public.legal_jurisdictions(id) on delete restrict,
  country_code text,
  level_code text,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_issuing_bodies (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name_fa text not null,
  normalized_name text generated always as (public.legal_normalize_text(name_fa)) stored,
  name_en text,
  parent_id uuid references public.legal_issuing_bodies(id) on delete restrict,
  jurisdiction_id uuid references public.legal_jurisdictions(id) on delete restrict,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_sources (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fa text not null,
  name_en text,
  base_url text,
  source_kind text,
  is_official boolean not null default false,
  priority integer not null default 100,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_source_records (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.legal_sources(id) on delete restrict,
  external_id text,
  record_url text,
  title_as_published text,
  published_at timestamptz,
  retrieved_at timestamptz not null default now(),
  content_sha256 text,
  raw_storage_bucket text,
  raw_storage_key text,
  raw_payload jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index legal_source_records_external_uidx
  on public.legal_source_records(source_id, external_id)
  where external_id is not null;

create unique index legal_source_records_url_uidx
  on public.legal_source_records(source_id, record_url)
  where record_url is not null;

create table public.legal_taxonomies (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fa text not null,
  name_en text,
  taxonomy_kind text,
  description text,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_categories (
  id uuid primary key default gen_random_uuid(),
  taxonomy_id uuid not null references public.legal_taxonomies(id) on delete cascade,
  parent_id uuid,
  code text,
  name_fa text not null,
  normalized_name text generated always as (public.legal_normalize_text(name_fa)) stored,
  name_en text,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id, taxonomy_id),
  constraint legal_categories_parent_same_taxonomy_fk
    foreign key(parent_id, taxonomy_id)
    references public.legal_categories(id, taxonomy_id)
    on delete restrict
);

create unique index legal_categories_code_uidx
  on public.legal_categories(taxonomy_id, code)
  where code is not null;

create index legal_categories_parent_idx on public.legal_categories(parent_id);
create index legal_categories_name_trgm_idx
  on public.legal_categories using gin (normalized_name extensions.gin_trgm_ops);

create table public.legal_authorities (
  id uuid primary key default gen_random_uuid(),
  authority_type_code text not null references public.legal_authority_types(code) on update cascade,
  canonical_title text not null,
  normalized_title text generated always as (public.legal_normalize_text(canonical_title)) stored,
  short_title text,
  jurisdiction_id uuid references public.legal_jurisdictions(id) on delete restrict,
  issuing_body_id uuid references public.legal_issuing_bodies(id) on delete restrict,
  official_number text,
  issued_at date,
  effective_from date,
  effective_to date,
  publication_status_code text not null default 'draft' references public.legal_publication_statuses(code) on update cascade,
  content_status_code text not null default 'catalog_only' references public.legal_content_statuses(code) on update cascade,
  verification_status_code text not null default 'unverified' references public.legal_verification_statuses(code) on update cascade,
  effect_status_code text not null default 'unknown' references public.legal_effect_statuses(code) on update cascade,
  current_version_id uuid,
  is_public boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index legal_authorities_type_idx on public.legal_authorities(authority_type_code);
create index legal_authorities_jurisdiction_idx on public.legal_authorities(jurisdiction_id);
create index legal_authorities_issuing_body_idx on public.legal_authorities(issuing_body_id);
create index legal_authorities_official_number_idx on public.legal_authorities(official_number);
create index legal_authorities_status_idx on public.legal_authorities(publication_status_code, content_status_code, verification_status_code, effect_status_code);
create index legal_authorities_public_idx on public.legal_authorities(is_public) where is_public;
create index legal_authorities_title_trgm_idx
  on public.legal_authorities using gin (normalized_title extensions.gin_trgm_ops);

create table public.legal_authority_aliases (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  alias text not null,
  normalized_alias text generated always as (public.legal_normalize_text(alias)) stored,
  language_code text not null default 'fa',
  alias_kind text,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index legal_authority_aliases_authority_idx on public.legal_authority_aliases(authority_id);
create index legal_authority_aliases_trgm_idx
  on public.legal_authority_aliases using gin (normalized_alias extensions.gin_trgm_ops);

create table public.legal_external_ids (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  source_id uuid not null references public.legal_sources(id) on delete restrict,
  external_id text not null,
  external_url text,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(source_id, external_id)
);

create index legal_external_ids_authority_idx on public.legal_external_ids(authority_id);

create table public.legal_authority_categories (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  category_id uuid not null references public.legal_categories(id) on delete cascade,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  confidence numeric(5,4),
  relation_kind text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint legal_authority_categories_confidence_chk
    check (confidence is null or (confidence >= 0 and confidence <= 1))
);

create unique index legal_authority_categories_uidx
  on public.legal_authority_categories(
    authority_id,
    category_id,
    coalesce(source_record_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
create index legal_authority_categories_category_idx on public.legal_authority_categories(category_id);

create table public.legal_authority_versions (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  version_number integer not null check (version_number > 0),
  version_type_code text not null default 'original' references public.legal_version_types(code) on update cascade,
  version_label text,
  full_text text,
  normalized_text text,
  content_sha256 text,
  issued_at date,
  effective_from date,
  effective_to date,
  valid_from date,
  valid_to date,
  publication_status_code text not null default 'draft' references public.legal_publication_statuses(code) on update cascade,
  verification_status_code text not null default 'unverified' references public.legal_verification_statuses(code) on update cascade,
  is_consolidated boolean not null default false,
  is_public boolean not null default false,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(authority_id, version_number),
  unique(id, authority_id)
);

create index legal_authority_versions_authority_idx on public.legal_authority_versions(authority_id);
create index legal_authority_versions_dates_idx on public.legal_authority_versions(authority_id, effective_from, effective_to);
create index legal_authority_versions_public_idx on public.legal_authority_versions(is_public) where is_public;
create index legal_authority_versions_fulltext_fts_idx
  on public.legal_authority_versions using gin (to_tsvector('simple', coalesce(normalized_text, full_text, '')));

alter table public.legal_authorities
  add constraint legal_authorities_current_version_same_authority_fk
  foreign key(current_version_id, id)
  references public.legal_authority_versions(id, authority_id)
  deferrable initially deferred;

create table public.legal_units (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  parent_unit_id uuid,
  unit_type_code text not null references public.legal_unit_types(code) on update cascade,
  stable_key text not null,
  canonical_number text,
  canonical_label text,
  heading text,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(authority_id, stable_key),
  unique(id, authority_id),
  constraint legal_units_parent_same_authority_fk
    foreign key(parent_unit_id, authority_id)
    references public.legal_units(id, authority_id)
    on delete restrict
);

create index legal_units_authority_idx on public.legal_units(authority_id);
create index legal_units_parent_idx on public.legal_units(parent_unit_id);
create index legal_units_lookup_idx on public.legal_units(authority_id, unit_type_code, canonical_number);

create table public.legal_unit_versions (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null,
  unit_id uuid not null,
  authority_version_id uuid not null,
  heading text,
  text_content text,
  normalized_text text,
  valid_from date,
  valid_to date,
  verification_status_code text not null default 'unverified' references public.legal_verification_statuses(code) on update cascade,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(unit_id, authority_version_id),
  unique(id, authority_id),
  constraint legal_unit_versions_unit_same_authority_fk
    foreign key(unit_id, authority_id)
    references public.legal_units(id, authority_id)
    on delete cascade,
  constraint legal_unit_versions_version_same_authority_fk
    foreign key(authority_version_id, authority_id)
    references public.legal_authority_versions(id, authority_id)
    on delete cascade
);

create index legal_unit_versions_authority_idx on public.legal_unit_versions(authority_id);
create index legal_unit_versions_version_idx on public.legal_unit_versions(authority_version_id);
create index legal_unit_versions_text_fts_idx
  on public.legal_unit_versions using gin (to_tsvector('simple', coalesce(normalized_text, text_content, '')));

create table public.legal_relations (
  id uuid primary key default gen_random_uuid(),
  relation_type_code text not null references public.legal_relation_types(code) on update cascade,
  source_authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  source_unit_id uuid,
  target_authority_id uuid not null references public.legal_authorities(id) on delete cascade,
  target_unit_id uuid,
  effective_from date,
  effective_to date,
  verification_status_code text not null default 'unverified' references public.legal_verification_statuses(code) on update cascade,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  pinpoint_text text,
  note text,
  is_public boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_relations_source_unit_same_authority_fk
    foreign key(source_unit_id, source_authority_id)
    references public.legal_units(id, authority_id)
    on delete cascade,
  constraint legal_relations_target_unit_same_authority_fk
    foreign key(target_unit_id, target_authority_id)
    references public.legal_units(id, authority_id)
    on delete cascade
);

create index legal_relations_source_idx on public.legal_relations(source_authority_id, relation_type_code);
create index legal_relations_target_idx on public.legal_relations(target_authority_id, relation_type_code);
create index legal_relations_public_idx on public.legal_relations(is_public) where is_public;

create table public.legal_assets (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid,
  authority_version_id uuid,
  unit_version_id uuid,
  source_record_id uuid references public.legal_source_records(id) on delete set null,
  asset_kind text,
  storage_provider text not null default 'supabase',
  storage_bucket text not null,
  storage_key text not null,
  original_filename text,
  mime_type text,
  sha256 text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(storage_provider, storage_bucket, storage_key),
  constraint legal_assets_has_parent_chk
    check (
      authority_id is not null or
      authority_version_id is not null or
      unit_version_id is not null or
      source_record_id is not null
    ),
  constraint legal_assets_version_requires_authority_chk
    check (authority_version_id is null or authority_id is not null),
  constraint legal_assets_unit_version_requires_authority_chk
    check (unit_version_id is null or authority_id is not null),
  constraint legal_assets_authority_fk
    foreign key(authority_id)
    references public.legal_authorities(id)
    on delete cascade,
  constraint legal_assets_version_same_authority_fk
    foreign key(authority_version_id, authority_id)
    references public.legal_authority_versions(id, authority_id)
    on delete cascade,
  constraint legal_assets_unit_version_same_authority_fk
    foreign key(unit_version_id, authority_id)
    references public.legal_unit_versions(id, authority_id)
    on delete cascade
);

create index legal_assets_authority_idx on public.legal_assets(authority_id);
create index legal_assets_source_record_idx on public.legal_assets(source_record_id);

create table public.legal_ingestion_batches (
  id uuid primary key default gen_random_uuid(),
  source_id uuid references public.legal_sources(id) on delete set null,
  import_kind text not null,
  source_filename text,
  source_checksum_sha256 text,
  status text not null default 'created',
  total_rows integer,
  processed_rows integer not null default 0,
  created_rows integer not null default 0,
  matched_rows integer not null default 0,
  issue_rows integer not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.legal_ingestion_records (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.legal_ingestion_batches(id) on delete cascade,
  row_number integer not null,
  external_id text,
  raw_payload jsonb not null,
  normalized_payload jsonb,
  resolution_status text not null default 'pending',
  matched_authority_id uuid references public.legal_authorities(id) on delete set null,
  created_authority_id uuid references public.legal_authorities(id) on delete set null,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(batch_id, row_number)
);

create index legal_ingestion_records_status_idx on public.legal_ingestion_records(batch_id, resolution_status);
create index legal_ingestion_records_match_idx on public.legal_ingestion_records(matched_authority_id);

create table public.legal_ingestion_issues (
  id uuid primary key default gen_random_uuid(),
  ingestion_record_id uuid not null references public.legal_ingestion_records(id) on delete cascade,
  severity text not null,
  issue_code text not null,
  field_name text,
  message text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index legal_ingestion_issues_record_idx on public.legal_ingestion_issues(ingestion_record_id);

create table public.legal_search_chunks (
  id uuid primary key default gen_random_uuid(),
  authority_id uuid not null,
  authority_version_id uuid not null,
  unit_version_id uuid,
  chunk_index integer not null check (chunk_index >= 0),
  content text not null,
  content_sha256 text,
  search_vector tsvector generated always as (to_tsvector('simple', content)) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint legal_search_chunks_version_same_authority_fk
    foreign key(authority_version_id, authority_id)
    references public.legal_authority_versions(id, authority_id)
    on delete cascade,
  constraint legal_search_chunks_unit_version_same_authority_fk
    foreign key(unit_version_id, authority_id)
    references public.legal_unit_versions(id, authority_id)
    on delete cascade
);

create unique index legal_search_chunks_uidx
  on public.legal_search_chunks(
    authority_version_id,
    coalesce(unit_version_id, '00000000-0000-0000-0000-000000000000'::uuid),
    chunk_index
  );
create index legal_search_chunks_authority_idx on public.legal_search_chunks(authority_id);
create index legal_search_chunks_fts_idx on public.legal_search_chunks using gin(search_vector);

insert into public.legal_authority_types(code,name_fa,name_en,sort_order) values
('law','قانون','Law',10),
('regulation','مقرره','Regulation',20),
('bylaw','آیین‌نامه','Bylaw',30),
('resolution','تصویب‌نامه / مصوبه','Resolution',40),
('circular','بخشنامه','Circular',50),
('directive','دستورالعمل','Directive',60),
('treaty','معاهده / موافقت‌نامه بین‌المللی','Treaty',70),
('unity_precedent','رأی وحدت رویه','Unity precedent',80),
('advisory_opinion','نظریه مشورتی','Advisory opinion',90),
('judicial_decision','رأی قضایی','Judicial decision',100),
('administrative_decision','رأی / تصمیم اداری','Administrative decision',110),
('constitutional_opinion','نظر / تصمیم قانون اساسی','Constitutional opinion',120),
('procedure','شیوه‌نامه / دستور کار','Procedure',130),
('tariff','تعرفه','Tariff',140),
('other','سایر','Other',999)
on conflict(code) do nothing;

insert into public.legal_unit_types(code,name_fa,name_en,sort_order) values
('preamble','مقدمه','Preamble',10),
('book','کتاب','Book',20),
('part','قسمت','Part',30),
('chapter','فصل','Chapter',40),
('section','بخش','Section',50),
('article','ماده','Article',60),
('note','تبصره','Note',70),
('paragraph','پاراگراف','Paragraph',80),
('clause','بند','Clause',90),
('item','جزء','Item',100),
('subitem','زیرجزء','Subitem',110),
('facts','شرح / وقایع','Facts',200),
('procedure','گردش کار / سابقه رسیدگی','Procedure',210),
('reasoning','استدلال','Reasoning',220),
('holding','رأی / نتیجه حقوقی','Holding',230),
('question','استعلام / پرسش','Question',240),
('answer','پاسخ','Answer',250),
('conclusion','نتیجه','Conclusion',260),
('attachment','پیوست','Attachment',900),
('other','سایر','Other',999)
on conflict(code) do nothing;

insert into public.legal_relation_types(code,name_fa,name_en,is_directional,sort_order) values
('amends','اصلاح می‌کند','Amends',true,10),
('repeals','نسخ می‌کند','Repeals',true,20),
('partially_repeals','جزئاً نسخ می‌کند','Partially repeals',true,30),
('supersedes','جایگزین می‌شود / جایگزین می‌کند','Supersedes',true,40),
('invalidates','ابطال می‌کند','Invalidates',true,50),
('implements','اجرا / تبیین اجرایی می‌کند','Implements',true,60),
('interprets','تفسیر می‌کند','Interprets',true,70),
('clarifies','توضیح / رفع ابهام می‌کند','Clarifies',true,80),
('cites','استناد می‌کند','Cites',true,90),
('conflicts_with','متعارض است با','Conflicts with',false,100),
('related_to','مرتبط است با','Related to',false,999)
on conflict(code) do nothing;

insert into public.legal_content_statuses(code,name_fa,name_en,sort_order) values
('catalog_only','فقط فهرست / عنوان','Catalog only',10),
('partial_text','متن ناقص / بخشی','Partial text',20),
('full_text','متن کامل','Full text',30)
on conflict(code) do nothing;

insert into public.legal_verification_statuses(code,name_fa,name_en,sort_order) values
('unverified','تأییدنشده','Unverified',10),
('source_verified','منبع بررسی‌شده','Source verified',20),
('official_verified','تأییدشده با منبع رسمی','Officially verified',30),
('disputed','نیازمند بررسی / محل اختلاف','Disputed',40)
on conflict(code) do nothing;

insert into public.legal_publication_statuses(code,name_fa,name_en,sort_order) values
('draft','پیش‌نویس / داخلی','Draft',10),
('published','منتشرشده','Published',20),
('withdrawn','پس‌گرفته‌شده','Withdrawn',30),
('archived','آرشیوی','Archived',40)
on conflict(code) do nothing;

insert into public.legal_effect_statuses(code,name_fa,name_en,sort_order) values
('unknown','نامشخص','Unknown',10),
('active','لازم‌الاجرا / معتبر','Active',20),
('partially_repealed','جزئاً منسوخ','Partially repealed',30),
('repealed','منسوخ','Repealed',40),
('suspended','معلق','Suspended',50),
('superseded','جایگزین‌شده','Superseded',60),
('expired','منقضی','Expired',70)
on conflict(code) do nothing;

insert into public.legal_version_types(code,name_fa,name_en,sort_order) values
('original','نسخه اولیه','Original',10),
('amendment','اصلاحیه','Amendment',20),
('consolidated','متن تلفیقی','Consolidated',30),
('corrected','نسخه اصلاح‌شده / تصحیحی','Corrected',40),
('historical_snapshot','نسخه تاریخی','Historical snapshot',50),
('other','سایر','Other',999)
on conflict(code) do nothing;

insert into public.legal_jurisdictions(code,name_fa,name_en,country_code,level_code)
values ('IR','ایران','Iran','IR','country')
on conflict(code) do nothing;

insert into public.legal_taxonomies(code,name_fa,name_en,taxonomy_kind,description)
values
('master_subjects','طبقه‌بندی موضوعی مرجع','Master subject taxonomy','subject','طبقه‌بندی اصلی و قابل‌توسعه موضوعات حقوقی در دستیار وکیل'),
('source_taxonomies','طبقه‌بندی‌های منبع','Source taxonomies','source','برای حفظ دسته‌بندی هر منبع بدون تحمیل آن به طبقه‌بندی مرجع')
on conflict(code) do nothing;

do $$
declare
  t text;
begin
  foreach t in array array[
    'legal_authority_types',
    'legal_unit_types',
    'legal_relation_types',
    'legal_jurisdictions',
    'legal_issuing_bodies',
    'legal_sources',
    'legal_taxonomies',
    'legal_categories',
    'legal_authorities',
    'legal_authority_versions',
    'legal_units',
    'legal_unit_versions',
    'legal_relations',
    'legal_ingestion_batches',
    'legal_ingestion_records'
  ]
  loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I', t, t);
    execute format(
      'create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      t, t
    );
  end loop;
end $$;

alter table public.legal_authority_types enable row level security;
alter table public.legal_unit_types enable row level security;
alter table public.legal_relation_types enable row level security;
alter table public.legal_content_statuses enable row level security;
alter table public.legal_verification_statuses enable row level security;
alter table public.legal_publication_statuses enable row level security;
alter table public.legal_effect_statuses enable row level security;
alter table public.legal_version_types enable row level security;
alter table public.legal_jurisdictions enable row level security;
alter table public.legal_issuing_bodies enable row level security;
alter table public.legal_sources enable row level security;
alter table public.legal_source_records enable row level security;
alter table public.legal_taxonomies enable row level security;
alter table public.legal_categories enable row level security;
alter table public.legal_authorities enable row level security;
alter table public.legal_authority_aliases enable row level security;
alter table public.legal_external_ids enable row level security;
alter table public.legal_authority_categories enable row level security;
alter table public.legal_authority_versions enable row level security;
alter table public.legal_units enable row level security;
alter table public.legal_unit_versions enable row level security;
alter table public.legal_relations enable row level security;
alter table public.legal_assets enable row level security;
alter table public.legal_ingestion_batches enable row level security;
alter table public.legal_ingestion_records enable row level security;
alter table public.legal_ingestion_issues enable row level security;
alter table public.legal_search_chunks enable row level security;

revoke all on
  public.legal_authority_types,
  public.legal_unit_types,
  public.legal_relation_types,
  public.legal_content_statuses,
  public.legal_verification_statuses,
  public.legal_publication_statuses,
  public.legal_effect_statuses,
  public.legal_version_types,
  public.legal_jurisdictions,
  public.legal_issuing_bodies,
  public.legal_sources,
  public.legal_source_records,
  public.legal_taxonomies,
  public.legal_categories,
  public.legal_authorities,
  public.legal_authority_aliases,
  public.legal_external_ids,
  public.legal_authority_categories,
  public.legal_authority_versions,
  public.legal_units,
  public.legal_unit_versions,
  public.legal_relations,
  public.legal_assets,
  public.legal_ingestion_batches,
  public.legal_ingestion_records,
  public.legal_ingestion_issues,
  public.legal_search_chunks
from anon, authenticated;

grant select on
  public.legal_authority_types,
  public.legal_unit_types,
  public.legal_relation_types,
  public.legal_content_statuses,
  public.legal_verification_statuses,
  public.legal_publication_statuses,
  public.legal_effect_statuses,
  public.legal_version_types,
  public.legal_jurisdictions,
  public.legal_issuing_bodies,
  public.legal_sources,
  public.legal_taxonomies,
  public.legal_categories,
  public.legal_authorities,
  public.legal_authority_aliases,
  public.legal_external_ids,
  public.legal_authority_categories,
  public.legal_authority_versions,
  public.legal_units,
  public.legal_unit_versions,
  public.legal_relations
to anon, authenticated;

grant all privileges on
  public.legal_authority_types,
  public.legal_unit_types,
  public.legal_relation_types,
  public.legal_content_statuses,
  public.legal_verification_statuses,
  public.legal_publication_statuses,
  public.legal_effect_statuses,
  public.legal_version_types,
  public.legal_jurisdictions,
  public.legal_issuing_bodies,
  public.legal_sources,
  public.legal_source_records,
  public.legal_taxonomies,
  public.legal_categories,
  public.legal_authorities,
  public.legal_authority_aliases,
  public.legal_external_ids,
  public.legal_authority_categories,
  public.legal_authority_versions,
  public.legal_units,
  public.legal_unit_versions,
  public.legal_relations,
  public.legal_assets,
  public.legal_ingestion_batches,
  public.legal_ingestion_records,
  public.legal_ingestion_issues,
  public.legal_search_chunks
to service_role;

create policy legal_authority_types_public_read
on public.legal_authority_types for select to anon, authenticated
using (is_active);

create policy legal_unit_types_public_read
on public.legal_unit_types for select to anon, authenticated
using (is_active);

create policy legal_relation_types_public_read
on public.legal_relation_types for select to anon, authenticated
using (is_active);

create policy legal_content_statuses_public_read
on public.legal_content_statuses for select to anon, authenticated
using (is_active);

create policy legal_verification_statuses_public_read
on public.legal_verification_statuses for select to anon, authenticated
using (is_active);

create policy legal_publication_statuses_public_read
on public.legal_publication_statuses for select to anon, authenticated
using (is_active);

create policy legal_effect_statuses_public_read
on public.legal_effect_statuses for select to anon, authenticated
using (is_active);

create policy legal_version_types_public_read
on public.legal_version_types for select to anon, authenticated
using (is_active);

create policy legal_jurisdictions_public_read
on public.legal_jurisdictions for select to anon, authenticated
using (is_active);

create policy legal_issuing_bodies_public_read
on public.legal_issuing_bodies for select to anon, authenticated
using (is_active);

create policy legal_sources_public_read
on public.legal_sources for select to anon, authenticated
using (is_active);

create policy legal_taxonomies_public_read
on public.legal_taxonomies for select to anon, authenticated
using (is_active);

create policy legal_categories_public_read
on public.legal_categories for select to anon, authenticated
using (is_active);

create policy legal_authorities_public_read
on public.legal_authorities for select to anon, authenticated
using (is_public);

create policy legal_authority_aliases_public_read
on public.legal_authority_aliases for select to anon, authenticated
using (
  exists (
    select 1 from public.legal_authorities a
    where a.id = legal_authority_aliases.authority_id
      and a.is_public
  )
);

create policy legal_external_ids_public_read
on public.legal_external_ids for select to anon, authenticated
using (
  exists (
    select 1 from public.legal_authorities a
    where a.id = legal_external_ids.authority_id
      and a.is_public
  )
);

create policy legal_authority_categories_public_read
on public.legal_authority_categories for select to anon, authenticated
using (
  exists (
    select 1 from public.legal_authorities a
    where a.id = legal_authority_categories.authority_id
      and a.is_public
  )
);

create policy legal_authority_versions_public_read
on public.legal_authority_versions for select to anon, authenticated
using (
  is_public
  and exists (
    select 1 from public.legal_authorities a
    where a.id = legal_authority_versions.authority_id
      and a.is_public
  )
);

create policy legal_units_public_read
on public.legal_units for select to anon, authenticated
using (
  exists (
    select 1 from public.legal_authorities a
    where a.id = legal_units.authority_id
      and a.is_public
  )
);

create policy legal_unit_versions_public_read
on public.legal_unit_versions for select to anon, authenticated
using (
  exists (
    select 1
    from public.legal_authority_versions v
    join public.legal_authorities a on a.id = v.authority_id
    where v.id = legal_unit_versions.authority_version_id
      and v.is_public
      and a.is_public
  )
);

create policy legal_relations_public_read
on public.legal_relations for select to anon, authenticated
using (
  is_public
  and exists (
    select 1 from public.legal_authorities a
    where a.id = legal_relations.source_authority_id
      and a.is_public
  )
  and exists (
    select 1 from public.legal_authorities a
    where a.id = legal_relations.target_authority_id
      and a.is_public
  )
);

