
create index if not exists legal_authority_redirects_resolution_decision_idx
  on public.legal_authority_redirects(resolution_decision_id)
  where resolution_decision_id is not null;

