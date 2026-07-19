# SwiftReadability

A native Swift rewrite of [Mozilla Readability](https://github.com/mozilla/readability), using [SwiftSoup](https://github.com/scinfu/SwiftSoup) for standards-aware HTML parsing and DOM operations.

`SwiftReadability` extracts the primary article from an HTML document without a browser, JavaScript runtime, Node process, or network service. Mozilla Readability at commit [`ab4027a`](https://github.com/mozilla/readability/commit/ab4027a) is the behavioral authority for this package. The earlier [lake-of-fire Swift port](https://github.com/lake-of-fire/swift-readability) is important provenance and supplied native Swift foundation; default compatibility is measured against the pinned Mozilla reference: when inherited behavior and Mozilla disagree, the Mozilla contract wins unless an explicitly isolated compatibility extension is being exercised.

## Architecture

SwiftReadability is a standalone Swift Package Manager library for macOS, iOS, server, and command-line clients. It exposes two deliberately separate library products:

| Product | Purpose | Runtime JavaScript |
| --- | --- | --- |
| `SwiftReadability` | Production article extraction | None |
| `SwiftReadabilityJavaScriptReference` | Optional pinned Mozilla source for browser integrations, fixture oracles, and differential testing | Reference resources only |

The production pipeline is native Swift. SwiftSoup parses HTML and provides DOM operations; SwiftReadability owns metadata discovery, candidate scoring, cleanup, URL normalization, and result serialization. The `SwiftReadability` target neither contains nor depends on the JavaScript reference target.

Project-specific behavior is an explicit compatibility layer, not a competing Readability implementation. `ReadabilityOptions()` enables no extensions and is the mode compared directly with Mozilla. consumer application opts into its publisher cleanup and media-recovery policy through `ReadabilityExtensions.publisherAdaptations`; individual behaviors remain named flags, with carousel recovery isolated in `ImageCarouselNormalizer`. An extension may be added only with focused positive and false-positive tests while the complete default-mode Mozilla differential remains green.

## Requirements

- Swift 6.2
- iOS 15+, macOS 13+, tvOS 15+, or watchOS 9+
- SwiftSoup 2.13.6 is the exact tested DOM baseline. `Package.resolved` pins revision `ead56133a693d0184d8c2db1a6d6394410cacfd6`.

Node and npm are needed only for the optional JavaScript reference and differential test runners. Applications that depend only on `SwiftReadability` do not need them.

## Installation

Add SwiftReadability with Swift Package Manager:

```swift
.package(
    url: "https://github.com/wolfyy970/swift-readability.git",
    from: "0.1.0"
)
```

Then add only the native product to an application target:

```swift
.product(name: "SwiftReadability", package: "swift-readability")
```

The JavaScript reference product is optional and should not be linked into an application unless its source resources are intentionally needed.

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

Default options provide Mozilla-compatible behavior. A client that deliberately wants consumer application's enhanced publisher handling must opt in:

```swift
let publisherAdaptationsReader = Readability(
    html: htmlString,
    url: URL(string: "https://example.com/article")!,
    options: ReadabilityOptions(extensions: .publisherAdaptations)
)

let article = try publisherAdaptationsReader.parse()
```

The profile combines image-carousel recovery, publisher-chrome cleanup, article-body preservation, significant-media preservation, and ruby normalization. Selective opt-in is also supported, for example `extensions: [.imageCarouselRecovery, .significantMediaPreservation]`.

Check whether a document is likely to contain a readable article:

```swift
let isReaderable = Readability.isProbablyReaderable(html: htmlString)
```

Provide a custom serializer when extracted content should be returned as a type other than `String`:

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
- `extensions`

`Readability(document:)` operates on the supplied SwiftSoup document directly and destructively normalizes it, matching Mozilla's mutation model. The default serializer emits HTML; XML serialization is available when exact XML-style output is required.

## Behavioral authority and provenance

The compatibility corpus contains 136 Mozilla-format HTML inputs. In default mode, the direct differential compares every input and every observable result field with the byte-for-byte upstream Mozilla JavaScript at commit `ab4027a`; Swift and Mozilla currently match **136/136**. The official `Readability.js` and `Readability-readerable.js` files are protected by fixed SHA-256 integrity tests so the oracle cannot be edited to make a divergence disappear.

The same corpus also contains five explicitly profiled consumer application regressions for difficult Asahi article chrome, a Hypebeast carousel, a Web Japan feature, and BEPAL content. Their enhanced expected metadata, DOM, and content assertions describe `ReadabilityExtensions.publisherAdaptations`, not Mozilla's output. The differential runner intentionally ignores those enhancement profiles and parses all 136 sources with empty extensions on both sides; this preserves a clean Mozilla baseline while letting the native expected-output suite verify the opt-in client behavior separately.

The repository was forked from lake-of-fire's Swift implementation and retains its BSD license, attribution, and history. That implementation was an ambitious and useful starting point, informed in turn by Mozilla Readability and Readability4J. The current engineering direction is a reliable Swift implementation governed directly by the pinned Mozilla behavior, built on that lineage while following the pinned Mozilla contract. See [Third-party notices](THIRD_PARTY_NOTICES.md) for attribution and licensing details.

## Testing

Run the native Swift suite, including the packaged fixture corpus and focused regression tests:

```sh
swift test
# or
mise run test:swift
```

Run the native suite, pinned JavaScript oracle checks, and direct Swift-versus-Mozilla differential:

```sh
mise run test:parity
```

The fixture loaders fail closed: missing or malformed manifests, unknown selections or profiles, invalid regular expressions, missing sources, and zero selected fixtures are test failures rather than silent passes. The native expected-output runner applies `.publisherAdaptations` only to fixtures explicitly named under `extensionProfiles`; JavaScript expectations for those enhanced profiles are deliberately not treated as Mozilla expectations.

Run the direct Swift-versus-Mozilla result contract:

```sh
npm --prefix Tests/JavaScript ci
npm --prefix Tests/JavaScript run test:differential
```

The differential checks parse success, readerability, metadata, canonical extracted DOM, text content, and Mozilla-compatible UTF-16 length in default, no-extension mode. The current full result is 136/136. It uses the optional `SwiftReadabilityJavaScriptReference` product as an oracle; it does not add JavaScript to the native product. Mozilla comparisons run in bounded, short-lived fixture batches so multi-megabyte JSDOM pages cannot accumulate across the corpus; injected mismatches and malformed batches are covered by fail-closed tests.

`npm test` also verifies that both oracle files are byte-for-byte Mozilla `ab4027a` using pinned SHA-256 values. A source change therefore fails independently of behavioral fixture results:

```sh
npm --prefix Tests/JavaScript test
```

Filter the expected-output fixture runners with an exact comma-separated selection or regular expression:

```sh
SWIFT_READABILITY_FIXTURES=nytimes-3,qq mise run test:parity
SWIFT_READABILITY_FIXTURE_REGEX='^(mathjax|videos-2)$' mise run test:parity
```

Filter the direct differential runner by fixture-name substring:

```sh
SWIFT_READABILITY_DIFFERENTIAL_FILTER=guardian-1 \
  npm --prefix Tests/JavaScript run test:differential
```

The full, unfiltered suites are the release gates. A filtered run is only a debugging aid.

## Benchmarking

Run the fail-closed fixture benchmark in release mode:

```sh
swift run -c release SwiftReadabilityBench --iterations 5 --warmup 1
```

Inspect one fixture with internal pipeline distributions, or emit only an aggregate summary:

```sh
swift run -c release SwiftReadabilityBench \
  --filter guardian-1 --iterations 10 --warmup 2 --timings

swift run -c release SwiftReadabilityBench \
  --iterations 5 --warmup 1 --summary-only
```

Use `--fixtures PATH` and, if needed, `--manifest PATH` for another Mozilla-format corpus. Other flags are `--xml` and `--help`.

The rebuilt harness rejects unknown or malformed arguments, missing or empty corpora, missing sources, parse failures, empty output, invalid UTF-16 lengths, nondeterministic repeated output, invalid timing samples, and zero-duration measurements. Each warmup and measured iteration constructs a fresh reader. Output includes per-fixture and aggregate p50, p95, and mean latency, article and input throughput, and a deterministic result checksum; `--timings` adds distributions for internal pipeline labels. A release-mode benchmark smoke is now a CI gate, and distribution failure modes have focused tests.

Benchmark results supplement correctness evidence; they do not replace parity, differential, or state-isolation tests. 

## Security

SwiftReadability selects and extracts article content; it does **not** sanitize untrusted HTML. A client that renders `result.content` must apply an appropriate HTML sanitizer and Content Security Policy first, consistent with [Mozilla Readability's security guidance](https://github.com/mozilla/readability#security). consumer application only projects the extracted structure into native narration text and does not render `result.content` as a web page.

## License

SwiftReadability is distributed under the BSD 3-Clause license. Derived components and fixtures remain subject to their original licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
