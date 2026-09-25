
update public.legal_authorities
set is_public=true,
    publication_status_code='published',
    updated_at=now()
where metadata->>'current_master_catalog'='master_catalog_expanded_1405_07_03';

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
  coalesce((a.metadata->>'current_master_row')::integer,999999999) as master_sort_order
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
      when 'canonical_master_classification' then 1
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

