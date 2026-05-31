# AGENTS

## Readability Parity

- Keep the browser JavaScript implementation and the Swift/Soup implementation behaviorally aligned through the shared Mozilla-format fixture corpus under `Tests/SwiftReadabilityTests/Fixtures/test-pages`.
- `Tests/SwiftReadabilityTests/Fixtures/readability-suite.json` is the shared fixture manifest for both runners. Put fixture selection, base URL, and per-runner known failures there instead of adding runner-local lists.
- The JavaScript Readability sources live in this package under `Sources/SwiftReadability/Resources/`. Do not add or maintain separate Readability.js test/runtime copies outside this package.
- When changing extraction or readerable behavior, update/add fixtures first, then run `mise run test:parity` from this package. If mise has not trusted this package config yet, run `mise trust` in this directory first. From the app repo root, run `mise run test:readability-parity`.
- Prefer keeping JavaScript as the browser-DOM source of truth for live reader-mode availability and using SwiftReadability for native/offline HTML parsing.
