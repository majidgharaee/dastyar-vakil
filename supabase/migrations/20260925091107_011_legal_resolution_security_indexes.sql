
create index if not exists legal_authority_type_rules_type_idx
  on public.legal_authority_type_rules(authority_type_code);

create index if not exists legal_resolution_decisions_decided_by_idx
  on public.legal_resolution_decisions(decided_by)
  where decided_by is not null;

create index if not exists legal_resolution_decisions_target_ingestion_idx
  on public.legal_resolution_decisions(target_ingestion_record_id)
  where target_ingestion_record_id is not null;

drop policy if exists legal_authority_type_rules_service_role_all
  on public.legal_authority_type_rules;
create policy legal_authority_type_rules_service_role_all
  on public.legal_authority_type_rules
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists legal_ingestion_candidates_service_role_all
  on public.legal_ingestion_candidates;
create policy legal_ingestion_candidates_service_role_all
  on public.legal_ingestion_candidates
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists legal_resolution_decisions_service_role_all
  on public.legal_resolution_decisions;
create policy legal_resolution_decisions_service_role_all
  on public.legal_resolution_decisions
  for all
  to service_role
  using (true)
  with check (true);

