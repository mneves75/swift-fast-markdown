import Foundation
import SwiftUI

public struct AttributedStringRenderer {
    public init() {}

    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        var result = AttributedString()
        let blocks = document.blocks
        let blockCount = blocks.count
        let blockSpacing = style.blockSpacing

        for index in blocks.indices {
            result.append(renderBlock(blocks[index], source: document.sourceData, style: style, indentLevel: 0))
            if index < blockCount - 1 {
                if blockSpacing > 1 {
                    result.append(AttributedString(String(repeating: "\n", count: blockSpacing)))
                } else {
                    result.append(AttributedString("\n"))
                }
            }
        }
        return result
    }

    public func renderInline(
        _ spans: [MarkdownSpan],
        source: Data,
        style: MarkdownStyle = .default,
        fontOverride: Font? = nil
    ) -> AttributedString {
        let font = fontOverride ?? style.baseFont
        return renderInline(spans, source: source, style: style, fontOverride: font)
    }

    private func renderBlock(_ block: MarkdownBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        switch block {
        case .paragraph(let paragraph):
            return renderSpans(paragraph.spans, source: source, style: style, fontOverride: style.baseFont, indentLevel: indentLevel)
        case .heading(let heading):
            let font = headingFont(level: heading.level, style: style)
            return renderSpans(heading.spans, source: source, style: style, fontOverride: font, indentLevel: indentLevel)
        case .codeBlock(let codeBlock):
            return renderCodeBlock(codeBlock, source: source, style: style, indentLevel: indentLevel)
        case .blockQuote(let quote):
            return renderBlockQuote(quote, source: source, style: style, indentLevel: indentLevel)
        case .list(let list):
            return renderList(list, source: source, style: style, indentLevel: indentLevel)
        case .table(let table):
            return renderTable(table, source: source, style: style, indentLevel: indentLevel)
        case .thematicBreak:
            return AttributedString(String(repeating: "—", count: 20))
        case .htmlBlock(let html):
            return renderHTML(html, source: source, style: style, indentLevel: indentLevel)
        }
    }

    @inline(__always)
    private func renderSpans(
        _ spans: [MarkdownSpan],
        source: Data,
        style: MarkdownStyle,
        fontOverride: Font,
        indentLevel: Int
    ) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            result.append(renderSpan(span, source: source, style: style, fontOverride: fontOverride))
        }
        if indentLevel > 0 {
            let prefix = String(repeating: " ", count: indentLevel)
            return AttributedString(prefix) + result
        }
        return result
    }

    @inline(__always)
    private func renderSpan(
        _ span: MarkdownSpan,
        source: Data,
        style: MarkdownStyle,
        fontOverride: Font
    ) -> AttributedString {
        switch span {
        case .text(let content):
            return applyBaseAttributes(AttributedString(content.string(in: source)), font: fontOverride, color: style.textColor)
        case .emphasis(let children):
            var attributed = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            attributed.inlinePresentationIntent = .emphasized
            return attributed
        case .strong(let children):
            var attributed = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            attributed.inlinePresentationIntent = .stronglyEmphasized
            return attributed
        case .strikethrough(let children):
            var attributed = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            attributed.strikethroughStyle = .single
            return attributed
        case .underline(let children):
            var attributed = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            attributed.underlineStyle = .single
            return attributed
        case .code(let content):
            var attributed = applyBaseAttributes(AttributedString(content.string(in: source)), font: style.codeFont, color: style.codeTextColor)
            attributed.backgroundColor = style.codeBackgroundColor
            return attributed
        case .link(let children, let destination, _):
            var attributed = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            attributed.foregroundColor = style.linkColor
            if let destination {
                let link = destination.string(in: source)
                if let url = URL(string: link) {
                    attributed.link = url
                }
            }
            return attributed
        case .image(let alt, _, _):
            return renderInline(alt, source: source, style: style, fontOverride: fontOverride)
        case .lineBreak:
            return AttributedString("\n")
        case .softBreak:
            return AttributedString(" ")
        case .html(let content):
            return applyBaseAttributes(AttributedString(content.string(in: source)), font: fontOverride, color: style.textColor)
        case .wikiLink(let target, let children):
            let label = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            var attributed = label
            attributed.foregroundColor = style.linkColor
            let link = target.string(in: source)
            if let url = URL(string: link) {
                attributed.link = url
            }
            return attributed
        case .latexInline(let content), .latexDisplay(let content):
            return applyBaseAttributes(AttributedString(content.string(in: source)), font: style.codeFont, color: style.codeTextColor)
        }
    }

    @inline(__always)
    private func renderInline(
        _ spans: [MarkdownSpan],
        source: Data,
        style: MarkdownStyle,
        fontOverride: Font
    ) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            result.append(renderSpan(span, source: source, style: style, fontOverride: fontOverride))
        }
        return result
    }

    @inline(__always)
    private func renderCodeBlock(_ codeBlock: CodeBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        var content = AttributedString(codeBlock.content.string(in: source))
        content = applyBaseAttributes(content, font: style.codeFont, color: style.codeTextColor)
        content.backgroundColor = style.codeBackgroundColor
        if indentLevel > 0 {
            let prefix = String(repeating: " ", count: indentLevel)
            return AttributedString(prefix) + content
        }
        return content
    }

    @inline(__always)
    private func renderBlockQuote(_ quote: BlockQuoteBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let prefix = String(repeating: " ", count: indentLevel) + "› "
        var result = AttributedString()
        let blocks = quote.blocks
        let count = blocks.count
        for index in blocks.indices {
            result.append(AttributedString(prefix))
            result.append(renderBlock(blocks[index], source: source, style: style, indentLevel: indentLevel + style.listIndent))
            if index < count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    @inline(__always)
    private func renderList(_ list: ListBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        var result = AttributedString()
        let items = list.items
        let count = items.count
        let ordered = list.ordered
        let start = list.start

        for index in items.indices {
            let marker: String
            if ordered {
                marker = "\(start + index). "
            } else {
                marker = "• "
            }
            var renderedItem = AttributedString(marker)
            let blocks = items[index].blocks
            let blockCount = blocks.count
            for blockIndex in blocks.indices {
                renderedItem.append(renderBlock(blocks[blockIndex], source: source, style: style, indentLevel: indentLevel + style.listIndent))
                if blockIndex < blockCount - 1 {
                    renderedItem.append(AttributedString("\n"))
                }
            }
            let prefix = String(repeating: " ", count: indentLevel)
            result.append(AttributedString(prefix) + renderedItem)
            if index < count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    @inline(__always)
    private func renderTable(_ table: TableBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let rows = table.headerRows + table.bodyRows
        guard !rows.isEmpty else { return AttributedString() }
        let prefix = String(repeating: " ", count: indentLevel)
        var result = AttributedString()
        let rowCount = rows.count
        for index in rows.indices {
            let row = rows[index]
            let cells = row.cells
            let cellCount = cells.count
            var rowString = AttributedString(prefix)
            for cellIndex in cells.indices {
                rowString.append(renderSpans(cells[cellIndex].spans, source: source, style: style, fontOverride: style.baseFont, indentLevel: 0))
                if cellIndex < cellCount - 1 {
                    rowString.append(AttributedString(" | "))
                }
            }
            result.append(rowString)
            if index < rowCount - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    @inline(__always)
    private func renderHTML(_ html: HTMLBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        if indentLevel > 0 {
            let prefix = String(repeating: " ", count: indentLevel)
            return AttributedString(prefix) + applyBaseAttributes(AttributedString(html.content.string(in: source)), font: style.baseFont, color: style.textColor)
        }
        return applyBaseAttributes(AttributedString(html.content.string(in: source)), font: style.baseFont, color: style.textColor)
    }

    @inline(__always)
    private func headingFont(level: Int, style: MarkdownStyle) -> Font {
        let index = max(0, min(level - 1, style.headingFonts.count - 1))
        return style.headingFonts[index]
    }

    @inline(__always)
    private func applyBaseAttributes(_ string: AttributedString, font: Font, color: Color) -> AttributedString {
        var attributed = string
        attributed.font = font
        attributed.foregroundColor = color
        return attributed
    }
}
