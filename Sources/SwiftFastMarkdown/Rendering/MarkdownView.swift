import SwiftUI

public struct MarkdownView: View {
    private let document: MarkdownDocument
    private let style: MarkdownStyle
    private let highlighter: any SyntaxHighlighting
    private let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    public init(
        document: MarkdownDocument,
        style: MarkdownStyle = .default,
        highlighter: any SyntaxHighlighting = SyntaxHighlightingFactory.makeDefault(),
        onToggleTask: ((ListItemBlock, Bool) -> Void)? = nil
    ) {
        self.document = document
        self.style = style
        self.highlighter = highlighter
        self.onToggleTask = onToggleTask
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: CGFloat(style.blockSpacing) * 4.0) {
            ForEach(document.blocks) { block in
                BlockContentView(
                    block: block,
                    source: document.sourceData,
                    style: style,
                    highlighter: highlighter,
                    onToggleTask: onToggleTask
                )
            }
        }
    }
}
