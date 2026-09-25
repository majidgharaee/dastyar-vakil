# v9 source import notes

The v9 source is imported into `android/` on branch `v10-cloud-foundation` as one cleaned source import.

Import verification:
- 55 source/documentation files selected from the frozen v9 baseline.
- 690,098 bytes imported, excluding the two bulk legal-data payloads listed below.
- Secret scan found no OpenAI/GitHub/private-key/service-role credential patterns in the selected source set.
- Build/release/QA output directories, Gradle caches, duplicate source packages, keystores and secrets are excluded.

Two legacy bulk legal-data payloads are intentionally not committed to Git because v10 will migrate the legal corpus into the database/search pipeline:

- `android/app/src/main/assets/legal-data.json`
  - original bytes: 8,258,097
  - SHA-256: `eed48713f6d484ee96fc5a922f15b6d5e2fb2d409e9003fc109d310abfad8d98`
- `android/tools/legacy-legal-data.js`
  - original bytes: 3,065,996
  - SHA-256: `d62b3931a89bec98ae9e67bcbe880f5df63bb3211e3dc0fb9a08ef07f0a034d8`

The original v9 RAR remains the canonical frozen baseline for those bulk payloads until their database migration is independently verified.
