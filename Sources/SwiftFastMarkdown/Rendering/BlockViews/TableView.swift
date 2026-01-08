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
                            InlineText(
                                spans: cell.spans,
                                source: source,
                                style: style,
                                fontOverride: style.baseFont.bold()
                            )
                            .gridColumnAlignment(horizontalAlignment(for: cell.alignment))
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
                            InlineText(
                                spans: cell.spans,
                                source: source,
                                style: style,
                                fontOverride: style.baseFont
                            )
                            .gridColumnAlignment(horizontalAlignment(for: cell.alignment))
                        }
                    }
                }
            }
            .padding(12)
        }
        .liquidGlassSurface(cornerRadius: 12)
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
