import SwiftUI

struct TableView: View {
    let block: TableBlock
    let source: Data
    let style: MarkdownStyle

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                // Header rows
                ForEach(block.headerRows) { row in
                    GridRow {
                        ForEach(row.cells) { cell in
                            cellView(for: cell, isHeader: true)
                        }
                    }
                }

                // Separator
                if !block.headerRows.isEmpty && !block.bodyRows.isEmpty {
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { _ in
                            Divider()
                        }
                    }
                }

                // Body rows
                ForEach(block.bodyRows) { row in
                    GridRow {
                        ForEach(row.cells) { cell in
                            cellView(for: cell, isHeader: false)
                        }
                    }
                }
            }
            .padding(12)
        }
        .liquidGlassSurface(cornerRadius: 12)
    }

    /// Renders a table cell with appropriate styling for header vs body rows.
    @ViewBuilder
    private func cellView(for cell: TableCell, isHeader: Bool) -> some View {
        InlineText(
            spans: cell.spans,
            source: source,
            style: style,
            fontOverride: isHeader ? style.baseFont.bold() : style.baseFont
        )
        .gridColumnAlignment(horizontalAlignment(for: cell.alignment))
    }

    private var columnCount: Int {
        let headerCount = block.headerRows.first?.cells.count ?? 0
        let bodyCount = block.bodyRows.first?.cells.count ?? 0
        return max(headerCount, bodyCount, block.alignments.count)
    }

    private func horizontalAlignment(for alignment: TableAlignment) -> HorizontalAlignment {
        switch alignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        case .none:
            return .leading
        }
    }
}
