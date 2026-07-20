# Third-party notices

SwiftReadability is a multi-license distribution. The inherited Swift implementation and original Swift contributions are distributed under the repository's BSD 3-Clause license unless otherwise noted. Material derived from Apache-licensed Readability implementations, the optional Mozilla reference resources, and Mozilla-derived fixtures remain subject to Apache-2.0. Runtime dependencies retain their own licenses. Nothing in this repository's BSD license is intended to relicense third-party material or erase its attribution.

See [`docs/provenance-and-licensing.md`](docs/provenance-and-licensing.md) for the product-by-product component and runtime-linkage map.

## Lake of Fire SwiftReadability

This repository is a fork of the SwiftReadability implementation published by Lake of Fire. That implementation established the native Swift foundation and remains part of this repository's provenance and Git history. Its BSD 3-Clause license and 2025 Lake of Fire copyright notice are preserved in [`LICENSE`](LICENSE).

The Lake of Fire implementation is credited as lineage, not treated as the behavioral specification for current work. Compatibility decisions are validated directly against the pinned Mozilla Readability implementation described below.

Project: <https://github.com/lake-of-fire/swift-readability>

## Mozilla Readability

Copyright © 2010 Arc90 Inc. Mozilla Readability is licensed under the Apache License, Version 2.0. Mozilla Readability at commit [`ab4027a8b37669745016869a37a504727992b2ba`](https://github.com/mozilla/readability/commit/ab4027a8b37669745016869a37a504727992b2ba) is the behavioral authority used by this package.

The optional `SwiftReadabilityJavaScriptReference` product packages the official JavaScript sources from Mozilla under `Sources/SwiftReadabilityJavaScriptReference/Resources/`. Both files are byte-for-byte copies from commit `ab4027a`; tests pin their SHA-256 digests as follows:

| File | SHA-256 |
| --- | --- |
| `Readability.js` | `e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed` |
| `Readability-readerable.js` | `e73600367067be2da322c0f26be9c4ec7759cd01b630dbb57278c326e5b5aba8` |

The shared compatibility fixtures retain Mozilla's applicable copyright and license terms. Project-specific enhanced fixture profiles are separately identified in the fixture manifest and are not represented as Mozilla expectations. The production `SwiftReadability` product is a native Swift implementation and does not contain or depend on the JavaScript resources. Native Swift files which adapt Mozilla behavior have been materially changed from the upstream JavaScript; this package does not represent them as clean-room work.

Project: <https://github.com/mozilla/readability>

## Readability4J

Copyright © 2017 dankito. The initial native implementation drew from Readability4J, a Kotlin port of Mozilla Readability, licensed under the Apache License, Version 2.0. The current implementation is validated directly against the pinned Mozilla behavior rather than treating Readability4J as a specification.

Project: <https://github.com/dankito/Readability4J>

## SwiftSoup

SwiftReadability links SwiftSoup for HTML parsing and DOM operations. SwiftSoup is distributed under the MIT license. The exact tested baseline is SwiftSoup 2.13.6, revision `ead56133a693d0184d8c2db1a6d6394410cacfd6`, as recorded in `Package.resolved`.

Project: <https://github.com/scinfu/SwiftSoup>

Copyright © 2009–2025 Jonathan Hedley. Copyright © 2016–2025 Nabil Chatbi (Swift port). The complete license is reproduced at [`LICENSES/SwiftSoup-MIT.txt`](LICENSES/SwiftSoup-MIT.txt).

## swift-url (WebURL)

SwiftReadability links the `WebURL` product for browser-compatible WHATWG URL parsing and relative-reference resolution. swift-url is licensed under the Apache License, Version 2.0. The exact tested baseline is WebURL 0.4.2, revision `9306a962396a50d7d88e924afcd7ec67226763db`, as recorded in `Package.resolved`.

Project: <https://github.com/karwa/swift-url>

The upstream NOTICE attribution is reproduced verbatim:

> swift-url (WebURL)
>
> Copyright Karl Wagner, and the swift-url Contributors.

## Swift System

swift-url declares Swift System as a package dependency for its separate `WebURLSystemExtras` product. Consequently SwiftPM resolves Swift System 1.7.4 at revision `b5544ba79a70a0cb3563e75bf26dc198d6b40ed3` into `Package.resolved`. SwiftReadability selects only the core `WebURL` product, whose target closure is `WebURL` → `IDNA` → `UnicodeDataStructures`; none of those targets depends on `SystemPackage`. Swift System is therefore not linked into the `SwiftReadability` production product.

Swift System is licensed under Apache-2.0 with the Runtime Library Exception. The exception is reproduced at [`LICENSES/Swift-System-Runtime-Library-Exception.txt`](LICENSES/Swift-System-Runtime-Library-Exception.txt) alongside the complete Apache-2.0 text. It is recorded here for dependency-graph transparency, not as a claim that Swift System ships in the production library.

Project: <https://github.com/apple/swift-system>

## License texts and binary redistribution

The complete Apache License, Version 2.0 is included at [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt). A binary application embedding `SwiftReadability` should reproduce the repository BSD notice, applicable Readability Apache notices, the SwiftSoup MIT notice and license, and the swift-url Apache license and NOTICE attribution in its acknowledgements or accompanying documentation. The optional Mozilla JavaScript resources need an additional shipped-content attribution only when an application deliberately links `SwiftReadabilityJavaScriptReference`.
