import SwiftSoup

/// Serializes a SwiftSoup subtree with the HTML fragment spelling exposed by
/// browser `Element.innerHTML`, which is Mozilla Readability's default content
/// serializer. SwiftSoup deliberately uses jsoup-style output (`<br />`, bare
/// empty boolean attributes, and unescaped NBSP), so delegating to `html()`
/// changes the public `content` string even when the DOM is otherwise equal.
struct MozillaHTMLSerializer {
    private enum Namespace {
        case html
        case svg
        case mathML
    }

    private static let htmlVoidElements: Set<String> = [
        "area", "base", "basefont", "bgsound", "br", "col", "embed", "hr",
        "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    private static let rawTextElements: Set<String> = [
        "iframe", "noembed", "noframes", "noscript", "plaintext", "script", "style", "xmp",
    ]

    // HTML's "adjust SVG tag names" table. SwiftSoup currently lowercases
    // foreign-content names because it does not retain DOM namespaces.
    private static let svgElementNames: [String: String] = [
        "altglyph": "altGlyph",
        "altglyphdef": "altGlyphDef",
        "altglyphitem": "altGlyphItem",
        "animatecolor": "animateColor",
        "animatemotion": "animateMotion",
        "animatetransform": "animateTransform",
        "clippath": "clipPath",
        "feblend": "feBlend",
        "fecolormatrix": "feColorMatrix",
        "fecomponenttransfer": "feComponentTransfer",
        "fecomposite": "feComposite",
        "feconvolvematrix": "feConvolveMatrix",
        "fediffuselighting": "feDiffuseLighting",
        "fedisplacementmap": "feDisplacementMap",
        "fedistantlight": "feDistantLight",
        "fedropshadow": "feDropShadow",
        "feflood": "feFlood",
        "fefunca": "feFuncA",
        "fefuncb": "feFuncB",
        "fefuncg": "feFuncG",
        "fefuncr": "feFuncR",
        "fegaussianblur": "feGaussianBlur",
        "feimage": "feImage",
        "femerge": "feMerge",
        "femergenode": "feMergeNode",
        "femorphology": "feMorphology",
        "feoffset": "feOffset",
        "fepointlight": "fePointLight",
        "fespecularlighting": "feSpecularLighting",
        "fespotlight": "feSpotLight",
        "fetile": "feTile",
        "feturbulence": "feTurbulence",
        "foreignobject": "foreignObject",
        "glyphref": "glyphRef",
        "lineargradient": "linearGradient",
        "radialgradient": "radialGradient",
        "textpath": "textPath",
    ]

    // HTML's "adjust SVG attributes" table.
    private static let svgAttributeNames: [String: String] = [
        "attributename": "attributeName",
        "attributetype": "attributeType",
        "basefrequency": "baseFrequency",
        "baseprofile": "baseProfile",
        "calcmode": "calcMode",
        "clippathunits": "clipPathUnits",
        "diffuseconstant": "diffuseConstant",
        "edgemode": "edgeMode",
        "filterunits": "filterUnits",
        "glyphref": "glyphRef",
        "gradienttransform": "gradientTransform",
        "gradientunits": "gradientUnits",
        "kernelmatrix": "kernelMatrix",
        "kernelunitlength": "kernelUnitLength",
        "keypoints": "keyPoints",
        "keysplines": "keySplines",
        "keytimes": "keyTimes",
        "lengthadjust": "lengthAdjust",
        "limitingconeangle": "limitingConeAngle",
        "markerheight": "markerHeight",
        "markerunits": "markerUnits",
        "markerwidth": "markerWidth",
        "maskcontentunits": "maskContentUnits",
        "maskunits": "maskUnits",
        "numoctaves": "numOctaves",
        "pathlength": "pathLength",
        "patterncontentunits": "patternContentUnits",
        "patterntransform": "patternTransform",
        "patternunits": "patternUnits",
        "pointsatx": "pointsAtX",
        "pointsaty": "pointsAtY",
        "pointsatz": "pointsAtZ",
        "preservealpha": "preserveAlpha",
        "preserveaspectratio": "preserveAspectRatio",
        "primitiveunits": "primitiveUnits",
        "refx": "refX",
        "refy": "refY",
        "repeatcount": "repeatCount",
        "repeatdur": "repeatDur",
        "requiredextensions": "requiredExtensions",
        "requiredfeatures": "requiredFeatures",
        "specularconstant": "specularConstant",
        "specularexponent": "specularExponent",
        "spreadmethod": "spreadMethod",
        "startoffset": "startOffset",
        "stddeviation": "stdDeviation",
        "stitchtiles": "stitchTiles",
        "surfacescale": "surfaceScale",
        "systemlanguage": "systemLanguage",
        "tablevalues": "tableValues",
        "targetx": "targetX",
        "targety": "targetY",
        "textlength": "textLength",
        "viewbox": "viewBox",
        "viewtarget": "viewTarget",
        "xchannelselector": "xChannelSelector",
        "ychannelselector": "yChannelSelector",
        "zoomandpan": "zoomAndPan",
    ]

    static func innerHTML(of element: Element) -> String {
        var result = ""
        for child in element.getChildNodes() {
            append(
                child,
                parentNamespace: .html,
                parentTag: element.tagName().lowercased(),
                parentElement: element,
                to: &result
            )
        }
        return result
    }

    private static func append(
        _ node: Node,
        parentNamespace: Namespace,
        parentTag: String,
        parentElement: Element,
        to result: inout String
    ) {
        if let text = node as? TextNode {
            let value = text.getWholeText()
            if parentNamespace == .html, rawTextElements.contains(parentTag) {
                result += value
            } else {
                appendEscapedText(value, to: &result)
            }
            return
        }

        if let data = node as? DataNode {
            result += data.getWholeData()
            return
        }

        if let comment = node as? Comment {
            result += "<!--"
            result += comment.getData()
            result += "-->"
            return
        }

        guard let element = node as? Element else {
            result += (try? node.outerHtml()) ?? ""
            return
        }

        let rawTag = element.tagName().lowercased()
        let namespace = namespace(
            for: rawTag,
            parentNamespace: parentNamespace,
            parentTag: parentTag,
            parentElement: parentElement
        )
        let serializedTag = adjustedElementName(rawTag, namespace: namespace)

        result += "<"
        result += serializedTag
        if let attributes = element.getAttributes() {
            for attribute in attributes {
                result += " "
                result += adjustedAttributeName(attribute.getKey(), namespace: namespace)
                result += "=\""
                appendEscapedAttribute(attribute.getValue(), to: &result)
                result += "\""
            }
        }
        result += ">"

        if namespace == .html, htmlVoidElements.contains(rawTag) {
            return
        }

        for child in element.getChildNodes() {
            append(
                child,
                parentNamespace: namespace,
                parentTag: rawTag,
                parentElement: element,
                to: &result
            )
        }
        result += "</"
        result += serializedTag
        result += ">"
    }

    private static func namespace(
        for rawTag: String,
        parentNamespace: Namespace,
        parentTag: String,
        parentElement: Element
    ) -> Namespace {
        func namespaceFromHTML() -> Namespace {
            if rawTag == "svg" { return .svg }
            if rawTag == "math" { return .mathML }
            return .html
        }

        switch parentNamespace {
        case .html:
            return namespaceFromHTML()
        case .svg:
            if parentTag == "foreignobject" || parentTag == "desc" || parentTag == "title" {
                return namespaceFromHTML()
            }
            return .svg
        case .mathML:
            if ["mi", "mo", "mn", "ms", "mtext"].contains(parentTag),
               rawTag != "mglyph", rawTag != "malignmark" {
                return namespaceFromHTML()
            }
            if parentTag == "annotation-xml" {
                let encoding = ((try? parentElement.attr("encoding")) ?? "").lowercased()
                if encoding == "text/html" || encoding == "application/xhtml+xml" {
                    return namespaceFromHTML()
                }
            }
            return .mathML
        }
    }

    private static func adjustedElementName(_ rawName: String, namespace: Namespace) -> String {
        guard namespace == .svg else { return rawName }
        return svgElementNames[rawName] ?? rawName
    }

    private static func adjustedAttributeName(_ rawName: String, namespace: Namespace) -> String {
        let lowercase = rawName.lowercased()
        if namespace == .svg {
            return svgAttributeNames[lowercase] ?? rawName
        }
        if namespace == .mathML, lowercase == "definitionurl" {
            return "definitionURL"
        }
        return rawName
    }

    private static func appendEscapedText(_ value: String, to result: inout String) {
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x26: result += "&amp;"
            case 0x3C: result += "&lt;"
            case 0x3E: result += "&gt;"
            case 0x00A0: result += "&nbsp;"
            default: result.unicodeScalars.append(scalar)
            }
        }
    }

    private static func appendEscapedAttribute(_ value: String, to result: inout String) {
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "&quot;"
            case 0x26: result += "&amp;"
            case 0x00A0: result += "&nbsp;"
            default: result.unicodeScalars.append(scalar)
            }
        }
    }
}
