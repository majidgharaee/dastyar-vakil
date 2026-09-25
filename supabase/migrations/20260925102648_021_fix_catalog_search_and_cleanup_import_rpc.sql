
drop index if exists public.legal_authorities_normalized_title_trgm_idx;

drop function if exists public.service_stage_master_catalog_rows(uuid,jsonb,text);

create or replace function public.search_legal_catalog(
  p_query text default null,
  p_category_code text default null,
  p_authority_type_code text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  authority_id uuid,
  title text,
  authority_type_code text,
  authority_type_name_fa text,
  category_code text,
  category_name_fa text,
  subtopic text,
  content_status_code text,
  verification_status_code text,
  effect_status_code text,
  has_text boolean,
  rag_eligible boolean,
  relevance real
)
language sql
stable
security invoker
set search_path=public,extensions
as $$
  with q as (
    select coalesce(public.legal_normalize_text(coalesce(p_query,'')),'') as nq
  )
  select
    lc.authority_id,
    lc.title,
    lc.authority_type_code,
    lc.authority_type_name_fa,
    lc.category_code,
    lc.category_name_fa,
    lc.subtopic,
    lc.content_status_code,
    lc.verification_status_code,
    lc.effect_status_code,
    lc.has_text,
    lc.rag_eligible,
    case
      when q.nq='' then 0::real
      when a.normalized_title=q.nq then 1::real
      when a.normalized_title like q.nq||'%' then 0.98::real
      when a.normalized_title like '%'||q.nq||'%' then 0.95::real
      else extensions.similarity(a.normalized_title,q.nq)::real
    end as relevance
  from public.legal_catalog_current lc
  join public.legal_authorities a on a.id=lc.authority_id
  cross join q
  where
    (p_category_code is null or p_category_code='' or lc.category_code=p_category_code)
    and
    (p_authority_type_code is null or p_authority_type_code='' or lc.authority_type_code=p_authority_type_code)
    and
    (
      q.nq=''
      or a.normalized_title like '%'||q.nq||'%'
      or extensions.similarity(a.normalized_title,q.nq)>=0.25
    )
  order by
    case when q.nq='' then lc.master_sort_order else 0 end,
    case
      when q.nq='' then 0
      when a.normalized_title=q.nq then 1
      when a.normalized_title like q.nq||'%' then 2
      when a.normalized_title like '%'||q.nq||'%' then 3
      else 4
    end,
    case when q.nq='' then 0 else extensions.similarity(a.normalized_title,q.nq) end desc,
    lc.master_sort_order,
    lc.title
  limit least(greatest(coalesce(p_limit,50),1),100)
  offset greatest(coalesce(p_offset,0),0);
$$;

revoke all on function public.search_legal_catalog(text,text,text,integer,integer) from public;
grant execute on function public.search_legal_catalog(text,text,text,integer,integer)
to anon,authenticated;

