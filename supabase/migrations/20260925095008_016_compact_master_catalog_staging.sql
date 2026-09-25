
create or replace function private.stage_master_catalog_compact(
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
  v_expanded jsonb;
begin
  select jsonb_agg(
    jsonb_build_object(
      'id',(x.value->>0)::integer,
      'title',x.value->>1,
      'doc_type',x.value->>2,
      'old_category',nullif(x.value->>3,''),
      'cat_code',x.value->>4,
      'cat_name',x.value->>5,
      'subtopic',nullif(x.value->>6,''),
      'legacy_app_category',nullif(x.value->>7,''),
      'app_category_status',nullif(x.value->>8,''),
      'in_base',nullif(x.value->>9,''),
      'project_status',nullif(x.value->>10,''),
      'source_name',nullif(x.value->>11,''),
      'source_level',nullif(x.value->>12,''),
      'source_url',nullif(x.value->>13,''),
      'national_url',nullif(x.value->>14,''),
      'official_gazette_url',nullif(x.value->>15,''),
      'validity_note',nullif(x.value->>16,''),
      'research_note',nullif(x.value->>17,'')
    )
    order by (x.value->>0)::integer
  )
  into v_expanded
  from jsonb_array_elements(p_rows) x;

  return private.stage_master_catalog_rows(p_batch_id,v_expanded,p_master_version);
end;
$$;

revoke all on function private.stage_master_catalog_compact(uuid,jsonb,text)
  from public,anon,authenticated;
grant execute on function private.stage_master_catalog_compact(uuid,jsonb,text)
  to service_role;

