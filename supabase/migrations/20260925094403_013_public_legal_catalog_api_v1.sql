
create or replace view public.legal_catalog_authorities_v1
with (security_invoker = true)
as
select
  a.id,
  a.canonical_title,
  a.normalized_title,
  a.short_title,
  a.authority_type_code,
  at.name_fa as authority_type_name_fa,
  a.official_number,
  a.issued_at,
  a.effective_from,
  a.effective_to,
  a.publication_status_code,
  a.content_status_code,
  a.verification_status_code,
  a.effect_status_code,
  a.current_version_id,
  (a.content_status_code = 'full_text') as has_full_text,
  coalesce((a.metadata->>'entity_resolution_review')::boolean,false) as entity_resolution_review,
  a.updated_at
from public.legal_authorities a
join public.legal_authority_types at
  on at.code=a.authority_type_code
where a.is_public;

create or replace view public.legal_catalog_categories_v1
with (security_invoker = true)
as
select
  c.id,
  c.taxonomy_id,
  t.code as taxonomy_code,
  t.name_fa as taxonomy_name_fa,
  t.taxonomy_kind,
  c.parent_id,
  c.code as category_code,
  c.name_fa,
  c.name_en,
  c.sort_order
from public.legal_categories c
join public.legal_taxonomies t on t.id=c.taxonomy_id
where c.is_active and t.is_active;

create or replace view public.legal_catalog_authority_categories_v1
with (security_invoker = true)
as
select
  ac.authority_id,
  ac.category_id,
  t.code as taxonomy_code,
  ac.relation_kind,
  ac.confidence
from public.legal_authority_categories ac
join public.legal_authorities a on a.id=ac.authority_id
join public.legal_categories c on c.id=ac.category_id
join public.legal_taxonomies t on t.id=c.taxonomy_id
where a.is_public and c.is_active and t.is_active;

revoke all on public.legal_catalog_authorities_v1 from public;
revoke all on public.legal_catalog_categories_v1 from public;
revoke all on public.legal_catalog_authority_categories_v1 from public;

grant select on public.legal_catalog_authorities_v1 to anon,authenticated;
grant select on public.legal_catalog_categories_v1 to anon,authenticated;
grant select on public.legal_catalog_authority_categories_v1 to anon,authenticated;

