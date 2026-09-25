
create index if not exists legal_authorities_normalized_title_trgm_idx
  on public.legal_authorities
  using gin (normalized_title extensions.gin_trgm_ops);

create index if not exists legal_authorities_public_type_idx
  on public.legal_authorities (is_public,authority_type_code)
  where is_public;

create index if not exists legal_authority_categories_category_authority_idx
  on public.legal_authority_categories (category_id,authority_id);

create or replace view public.legal_category_catalog_counts
with (security_invoker=true)
as
select
  c.id as category_id,
  c.code as category_code,
  c.name_fa as category_name_fa,
  c.sort_order,
  count(distinct a.id) filter (where a.is_public) as total_count,
  count(distinct a.id) filter (
    where a.is_public and a.content_status_code='catalog_only'
  ) as catalog_only_count,
  count(distinct a.id) filter (
    where a.is_public and a.content_status_code='full_text'
  ) as full_text_count,
  count(distinct a.id) filter (
    where a.is_public and a.verification_status_code='official_verified'
  ) as official_verified_count
from public.legal_categories c
join public.legal_taxonomies t on t.id=c.taxonomy_id
left join public.legal_authority_categories ac on ac.category_id=c.id
left join public.legal_authorities a on a.id=ac.authority_id
where t.code='master_subjects'
  and c.is_active
group by c.id,c.code,c.name_fa,c.sort_order;

grant select on public.legal_category_catalog_counts to anon,authenticated;

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
    select public.legal_normalize_text(coalesce(p_query,'')) as nq
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

