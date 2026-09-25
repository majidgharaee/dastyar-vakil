
update public.legal_authority_categories ac
set relation_kind='master_classification_pending_qa',
    metadata=ac.metadata||jsonb_build_object(
      'category_review_status','pending_qa',
      'category_source','expanded_master_catalog',
      'master_version','1405-07-03-expanded-v1'
    )
from public.legal_authorities a
join public.legal_categories c on true
join public.legal_taxonomies t on t.id=c.taxonomy_id
where ac.authority_id=a.id
  and ac.category_id=c.id
  and t.code='master_subjects'
  and a.metadata->>'current_master_catalog'='master_catalog_expanded_1405_07_03'
  and ac.relation_kind<>'canonical_verified';

create or replace view private.legal_content_enrichment_queue
as
select
  lc.authority_id,
  lc.title,
  lc.authority_type_code,
  lc.category_code,
  lc.category_name_fa,
  lc.subtopic,
  lc.content_status_code,
  lc.verification_status_code,
  lc.effect_status_code,
  lc.master_sort_order,
  case
    when lc.content_status_code='catalog_only' then 'acquire_text'
    when lc.content_status_code='partial_text' then 'complete_text'
    when lc.content_status_code='full_text'
         and lc.verification_status_code='unverified' then 'verify_source'
    when lc.content_status_code='full_text'
         and lc.verification_status_code='source_verified' then 'upgrade_official_source'
    else 'none'
  end as next_action,
  case
    when lc.authority_type_code in ('law','legislative_decree') then 10
    when lc.authority_type_code in ('bylaw','regulation','decree','resolution') then 20
    else 30
  end as default_priority
from public.legal_catalog_current lc
where not lc.rag_eligible;


