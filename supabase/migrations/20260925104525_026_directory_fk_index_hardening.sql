
create index if not exists directory_entities_current_version_idx
  on public.directory_entities(current_version_id);
create index if not exists directory_classifications_source_record_idx
  on public.directory_entity_classifications(source_record_id);
create index if not exists directory_versions_source_record_idx
  on public.directory_entity_versions(source_record_id);
create index if not exists directory_external_ids_source_record_idx
  on public.directory_external_ids(source_record_id);

