
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.legal_authority_type_rules (
  id uuid primary key default gen_random_uuid(),
  authority_type_code text not null references public.legal_authority_types(code) on update cascade,
  rule_name text not null,
  match_kind text not null,
  pattern text not null,
  priority integer not null default 100,
  confidence numeric(5,4) not null default 0.9000 check (confidence >= 0 and confidence <= 1),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (rule_name)
);

create index if not exists legal_authority_type_rules_lookup_idx
  on public.legal_authority_type_rules (is_active, priority, authority_type_code);

alter table public.legal_authority_type_rules enable row level security;
revoke all on public.legal_authority_type_rules from anon, authenticated;
grant select, insert, update, delete on public.legal_authority_type_rules to service_role;

create table if not exists public.legal_ingestion_candidates (
  id uuid primary key default gen_random_uuid(),
  ingestion_record_id uuid not null references public.legal_ingestion_records(id) on delete cascade,
  candidate_authority_id uuid references public.legal_authorities(id) on delete cascade,
  candidate_ingestion_record_id uuid references public.legal_ingestion_records(id) on delete cascade,
  candidate_kind text not null default 'identity',
  match_method text not null,
  score numeric(6,5) not null check (score >= 0 and score <= 1),
  rank integer,
  algorithm_version text not null,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'candidate',
  created_at timestamptz not null default now(),
  constraint legal_ingestion_candidates_one_target_chk
    check (num_nonnulls(candidate_authority_id, candidate_ingestion_record_id) = 1),
  constraint legal_ingestion_candidates_not_self_chk
    check (candidate_ingestion_record_id is null or candidate_ingestion_record_id <> ingestion_record_id)
);

create unique index if not exists legal_ingestion_candidates_authority_uidx
  on public.legal_ingestion_candidates
  (ingestion_record_id, candidate_authority_id, match_method, algorithm_version)
  where candidate_authority_id is not null;

create unique index if not exists legal_ingestion_candidates_record_uidx
  on public.legal_ingestion_candidates
  (ingestion_record_id, candidate_ingestion_record_id, match_method, algorithm_version)
  where candidate_ingestion_record_id is not null;

create index if not exists legal_ingestion_candidates_record_score_idx
  on public.legal_ingestion_candidates (ingestion_record_id, score desc);

create index if not exists legal_ingestion_candidates_authority_idx
  on public.legal_ingestion_candidates (candidate_authority_id)
  where candidate_authority_id is not null;

create index if not exists legal_ingestion_candidates_ingestion_target_idx
  on public.legal_ingestion_candidates (candidate_ingestion_record_id)
  where candidate_ingestion_record_id is not null;

alter table public.legal_ingestion_candidates enable row level security;
revoke all on public.legal_ingestion_candidates from anon, authenticated;
grant select, insert, update, delete on public.legal_ingestion_candidates to service_role;

create table if not exists public.legal_resolution_decisions (
  id uuid primary key default gen_random_uuid(),
  ingestion_record_id uuid not null unique references public.legal_ingestion_records(id) on delete cascade,
  decision_code text not null,
  target_authority_id uuid references public.legal_authorities(id) on delete restrict,
  target_ingestion_record_id uuid references public.legal_ingestion_records(id) on delete restrict,
  confidence numeric(6,5) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  decision_method text not null,
  evidence jsonb not null default '{}'::jsonb,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists legal_resolution_decisions_code_idx
  on public.legal_resolution_decisions (decision_code);

create index if not exists legal_resolution_decisions_target_authority_idx
  on public.legal_resolution_decisions (target_authority_id)
  where target_authority_id is not null;

alter table public.legal_resolution_decisions enable row level security;
revoke all on public.legal_resolution_decisions from anon, authenticated;
grant select, insert, update, delete on public.legal_resolution_decisions to service_role;

insert into public.legal_authority_type_rules
  (authority_type_code, rule_name, match_kind, pattern, priority, confidence, metadata)
values
  ('law','title_starts_law','regex','^قانون( |‌|$)',10,0.9900,'{"scope":"fa_title"}'),
  ('bylaw','title_starts_bylaw','regex','^آ(ی|ئ)ین[‌ -]?نامه( |‌|$)',20,0.9800,'{"scope":"fa_title"}'),
  ('circular','title_starts_circular','regex','^بخشنامه( |‌|$)',30,0.9800,'{"scope":"fa_title"}'),
  ('directive','title_starts_directive','regex','^دستورالعمل( |‌|$)',40,0.9800,'{"scope":"fa_title"}'),
  ('resolution','title_starts_resolution','regex','^(تصویب[‌ -]?نامه|مصوبه)( |‌|$)',50,0.9700,'{"scope":"fa_title"}'),
  ('unity_precedent','title_starts_unity','regex','^(رأی|رای) وحدت رویه( |‌|$)',60,0.9900,'{"scope":"fa_title"}'),
  ('advisory_opinion','title_starts_advisory','regex','^نظریه مشورتی( |‌|$)',70,0.9900,'{"scope":"fa_title"}')
on conflict (rule_name) do update
set authority_type_code=excluded.authority_type_code,
    match_kind=excluded.match_kind,
    pattern=excluded.pattern,
    priority=excluded.priority,
    confidence=excluded.confidence,
    metadata=excluded.metadata,
    is_active=true,
    updated_at=now();

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
  where r.batch_id = p_batch_id;
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
   and extensions.similarity(
      public.legal_normalize_text(coalesce(r1.normalized_payload->>'normalized_title', r1.raw_payload->>'title')),
      public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))
   ) >= p_min_similarity
  where r1.batch_id = p_batch_id
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
  where r1.batch_id = p_batch_id
    and length(public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))) >= 10
    and position(
      public.legal_normalize_text(coalesce(r2.normalized_payload->>'normalized_title', r2.raw_payload->>'title'))
      in public.legal_normalize_text(coalesce(r1.normalized_payload->>'normalized_title', r1.raw_payload->>'title'))
    ) > 0
  on conflict do nothing;
  get diagnostics v_count = row_count;
  v_total := v_total + v_count;

  with ranked as (
    select id,
           row_number() over (partition by ingestion_record_id order by score desc, created_at, id) as rn
    from public.legal_ingestion_candidates c
    join public.legal_ingestion_records r on r.id=c.ingestion_record_id
    where r.batch_id=p_batch_id and c.algorithm_version=p_algorithm_version
  )
  update public.legal_ingestion_candidates c
  set rank=ranked.rn
  from ranked
  where c.id=ranked.id;

  return v_total;
end;
$$;

revoke all on function private.generate_legal_ingestion_candidates(uuid,numeric,text) from public, anon, authenticated;
grant execute on function private.generate_legal_ingestion_candidates(uuid,numeric,text) to service_role;

