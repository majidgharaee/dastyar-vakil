
alter function public.legal_normalize_text(text)
  set search_path = pg_catalog;

create policy legal_source_records_explicit_deny
on public.legal_source_records
for all to anon, authenticated
using (false)
with check (false);

create policy legal_assets_explicit_deny
on public.legal_assets
for all to anon, authenticated
using (false)
with check (false);

create policy legal_ingestion_batches_explicit_deny
on public.legal_ingestion_batches
for all to anon, authenticated
using (false)
with check (false);

create policy legal_ingestion_records_explicit_deny
on public.legal_ingestion_records
for all to anon, authenticated
using (false)
with check (false);

create policy legal_ingestion_issues_explicit_deny
on public.legal_ingestion_issues
for all to anon, authenticated
using (false)
with check (false);

create policy legal_search_chunks_explicit_deny
on public.legal_search_chunks
for all to anon, authenticated
using (false)
with check (false);

create index legal_assets_unit_version_authority_idx
  on public.legal_assets(unit_version_id, authority_id);
create index legal_assets_version_authority_idx
  on public.legal_assets(authority_version_id, authority_id);

create index legal_authorities_content_status_idx
  on public.legal_authorities(content_status_code);
create index legal_authorities_created_by_idx
  on public.legal_authorities(created_by);
create index legal_authorities_current_version_authority_idx
  on public.legal_authorities(current_version_id, id);
create index legal_authorities_effect_status_idx
  on public.legal_authorities(effect_status_code);
create index legal_authorities_updated_by_idx
  on public.legal_authorities(updated_by);
create index legal_authorities_verification_status_idx
  on public.legal_authorities(verification_status_code);

create index legal_authority_aliases_source_record_idx
  on public.legal_authority_aliases(source_record_id);
create index legal_authority_categories_source_record_idx
  on public.legal_authority_categories(source_record_id);

create index legal_authority_versions_created_by_idx
  on public.legal_authority_versions(created_by);
create index legal_authority_versions_publication_status_idx
  on public.legal_authority_versions(publication_status_code);
create index legal_authority_versions_source_record_idx
  on public.legal_authority_versions(source_record_id);
create index legal_authority_versions_verification_status_idx
  on public.legal_authority_versions(verification_status_code);
create index legal_authority_versions_version_type_idx
  on public.legal_authority_versions(version_type_code);

create index legal_categories_parent_taxonomy_idx
  on public.legal_categories(parent_id, taxonomy_id);

create index legal_external_ids_source_record_idx
  on public.legal_external_ids(source_record_id);

create index legal_ingestion_batches_created_by_idx
  on public.legal_ingestion_batches(created_by);
create index legal_ingestion_batches_source_idx
  on public.legal_ingestion_batches(source_id);
create index legal_ingestion_records_created_authority_idx
  on public.legal_ingestion_records(created_authority_id);

create index legal_issuing_bodies_jurisdiction_idx
  on public.legal_issuing_bodies(jurisdiction_id);
create index legal_issuing_bodies_parent_idx
  on public.legal_issuing_bodies(parent_id);
create index legal_jurisdictions_parent_idx
  on public.legal_jurisdictions(parent_id);

create index legal_relation_types_inverse_idx
  on public.legal_relation_types(inverse_code);

create index legal_relations_type_idx
  on public.legal_relations(relation_type_code);
create index legal_relations_source_record_idx
  on public.legal_relations(source_record_id);
create index legal_relations_source_unit_authority_idx
  on public.legal_relations(source_unit_id, source_authority_id);
create index legal_relations_target_unit_authority_idx
  on public.legal_relations(target_unit_id, target_authority_id);
create index legal_relations_verification_status_idx
  on public.legal_relations(verification_status_code);

create index legal_search_chunks_unit_version_authority_idx
  on public.legal_search_chunks(unit_version_id, authority_id);
create index legal_search_chunks_version_authority_idx
  on public.legal_search_chunks(authority_version_id, authority_id);

create index legal_unit_versions_source_record_idx
  on public.legal_unit_versions(source_record_id);
create index legal_unit_versions_unit_authority_idx
  on public.legal_unit_versions(unit_id, authority_id);
create index legal_unit_versions_verification_status_idx
  on public.legal_unit_versions(verification_status_code);
create index legal_unit_versions_version_authority_idx
  on public.legal_unit_versions(authority_version_id, authority_id);

create index legal_units_parent_authority_idx
  on public.legal_units(parent_unit_id, authority_id);
create index legal_units_type_idx
  on public.legal_units(unit_type_code);

