# SwiftReadability

A native Swift implementation of [Mozilla Readability](https://github.com/mozilla/readability), using [SwiftSoup](https://github.com/scinfu/SwiftSoup) for standards-aware HTML parsing and DOM operations and [WebURL](https://github.com/karwa/swift-url) for WHATWG URL resolution.

`SwiftReadability` extracts the primary article from an HTML document without a browser, JavaScript runtime, Node process, or network service. Mozilla Readability at commit [`ab4027a`](https://github.com/mozilla/readability/commit/ab4027a) is the behavioral authority for this package. The earlier [lake-of-fire Swift port](https://github.com/lake-of-fire/swift-readability) is important provenance and supplied native Swift foundation; default compatibility is measured against the pinned Mozilla reference: when inherited behavior and Mozilla disagree, the Mozilla contract wins unless an explicitly isolated compatibility extension is being exercised.

## Architecture

SwiftReadability is a standalone Swift Package Manager library for macOS, iOS, server, and command-line clients. It exposes two deliberately separate library products:

| Product | Purpose | Runtime JavaScript |
| --- | --- | --- |
| `SwiftReadability` | Production article extraction | None |
| `SwiftReadabilityJavaScriptReference` | Optional pinned Mozilla source for browser integrations, fixture oracles, and differential testing | Reference resources only |

The production pipeline is native Swift. SwiftSoup parses HTML and provides DOM operations; WebURL supplies browser-compatible URL parsing and relative-reference resolution; SwiftReadability owns metadata discovery, candidate scoring, cleanup, and result serialization. The `SwiftReadability` target neither contains nor depends on the JavaScript reference target.

Non-Mozilla behavior is an explicit compatibility layer, not a competing Readability implementation. `ReadabilityOptions()` enables no extensions and is the mode compared directly with Mozilla. Clients compose only the granular `ReadabilityExtensions` flags they deliberately need; the package provides no client-specific presets. An extension may be added only with focused positive and false-positive tests while the complete default-mode Mozilla differential remains green.

## Requirements

- Swift 6.2
- iOS 15+, macOS 13+, tvOS 15+, or watchOS 9+
- SwiftSoup 2.13.6 is the exact tested DOM baseline. `Package.resolved` pins revision `ead56133a693d0184d8c2db1a6d6394410cacfd6`.
- WebURL 0.4.2 is the exact tested WHATWG URL baseline. `Package.resolved` pins revision `9306a962396a50d7d88e924afcd7ec67226763db`.

Node and npm are needed only for the optional JavaScript reference and differential test runners. Applications that depend only on `SwiftReadability` do not need them.

WebURL is a pure-Swift, web-platform-test-verified implementation whose Swift 5.5 package manifest back-deploys across every platform supported here. Its core target has no platform runtime dependency: `SwiftReadability` links `WebURL`, `IDNA`, and `UnicodeDataStructures`. SwiftPM also resolves the separately declared Swift System integration package, but no Swift System target is linked into the production product. Binary distributors must retain WebURL's Apache-2.0 license and NOTICE attribution as described in [Third-party notices](THIRD_PARTY_NOTICES.md).

WebURL adds native code to statically linked clients, so applications should measure final artifact size and extraction performance in their own build configuration. The checked Release benchmark smoke verifies that the harness remains deterministic and fail-closed; it is not a performance-regression gate because no stored baseline or threshold is enforced. This project does not present a stale point-in-time binary measurement as a universal size or speed claim.

## Installation

Add SwiftReadability with Swift Package Manager:

```swift
.package(
    url: "https://github.com/wolfyy970/swift-readability.git",
    from: "0.3.0"
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

Default options provide Mozilla-compatible behavior. Clients may deliberately compose individual non-Mozilla policies when their input requires them:

```swift
let adaptedReader = Readability(
    html: htmlString,
    url: URL(string: "https://example.com/article")!,
    options: ReadabilityOptions(
        extensions: [.imageCarouselRecovery, .publisherChromeCleanup]
    )
)

let article = try adaptedReader.parse()
```

Available flags cover image-carousel recovery, publisher-chrome cleanup, article-body preservation, significant-media preservation, and ruby normalization. There is intentionally no aggregate preset: choosing and versioning a policy combination belongs to the consuming application.

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

Most `ReadabilityOptions` fields correspond directly to Mozilla Readability options: `debug`, `maxElemsToParse`, `nbTopCandidates`, `charThreshold`, `classesToPreserve`, `keepClasses`, `serializer`, `disableJSONLD`, `allowedVideoRegex`, and `linkDensityModifier`. Their default, extension-free behavior is covered by the Mozilla differential.

Two fields are intentionally Swift-specific and are not represented as Mozilla options:

- `useXMLSerializer` requests SwiftSoup's XML output syntax when the supplied document was parsed as XML. It exists for Swift serialization use cases; it is not part of the JavaScript API and is outside the default HTML differential contract.
- `extensions` enables explicitly named, non-Mozilla compatibility policies for publisher cleanup, content recovery, media preservation, and ruby normalization. Its default is the empty set.

`Readability(document:)` operates on the supplied SwiftSoup document directly and destructively normalizes it, matching Mozilla's mutation model. The default serializer emits HTML. Prefer the generic `parse(serializer:)` overload when a caller needs a non-string projection; use XML serialization only for an actual XML input whose consumer requires XML syntax.

## Behavioral authority and provenance

The compatibility corpus contains 136 Mozilla-format HTML inputs. In default mode, the direct differential compares every input and every observable result field with the byte-for-byte upstream Mozilla JavaScript at commit `ab4027a`; Swift and Mozilla currently match **136/136**. The official `Readability.js` and `Readability-readerable.js` files are protected by fixed SHA-256 integrity tests, making any oracle change require an explicit digest update and upstream verification during review.

Mozilla's own JSDOM fixture runner deliberately removes source comments before comparing its frozen `expected.html` files, even though production Readability preserves comments inside selected content. This repository retains those upstream snapshots unchanged as provenance. For the 33 upstream inputs where raw comments change observable output, `expected-raw-input.html` is a generated overlay from the byte-verified Mozilla oracle. Generation first proves the legacy file still matches Mozilla under its historical comment-free input policy, then records the untouched raw-input result. Native and JavaScript fixture comparisons prefer the overlay and compare comment position and data strictly; neither production output nor the direct differential removes or masks comments.

The same corpus also contains five explicitly profiled extension regressions for difficult Asahi article chrome, a Hypebeast carousel, a Web Japan feature, and BEPAL content. Their enhanced expected metadata, DOM, and content assertions use the test-only `publisherAdaptations` profile, which composes all granular extensions and is not public API or Mozilla output. The differential runner intentionally ignores enhancement profiles and parses all 136 sources with empty extensions on both sides; this preserves a clean Mozilla baseline while letting the native expected-output suite verify opt-in behavior separately.

The repository was forked from lake-of-fire's Swift implementation and retains its BSD license, attribution, and history. That implementation was an ambitious and useful starting point, informed in turn by Mozilla Readability and Readability4J. The current engineering direction is a reliable Swift implementation governed directly by the pinned Mozilla behavior, built on that lineage while following the pinned Mozilla contract.

This is not represented as a clean-room implementation. It is a materially rewritten work in a documented lineage: the earlier Swift port supplied scaffolding, Mozilla supplies the pinned behavioral contract and the optional byte-identical oracle, and both Mozilla Readability and Readability4J remain credited where their Apache-licensed work informs the native implementation. See [Provenance and licensing](docs/provenance-and-licensing.md) for the component map and [Third-party notices](THIRD_PARTY_NOTICES.md) for attribution and redistribution terms.

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

The fixture loaders fail closed: missing or malformed manifests, unknown selections or profiles, invalid regular expressions, missing sources, and zero selected fixtures are test failures rather than silent passes. Source bytes are passed to both implementations without trimming. The native expected-output runner applies the test-only `publisherAdaptations` composition only to fixtures explicitly named under `extensionProfiles`; JavaScript expectations for those enhanced profiles are deliberately not treated as Mozilla expectations.

Run the direct Swift-versus-Mozilla result contract:

```sh
npm --prefix Tests/JavaScript ci
npm --prefix Tests/JavaScript run test:differential
```

The differential checks parse success, readerability, every metadata field, exact browser-serialized `content`, text content, and Mozilla-compatible UTF-16 length with true default options and no extensions. A canonical DOM comparison runs as an additional structural diagnostic rather than masking serialization differences. The current full result is 136/136. It uses the optional `SwiftReadabilityJavaScriptReference` product as an oracle; it does not add JavaScript to the native product. The executable oracle environment is pinned by `Tests/JavaScript/package-lock.json` to Node 22 in CI and JSDOM 29.1.1, because DOM and serialization behavior are part of the comparison surface. Mozilla comparisons run in bounded, short-lived fixture batches so multi-megabyte JSDOM pages cannot accumulate across the corpus; injected mismatches and malformed batches are covered by fail-closed tests.

`npm test` also verifies that both oracle files are byte-for-byte Mozilla `ab4027a` using pinned SHA-256 values. A source change therefore fails independently of behavioral fixture results:

```sh
npm --prefix Tests/JavaScript test
```

The same command checks every raw-input overlay by regenerating it in memory from the pinned oracle. Maintainers can explicitly rewrite the overlays after a reviewed oracle or corpus update:

```sh
npm --prefix Tests/JavaScript run fixtures:write-raw-input
npm --prefix Tests/JavaScript run fixtures:check-raw-input
```

The write command is deterministic and refuses to create an overlay unless the corresponding legacy `expected.html` still matches the pinned Mozilla implementation after reproducing Mozilla's documented comment-removal fixture setup.

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

SwiftReadability selects and extracts article content; it does **not** sanitize untrusted HTML. A client that renders `result.content` must apply an appropriate HTML sanitizer and Content Security Policy first, consistent with [Mozilla Readability's security guidance](https://github.com/mozilla/readability#security). The package neither renders nor executes extracted content.

## License

The repository is a multi-license distribution. The inherited Swift implementation and original Swift contributions are distributed under the BSD 3-Clause license in [`LICENSE`](LICENSE); Apache-derived implementation material, the Mozilla oracle, and Mozilla-derived fixtures remain subject to Apache-2.0; SwiftSoup is MIT; and WebURL is Apache-2.0 with its upstream NOTICE attribution. This is not a blanket relicensing of third-party work. See [Provenance and licensing](docs/provenance-and-licensing.md) and [Third-party notices](THIRD_PARTY_NOTICES.md).
