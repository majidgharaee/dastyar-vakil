
grant select on public.directory_external_ids to anon,authenticated;

drop policy if exists directory_external_ids_public_read
on public.directory_external_ids;

create policy directory_external_ids_public_read
on public.directory_external_ids
for select to anon,authenticated
using (
  exists (
    select 1
    from public.directory_entities e
    where e.id=directory_external_ids.entity_id
      and e.is_public
  )
);

