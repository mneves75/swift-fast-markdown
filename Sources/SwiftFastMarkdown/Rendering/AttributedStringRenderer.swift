import Foundation
import SwiftUI

public struct AttributedStringRenderer {
    public init() {}

    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        var result = AttributedString()
        for (index, block) in document.blocks.enumerated() {
            let rendered = renderBlock(block, source: document.sourceData, style: style, indentLevel: 0)
            result.append(rendered)
            if index < document.blocks.count - 1 {
                result.append(AttributedString(String(repeating: "\n", count: style.blockSpacing)))
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
            // Apply italic font trait for visual styling
            let italicFont = fontOverride.italic()
            var attributed = renderInline(children, source: source, style: style, fontOverride: italicFont)
            attributed.inlinePresentationIntent = .emphasized
            return attributed
        case .strong(let children):
            // Apply bold font trait for visual styling
            let boldFont = fontOverride.bold()
            var attributed = renderInline(children, source: source, style: style, fontOverride: boldFont)
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

    private func renderCodeBlock(_ codeBlock: CodeBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        var content = AttributedString(codeBlock.content.string(in: source))
        content = applyBaseAttributes(content, font: style.codeFont, color: style.codeTextColor)
        content.backgroundColor = style.codeBackgroundColor
        let prefix = String(repeating: " ", count: indentLevel)
        return AttributedString(prefix) + content
    }

    private func renderBlockQuote(_ quote: BlockQuoteBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let prefix = String(repeating: " ", count: indentLevel) + "› "
        var result = AttributedString()
        for (index, block) in quote.blocks.enumerated() {
            let rendered = renderBlock(block, source: source, style: style, indentLevel: indentLevel + style.listIndent)
            result.append(AttributedString(prefix))
            result.append(rendered)
            if index < quote.blocks.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func renderList(_ list: ListBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        var result = AttributedString()
        for (index, item) in list.items.enumerated() {
            let marker: String
            if list.ordered {
                marker = "\(list.start + index). "
            } else {
                marker = "• "
            }
            var renderedItem = AttributedString(marker)
            for (blockIndex, block) in item.blocks.enumerated() {
                let rendered = renderBlock(block, source: source, style: style, indentLevel: indentLevel + style.listIndent)
                renderedItem.append(rendered)
                if blockIndex < item.blocks.count - 1 {
                    renderedItem.append(AttributedString("\n"))
                }
            }
            let prefix = String(repeating: " ", count: indentLevel)
            result.append(AttributedString(prefix) + renderedItem)
            if index < list.items.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func renderTable(_ table: TableBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let rows = table.headerRows + table.bodyRows
        guard !rows.isEmpty else { return AttributedString() }
        let prefix = String(repeating: " ", count: indentLevel)
        var result = AttributedString()
        for (index, row) in rows.enumerated() {
            let cellText = row.cells.map { cell in
                renderSpans(cell.spans, source: source, style: style, fontOverride: style.baseFont, indentLevel: 0)
            }
            var rowString = AttributedString(prefix)
            for (cellIndex, cellValue) in cellText.enumerated() {
                rowString.append(cellValue)
                if cellIndex < cellText.count - 1 {
                    rowString.append(AttributedString(" | "))
                }
            }
            result.append(rowString)
            if index < rows.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func renderHTML(_ html: HTMLBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let prefix = String(repeating: " ", count: indentLevel)
        return AttributedString(prefix) + applyBaseAttributes(AttributedString(html.content.string(in: source)), font: style.baseFont, color: style.textColor)
    }

    private func headingFont(level: Int, style: MarkdownStyle) -> Font {
        let index = max(0, min(level - 1, style.headingFonts.count - 1))
        return style.headingFonts[index]
    }

    private func applyBaseAttributes(_ string: AttributedString, font: Font, color: Color) -> AttributedString {
        var attributed = string
        attributed.font = font
        attributed.foregroundColor = color
        return attributed
    }

}
