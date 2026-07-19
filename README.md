# SwiftReadability

A pure Swift implementation of [Mozilla Readability](https://github.com/mozilla/readability), using [SwiftSoup](https://github.com/scinfu/SwiftSoup) for native DOM parsing.

SwiftReadability extracts the primary article from an HTML document without a browser, JavaScript runtime, Node, or network service. It also ships the aligned Readability.js sources as optional package resources for browser integrations and cross-implementation parity testing.

## Requirements

- Swift 6.2
- iOS 15+, macOS 13+, tvOS 15+, or watchOS 9+

## Installation

Add SwiftReadability with Swift Package Manager:

```swift
.package(
    url: "https://github.com/lake-of-fire/swift-readability.git",
    branch: "main"
)
```

Then add `SwiftReadability` to your target's dependencies.

## Usage

```swift
import SwiftReadability

let reader = Readability(
    html: htmlString,
    url: URL(string: "https://example.com/article")!
)

if let article = try reader.parse() {
    print(article.title ?? "Untitled")
    print(article.contentHTML)
    print(article.textContent)
}
```

Check whether a document is likely to contain a readable article:

```swift
let isReaderable = Readability.isProbablyReaderable(html: htmlString)
```

Provide a custom serializer when the extracted content should be returned as a type other than `String`:

```swift
let result = try reader.parse { articleElement in
    articleElement
}
```

## Options

`ReadabilityOptions` mirrors Mozilla Readability's public options:

- `debug`
- `maxElemsToParse`
- `nbTopCandidates`
- `charThreshold`
- `classesToPreserve`
- `keepClasses`
- `serializer`
- `useXMLSerializer`
- `disableJSONLD`
- `allowedVideoRegex`
- `linkDensityModifier`

`Readability(document:)` operates on the supplied SwiftSoup document directly. The default serializer emits HTML; XML serialization is available when exact XML-style output is required.

## Compatibility and provenance

The native implementation is tested against 136 shared Mozilla-format fixtures. The reference behavior and overlapping fixtures are synchronized through [Mozilla Readability commit `ab4027a`](https://github.com/mozilla/readability/commit/ab4027a), which follows the 0.6.0 release with MathJax preservation, en/em-dash title handling, Bilibili video support, and paragraph-wrapping fixes.

The corpus also includes project-specific regressions for Asahi article chrome, Hypebeast carousels, Web Japan feature pages, and BEPAL content. Both the Swift implementation and the bundled JavaScript reference pass the complete shared corpus; there are no skipped known failures.

This project began as a Swift port informed by both Mozilla Readability and Readability4J. Those origins and their licenses are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Testing

Run the complete Swift and JavaScript parity matrix:

```sh
mise run test:parity
```

The Swift runtime and Swift test suite are fully native and require neither Node nor npm:

```sh
swift test
# or
mise run test:swift
```

The optional JavaScript reference suite requires Node and installs its isolated development dependencies with `npm ci`:

```sh
mise run test:javascript
```

Filter either fixture runner with an exact comma-separated selection or a regular expression:

```sh
SWIFT_READABILITY_FIXTURES=nytimes-3,qq mise run test:parity
SWIFT_READABILITY_FIXTURE_REGEX='^(mathjax|videos-2)$' mise run test:parity
```

## Benchmarking

Run the fixture-based native benchmark harness in release mode:

```sh
swift run -c release SwiftReadabilityBench --iterations 5 --warmup 1
```

## License

SwiftReadability is distributed under the BSD 3-Clause license. Derived components and fixtures remain subject to their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
