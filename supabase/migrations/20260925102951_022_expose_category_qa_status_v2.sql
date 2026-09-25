
update public.legal_authority_categories ac
set relation_kind='master_classification_pending_qa',
    metadata=ac.metadata||jsonb_build_object(
      'category_review_status','pending_qa',
      'category_source','expanded_master_catalog'
    )
where ac.metadata->>'master_version'='1405-07-03-expanded-v1'
  and ac.relation_kind in ('canonical_master_classification','master_classification_pending_qa');

create or replace view public.legal_catalog_current
with (security_invoker=true)
as
select
  a.id as authority_id,
  a.authority_type_code,
  at.name_fa as authority_type_name_fa,
  a.canonical_title as title,
  a.content_status_code,
  cs.name_fa as content_status_name_fa,
  a.verification_status_code,
  vs.name_fa as verification_status_name_fa,
  a.effect_status_code,
  es.name_fa as effect_status_name_fa,
  cat.code as category_code,
  cat.name_fa as category_name_fa,
  ac.metadata->>'subtopic' as subtopic,
  (a.content_status_code in ('partial_text','full_text')) as has_text,
  (
    a.content_status_code='full_text'
    and a.verification_status_code in ('source_verified','official_verified')
  ) as rag_eligible,
  (a.verification_status_code='official_verified') as official_verified,
  coalesce((a.metadata->>'current_master_row')::integer,999999999) as master_sort_order,
  coalesce(ac.relation_kind,'unclassified') as category_relation_kind,
  case
    when ac.relation_kind='canonical_verified' then 'verified'
    when ac.relation_kind='master_classification_pending_qa' then 'pending_qa'
    when ac.relation_kind is null then 'unclassified'
    else 'source_classification'
  end as category_review_status,
  (ac.relation_kind='canonical_verified') as category_verified
from public.legal_authorities a
join public.legal_authority_types at on at.code=a.authority_type_code
join public.legal_content_statuses cs on cs.code=a.content_status_code
join public.legal_verification_statuses vs on vs.code=a.verification_status_code
join public.legal_effect_statuses es on es.code=a.effect_status_code
left join lateral (
  select ac1.*
  from public.legal_authority_categories ac1
  join public.legal_categories c1 on c1.id=ac1.category_id
  join public.legal_taxonomies t1 on t1.id=c1.taxonomy_id
  where ac1.authority_id=a.id
    and t1.code='master_subjects'
  order by
    case ac1.relation_kind
      when 'canonical_verified' then 1
      when 'master_classification_pending_qa' then 2
      else 9
    end,
    ac1.created_at desc
  limit 1
) ac on true
left join public.legal_categories cat on cat.id=ac.category_id
where a.is_public
  and a.metadata->>'current_master_catalog'='master_catalog_expanded_1405_07_03';

grant select on public.legal_catalog_current to anon,authenticated;

create or replace view private.legal_catalog_review_queue
as
select
  r.id as ingestion_record_id,
  r.row_number,
  r.raw_payload->>'عنوان قانون/مقرره' as title,
  r.raw_payload->>'نوع سند' as document_type_label,
  r.raw_payload->>'کد دسته نهایی' as source_category_code,
  r.raw_payload->>'دسته اصلی نهایی' as source_category_name,
  r.raw_payload->>'زیرموضوع پیشنهادی' as source_subtopic,
  coalesce(r.matched_authority_id,r.created_authority_id) as authority_id,
  exists (
    select 1
    from public.legal_ingestion_issues i
    where i.ingestion_record_id=r.id
      and i.issue_code='possible_title_similarity'
  ) as title_similarity_review_required,
  true as category_review_required,
  r.resolution_status
from public.legal_ingestion_records r
where r.batch_id='241d546e-59b1-43b3-99e1-656c08045dc4'::uuid;

