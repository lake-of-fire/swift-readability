# Third-party notices

SwiftReadability's original Swift contributions are distributed under the repository's BSD 3-Clause license. The repository history, extraction behavior, reference resources, and fixtures include or derive from the projects below.

## Lake of Fire SwiftReadability

This repository is a fork of the SwiftReadability implementation published by Lake of Fire. That implementation supplied the initial Swift scaffolding and remains part of this repository's provenance and Git history. Its BSD 3-Clause license and copyright notice are preserved in [`LICENSE`](LICENSE).

The Lake of Fire implementation is credited as lineage, not treated as the behavioral specification for current work. Compatibility decisions are validated directly against the pinned Mozilla Readability implementation described below.

Project: <https://github.com/lake-of-fire/swift-readability>

## Mozilla Readability

Copyright © 2010 Arc90 Inc. Mozilla Readability is licensed under the Apache License, Version 2.0. Mozilla Readability at commit [`ab4027a`](https://github.com/mozilla/readability/commit/ab4027a) is the behavioral authority used by this package.

The optional `SwiftReadabilityJavaScriptReference` product packages the official JavaScript sources from Mozilla under `Sources/SwiftReadabilityJavaScriptReference/Resources/`. Both files are byte-for-byte copies from commit `ab4027a`; tests pin their SHA-256 digests as follows:

| File | SHA-256 |
| --- | --- |
| `Readability.js` | `e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed` |
| `Readability-readerable.js` | `e73600367067be2da322c0f26be9c4ec7759cd01b630dbb57278c326e5b5aba8` |

The shared compatibility fixtures retain Mozilla's applicable copyright and license notices. Project-specific enhanced fixture profiles are separately identified in the fixture manifest and are not represented as Mozilla expectations. The production `SwiftReadability` product is a native Swift implementation and does not contain or depend on the JavaScript resources.

Project: <https://github.com/mozilla/readability>

## Readability4J

Copyright © 2017 dankito. The initial native implementation drew from Readability4J, a Kotlin port of Mozilla Readability, licensed under the Apache License, Version 2.0. The current implementation is validated directly against the pinned Mozilla behavior rather than treating Readability4J as a specification.

Project: <https://github.com/dankito/Readability4J>

The full Apache License, Version 2.0 is included at [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt).

## SwiftSoup

SwiftReadability uses SwiftSoup for HTML parsing and DOM operations. SwiftSoup is distributed under the MIT license. The exact tested baseline is SwiftSoup 2.13.6, revision `ead56133a693d0184d8c2db1a6d6394410cacfd6`, as recorded in `Package.resolved`.

Project: <https://github.com/scinfu/SwiftSoup>
