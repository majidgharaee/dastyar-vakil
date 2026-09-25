# Dastyar Vakil v10.0.0 — Cloud Catalog and Directory

This branch upgrades the v9 Android application in place. It preserves package `ir.dadban.app` and local user storage while moving the legal catalog and directory primary sources to the public, RLS-protected Supabase APIs. Persistent SQLite mirrors provide offline cache and the bundled legacy data is fallback-only.

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

## Android release
- `versionName=10.0.0`, `versionCode=11`
- package remains `ir.dadban.app`
- only `DV_SUPABASE_PUBLISHABLE_KEY` is accepted by the Android data layer
- `catalog_only`, `unverified`, and `rag_eligible` are surfaced in the UI
- records with `rag_eligible=false` are prohibited from being presented to AI as authoritative text
- build with `android/tools/build_release_v10.ps1`

See `docs/v10/CHANGELOG-v10.0.0.md` and `docs/v10/QA-REPORT-v10.0.0.md`.
