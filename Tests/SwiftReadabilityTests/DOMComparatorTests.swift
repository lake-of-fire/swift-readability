import Testing
@testable import SwiftReadability

struct DOMComparatorTests {
    @Test func inlineBoundaryWhitespaceIsSignificant() {
        let comparison = DOMComparator.compare(
            actualHTML: "<p>Hello <em>world</em></p>",
            expectedHTML: "<p>Hello<em>world</em></p>"
        )

        #expect(!comparison.isEqual)
    }

    @Test func runsOfWhitespaceAreCollapsed() {
        let comparison = DOMComparator.compare(
            actualHTML: "<p>Hello \n\t world</p>",
            expectedHTML: "<p>Hello world</p>"
        )

        #expect(comparison.isEqual)
    }

    @Test func terminalFormattingWhitespaceIsIgnored() {
        let comparison = DOMComparator.compare(
            actualHTML: "<p>Text</p>",
            expectedHTML: "<p>Text \n</p>"
        )

        #expect(comparison.isEqual)
    }

    @Test func whitespaceOnlyNodesAreIgnored() {
        let comparison = DOMComparator.compare(
            actualHTML: "<div>\n<p>Text</p>\n</div>",
            expectedHTML: "<div><p>Text</p></div>"
        )

        #expect(comparison.isEqual)
    }

    @Test func commentsAreObservable() {
        let missing = DOMComparator.compare(
            actualHTML: "<div><!-- implementation note --><p>Text</p></div>",
            expectedHTML: "<div><p>Text</p></div>"
        )
        let changed = DOMComparator.compare(
            actualHTML: "<div><!-- first --><p>Text</p></div>",
            expectedHTML: "<div><!-- second --><p>Text</p></div>"
        )
        let identical = DOMComparator.compare(
            actualHTML: "<div><!-- retained --><p>Text</p></div>",
            expectedHTML: "<div><!-- retained --><p>Text</p></div>"
        )

        #expect(!missing.isEqual)
        #expect(!changed.isEqual)
        #expect(identical.isEqual)
    }

    @Test func attributeOrderIsSignificantLikeTheJavaScriptOracle() {
        let comparison = DOMComparator.compare(
            actualHTML: #"<p id="article" class="body">Text</p>"#,
            expectedHTML: #"<p class="body" id="article">Text</p>"#
        )

        #expect(!comparison.isEqual)
    }

    @Test func validUnicodeAttributeNamesAreCompared() {
        let comparison = DOMComparator.compare(
            actualHTML: #"<p å="actual">Text</p>"#,
            expectedHTML: #"<p å="expected">Text</p>"#
        )

        #expect(!comparison.isEqual)
    }

    @Test func differentTreeLengthsAreRejected() {
        let comparison = DOMComparator.compare(
            actualHTML: "<div><p>One</p><p>Two</p></div>",
            expectedHTML: "<div><p>One</p></div>"
        )

        #expect(!comparison.isEqual)
    }
}
