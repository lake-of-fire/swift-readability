# SwiftReadability

A Swift 6.2 port of Mozilla's Readability.js using SwiftSoup for DOM parsing.

## Requirements

- Swift 6.2
- iOS 15+, macOS 15+

## Installation (SwiftPM)

Add the package dependency:

```
.package(url: "https://github.com/lake-of-fire/swift-readability", from: "0.1.0")
```

Then add `SwiftReadability` to your target dependencies.

## Usage

Basic extraction:

```swift
import SwiftReadability

let reader = Readability(
    html: htmlString,
    url: URL(string: "https://example.com")!
)
let result = try reader.parse()
print(result?.title ?? "(no title)")
print(result?.contentHTML ?? "(no content)")
```

Custom serialization (mirrors Readability.js `serializer`):

```swift
let result = try reader.parse { element in
    // Return any type you want from the article content element.
    element
}
```

Readerable check:

```swift
let readerable = Readability.isProbablyReaderable(html: htmlString)
```

## Options

`ReadabilityOptions` mirrors Readability.js:

- `debug` (Bool)
- `maxElemsToParse` (Int)
- `nbTopCandidates` (Int)
- `charThreshold` (Int)
- `classesToPreserve` ([String])
- `keepClasses` (Bool)
- `serializer` ((Element) -> String)
- `useXMLSerializer` (Bool, defaults to `false` for parity with Readability.js). The test suite enables XML serialization explicitly to match Mozilla's fixture expectations for boolean attributes.
- `disableJSONLD` (Bool)
- `allowedVideoRegex` (NSRegularExpression)
- `linkDensityModifier` (Double)

## Parity notes

- Fixture parity: the fixture tests enable `useXMLSerializer: true` to preserve boolean attribute values (Mozilla fixtures expect `itemscope="itemscope"`).
- Live DOM: `Readability(document:)` operates directly on the passed `Document` (no reparse), matching JS behavior and improving performance.
- Serializer parity: default output uses HTML serialization (JS `innerHTML`), while XML serialization is available via `useXMLSerializer`.

## Tests

The test suite ports Mozilla's `test-readability.js` and `test-isProbablyReaderable.js`,
including the full fixture corpus under `Tests/SwiftReadabilityTests/Fixtures`.

Run all tests:

```
swift test -q -Xswiftc -suppress-warnings
```

Filter fixtures:

```
SWIFT_READABILITY_FIXTURES=nytimes-3 swift test -q -Xswiftc -suppress-warnings
```
