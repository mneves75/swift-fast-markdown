import SwiftUI

struct BlockContentView: View {
    static let maxNestingDepth = 32

    let block: MarkdownBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting
    let onToggleTask: ((ListItemBlock, Bool) -> Void)?
    var depth: Int = 0

    var body: some View {
        if depth >= Self.maxNestingDepth {
            Text(AttributedStringRenderer().render(MarkdownDocument(blocks: [block], sourceData: source), style: style))
        } else {
            switch block {
            case .paragraph(let paragraph):
                InlineText(spans: paragraph.spans, source: source, style: style, fontOverride: style.baseFont)
            case .heading(let heading):
                HeadingView(block: heading, source: source, style: style)
            case .codeBlock(let codeBlock):
                CodeBlockView(block: codeBlock, source: source, style: style, highlighter: highlighter, depth: depth)
            case .blockQuote(let quote):
                BlockQuoteView(block: quote, source: source, style: style, highlighter: highlighter, onToggleTask: onToggleTask, depth: depth + 1)
            case .list(let list):
                ListView(block: list, source: source, style: style, highlighter: highlighter, onToggleTask: onToggleTask, depth: depth + 1)
            case .table(let table):
                TableView(block: table, source: source, style: style, depth: depth)
            case .thematicBreak:
                Divider()
            case .htmlBlock(let html):
                InlineText(spans: [.text(html.content)], source: source, style: style, fontOverride: style.baseFont)
            }
        }
    }
}
