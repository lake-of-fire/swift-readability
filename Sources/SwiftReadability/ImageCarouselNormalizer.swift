import Foundation
import SwiftSoup

/// consumer application compatibility extension for JavaScript-driven image galleries.
///
/// Mozilla Readability cannot retain images that exist only in hidden carousel
/// slides after ordinary scoring. This phase converts strongly identified,
/// image-dominant carousels into semantic figures before the Mozilla pipeline
/// runs. It intentionally requires multiple independent signals to avoid
/// rewriting ordinary article sections that happen to use “gallery” in a class.
final class ImageCarouselNormalizer: ProcessorBase {
    private let regEx: RegExUtil
    private let imageCarouselPattern = try! NSRegularExpression(
        pattern: "carousel|slider|slideshow|swiper|flickity|splide|keen-slider|glide",
        options: [.caseInsensitive]
    )
    private let imageGalleryRolePattern = try! NSRegularExpression(
        pattern: #"\bimage\s+gallery\b"#,
        options: [.caseInsensitive]
    )
    private let galleryPattern = try! NSRegularExpression(
        pattern: #"\bgallery\b"#,
        options: [.caseInsensitive]
    )
    private let rasterImageURLPattern = try! NSRegularExpression(
        pattern: #"(?i)\.(jpe?g|png|webp|gif)(\?|#|$)"#
    )

    private struct ImageItem {
        let image: Element
        let source: String
    }

    init(regEx: RegExUtil) {
        self.regEx = regEx
    }

    func normalize(_ document: Document) {
        let candidates = allElements(in: document).filter(isLikelyImageCarousel)
        var normalized: [Element] = []

        for candidate in candidates {
            if normalized.contains(where: { containsElement($0, candidate) }) {
                continue
            }
            guard candidate.parent() != nil,
                  let replacement = buildReadabilityCarousel(from: candidate, document: document)
            else {
                continue
            }
            normalized.append(candidate)
            _ = try? candidate.replaceWith(replacement)
        }
    }

    private func isLikelyImageCarousel(_ node: Element) -> Bool {
        let marker = [
            node.classNameSafe(),
            node.idSafe(),
            node.attrOrEmpty("role"),
            node.attrOrEmpty("aria-roledescription"),
            node.attrOrEmpty("data-ride"),
            node.attrOrEmpty("data-gallery"),
            node.attrOrEmpty("data-component"),
        ].joined(separator: " ")
        let hasStrongCarouselMarker = matches(imageCarouselPattern, in: marker)
        let hasImageGallerySemantics = matches(imageGalleryRolePattern, in: marker)
            || (matches(galleryPattern, in: marker) && allElements(in: node).contains { child in
                child !== node && matches(imageCarouselPattern, in: child.classNameSafe() + " " + child.idSafe())
            })
        guard hasStrongCarouselMarker || hasImageGallerySemantics else { return false }

        let images = imageItems(in: node)
        guard images.count >= 2 else { return false }

        let text = getInnerText(node, regEx: regEx)
        guard text.count <= 1_600 else { return false }
        if text.count > 120,
           linkDensity(in: node, textLength: javaScriptStringLength(text)) > 0.6 {
            return false
        }
        return true
    }

    private func imageItems(in node: Element) -> [ImageItem] {
        guard let images = try? node.getElementsByTag("img").array() else { return [] }
        var items: [ImageItem] = []
        var seen = Set<String>()

        for image in images {
            let source = bestImageSource(for: image)
            guard !source.isEmpty, seen.insert(source).inserted else { continue }
            items.append(ImageItem(image: image, source: source))
        }
        return items
    }

    private func bestImageSource(for image: Element) -> String {
        for attribute in [
            "src",
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-flickity-lazyload-src",
            "data-flickity-lazyload",
            "data-url",
        ] {
            let value = image.attrOrEmpty(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeRasterImageURL(value) { return value }
        }

        let ordinarySrcset = image.attrOrEmpty("srcset")
        if let value = firstImageFromSrcset(
            ordinarySrcset.isEmpty ? image.attrOrEmpty("data-srcset") : ordinarySrcset
        ) {
            return value
        }
        if let value = firstImageFromSrcset(image.attrOrEmpty("data-flickity-lazyload-srcset")) {
            return value
        }

        if let picture = image.parents().first(where: { $0.tagNameNormal() == "picture" }),
           let sources = try? picture.getElementsByTag("source").array() {
            for source in sources {
                let ordinarySrcset = source.attrOrEmpty("srcset")
                let srcset = ordinarySrcset.isEmpty ? source.attrOrEmpty("data-srcset") : ordinarySrcset
                if let value = firstImageFromSrcset(srcset) { return value }
            }
        }
        return ""
    }

    private func looksLikeRasterImageURL(_ value: String) -> Bool {
        !value.isEmpty && matches(rasterImageURLPattern, in: value)
    }

    private func firstImageFromSrcset(_ srcset: String) -> String? {
        for candidate in srcset.split(separator: ",") {
            guard let url = candidate.split(whereSeparator: { $0.isWhitespace }).first else { continue }
            let value = String(url).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeRasterImageURL(value) { return value }
        }
        return nil
    }

    private func buildReadabilityCarousel(from sourceNode: Element, document: Document) -> Element? {
        let items = imageItems(in: sourceNode)
        guard items.count >= 2,
              let figure = try? document.createElement("figure"),
              let track = try? document.createElement("div")
        else {
            return nil
        }

        _ = try? figure.attr("data-readability-carousel", "true")
        _ = try? figure.attr("role", "group")
        _ = try? figure.attr("aria-label", "Image gallery")
        _ = try? track.attr("data-readability-carousel-track", "")
        _ = try? figure.appendChild(track)

        for item in items {
            guard let slide = try? document.createElement("figure"),
                  let image = try? document.createElement("img")
            else {
                continue
            }
            _ = try? slide.attr("data-readability-carousel-slide", "")
            _ = try? image.attr("src", item.source)

            for attribute in ["alt", "width", "height"] {
                let value = item.image.attrOrEmpty(attribute)
                if !value.isEmpty { _ = try? image.attr(attribute, value) }
            }
            _ = try? slide.appendChild(image)

            if let caption = carouselCaption(for: item.image, boundary: sourceNode),
               let figcaption = try? document.createElement("figcaption") {
                _ = try? figcaption.text(caption)
                _ = try? slide.appendChild(figcaption)
            }
            _ = try? track.appendChild(slide)
        }
        return figure
    }

    private func carouselCaption(for image: Element, boundary: Element) -> String? {
        var current: Element? = image
        while let element = current, element !== boundary {
            if let caption = try? element.select("figcaption, [class*=caption], [class*=credit]").first() {
                let text = getInnerText(caption, regEx: regEx)
                if !text.isEmpty,
                   text.range(
                       of: #"^\d+\s+of\s+\d+$"#,
                       options: [.regularExpression, .caseInsensitive]
                   ) == nil {
                    return text
                }
            }
            current = element.parent()
        }
        return nil
    }

    private func containsElement(_ ancestor: Element, _ descendant: Element) -> Bool {
        var current = descendant.parent()
        while let element = current {
            if element === ancestor { return true }
            current = element.parent()
        }
        return false
    }

    private func allElements(in root: Element) -> [Element] {
        var result: [Element] = []
        var stack = [root]
        while let current = stack.popLast() {
            result.append(current)
            stack.append(contentsOf: current.children().reversed())
        }
        return result
    }

    private func linkDensity(in element: Element, textLength: Int) -> Double {
        guard textLength > 0,
              let links = try? element.getElementsByTag("a").array(),
              !links.isEmpty
        else {
            return 0
        }
        let linkLength = links.reduce(0) { partial, link in
            partial + javaScriptStringLength(getInnerText(link, regEx: regEx))
        }
        return Double(linkLength) / Double(textLength)
    }

    private func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
