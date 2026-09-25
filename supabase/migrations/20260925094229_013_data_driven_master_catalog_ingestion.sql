
create table if not exists public.legal_authority_type_labels (
  id uuid primary key default gen_random_uuid(),
  source_scope text not null default 'global',
  label text not null,
  normalized_label text generated always as (public.legal_normalize_text(label)) stored,
  authority_type_code text not null references public.legal_authority_types(code) on update cascade,
  priority integer not null default 100,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_scope, normalized_label)
);

create index if not exists legal_authority_type_labels_type_idx
  on public.legal_authority_type_labels(authority_type_code);

alter table public.legal_authority_type_labels enable row level security;
revoke all on public.legal_authority_type_labels from anon, authenticated;
grant select,insert,update,delete on public.legal_authority_type_labels to service_role;

drop policy if exists legal_authority_type_labels_service_role_all
  on public.legal_authority_type_labels;
create policy legal_authority_type_labels_service_role_all
  on public.legal_authority_type_labels
  for all to service_role using (true) with check (true);

insert into public.legal_authority_type_labels
  (source_scope,label,authority_type_code,priority,metadata)
values
('global','قانون','law',10,'{}'::jsonb),
('global','آیین‌نامه','bylaw',20,'{}'::jsonb),
('global','سایر سند حقوقی','other_legal_document',990,'{}'::jsonb),
('global','دستورالعمل','directive',30,'{}'::jsonb),
('global','لایحه قانونی','legislative_decree',15,'{}'::jsonb),
('global','بخشنامه','circular',40,'{}'::jsonb),
('global','سند/سیاست','policy_document',50,'{}'::jsonb),
('global','مقررات','regulation',60,'{}'::jsonb),
('global','ضوابط','standards_rules',70,'{}'::jsonb),
('global','اساسنامه','statute',80,'{}'::jsonb),
('global','مصوبه','resolution',90,'{}'::jsonb),
('global','نظام/چارچوب','framework',100,'{}'::jsonb),
('global','شیوه‌نامه','procedure',110,'{}'::jsonb),
('global','تصویب‌نامه','decree',120,'{}'::jsonb),
('global','نظامنامه','rulebook',130,'{}'::jsonb),
('global','شرایط عمومی/قراردادی','contractual_terms',140,'{}'::jsonb)
on conflict (source_scope,normalized_label) do update
set authority_type_code=excluded.authority_type_code,
    priority=excluded.priority,
    is_active=true,
    metadata=excluded.metadata,
    updated_at=now();

create or replace function private.stage_master_catalog_rows(
  p_batch_id uuid,
  p_rows jsonb,
  p_master_version text default 'current'
)
returns integer
language plpgsql
security invoker
set search_path = public, private
as $$
declare
  v_source_id uuid;
  v_count integer := 0;
begin
  select b.source_id into v_source_id
  from public.legal_ingestion_batches b
  where b.id=p_batch_id;

  if v_source_id is null then
    raise exception 'Unknown ingestion batch %', p_batch_id;
  end if;

  with input_rows as (
    select *
    from jsonb_to_recordset(p_rows)
    as x(
      id integer,
      title text,
      doc_type text,
      old_category text,
      cat_code text,
      cat_name text,
      subtopic text,
      legacy_app_category text,
      app_category_status text,
      in_base text,
      project_status text,
      source_name text,
      source_level text,
      source_url text,
      national_url text,
      official_gazette_url text,
      validity_note text,
      research_note text
    )
  ),
  typed as (
    select i.*,
           coalesce(tl.authority_type_code,'other_legal_document') as type_code,
           c.id as category_id
    from input_rows i
    left join public.legal_authority_type_labels tl
      on tl.source_scope='global'
     and tl.normalized_label=public.legal_normalize_text(i.doc_type)
     and tl.is_active
    left join public.legal_taxonomies tx on tx.code='master_subjects'
    left join public.legal_categories c
      on c.taxonomy_id=tx.id and c.code=i.cat_code
  ),
  source_rows as (
    insert into public.legal_source_records
      (source_id,external_id,title_as_published,raw_payload,metadata)
    select
      v_source_id,
      'master-row-'||lpad(typed.id::text,4,'0'),
      typed.title,
      jsonb_build_object(
        'ID',typed.id,
        'عنوان قانون/مقرره',typed.title,
        'نوع سند',typed.doc_type,
        'دسته قدیمی مستقل',typed.old_category,
        'کد دسته نهایی',typed.cat_code,
        'دسته اصلی نهایی',typed.cat_name,
        'زیرموضوع پیشنهادی',typed.subtopic,
        'نزدیک‌ترین دسته اپ',typed.legacy_app_category,
        'وضعیت دسته در اپ',typed.app_category_status,
        'در فهرست پایه؟',typed.in_base,
        'وضعیت پروژه',typed.project_status,
        'منبع کشف/تطبیق',typed.source_name,
        'سطح منبع',typed.source_level,
        'URL منبع',typed.source_url,
        'سامانه ملی',typed.national_url,
        'روزنامه رسمی',typed.official_gazette_url,
        'وضعیت تنقیحی/اعتبار',typed.validity_note,
        'یادداشت پژوهش',typed.research_note
      ),
      jsonb_build_object(
        'master_version',p_master_version,
        'source_listing_url',typed.source_url,
        'national_reference_url',typed.national_url,
        'official_gazette_url',typed.official_gazette_url
      )
    from typed
    on conflict (source_id,external_id) where external_id is not null do update
    set title_as_published=excluded.title_as_published,
        raw_payload=excluded.raw_payload,
        metadata=public.legal_source_records.metadata || excluded.metadata
    returning id,external_id,raw_payload
  ),
  prepared as (
    select
      typed.*,
      sr.id as source_record_id
    from typed
    join source_rows sr
      on sr.external_id=('master-row-'||lpad(typed.id::text,4,'0'))
  ),
  upserted as (
    insert into public.legal_ingestion_records
      (batch_id,row_number,external_id,raw_payload,normalized_payload,resolution_status,metadata)
    select
      p_batch_id,
      prepared.id,
      'master-row-'||lpad(prepared.id::text,4,'0'),
      prepared.source_record_id::text::jsonb || '{}'::jsonb,
      jsonb_build_object(
        'normalized_title',public.legal_normalize_text(prepared.title),
        'document_type_code',prepared.type_code,
        'canonical_category_code',prepared.cat_code,
        'canonical_category_id',prepared.category_id,
        'source_record_id',prepared.source_record_id
      ),
      'pending',
      jsonb_build_object(
        'master_catalog',true,
        'master_version',p_master_version,
        'source_record_id',prepared.source_record_id,
        'title',prepared.title,
        'doc_type_label',prepared.doc_type,
        'category_name',prepared.cat_name,
        'subtopic',prepared.subtopic,
        'source_name',prepared.source_name,
        'source_level',prepared.source_level,
        'source_url',prepared.source_url,
        'national_url',prepared.national_url,
        'official_gazette_url',prepared.official_gazette_url,
        'validity_note',prepared.validity_note,
        'research_note',prepared.research_note,
        'old_category',prepared.old_category,
        'legacy_app_category',prepared.legacy_app_category,
        'app_category_status',prepared.app_category_status,
        'in_base',prepared.in_base,
        'project_status',prepared.project_status
      )
    from prepared
    on conflict (batch_id,row_number) do update
    set external_id=excluded.external_id,
        normalized_payload=excluded.normalized_payload,
        metadata=public.legal_ingestion_records.metadata || excluded.metadata,
        resolution_status=case
          when public.legal_ingestion_records.resolution_status in
               ('matched_existing','created_new','matched_batch_duplicate','review_required')
          then public.legal_ingestion_records.resolution_status
          else 'pending'
        end,
        updated_at=now()
    returning id
  )
  select count(*) into v_count from upserted;

  update public.legal_ingestion_batches
  set status=case when status='registered' then 'staging' else status end,
      metadata=metadata || jsonb_build_object('last_stage_at',now(),'master_version',p_master_version),
      updated_at=now()
  where id=p_batch_id;

  return v_count;
end;
$$;

revoke all on function private.stage_master_catalog_rows(uuid,jsonb,text)
  from public,anon,authenticated;
grant execute on function private.stage_master_catalog_rows(uuid,jsonb,text)
  to service_role;

create or replace function private.generate_legal_ingestion_candidates(
  p_batch_id uuid,
  p_min_similarity numeric default 0.72,
  p_algorithm_version text default 'title-v2'
)
returns integer
language plpgsql
security invoker
set search_path = public, extensions, private
as $$
declare
  v_total integer := 0;
  v_count integer := 0;
begin
  delete from public.legal_ingestion_candidates c
  using public.legal_ingestion_records r
  where c.ingestion_record_id=r.id
    and r.batch_id=p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
    and c.algorithm_version=p_algorithm_version;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id,candidate_authority_id,candidate_kind,match_method,score,algorithm_version,evidence)
  select
    r.id,a.id,'identity','exact_canonical_title',1.00000,p_algorithm_version,
    jsonb_build_object('candidate_title',a.canonical_title)
  from public.legal_ingestion_records r
  join public.legal_authorities a
    on a.normalized_title=r.normalized_payload->>'normalized_title'
  where r.batch_id=p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
  on conflict do nothing;
  get diagnostics v_count=row_count; v_total:=v_total+v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id,candidate_authority_id,candidate_kind,match_method,score,algorithm_version,evidence)
  select
    r.id,al.authority_id,'identity','exact_alias',0.99500,p_algorithm_version,
    jsonb_build_object('alias_id',al.id,'alias',al.alias)
  from public.legal_ingestion_records r
  join public.legal_authority_aliases al
    on al.normalized_alias=r.normalized_payload->>'normalized_title'
  where r.batch_id=p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
  on conflict do nothing;
  get diagnostics v_count=row_count; v_total:=v_total+v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id,candidate_ingestion_record_id,candidate_kind,match_method,score,algorithm_version,evidence)
  select
    r1.id,r2.id,'identity','within_batch_exact_title',1.00000,p_algorithm_version,
    jsonb_build_object('candidate_row_number',r2.row_number,'candidate_title',r2.metadata->>'title')
  from public.legal_ingestion_records r1
  join public.legal_ingestion_records r2
    on r2.batch_id=r1.batch_id
   and r2.row_number<r1.row_number
   and r2.normalized_payload->>'normalized_title'=r1.normalized_payload->>'normalized_title'
  where r1.batch_id=p_batch_id
    and r1.created_authority_id is null
    and r1.matched_authority_id is null
  on conflict do nothing;
  get diagnostics v_count=row_count; v_total:=v_total+v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id,candidate_authority_id,candidate_kind,match_method,score,algorithm_version,evidence)
  select
    r.id,a.id,'identity','fuzzy_canonical_title',
    extensions.similarity(r.normalized_payload->>'normalized_title',a.normalized_title)::numeric(6,5),
    p_algorithm_version,jsonb_build_object('candidate_title',a.canonical_title)
  from public.legal_ingestion_records r
  join public.legal_authorities a
    on extensions.similarity(r.normalized_payload->>'normalized_title',a.normalized_title)>=p_min_similarity
  where r.batch_id=p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
    and a.normalized_title<>r.normalized_payload->>'normalized_title'
  on conflict do nothing;
  get diagnostics v_count=row_count; v_total:=v_total+v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id,candidate_ingestion_record_id,candidate_kind,match_method,score,algorithm_version,evidence)
  select
    r1.id,r2.id,'identity','within_batch_fuzzy_title',
    extensions.similarity(r1.normalized_payload->>'normalized_title',r2.normalized_payload->>'normalized_title')::numeric(6,5),
    p_algorithm_version,
    jsonb_build_object('candidate_row_number',r2.row_number,'candidate_title',r2.metadata->>'title')
  from public.legal_ingestion_records r1
  join public.legal_ingestion_records r2
    on r2.batch_id=r1.batch_id
   and r2.id<>r1.id
   and extensions.similarity(r1.normalized_payload->>'normalized_title',r2.normalized_payload->>'normalized_title')>=p_min_similarity
  where r1.batch_id=p_batch_id
    and r1.created_authority_id is null
    and r1.matched_authority_id is null
    and r1.normalized_payload->>'normalized_title'<>r2.normalized_payload->>'normalized_title'
  on conflict do nothing;
  get diagnostics v_count=row_count; v_total:=v_total+v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id,candidate_ingestion_record_id,candidate_kind,match_method,score,algorithm_version,evidence)
  select
    r1.id,r2.id,'related_or_variant','within_batch_title_containment',0.70000,p_algorithm_version,
    jsonb_build_object('candidate_row_number',r2.row_number,'candidate_title',r2.metadata->>'title')
  from public.legal_ingestion_records r1
  join public.legal_ingestion_records r2
    on r2.batch_id=r1.batch_id and r2.id<>r1.id
  where r1.batch_id=p_batch_id
    and r1.created_authority_id is null
    and r1.matched_authority_id is null
    and length(r2.normalized_payload->>'normalized_title')>=10
    and position(r2.normalized_payload->>'normalized_title' in r1.normalized_payload->>'normalized_title')>0
    and r1.normalized_payload->>'normalized_title'<>r2.normalized_payload->>'normalized_title'
  on conflict do nothing;
  get diagnostics v_count=row_count; v_total:=v_total+v_count;

  with ranked as (
    select c.id as candidate_id,
           row_number() over (
             partition by c.ingestion_record_id
             order by c.score desc,c.created_at,c.id
           ) as rn
    from public.legal_ingestion_candidates c
    join public.legal_ingestion_records r on r.id=c.ingestion_record_id
    where r.batch_id=p_batch_id
      and r.created_authority_id is null
      and r.matched_authority_id is null
      and c.algorithm_version=p_algorithm_version
  )
  update public.legal_ingestion_candidates c
  set rank=ranked.rn
  from ranked
  where c.id=ranked.candidate_id;

  return v_total;
end;
$$;

revoke all on function private.generate_legal_ingestion_candidates(uuid,numeric,text)
  from public,anon,authenticated;
grant execute on function private.generate_legal_ingestion_candidates(uuid,numeric,text)
  to service_role;

