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
        // On iOS 26+, wrap in GlassEffectContainer for proper glass blending
        // between code blocks, block quotes, and tables with glass surfaces.
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: CGFloat(style.blockSpacing) * 4.0) {
                contentStack
            }
        } else {
            contentStack
        }
    }

    @ViewBuilder
    private var contentStack: some View {
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
