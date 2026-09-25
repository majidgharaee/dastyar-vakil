# ADR-001 — Perpetual Legal Data Evolution

Status: Accepted  
Scope: Dastyar Vakil legal knowledge base, Android, future web client, ingestion, search and AI.

## Non-negotiable invariant

Every legal-data design must support indefinite growth in record count, source types, document types, taxonomies, versions, relations and provenance without requiring a fundamental redesign.

A design is rejected if multiplying the corpus by 100 or adding a new legal-authority type would require replacing the core schema or breaking stable identifiers.

## Consequences

- Canonical records use immutable UUIDs independent of title, Excel row, source URL or official number.
- Laws, regulations, unity precedents, advisory opinions, judicial decisions, circulars, treaties and future source types share the generic `legal_authorities` identity layer.
- Types, statuses, unit types, relation types and taxonomies are data-driven lookup records, not application enums that require a client release.
- Source taxonomies are retained as provenance. They are never silently rewritten into the master taxonomy.
- Classification is many-to-many and hierarchical.
- Full text is versioned separately from authority identity.
- Legal units and unit versions support article/paragraph/clause structures and non-statutory document structures.
- Ingestion is staged. Raw source rows survive normalization, matching and canonicalization.
- Fuzzy title similarity is evidence only. It must not automatically merge legal authorities.
- Potential duplicate merges use `legal_authority_redirects` so an old UUID never becomes a dead identifier.
- Catalog-only records may be discoverable by title and category but are never treated as verified legal text or RAG evidence.
- Search and AI retrieval must respect content and verification status.
- App-facing database contracts are versioned views/RPCs (for example `*_v1`) rather than direct coupling to internal tables.
- Mobile local data is paged/indexed and must not require loading the entire legal corpus into WebView memory.
- Original sources, checksums, ingestion batches, resolution evidence and review decisions remain auditable.

## Current catalog snapshot

Source snapshot: `1405-07-03`

- 706 catalog authorities
- 38 source categories in the current default taxonomy
- 706 source-row provenance records
- 706 stable source external IDs
- 0 automatic fuzzy merges
- 93 authorities flagged for entity-resolution review
- 109 review issues: 60 possible-identity checks and 49 related-title checks
- All imported titles currently remain `catalog_only` and `unverified` until text/source verification is completed.

## Client contract

Android uses a local SQLite mirror and page-based query interface. Supabase remains the source of truth. A modern Supabase publishable key is a public client credential; authorization remains enforced by RLS.

Future web/mobile clients should consume the same versioned catalog contract instead of reimplementing legal identity rules.
