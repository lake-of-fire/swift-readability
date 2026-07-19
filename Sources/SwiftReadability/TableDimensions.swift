import SwiftSoup

/// Computes table dimensions using the same raw-attribute and JavaScript
/// `parseInt(..., 10) || 1` rules as Mozilla Readability.
func readabilityTableDimensions(_ table: Element) -> (rows: Double, columns: Double) {
    var rows = 0.0
    var columns = 0.0

    guard let tableRows = try? table.getElementsByTag("tr") else {
        return (rows, columns)
    }

    for row in tableRows {
        rows += javaScriptTableSpan(row.attrOrEmpty("rowspan"))

        var columnsInRow = 0.0
        if let cells = try? row.getElementsByTag("td") {
            for cell in cells {
                columnsInRow += javaScriptTableSpan(cell.attrOrEmpty("colspan"))
            }
        }
        columns = max(columns, columnsInRow)
    }

    return (rows, columns)
}
