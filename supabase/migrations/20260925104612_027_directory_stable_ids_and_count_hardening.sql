
create or replace view public.directory_group_counts
with (security_invoker=true)
as
select
  g.id as group_id,
  g.code as group_code,
  g.name_fa as group_name,
  g.sort_order,
  count(distinct e.id) as entity_count
from public.directory_groups g
left join public.directory_entity_classifications c on c.group_id=g.id
left join public.directory_entities e on e.id=c.entity_id and e.is_public
where g.is_active
group by g.id,g.code,g.name_fa,g.sort_order;

create or replace view public.directory_subgroup_counts
with (security_invoker=true)
as
select
  sg.id as subgroup_id,
  sg.code as subgroup_code,
  sg.name_fa as subgroup_name,
  g.code as group_code,
  g.name_fa as group_name,
  sg.sort_order,
  count(distinct e.id) as entity_count
from public.directory_subgroups sg
join public.directory_groups g on g.id=sg.group_id
left join public.directory_entity_classifications c on c.subgroup_id=sg.id
left join public.directory_entities e on e.id=c.entity_id and e.is_public
where sg.is_active and g.is_active
group by sg.id,sg.code,sg.name_fa,g.code,g.name_fa,sg.sort_order;

create or replace view public.directory_current
with (security_invoker=true)
as
select
  e.id as entity_id,
  e.canonical_name as name,
  e.status_code,
  v.province,
  v.county,
  v.city,
  v.municipal_region,
  v.jurisdiction_scope,
  v.address,
  v.postal_code,
  v.hours_text,
  v.operational_status,
  v.confidence_level,
  v.verification_status,
  v.source_date_text,
  v.source_name,
  v.source_url,
  v.map_url,
  v.lawyer_use,
  v.project_scope,
  v.notes,
  v.latitude,
  v.longitude,
  v.geocode_status,
  p.group_code as primary_group_code,
  p.group_name as primary_group_name,
  p.subgroup_code as primary_subgroup_code,
  p.subgroup_name as primary_subgroup_name,
  coalesce(ph.phone_text,'') as phone,
  coalesce(cls.memberships,'[]'::jsonb) as classifications,
  (v.verification_status='official_verified') as official_verified,
  (v.verification_status='needs_verification') as verification_required,
  (v.geocode_status='verified') as coordinate_verified,
  e.updated_at,
  ids.primary_external_id,
  coalesce(ids.external_ids,'[]'::jsonb) as external_ids
from public.directory_entities e
join public.directory_entity_versions v
  on v.id=e.current_version_id and v.is_current
left join lateral (
  select
    g.code as group_code,
    g.name_fa as group_name,
    sg.code as subgroup_code,
    sg.name_fa as subgroup_name
  from public.directory_entity_classifications c
  join public.directory_groups g on g.id=c.group_id
  left join public.directory_subgroups sg on sg.id=c.subgroup_id
  where c.entity_id=e.id
  order by c.is_primary desc,c.created_at,c.id
  limit 1
) p on true
left join lateral (
  select string_agg(c.value,' / ' order by c.is_primary desc,c.sort_order,c.created_at) as phone_text
  from public.directory_contacts c
  where c.entity_version_id=v.id and c.contact_type='phone'
) ph on true
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'group_code',g.code,
      'group_name',g.name_fa,
      'subgroup_code',sg.code,
      'subgroup_name',sg.name_fa,
      'is_primary',c.is_primary
    )
    order by c.is_primary desc,g.sort_order,sg.sort_order
  ) as memberships
  from public.directory_entity_classifications c
  join public.directory_groups g on g.id=c.group_id
  left join public.directory_subgroups sg on sg.id=c.subgroup_id
  where c.entity_id=e.id
) cls on true
left join lateral (
  select
    (array_agg(x.external_id order by x.created_at,x.external_id))[1] as primary_external_id,
    jsonb_agg(x.external_id order by x.created_at,x.external_id) as external_ids
  from public.directory_external_ids x
  where x.entity_id=e.id
    and x.source_code='tehran_legal_directory'
) ids on true
where e.is_public;

grant select on public.directory_current to anon,authenticated;

