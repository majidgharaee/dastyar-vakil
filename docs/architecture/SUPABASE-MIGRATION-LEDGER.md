# Applied Supabase migration ledger

The authoritative migration history is the `supabase_migrations.schema_migrations` ledger in DEV project `dastyar-vakil-dev`.

Files with timestamp prefixes in `supabase/migrations/` are mirrored from the SQL statements actually applied to DEV. Do not renumber them or infer order from the embedded logical prefix (for example two different migrations may both have a logical `012_` prefix).

New migrations must:
1. be applied through Supabase migration tooling,
2. use a unique timestamp,
3. be mirrored to GitHub from the applied ledger,
4. preserve backwards compatibility unless a separately reviewed migration plan explicitly requires otherwise,
5. run Security Advisor after DDL changes.

Legacy untimestamped migration files 001/002/004 are retained as the original foundation history; timestamped files are the canonical mirror for the newer Legal Knowledge Base work.

The repository mirror currently includes the applied DEV ledger through:

- `20260925102203_018_canonical_master_catalog_resolution`
- `20260925102434_019_publish_safe_legal_catalog_view`
- `20260925102551_020_scalable_legal_catalog_search`
- `20260925102648_021_fix_catalog_search_and_cleanup_import_rpc`
- `20260925102951_022_expose_category_qa_status_v2`
- `20260925103039_023_normalize_category_qa_and_enrichment_queue`
- `20260925104036_024_scalable_legal_directory_foundation`
- `20260925104234_025_directory_import_and_public_api`
- `20260925104525_026_directory_fk_index_hardening`
- `20260925104612_027_directory_stable_ids_and_count_hardening`
- `20260925104634_028_directory_external_ids_public_read`
