
create or replace function private.generate_legal_ingestion_candidates(
  p_batch_id uuid,
  p_min_similarity numeric default 0.72,
  p_algorithm_version text default 'title-v1'
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
    and c.algorithm_version = p_algorithm_version;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_authority_id, candidate_kind, match_method, score, algorithm_version, evidence)
  select
    r.id, a.id, 'identity', 'exact_canonical_title', 1.00000, p_algorithm_version,
    jsonb_build_object('normalized_title', public.legal_normalize_text(coalesce(r.normalized_payload->>'normalized_title', r.raw_payload->>'title')))
  from public.legal_ingestion_records r
  join public.legal_authorities a
    on a.normalized_title = public.legal_normalize_text(coalesce(r.normalized_payload->>'normalized_title', r.raw_payload->>'title'))
  where r.batch_id = p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_authority_id, candidate_kind, match_method, score, algorithm_version, evidence)
  select
    r.id, al.authority_id, 'identity', 'exact_alias', 0.99500, p_algorithm_version,
    jsonb_build_object('alias_id', al.id, 'alias', al.alias)
  from public.legal_ingestion_records r
  join public.legal_authority_aliases al
    on al.normalized_alias = public.legal_normalize_text(coalesce(r.normalized_payload->>'normalized_title', r.raw_payload->>'title'))
  where r.batch_id = p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_authority_id, candidate_kind, match_method, score, algorithm_version, evidence)
  select
    r.id, a.id, 'identity', 'fuzzy_canonical_title',
    extensions.similarity(
      public.legal_normalize_text(coalesce(r.normalized_payload->>'normalized_title', r.raw_payload->>'title')),
      a.normalized_title
    )::numeric(6,5),
    p_algorithm_version,
    jsonb_build_object('candidate_title', a.canonical_title)
  from public.legal_ingestion_records r
  join public.legal_authorities a
    on extensions.similarity(
      public.legal_normalize_text(coalesce(r.normalized_payload->>'normalized_title', r.raw_payload->>'title')),
      a.normalized_title
    ) >= p_min_similarity
  where r.batch_id = p_batch_id
    and r.created_authority_id is null
    and r.matched_authority_id is null
    and a.normalized_title <> public.legal_normalize_text(coalesce(r.normalized_payload->>'normalized_title', r.raw_payload->>'title'))
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_ingestion_record_id, candidate_kind, match_method, score, algorithm_version, evidence)
  select
    r1.id, r2.id, 'identity', 'within_batch_fuzzy_title',
    extensions.similarity(
      public.legal_normalize_text(coalesce(r1.normalized_payload->>'normalized_title', r1.raw_payload->>'title')),
      public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))
    )::numeric(6,5),
    p_algorithm_version,
    jsonb_build_object('candidate_row_number',r2.row_number,'candidate_title',r2.raw_payload->>'title')
  from public.legal_ingestion_records r1
  join public.legal_ingestion_records r2
    on r2.batch_id = r1.batch_id
   and r2.id <> r1.id
   and r2.created_authority_id is null
   and r2.matched_authority_id is null
   and extensions.similarity(
      public.legal_normalize_text(coalesce(r1.normalized_payload->>'normalized_title', r1.raw_payload->>'title')),
      public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))
   ) >= p_min_similarity
  where r1.batch_id = p_batch_id
    and r1.created_authority_id is null
    and r1.matched_authority_id is null
    and public.legal_normalize_text(coalesce(r1.normalized_payload->>'normalized_title', r1.raw_payload->>'title'))
        <> public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  insert into public.legal_ingestion_candidates
    (ingestion_record_id, candidate_ingestion_record_id, candidate_kind, match_method, score, algorithm_version, evidence)
  select
    r1.id, r2.id, 'related_or_variant', 'within_batch_title_containment',
    0.70000, p_algorithm_version,
    jsonb_build_object('candidate_row_number',r2.row_number,'candidate_title',r2.raw_payload->>'title')
  from public.legal_ingestion_records r1
  join public.legal_ingestion_records r2
    on r2.batch_id = r1.batch_id
   and r2.id <> r1.id
   and r2.created_authority_id is null
   and r2.matched_authority_id is null
  where r1.batch_id = p_batch_id
    and r1.created_authority_id is null
    and r1.matched_authority_id is null
    and length(public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))) >= 10
    and position(
      public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))
      in public.legal_normalize_text(coalesce(r1.normalized_payload->>'normalized_title', r1.raw_payload->>'title'))
    ) > 0
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  with ranked as (
    select c.id as candidate_id,
           row_number() over (
             partition by c.ingestion_record_id
             order by c.score desc, c.created_at, c.id
           ) as rn
    from public.legal_ingestion_candidates c
    join public.legal_ingestion_records r on r.id=c.ingestion_record_id
    where r.batch_id=p_batch_id and c.algorithm_version=p_algorithm_version
  )
  update public.legal_ingestion_candidates c
  set rank=ranked.rn
  from ranked
  where c.id=ranked.candidate_id;

  return v_total;
end;
$$;

revoke all on function private.generate_legal_ingestion_candidates(uuid,numeric,text) from public, anon, authenticated;
grant execute on function private.generate_legal_ingestion_candidates(uuid,numeric,text) to service_role;

