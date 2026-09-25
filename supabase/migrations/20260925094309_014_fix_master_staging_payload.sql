
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
      sr.id as source_record_id,
      sr.raw_payload as source_raw_payload
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
      prepared.source_raw_payload || jsonb_build_object('source_record_id',prepared.source_record_id),
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
        'source_record_id',prepared.source_record_id
      )
    from prepared
    on conflict (batch_id,row_number) do update
    set external_id=excluded.external_id,
        raw_payload=excluded.raw_payload,
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
  set status=case when status in ('registered','pilot_reconciled_new_master') then 'staging' else status end,
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

