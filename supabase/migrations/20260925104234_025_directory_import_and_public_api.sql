
create or replace function private.import_directory_rows(
  p_batch_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private, extensions
as $$
declare
  r record;
  v_group_id uuid;
  v_subgroup_id uuid;
  v_source_record_id uuid;
  v_entity_id uuid;
  v_existing_external uuid;
  v_current_version_id uuid;
  v_current_fingerprint text;
  v_fingerprint text;
  v_version_no integer;
  v_created integer := 0;
  v_matched integer := 0;
  v_processed integer := 0;
  v_match_reason text;
  v_confidence text;
  v_verification text;
  v_status_code text;
  v_is_primary boolean;
  v_issue_rows integer := 0;
  phone_part text;
begin
  if not exists (select 1 from public.directory_import_batches where id=p_batch_id) then
    raise exception 'Unknown directory import batch %', p_batch_id;
  end if;

  update public.directory_import_batches
  set status='importing', started_at=coalesce(started_at,now())
  where id=p_batch_id;

  for r in
    select *
    from jsonb_to_recordset(p_rows) as x(
      row_number integer,
      external_id text,
      group_name text,
      subgroup_name text,
      name text,
      province text,
      county text,
      city text,
      municipal_region text,
      jurisdiction_scope text,
      address text,
      phone text,
      postal_code text,
      hours_text text,
      operational_status text,
      confidence text,
      source_date text,
      source_name text,
      source_url text,
      map_url text,
      lawyer_use text,
      project_scope text,
      notes text,
      raw jsonb
    )
    order by row_number
  loop
    v_processed := v_processed + 1;
    v_group_id := null;
    v_subgroup_id := null;
    v_source_record_id := null;
    v_entity_id := null;
    v_existing_external := null;
    v_match_reason := null;

    select id into v_group_id
    from public.directory_groups
    where normalized_name=public.directory_normalize_text(r.group_name);

    if v_group_id is null then
      insert into public.directory_groups(code,name_fa,sort_order,metadata)
      values(
        'g-'||substr(md5(coalesce(public.directory_normalize_text(r.group_name),r.group_name)),1,12),
        r.group_name,
        r.row_number,
        jsonb_build_object('source_batch_id',p_batch_id)
      )
      returning id into v_group_id;
    end if;

    if nullif(trim(coalesce(r.subgroup_name,'')),'') is not null then
      select id into v_subgroup_id
      from public.directory_subgroups
      where group_id=v_group_id
        and normalized_name=public.directory_normalize_text(r.subgroup_name);

      if v_subgroup_id is null then
        insert into public.directory_subgroups(group_id,code,name_fa,sort_order,metadata)
        values(
          v_group_id,
          'sg-'||substr(md5(
            coalesce(public.directory_normalize_text(r.group_name),'')||'|'||
            coalesce(public.directory_normalize_text(r.subgroup_name),'')
          ),1,12),
          r.subgroup_name,
          r.row_number,
          jsonb_build_object('source_batch_id',p_batch_id)
        )
        returning id into v_subgroup_id;
      end if;
    end if;

    insert into public.directory_source_records(
      batch_id,row_number,external_id,raw_payload,normalized_payload,resolution_status,metadata
    )
    values(
      p_batch_id,
      r.row_number,
      r.external_id,
      coalesce(r.raw,'{}'::jsonb),
      jsonb_build_object(
        'normalized_name',public.directory_normalize_text(r.name),
        'normalized_address',public.directory_normalize_text(r.address),
        'normalized_phone',public.directory_normalize_text(r.phone)
      ),
      'pending',
      jsonb_build_object('group_name',r.group_name,'subgroup_name',r.subgroup_name)
    )
    on conflict (batch_id,row_number) do update
    set external_id=excluded.external_id,
        raw_payload=excluded.raw_payload,
        normalized_payload=excluded.normalized_payload,
        metadata=public.directory_source_records.metadata||excluded.metadata,
        updated_at=now()
    returning id into v_source_record_id;

    select e.entity_id into v_existing_external
    from public.directory_external_ids e
    join public.directory_import_batches b on b.source_code=e.source_code
    where b.id=p_batch_id
      and e.external_id=r.external_id
    limit 1;

    if v_existing_external is not null then
      v_entity_id := v_existing_external;
      v_match_reason := 'external_id';
      v_matched := v_matched + 1;
    else
      select e.id into v_entity_id
      from public.directory_entities e
      join public.directory_entity_versions v
        on v.id=e.current_version_id and v.is_current
      where e.normalized_name=public.directory_normalize_text(r.name)
        and (
          v.normalized_address=public.directory_normalize_text(r.address)
          or (
            nullif(public.directory_normalize_text(r.phone),'') is not null
            and exists (
              select 1
              from public.directory_contacts c
              where c.entity_version_id=v.id
                and c.contact_type='phone'
                and c.normalized_value in (
                  select public.directory_normalize_text(trim(x))
                  from regexp_split_to_table(coalesce(r.phone,''),'[/،,]+') x
                  where nullif(trim(x),'') is not null
                )
            )
          )
        )
      order by e.created_at
      limit 1;

      if v_entity_id is not null then
        v_match_reason := 'exact_identity_evidence';
        v_matched := v_matched + 1;
      else
        v_status_code := case
          when coalesce(r.operational_status,'') ilike '%غیرفعال%' then 'inactive'
          else 'active'
        end;

        insert into public.directory_entities(
          canonical_name,status_code,is_public,metadata
        )
        values(
          r.name,
          v_status_code,
          true,
          jsonb_build_object(
            'first_batch_id',p_batch_id,
            'first_external_id',r.external_id
          )
        )
        returning id into v_entity_id;

        v_match_reason := 'created_new';
        v_created := v_created + 1;
      end if;
    end if;

    insert into public.directory_external_ids(
      entity_id,source_code,external_id,source_record_id,metadata
    )
    select
      v_entity_id,b.source_code,r.external_id,v_source_record_id,
      jsonb_build_object('batch_id',p_batch_id)
    from public.directory_import_batches b
    where b.id=p_batch_id
    on conflict (source_code,external_id) do update
    set entity_id=excluded.entity_id,
        source_record_id=excluded.source_record_id,
        metadata=public.directory_external_ids.metadata||excluded.metadata;

    v_confidence := case trim(coalesce(r.confidence,''))
      when 'بالا' then 'high'
      when 'متوسط' then 'medium'
      when 'پایین' then 'low'
      else 'unknown'
    end;

    v_verification := case
      when trim(coalesce(r.confidence,''))='پایین'
        or coalesce(r.operational_status,'') ilike '%نیازمند تکمیل%'
        or coalesce(r.address,'') ilike '%احراز نشد%'
        or coalesce(r.address,'') ilike '%راستی‌آزمایی%'
      then 'needs_verification'
      else 'source_reviewed'
    end;

    v_status_code := case
      when coalesce(r.operational_status,'') ilike '%غیرفعال%' then 'inactive'
      else 'active'
    end;

    update public.directory_entities
    set canonical_name=r.name,
        status_code=v_status_code,
        is_public=true,
        metadata=metadata||jsonb_build_object(
          'last_batch_id',p_batch_id,
          'last_external_id',r.external_id
        ),
        updated_at=now()
    where id=v_entity_id;

    v_fingerprint := md5(concat_ws('|',
      public.directory_normalize_text(r.name),
      public.directory_normalize_text(r.province),
      public.directory_normalize_text(r.county),
      public.directory_normalize_text(r.city),
      public.directory_normalize_text(r.municipal_region),
      public.directory_normalize_text(r.jurisdiction_scope),
      public.directory_normalize_text(r.address),
      public.directory_normalize_text(r.phone),
      public.directory_normalize_text(r.postal_code),
      public.directory_normalize_text(r.hours_text),
      public.directory_normalize_text(r.operational_status),
      v_confidence,
      public.directory_normalize_text(r.source_date),
      public.directory_normalize_text(r.source_name),
      r.source_url,
      r.map_url,
      public.directory_normalize_text(r.lawyer_use),
      public.directory_normalize_text(r.project_scope),
      public.directory_normalize_text(r.notes)
    ));

    select e.current_version_id, v.metadata->>'version_fingerprint'
    into v_current_version_id, v_current_fingerprint
    from public.directory_entities e
    left join public.directory_entity_versions v on v.id=e.current_version_id
    where e.id=v_entity_id;

    if v_current_version_id is null or v_current_fingerprint is distinct from v_fingerprint then
      if v_current_version_id is not null then
        update public.directory_entity_versions
        set is_current=false
        where id=v_current_version_id;
      end if;

      select coalesce(max(version_number),0)+1
      into v_version_no
      from public.directory_entity_versions
      where entity_id=v_entity_id;

      insert into public.directory_entity_versions(
        entity_id,version_number,source_record_id,name_at_source,
        province,county,city,municipal_region,jurisdiction_scope,address,
        postal_code,hours_text,operational_status,confidence_level,
        verification_status,source_date_text,source_name,source_url,map_url,
        lawyer_use,project_scope,notes,latitude,longitude,geocode_status,is_current,metadata
      )
      values(
        v_entity_id,v_version_no,v_source_record_id,r.name,
        nullif(r.province,''),nullif(r.county,''),nullif(r.city,''),
        nullif(r.municipal_region,''),nullif(r.jurisdiction_scope,''),r.address,
        nullif(r.postal_code,''),nullif(r.hours_text,''),nullif(r.operational_status,''),
        v_confidence,v_verification,nullif(r.source_date,''),nullif(r.source_name,''),
        nullif(r.source_url,''),nullif(r.map_url,''),nullif(r.lawyer_use,''),
        nullif(r.project_scope,''),nullif(r.notes,''),null,null,'search_link_only',true,
        jsonb_build_object(
          'version_fingerprint',v_fingerprint,
          'batch_id',p_batch_id,
          'external_id',r.external_id,
          'match_reason',v_match_reason
        )
      )
      returning id into v_current_version_id;

      update public.directory_entities
      set current_version_id=v_current_version_id
      where id=v_entity_id;

      delete from public.directory_contacts
      where entity_version_id=v_current_version_id;

      if nullif(trim(coalesce(r.phone,'')),'') is not null then
        for phone_part in
          select trim(x)
          from regexp_split_to_table(r.phone,'[/،,]+') x
          where nullif(trim(x),'') is not null
        loop
          insert into public.directory_contacts(
            entity_version_id,contact_type,value,is_primary,sort_order
          )
          values(
            v_current_version_id,'phone',phone_part,
            not exists (
              select 1 from public.directory_contacts c
              where c.entity_version_id=v_current_version_id and c.contact_type='phone'
            ),
            100
          )
          on conflict do nothing;
        end loop;
      end if;
    end if;

    select not exists(
      select 1 from public.directory_entity_classifications c
      where c.entity_id=v_entity_id and c.is_primary
    ) into v_is_primary;

    insert into public.directory_entity_classifications(
      entity_id,group_id,subgroup_id,source_record_id,is_primary,metadata
    )
    values(
      v_entity_id,v_group_id,v_subgroup_id,v_source_record_id,v_is_primary,
      jsonb_build_object('batch_id',p_batch_id,'external_id',r.external_id)
    )
    on conflict (entity_id,group_id,subgroup_id) do update
    set source_record_id=excluded.source_record_id,
        metadata=public.directory_entity_classifications.metadata||excluded.metadata;

    update public.directory_source_records
    set resolved_entity_id=v_entity_id,
        resolution_status=case
          when v_match_reason='created_new' then 'created_new'
          when v_match_reason='external_id' then 'matched_external_id'
          else 'matched_exact_identity'
        end,
        metadata=metadata||jsonb_build_object('match_reason',v_match_reason),
        updated_at=now()
    where id=v_source_record_id;

    delete from public.directory_ingestion_issues
    where source_record_id=v_source_record_id;

    if v_confidence='low' then
      insert into public.directory_ingestion_issues(
        source_record_id,severity,issue_code,field_name,message,details
      )
      values(
        v_source_record_id,'high','low_confidence','confidence',
        'سطح اطمینان این مرجع پایین است و پیش از انتشار به‌عنوان نشانی قطعی باید راستی‌آزمایی شود.',
        jsonb_build_object('external_id',r.external_id)
      );
    end if;

    if coalesce(r.operational_status,'') ilike '%نیازمند تکمیل%'
       or coalesce(r.address,'') ilike '%احراز نشد%'
       or coalesce(r.address,'') ilike '%راستی‌آزمایی%' then
      insert into public.directory_ingestion_issues(
        source_record_id,severity,issue_code,field_name,message,details
      )
      values(
        v_source_record_id,'high','address_needs_verification','address',
        'نشانی فعلی نیازمند تکمیل یا راستی‌آزمایی رسمی است.',
        jsonb_build_object('external_id',r.external_id,'address',r.address)
      );
    end if;

    if v_status_code='inactive' then
      insert into public.directory_ingestion_issues(
        source_record_id,severity,issue_code,field_name,message,details
      )
      values(
        v_source_record_id,'warning','inactive_source_record','operational_status',
        'مرجع در فایل منبع غیرفعال اعلام شده است و باید با همین وضعیت در اپ نمایش داده شود.',
        jsonb_build_object('external_id',r.external_id)
      );
    end if;

    if v_match_reason='exact_identity_evidence' then
      insert into public.directory_ingestion_issues(
        source_record_id,severity,issue_code,field_name,message,details
      )
      values(
        v_source_record_id,'info','duplicate_source_resolved','name',
        'این ردیف با قرینه هویتی قوی به مرجع canonical موجود متصل شد؛ رکورد منبع حذف نشده است.',
        jsonb_build_object('external_id',r.external_id,'entity_id',v_entity_id)
      );
    end if;
  end loop;

  select count(distinct i.source_record_id)
  into v_issue_rows
  from public.directory_ingestion_issues i
  join public.directory_source_records sr on sr.id=i.source_record_id
  where sr.batch_id=p_batch_id;

  update public.directory_import_batches
  set processed_rows=(select count(*) from public.directory_source_records where batch_id=p_batch_id),
      created_entities=(select count(*) from public.directory_source_records where batch_id=p_batch_id and resolution_status='created_new'),
      matched_entities=(select count(*) from public.directory_source_records where batch_id=p_batch_id and resolution_status<>'created_new'),
      issue_rows=v_issue_rows,
      status='completed',
      completed_at=now(),
      updated_at=now()
  where id=p_batch_id;

  return jsonb_build_object(
    'processed',v_processed,
    'created',v_created,
    'matched',v_matched,
    'issue_rows',v_issue_rows
  );
end;
$$;

revoke all on function private.import_directory_rows(uuid,jsonb)
from public,anon,authenticated;
grant execute on function private.import_directory_rows(uuid,jsonb)
to service_role;

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
  e.updated_at
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
where e.is_public;

grant select on public.directory_current to anon,authenticated;

create or replace view public.directory_group_counts
with (security_invoker=true)
as
select
  g.id as group_id,
  g.code as group_code,
  g.name_fa as group_name,
  g.sort_order,
  count(distinct c.entity_id) as entity_count
from public.directory_groups g
left join public.directory_entity_classifications c on c.group_id=g.id
left join public.directory_entities e on e.id=c.entity_id and e.is_public
where g.is_active
group by g.id,g.code,g.name_fa,g.sort_order;

grant select on public.directory_group_counts to anon,authenticated;

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
  count(distinct c.entity_id) as entity_count
from public.directory_subgroups sg
join public.directory_groups g on g.id=sg.group_id
left join public.directory_entity_classifications c on c.subgroup_id=sg.id
left join public.directory_entities e on e.id=c.entity_id and e.is_public
where sg.is_active and g.is_active
group by sg.id,sg.code,sg.name_fa,g.code,g.name_fa,sg.sort_order;

grant select on public.directory_subgroup_counts to anon,authenticated;

create or replace function public.search_directory(
  p_query text default null,
  p_group_code text default null,
  p_subgroup_code text default null,
  p_city text default null,
  p_confidence_level text default null,
  p_include_inactive boolean default true,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  entity_id uuid,
  name text,
  primary_group_code text,
  primary_group_name text,
  primary_subgroup_code text,
  primary_subgroup_name text,
  city text,
  jurisdiction_scope text,
  address text,
  phone text,
  operational_status text,
  confidence_level text,
  verification_status text,
  source_date_text text,
  source_name text,
  source_url text,
  map_url text,
  lawyer_use text,
  project_scope text,
  verification_required boolean,
  relevance real
)
language sql
stable
security invoker
set search_path=public,extensions
as $$
  with q as (
    select coalesce(public.directory_normalize_text(coalesce(p_query,'')),'') as nq
  )
  select
    d.entity_id,
    d.name,
    d.primary_group_code,
    d.primary_group_name,
    d.primary_subgroup_code,
    d.primary_subgroup_name,
    d.city,
    d.jurisdiction_scope,
    d.address,
    d.phone,
    d.operational_status,
    d.confidence_level,
    d.verification_status,
    d.source_date_text,
    d.source_name,
    d.source_url,
    d.map_url,
    d.lawyer_use,
    d.project_scope,
    d.verification_required,
    case
      when q.nq='' then 0::real
      when e.normalized_name=q.nq then 1::real
      when e.normalized_name like q.nq||'%' then 0.98::real
      when e.normalized_name like '%'||q.nq||'%' then 0.95::real
      when v.normalized_address like '%'||q.nq||'%' then 0.90::real
      else greatest(
        extensions.similarity(e.normalized_name,q.nq),
        extensions.similarity(v.normalized_address,q.nq)
      )::real
    end as relevance
  from public.directory_current d
  join public.directory_entities e on e.id=d.entity_id
  join public.directory_entity_versions v on v.id=e.current_version_id
  cross join q
  where
    (p_include_inactive or e.status_code<>'inactive')
    and (p_city is null or p_city='' or d.city=p_city)
    and (p_confidence_level is null or p_confidence_level='' or d.confidence_level=p_confidence_level)
    and (
      p_group_code is null or p_group_code='' or exists (
        select 1
        from public.directory_entity_classifications c
        join public.directory_groups g on g.id=c.group_id
        where c.entity_id=d.entity_id and g.code=p_group_code
      )
    )
    and (
      p_subgroup_code is null or p_subgroup_code='' or exists (
        select 1
        from public.directory_entity_classifications c
        join public.directory_subgroups sg on sg.id=c.subgroup_id
        where c.entity_id=d.entity_id and sg.code=p_subgroup_code
      )
    )
    and (
      q.nq=''
      or e.normalized_name like '%'||q.nq||'%'
      or v.normalized_address like '%'||q.nq||'%'
      or public.directory_normalize_text(d.jurisdiction_scope) like '%'||q.nq||'%'
      or public.directory_normalize_text(d.lawyer_use) like '%'||q.nq||'%'
      or extensions.similarity(e.normalized_name,q.nq)>=0.25
      or extensions.similarity(v.normalized_address,q.nq)>=0.25
    )
  order by
    case
      when q.nq='' then 0
      when e.normalized_name=q.nq then 1
      when e.normalized_name like q.nq||'%' then 2
      when e.normalized_name like '%'||q.nq||'%' then 3
      when v.normalized_address like '%'||q.nq||'%' then 4
      else 5
    end,
    case when q.nq='' then 0 else greatest(
      extensions.similarity(e.normalized_name,q.nq),
      extensions.similarity(v.normalized_address,q.nq)
    ) end desc,
    d.name
  limit least(greatest(coalesce(p_limit,50),1),100)
  offset greatest(coalesce(p_offset,0),0);
$$;

revoke all on function public.search_directory(text,text,text,text,text,boolean,integer,integer)
from public;
grant execute on function public.search_directory(text,text,text,text,text,boolean,integer,integer)
to anon,authenticated;

create or replace view private.directory_verification_queue
as
select
  sr.id as source_record_id,
  sr.external_id,
  sr.row_number,
  sr.resolved_entity_id as entity_id,
  sr.raw_payload->>'نام مرجع' as name,
  sr.raw_payload->>'نشانی' as address,
  sr.raw_payload->>'سطح اطمینان' as confidence,
  sr.raw_payload->>'وضعیت' as operational_status,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'severity',i.severity,
        'issue_code',i.issue_code,
        'field_name',i.field_name,
        'message',i.message
      )
      order by i.created_at
    ) filter (where i.id is not null),
    '[]'::jsonb
  ) as issues
from public.directory_source_records sr
left join public.directory_ingestion_issues i on i.source_record_id=sr.id
group by sr.id,sr.external_id,sr.row_number,sr.resolved_entity_id,sr.raw_payload
having count(i.id)>0;

