import Foundation
import SwiftUI

public struct AttributedStringRenderer {
    private static let newline = AttributedString("\n")
    private static let space = AttributedString(" ")
    private static let cellSeparator = AttributedString(" | ")
    private static let thematicBreakString = AttributedString(String(repeating: "—", count: 20))

    /// Schemes considered safe to expose as tappable links. Markdown often comes
    /// from untrusted sources (LLM output, user input); anything else —
    /// javascript:, data:, file:, etc. — is rendered as plain text.
    private static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    /// Returns a URL only when the destination is safe to attach as a link.
    /// Scheme-less (relative) destinations are allowed.
    static func safeLinkURL(_ destination: String) -> URL? {
        guard let url = URL(string: destination) else { return nil }
        guard let scheme = url.scheme else { return url }
        return allowedLinkSchemes.contains(scheme.lowercased()) ? url : nil
    }

    public init() {}

    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        var result = AttributedString()
        let blocks = document.blocks
        let blockCount = blocks.count
        let blockSpacing = style.blockSpacing

        let separator = blockSpacing > 1
            ? AttributedString(String(repeating: "\n", count: blockSpacing))
            : Self.newline
        for index in blocks.indices {
            result.append(renderBlock(blocks[index], source: document.sourceData, style: style, indentLevel: 0))
            if index < blockCount - 1 {
                result.append(separator)
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
        return renderInlineSpans(spans, source: source, style: style, fontOverride: font)
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
            return Self.thematicBreakString
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
        var result = indentLevel > 0
            ? AttributedString(String(repeating: " ", count: indentLevel))
            : AttributedString()
        for span in spans {
            result.append(renderSpan(span, source: source, style: style, fontOverride: fontOverride))
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
            if let destination, let url = Self.safeLinkURL(destination.string(in: source)) {
                attributed.link = url
            }
            return attributed
        case .image(let alt, _, _):
            return renderInline(alt, source: source, style: style, fontOverride: fontOverride)
        case .lineBreak:
            return Self.newline
        case .softBreak:
            return Self.space
        case .html(let content):
            return applyBaseAttributes(AttributedString(content.string(in: source)), font: fontOverride, color: style.textColor)
        case .wikiLink(let target, let children):
            var attributed = renderInline(children, source: source, style: style, fontOverride: fontOverride)
            attributed.foregroundColor = style.linkColor
            if let url = Self.safeLinkURL(target.string(in: source)) {
                attributed.link = url
            }
            return attributed
        case .latexInline(let content), .latexDisplay(let content):
            return applyBaseAttributes(AttributedString(content.string(in: source)), font: style.codeFont, color: style.codeTextColor)
        }
    }

    @inline(__always)
    private func renderInlineSpans(
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
        var content = applyBaseAttributes(AttributedString(codeBlock.content.string(in: source)), font: style.codeFont, color: style.codeTextColor)
        content.backgroundColor = style.codeBackgroundColor
        if indentLevel > 0 {
            var result = AttributedString(String(repeating: " ", count: indentLevel))
            result.append(content)
            return result
        }
        return content
    }

    @inline(__always)
    private func renderBlockQuote(_ quote: BlockQuoteBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let prefix = AttributedString(String(repeating: " ", count: indentLevel) + "› ")
        var result = AttributedString()
        let blocks = quote.blocks
        let count = blocks.count
        for index in blocks.indices {
            result.append(prefix)
            result.append(renderBlock(blocks[index], source: source, style: style, indentLevel: indentLevel + style.listIndent))
            if index < count - 1 {
                result.append(Self.newline)
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

        let prefix = AttributedString(String(repeating: " ", count: indentLevel))
        for index in items.indices {
            let marker = ordered ? "\(start + index). " : "• "
            result.append(prefix)
            result.append(AttributedString(marker))
            let blocks = items[index].blocks
            let blockCount = blocks.count
            for blockIndex in blocks.indices {
                result.append(renderBlock(blocks[blockIndex], source: source, style: style, indentLevel: indentLevel + style.listIndent))
                if blockIndex < blockCount - 1 {
                    result.append(Self.newline)
                }
            }
            if index < count - 1 {
                result.append(Self.newline)
            }
        }
        return result
    }

    @inline(__always)
    private func renderTable(_ table: TableBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let rows = table.headerRows + table.bodyRows
        guard !rows.isEmpty else { return AttributedString() }
        let prefix = AttributedString(String(repeating: " ", count: indentLevel))
        var result = AttributedString()
        let rowCount = rows.count
        for index in rows.indices {
            let cells = rows[index].cells
            let cellCount = cells.count
            result.append(prefix)
            for cellIndex in cells.indices {
                result.append(renderSpans(cells[cellIndex].spans, source: source, style: style, fontOverride: style.baseFont, indentLevel: 0))
                if cellIndex < cellCount - 1 {
                    result.append(Self.cellSeparator)
                }
            }
            if index < rowCount - 1 {
                result.append(Self.newline)
            }
        }
        return result
    }

    @inline(__always)
    private func renderHTML(_ html: HTMLBlock, source: Data, style: MarkdownStyle, indentLevel: Int) -> AttributedString {
        let content = applyBaseAttributes(AttributedString(html.content.string(in: source)), font: style.baseFont, color: style.textColor)
        if indentLevel > 0 {
            var result = AttributedString(String(repeating: " ", count: indentLevel))
            result.append(content)
            return result
        }
        return content
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
