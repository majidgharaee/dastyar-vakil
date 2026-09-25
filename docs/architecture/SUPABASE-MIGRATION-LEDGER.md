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
