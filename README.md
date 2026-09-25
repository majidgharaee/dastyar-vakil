# Dastyar Vakil v10 — Cloud Foundation

This branch establishes the backend/data foundation for Dastyar Vakil while preserving v9 as the stable Android baseline.

## DEV environment
Supabase project: `dastyar-vakil-dev`
Region: Frankfurt (`eu-central-1`)

## Core tables
- profiles
- organizations
- organization_members
- clients
- matters
- matter_clients
- hearings
- documents
- document_versions
- document_chunks

## Storage buckets
- legal-public
- case-files
- user-private
- generated-files

All buckets are private in DEV.

## Security
- RLS is enabled on exposed public tables.
- No service-role key or secret may be committed.
- No client/case documents belong in Git.
- v9 remains the stable baseline during migration.

## Next
1. Storage RLS policies through supported Storage administration path.
2. v9 local-data → cloud migration layer.
3. Legal corpus normalization and provenance.
4. Hybrid search.
5. Server-side AI gateway with citation validation.
