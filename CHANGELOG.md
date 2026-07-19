# Changelog

Notable changes to SwiftReadability are documented here. The project follows
[Semantic Versioning](https://semver.org/) while its public API matures.

## [Unreleased]

## [0.2.0] - 2026-07-20

### Changed

- Made Mozilla Readability commit `ab4027a` the executable behavioral authority;
  the inherited Lake of Fire port remains credited provenance and scaffolding,
  not the compatibility specification.
- Reworked default extraction, metadata, DOM cleanup, serialization, JavaScript
  string/number/regular-expression semantics, and readerability behavior around
  focused pinned-oracle regressions.
- Pinned SwiftSoup 2.13.6 and WebURL 0.4.2; browser-style URL resolution no longer
  relies on Foundation URL heuristics.
- Moved Mozilla JavaScript sources out of the production library and into an
  optional, byte-verified reference product.

### Added

- A fail-closed 136-fixture Swift-versus-Mozilla result differential under true
  default options, with exact serialized output, a supplemental canonical-DOM
  diagnostic, strict raw-input comment overlays, CSSOM oracle cases, and
  focused edge-case tests.
- Explicit opt-in `ReadabilityExtensions`, including the isolated consumer application
  profile, while keeping default behavior extension-free.
- Release-mode benchmark, immutable dependency, provenance, license, and native
  Linux compatibility gates.

### Fixed

- Unicode range crashes, cross-run mutable state, falsy option handling, HTML
  document traversal, language/direction discovery, link density, lazy image and
  URL property semantics, table span parsing, structured metadata edge cases,
  comment preservation, and browser serialization differences.

[Unreleased]: https://github.com/wolfyy970/swift-readability/compare/0.2.0...HEAD
[0.2.0]: https://github.com/wolfyy970/swift-readability/compare/0.1.0...0.2.0
