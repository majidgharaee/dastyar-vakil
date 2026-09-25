
create or replace function private.canonicalize_master_catalog_batch(
  p_batch_id uuid,
  p_algorithm_version text default 'title-v2'
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private
as $$
declare
  rec record;
  v_auth uuid;
  v_exact uuid;
  v_prev uuid;
  v_jurisdiction uuid;
  v_source uuid;
  v_source_record uuid;
  v_category uuid;
  v_created integer := 0;
  v_matched integer := 0;
  v_issues integer := 0;
begin
  select id into v_jurisdiction
  from public.legal_jurisdictions
  where code='IR'
  limit 1;

  select source_id into v_source
  from public.legal_ingestion_batches
  where id=p_batch_id;

  if v_source is null then
    raise exception 'Unknown ingestion batch %',p_batch_id;
  end if;

  for rec in
    select *
    from public.legal_ingestion_records
    where batch_id=p_batch_id
    order by row_number
  loop
    v_auth := coalesce(rec.matched_authority_id,rec.created_authority_id);
    v_exact := null;
    v_prev := null;

    if v_auth is null then
      select c.candidate_authority_id
      into v_exact
      from public.legal_ingestion_candidates c
      where c.ingestion_record_id=rec.id
        and c.algorithm_version=p_algorithm_version
        and c.candidate_authority_id is not null
        and c.match_method in ('exact_canonical_title','exact_alias')
        and c.score>=0.995
      order by c.score desc,c.rank nulls last,c.id
      limit 1;

      if v_exact is not null then
        v_auth := v_exact;
        update public.legal_ingestion_records
        set matched_authority_id=v_auth,
            resolution_status='matched_existing',
            updated_at=now()
        where id=rec.id;
        v_matched := v_matched + 1;

        insert into public.legal_resolution_decisions
          (ingestion_record_id,decision_code,target_authority_id,confidence,
           decision_method,evidence,metadata)
        values
          (rec.id,'match_existing_authority',v_auth,1.00000,
           'exact_title_or_alias_v1',
           jsonb_build_object('algorithm_version',p_algorithm_version),
           jsonb_build_object('master_catalog',true))
        on conflict (ingestion_record_id) do update
        set decision_code=excluded.decision_code,
            target_authority_id=excluded.target_authority_id,
            confidence=excluded.confidence,
            decision_method=excluded.decision_method,
            evidence=excluded.evidence,
            metadata=public.legal_resolution_decisions.metadata||excluded.metadata,
            decided_at=now();

      else
        select coalesce(r2.matched_authority_id,r2.created_authority_id)
        into v_prev
        from public.legal_ingestion_records r2
        where r2.batch_id=p_batch_id
          and r2.row_number<rec.row_number
          and r2.normalized_payload->>'normalized_title'
              =rec.normalized_payload->>'normalized_title'
          and coalesce(r2.matched_authority_id,r2.created_authority_id) is not null
        order by r2.row_number
        limit 1;

        if v_prev is not null then
          v_auth := v_prev;
          update public.legal_ingestion_records
          set matched_authority_id=v_auth,
              resolution_status='matched_batch_duplicate',
              updated_at=now()
          where id=rec.id;
          v_matched := v_matched + 1;

          insert into public.legal_resolution_decisions
            (ingestion_record_id,decision_code,target_authority_id,confidence,
             decision_method,evidence,metadata)
          values
            (rec.id,'match_batch_exact_duplicate',v_auth,1.00000,
             'within_batch_exact_normalized_title_v1',
             jsonb_build_object('algorithm_version',p_algorithm_version),
             jsonb_build_object('master_catalog',true))
          on conflict (ingestion_record_id) do update
          set decision_code=excluded.decision_code,
              target_authority_id=excluded.target_authority_id,
              confidence=excluded.confidence,
              decision_method=excluded.decision_method,
              evidence=excluded.evidence,
              metadata=public.legal_resolution_decisions.metadata||excluded.metadata,
              decided_at=now();
        else
          insert into public.legal_authorities(
            authority_type_code,canonical_title,jurisdiction_id,
            publication_status_code,content_status_code,verification_status_code,
            effect_status_code,is_public,metadata
          )
          values(
            coalesce(nullif(rec.normalized_payload->>'document_type_code',''),'other_legal_document'),
            rec.raw_payload->>'عنوان قانون/مقرره',
            v_jurisdiction,
            'draft','catalog_only','unverified','unknown',false,
            jsonb_build_object(
              'current_master_catalog','master_catalog_expanded_1405_07_03',
              'current_master_row',rec.row_number,
              'master_version',rec.metadata->>'master_version',
              'master_document_type_label',rec.raw_payload->>'نوع سند',
              'master_category_code',rec.raw_payload->>'کد دسته نهایی',
              'master_category_name',rec.raw_payload->>'دسته اصلی نهایی',
              'master_subtopic',rec.raw_payload->>'زیرموضوع پیشنهادی',
              'master_source_level',rec.raw_payload->>'سطح منبع',
              'master_validity_note',rec.raw_payload->>'وضعیت تنقیحی/اعتبار',
              'master_research_note',rec.raw_payload->>'یادداشت پژوهش',
              'source_ingestion_record_id',rec.id
            )
          )
          returning id into v_auth;

          update public.legal_ingestion_records
          set created_authority_id=v_auth,
              resolution_status='created_new',
              updated_at=now()
          where id=rec.id;
          v_created := v_created + 1;

          insert into public.legal_resolution_decisions(
            ingestion_record_id,decision_code,target_authority_id,confidence,
            decision_method,evidence,metadata
          )
          values(
            rec.id,'new_authority',v_auth,0.98000,
            'distinct_normalized_title_create_v1',
            jsonb_build_object(
              'algorithm_version',p_algorithm_version,
              'fuzzy_candidates_preserved_not_merged',true
            ),
            jsonb_build_object('master_catalog',true)
          )
          on conflict (ingestion_record_id) do update
          set decision_code=excluded.decision_code,
              target_authority_id=excluded.target_authority_id,
              confidence=excluded.confidence,
              decision_method=excluded.decision_method,
              evidence=excluded.evidence,
              metadata=public.legal_resolution_decisions.metadata||excluded.metadata,
              decided_at=now();
        end if;
      end if;
    end if;

    v_source_record := nullif(rec.normalized_payload->>'source_record_id','')::uuid;
    v_category := nullif(rec.normalized_payload->>'canonical_category_id','')::uuid;

    if v_auth is not null then
      update public.legal_authorities a
      set authority_type_code=
            coalesce(nullif(rec.normalized_payload->>'document_type_code',''),a.authority_type_code),
          metadata=a.metadata||jsonb_build_object(
            'current_master_catalog','master_catalog_expanded_1405_07_03',
            'current_master_row',rec.row_number,
            'master_version',rec.metadata->>'master_version',
            'master_document_type_label',rec.raw_payload->>'نوع سند',
            'master_category_code',rec.raw_payload->>'کد دسته نهایی',
            'master_category_name',rec.raw_payload->>'دسته اصلی نهایی',
            'master_subtopic',rec.raw_payload->>'زیرموضوع پیشنهادی',
            'master_source_level',rec.raw_payload->>'سطح منبع',
            'master_validity_note',rec.raw_payload->>'وضعیت تنقیحی/اعتبار',
            'master_research_note',rec.raw_payload->>'یادداشت پژوهش'
          ),
          updated_at=now()
      where a.id=v_auth;

      insert into public.legal_external_ids(
        authority_id,source_id,external_id,external_url,source_record_id,metadata
      )
      values(
        v_auth,v_source,
        'master-row-'||lpad(rec.row_number::text,4,'0'),
        nullif(rec.raw_payload->>'URL منبع',''),
        v_source_record,
        jsonb_build_object('master_version',rec.metadata->>'master_version')
      )
      on conflict (source_id,external_id) do update
      set authority_id=excluded.authority_id,
          external_url=excluded.external_url,
          source_record_id=excluded.source_record_id,
          metadata=public.legal_external_ids.metadata||excluded.metadata;

      if v_category is not null then
        insert into public.legal_authority_categories(
          authority_id,category_id,source_record_id,confidence,relation_kind,metadata
        )
        values(
          v_auth,v_category,v_source_record,0.9000,
          'master_classification_pending_qa',
          jsonb_build_object(
            'master_version',rec.metadata->>'master_version',
            'master_row',rec.row_number,
            'subtopic',rec.raw_payload->>'زیرموضوع پیشنهادی'
          )
        )
        on conflict do nothing;
      end if;
    end if;
  end loop;

  delete from public.legal_ingestion_issues i
  using public.legal_ingestion_records r
  where i.ingestion_record_id=r.id
    and r.batch_id=p_batch_id
    and i.issue_code='possible_title_similarity';

  insert into public.legal_ingestion_issues(
    ingestion_record_id,severity,issue_code,field_name,message,details
  )
  select distinct on (c.ingestion_record_id)
    c.ingestion_record_id,
    case when c.score>=0.95 then 'high' else 'warning' end,
    'possible_title_similarity',
    'title',
    'عنوان با یک مرجع دیگر شباهت بالا دارد؛ ادغام خودکار انجام نشد و بازبینی انسانی/منبع رسمی لازم است.',
    jsonb_build_object(
      'candidate_kind',c.candidate_kind,
      'match_method',c.match_method,
      'score',c.score,
      'candidate_authority_id',c.candidate_authority_id,
      'candidate_ingestion_record_id',c.candidate_ingestion_record_id,
      'algorithm_version',c.algorithm_version
    )
  from public.legal_ingestion_candidates c
  join public.legal_ingestion_records r on r.id=c.ingestion_record_id
  where r.batch_id=p_batch_id
    and c.algorithm_version=p_algorithm_version
    and c.match_method in ('fuzzy_canonical_title','within_batch_fuzzy_title')
    and c.score>=0.90
    and c.score<1.0
  order by c.ingestion_record_id,c.score desc,c.id;

  get diagnostics v_issues=row_count;

  update public.legal_ingestion_batches
  set status='canonicalized_catalog_only',
      processed_rows=(select count(*) from public.legal_ingestion_records where batch_id=p_batch_id),
      created_rows=(select count(*) from public.legal_ingestion_records where batch_id=p_batch_id and resolution_status='created_new'),
      matched_rows=(select count(*) from public.legal_ingestion_records where batch_id=p_batch_id and resolution_status in ('matched_existing','matched_batch_duplicate')),
      issue_rows=(select count(distinct i.ingestion_record_id)
                  from public.legal_ingestion_issues i
                  join public.legal_ingestion_records r on r.id=i.ingestion_record_id
                  where r.batch_id=p_batch_id),
      completed_at=now(),
      metadata=metadata||jsonb_build_object(
        'canonicalization_version','master-v1',
        'candidate_algorithm',p_algorithm_version,
        'fuzzy_auto_merge',false,
        'catalog_only',true
      ),
      updated_at=now()
  where id=p_batch_id;

  return jsonb_build_object(
    'created_new',v_created,
    'matched_this_run',v_matched,
    'issues_inserted',v_issues
  );
end;
$$;

revoke all on function private.canonicalize_master_catalog_batch(uuid,text)
from public,anon,authenticated;
grant execute on function private.canonicalize_master_catalog_batch(uuid,text)
to service_role;

