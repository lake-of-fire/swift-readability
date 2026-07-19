// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import SwiftSoup

/// The browser interfaces that matter to Readability are not identical across
/// HTML, SVG, and MathML. SwiftSoup deliberately does not retain namespaces, so
/// this small classifier reconstructs the HTML parser's foreign-content rules
/// needed by Mozilla's `style`, `className`, and `tagName` checks.
private enum BrowserDOMNamespace {
    case html
    case svg
    case mathML
    case other
}

/// Returns whether the browser element represented by `element` exposes a
/// CSSStyleDeclaration through `element.style` in the pinned Mozilla test DOM.
/// HTML and SVG do; generic MathML/XML elements do not.
func browserDOMExposesStyleProperty(_ element: Element) -> Bool {
    switch browserDOMNamespace(of: element) {
    case .html, .svg:
        return true
    case .mathML, .other:
        return false
    }
}

/// Mirrors the guarded JavaScript expression
/// `node.className && node.className.includes && node.className.includes(...)`.
/// `HTMLElement.className` is a String, while SVG exposes SVGAnimatedString and
/// generic MathML elements in the pinned DOM expose no `className` property.
func browserDOMClassNameIncludes(_ element: Element, _ substring: String) -> Bool {
    guard browserDOMNamespace(of: element) == .html else { return false }
    return element.classNameSafe().contains(substring)
}

/// Tests `tagName` with JavaScript's exact case-sensitive equality. Browser
/// HTML tag names are uppercase; foreign/XML tag names retain their DOM case.
func browserDOMTagName(_ element: Element, equals expected: String) -> Bool {
    switch browserDOMNamespace(of: element) {
    case .html:
        return element.tagName().uppercased() == expected
    case .svg, .mathML, .other:
        return element.tagName() == expected
    }
}

private func browserDOMNamespace(of element: Element) -> BrowserDOMNamespace {
    guard let parent = element.parent(), !(parent is Document) else {
        guard element.ownerDocument()?.outputSettings().syntax() != .xml else {
            return xmlNamespace(for: element, inherited: .other)
        }
        return htmlInsertionNamespace(for: element)
    }

    let parentNamespace = browserDOMNamespace(of: parent)
    if element.ownerDocument()?.outputSettings().syntax() == .xml {
        return xmlNamespace(for: element, inherited: parentNamespace)
    }

    switch parentNamespace {
    case .html:
        return htmlInsertionNamespace(for: element)
    case .svg:
        if isSVGHTMLIntegrationPoint(parent) {
            return htmlInsertionNamespace(for: element)
        }
        return .svg
    case .mathML:
        if isMathMLHTMLIntegrationPoint(parent, child: element) {
            return htmlInsertionNamespace(for: element)
        }
        return .mathML
    case .other:
        return .other
    }
}

private func htmlInsertionNamespace(for element: Element) -> BrowserDOMNamespace {
    switch element.tagName().lowercased() {
    case "svg":
        return .svg
    case "math":
        return .mathML
    default:
        return .html
    }
}

private func xmlNamespace(
    for element: Element,
    inherited: BrowserDOMNamespace
) -> BrowserDOMNamespace {
    let namespace = element.attrOrEmpty("xmlns").lowercased()
    switch namespace {
    case "http://www.w3.org/1999/xhtml":
        return .html
    case "http://www.w3.org/2000/svg":
        return .svg
    case "http://www.w3.org/1998/math/mathml":
        return .mathML
    case "":
        return inherited
    default:
        return .other
    }
}

private func isSVGHTMLIntegrationPoint(_ element: Element) -> Bool {
    switch element.tagName().lowercased() {
    case "foreignobject", "desc", "title":
        return true
    default:
        return false
    }
}

private func isMathMLHTMLIntegrationPoint(_ parent: Element, child: Element) -> Bool {
    switch parent.tagName().lowercased() {
    case "mi", "mo", "mn", "ms", "mtext":
        let childName = child.tagName().lowercased()
        return childName != "mglyph" && childName != "malignmark"
    case "annotation-xml":
        let encoding = parent.attrOrEmpty("encoding").lowercased()
        return encoding == "text/html" || encoding == "application/xhtml+xml"
    default:
        return false
    }
}
