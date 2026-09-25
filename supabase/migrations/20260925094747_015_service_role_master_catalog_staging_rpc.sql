
create or replace function public.service_stage_master_catalog_rows(
  p_batch_id uuid,
  p_rows jsonb,
  p_master_version text default 'current'
)
returns integer
language sql
security invoker
set search_path = public, private
as $$
  select private.stage_master_catalog_rows(p_batch_id,p_rows,p_master_version);
$$;

revoke all on function public.service_stage_master_catalog_rows(uuid,jsonb,text)
  from public, anon, authenticated;
grant execute on function public.service_stage_master_catalog_rows(uuid,jsonb,text)
  to service_role;

