import SwiftSoup
import WebURL

/// The document/base URL pair exposed by browser DOM URL properties.
///
/// Mozilla relies on both `document.baseURI` and reflected URL properties such
/// as `HTMLImageElement.src`. Keep that WHATWG resolution context in one place
/// so extraction-time inspection and post-processing cannot drift apart.
struct BrowserURLContext {
    let documentURL: WebURL
    let baseURL: WebURL

    init?(document: Document, documentURI: String) {
        guard let documentURL = WebURL(documentURI) else { return nil }
        self.documentURL = documentURL

        if let baseElement = try? document.select("base[href]").first() {
            let href = String(
                decoding: baseElement.attrOrEmptyUTF8(ReadabilityUTF8Arrays.href),
                as: UTF8.self
            )
            // The first <base href> wins. An invalid value falls back to the
            // document URL; browsers never continue to a later base element.
            baseURL = documentURL.resolve(href) ?? documentURL
        } else {
            baseURL = documentURL
        }
    }

    func resolve(_ reference: String) -> String? {
        baseURL.resolve(reference).map(String.init)
    }
}
