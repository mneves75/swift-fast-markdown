import SwiftUI

/// A SwiftUI view that renders a parsed markdown document.
///
/// Use `MarkdownParser` to parse markdown content into a `MarkdownDocument`,
/// then pass it to this view for rich rendering with syntax highlighting.
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

// MARK: - Preview

@available(iOS 18, macOS 15, *)
#Preview("MarkdownView") {
    let sampleMarkdown = """
    # Welcome to SwiftFastMarkdown

    A **high-performance** markdown renderer for SwiftUI.

    ## Features

    - Zero-copy parsing with ByteRange IR
    - Syntax highlighting for code blocks
    - iOS 26 Liquid Glass effects

    ```swift
    let parser = MarkdownParser()
    let doc = try parser.parse(markdown)
    ```

    > Quote: *Clarity over cleverness*
    """

    if let doc = try? MarkdownParser().parse(sampleMarkdown) {
        ScrollView {
            MarkdownView(document: doc)
                .padding()
        }
    }
}
