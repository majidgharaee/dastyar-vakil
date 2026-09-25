
update public.legal_taxonomies
set metadata = metadata - 'app_default',
    updated_at = now()
where coalesce((metadata->>'app_default')::boolean,false);

update public.legal_taxonomies
set metadata = metadata || jsonb_build_object(
      'app_default',true,
      'catalog_generation',1,
      'snapshot_date','1405-07-03'
    ),
    updated_at=now()
where code='lawlex_snapshot_1405_07_03';

create or replace view public.legal_catalog_taxonomies_v1
with (security_invoker = true)
as
select
  t.id,
  t.code,
  t.name_fa,
  t.name_en,
  t.taxonomy_kind,
  coalesce((t.metadata->>'app_default')::boolean,false) as app_default,
  t.updated_at
from public.legal_taxonomies t
where t.is_active;

grant select on public.legal_catalog_taxonomies_v1 to anon,authenticated;

create unique index if not exists legal_taxonomies_single_app_default_uidx
  on public.legal_taxonomies ((coalesce((metadata->>'app_default')::boolean,false)))
  where coalesce((metadata->>'app_default')::boolean,false);

