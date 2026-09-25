
alter table public.legal_ingestion_records
  add column if not exists normalized_title_index text
  generated always as (
    public.legal_normalize_text(
      coalesce(normalized_payload->>'normalized_title', raw_payload->>'title')
    )
  ) stored;

create index if not exists legal_ingestion_records_title_trgm_idx
  on public.legal_ingestion_records
  using gin (normalized_title_index extensions.gin_trgm_ops);

create index if not exists legal_ingestion_records_batch_title_idx
  on public.legal_ingestion_records (batch_id, normalized_title_index);

create table if not exists public.legal_authority_redirects (
  from_authority_id uuid primary key
    references public.legal_authorities(id) on delete restrict,
  to_authority_id uuid not null
    references public.legal_authorities(id) on delete restrict,
  redirect_kind text not null default 'duplicate_merge',
  reason text,
  resolution_decision_id uuid
    references public.legal_resolution_decisions(id) on delete set null,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_authority_redirects_not_self_chk
    check (from_authority_id <> to_authority_id)
);

create index if not exists legal_authority_redirects_target_idx
  on public.legal_authority_redirects(to_authority_id)
  where is_active;

alter table public.legal_authority_redirects enable row level security;
revoke all on public.legal_authority_redirects from anon, authenticated;
grant select, insert, update, delete on public.legal_authority_redirects to service_role;

drop policy if exists legal_authority_redirects_service_role_all
  on public.legal_authority_redirects;
create policy legal_authority_redirects_service_role_all
  on public.legal_authority_redirects
  for all to service_role
  using (true)
  with check (true);

insert into public.legal_authority_type_rules
  (authority_type_code, rule_name, match_kind, pattern, priority, confidence, metadata)
values
  ('law','title_starts_decree_law','regex','^لایحه قانونی( |‌|$)',11,0.9500,'{"scope":"fa_title","provisional_mapping":true}'),
  ('regulation','title_starts_regulations','regex','^مقررات( |‌|$)',21,0.9000,'{"scope":"fa_title"}'),
  ('regulation','title_starts_rules','regex','^ضوابط( |‌|$)',22,0.9000,'{"scope":"fa_title"}'),
  ('tariff','title_starts_tariff','regex','^تعرفه( |‌|$)',23,0.9500,'{"scope":"fa_title"}'),
  ('procedure','title_starts_procedure_ayin','regex','^آیین (دادرسی|رسیدگی)( |‌|$)',24,0.8500,'{"scope":"fa_title","requires_verification":true}')
on conflict (rule_name) do update
set authority_type_code=excluded.authority_type_code,
    match_kind=excluded.match_kind,
    pattern=excluded.pattern,
    priority=excluded.priority,
    confidence=excluded.confidence,
    metadata=excluded.metadata,
    is_active=true,
    updated_at=now();

update public.legal_ingestion_candidates
set candidate_kind='possible_identity'
where match_method in ('fuzzy_canonical_title','within_batch_fuzzy_title')
  and candidate_kind='identity';

create or replace function private.generate_legal_ingestion_candidates(
  p_batch_id uuid,
  p_min_similarity numeric default 0.72,
  p_algorithm_version text default 'title-v3-indexed'
)
returns integer
language plpgsql
security invoker
set search_path = public, extensions, private
as $$
declare
  v_total integer := 0;
  v_count integer := 0;
begin
  delete from public.legal_ingestion_candidates c
  using public.legal_ingestion_records r
  where c.ingestion_record_id = r.id
    and r.batch_id = p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
    and c.algorithm_version = p_algorithm_version;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_authority_id, candidate_kind,
     match_method, score, algorithm_version, evidence)
  select r.id, a.id, 'identity', 'exact_canonical_title', 1.00000,
         p_algorithm_version,
         jsonb_build_object('normalized_title', r.normalized_title_index)
  from public.legal_ingestion_records r
  join public.legal_authorities a
    on a.normalized_title = r.normalized_title_index
  where r.batch_id = p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_authority_id, candidate_kind,
     match_method, score, algorithm_version, evidence)
  select r.id, al.authority_id, 'identity', 'exact_alias', 0.99500,
         p_algorithm_version,
         jsonb_build_object('alias_id', al.id, 'alias', al.alias)
  from public.legal_ingestion_records r
  join public.legal_authority_aliases al
    on al.normalized_alias = r.normalized_title_index
  where r.batch_id = p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_authority_id, candidate_kind,
     match_method, score, algorithm_version, evidence)
  select r.id, a.id, 'possible_identity', 'fuzzy_canonical_title',
         extensions.similarity(r.normalized_title_index,a.normalized_title)::numeric(6,5),
         p_algorithm_version,
         jsonb_build_object('candidate_title',a.canonical_title)
  from public.legal_ingestion_records r
  join public.legal_authorities a
    on extensions.similarity(r.normalized_title_index,a.normalized_title) >= p_min_similarity
  where r.batch_id=p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
    and a.normalized_title <> r.normalized_title_index
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_ingestion_record_id, candidate_kind,
     match_method, score, algorithm_version, evidence)
  select src.id, cand.id, 'possible_identity', 'within_batch_fuzzy_title',
         cand.similarity_score::numeric(6,5),
         p_algorithm_version,
         jsonb_build_object(
           'candidate_row_number',cand.row_number,
           'candidate_title',cand.title
         )
  from public.legal_ingestion_records src
  cross join lateral (
    select r2.id, r2.row_number, r2.raw_payload->>'title' as title,
           extensions.similarity(src.normalized_title_index,r2.normalized_title_index) as similarity_score
    from public.legal_ingestion_records r2
    where r2.batch_id=src.batch_id
      and r2.id<>src.id
      and r2.created_authority_id is null
      and r2.matched_authority_id is null
      and r2.normalized_title_index % src.normalized_title_index
      and extensions.similarity(src.normalized_title_index,r2.normalized_title_index) >= p_min_similarity
    order by src.normalized_title_index <-> r2.normalized_title_index
    limit 8
  ) cand
  where src.batch_id=p_batch_id
    and src.created_authority_id is null
    and src.matched_authority_id is null
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_ingestion_record_id, candidate_kind,
     match_method, score, algorithm_version, evidence)
  select r1.id,r2.id,'related_or_variant','within_batch_title_containment',
         0.70000,p_algorithm_version,
         jsonb_build_object(
           'candidate_row_number',r2.row_number,
           'candidate_title',r2.raw_payload->>'title'
         )
  from public.legal_ingestion_records r1
  join public.legal_ingestion_records r2
    on r2.batch_id=r1.batch_id
   and r2.id<>r1.id
   and r2.created_authority_id is null
   and r2.matched_authority_id is null
  where r1.batch_id=p_batch_id
    and r1.created_authority_id is null
    and r1.matched_authority_id is null
    and length(r2.normalized_title_index)>=10
    and position(r2.normalized_title_index in r1.normalized_title_index)>0
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  with ranked as (
    select c.id as candidate_id,
           row_number() over (
             partition by c.ingestion_record_id
             order by
               case c.candidate_kind
                 when 'identity' then 1
                 when 'possible_identity' then 2
                 else 3
               end,
               c.score desc,c.created_at,c.id
           ) as rn
    from public.legal_ingestion_candidates c
    join public.legal_ingestion_records r on r.id=c.ingestion_record_id
    where r.batch_id=p_batch_id
      and r.created_authority_id is null
      and r.matched_authority_id is null
      and c.algorithm_version=p_algorithm_version
  )
  update public.legal_ingestion_candidates c
  set rank=ranked.rn
  from ranked
  where c.id=ranked.candidate_id;

  return v_total;
end;
$$;

revoke all on function private.generate_legal_ingestion_candidates(uuid,numeric,text)
from public,anon,authenticated;
grant execute on function private.generate_legal_ingestion_candidates(uuid,numeric,text)
to service_role;

