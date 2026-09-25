
create or replace function private.stage_master_catalog_minimal(
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
  select source_id into v_source_id
  from public.legal_ingestion_batches
  where id=p_batch_id;
  if v_source_id is null then raise exception 'Unknown batch %', p_batch_id; end if;

  with input_rows as (
    select
      (v->>0)::int as row_id,
      v->>1 as title,
      v->>2 as doc_type,
      v->>3 as category_code,
      nullif(v->>4,'') as subtopic,
      nullif(v->>5,'') as discovery_source,
      nullif(v->>6,'') as source_level,
      nullif(v->>7,'') as source_url
    from jsonb_array_elements(p_rows) e(v)
  ),
  prepared as (
    select i.*,
           coalesce(tl.authority_type_code,'other_legal_document') as type_code,
           c.id as category_id,
           c.name_fa as category_name
    from input_rows i
    left join public.legal_authority_type_labels tl
      on tl.source_scope='global'
     and tl.normalized_label=public.legal_normalize_text(i.doc_type)
     and tl.is_active
    left join public.legal_taxonomies tx on tx.code='master_subjects'
    left join public.legal_categories c
      on c.taxonomy_id=tx.id and c.code=i.category_code
  ),
  sr as (
    insert into public.legal_source_records
      (source_id,external_id,title_as_published,raw_payload,metadata)
    select
      v_source_id,
      'master-row-'||lpad(row_id::text,4,'0'),
      title,
      jsonb_build_object(
        'ID',row_id,
        'عنوان قانون/مقرره',title,
        'نوع سند',doc_type,
        'کد دسته نهایی',category_code,
        'دسته اصلی نهایی',category_name,
        'زیرموضوع پیشنهادی',subtopic,
        'منبع کشف/تطبیق',discovery_source,
        'سطح منبع',source_level,
        'URL منبع',source_url
      ),
      jsonb_build_object(
        'master_version',p_master_version,
        'discovery_source',discovery_source,
        'source_level',source_level,
        'source_listing_url',source_url,
        'requires_official_verification',true,
        'base_or_new',case when row_id<=706 then 'base' else 'expanded' end
      )
    from prepared
    on conflict (source_id,external_id) where external_id is not null do update
    set title_as_published=excluded.title_as_published,
        raw_payload=excluded.raw_payload,
        metadata=public.legal_source_records.metadata || excluded.metadata
    returning id,external_id,raw_payload
  ),
  joined as (
    select p.*,sr.id as source_record_id,sr.raw_payload
    from prepared p
    join sr on sr.external_id=('master-row-'||lpad(p.row_id::text,4,'0'))
  ),
  ins as (
    insert into public.legal_ingestion_records
      (batch_id,row_number,external_id,raw_payload,normalized_payload,resolution_status,metadata)
    select
      p_batch_id,
      row_id,
      'master-row-'||lpad(row_id::text,4,'0'),
      raw_payload || jsonb_build_object('source_record_id',source_record_id),
      jsonb_build_object(
        'normalized_title',public.legal_normalize_text(title),
        'document_type_code',type_code,
        'canonical_category_code',category_code,
        'canonical_category_id',category_id,
        'source_record_id',source_record_id
      ),
      'pending',
      jsonb_build_object(
        'master_catalog',true,
        'master_version',p_master_version,
        'source_record_id',source_record_id,
        'requires_official_verification',true
      )
    from joined
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
  select count(*) into v_count from ins;

  update public.legal_ingestion_batches
  set status='staging',
      metadata=metadata || jsonb_build_object(
        'last_stage_at',now(),
        'master_version',p_master_version,
        'normalized_repeated_fields',true
      ),
      updated_at=now()
  where id=p_batch_id;

  return v_count;
end;
$$;

revoke all on function private.stage_master_catalog_minimal(uuid,jsonb,text)
  from public,anon,authenticated;
grant execute on function private.stage_master_catalog_minimal(uuid,jsonb,text)
  to service_role;

