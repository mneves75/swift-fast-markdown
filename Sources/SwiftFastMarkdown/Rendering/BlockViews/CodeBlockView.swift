import SwiftUI

struct CodeBlockView: View {
    let block: CodeBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting

    @State private var highlighted: AttributedString?
    @State private var isHighlighting = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 8) {
                codeContent
                    .padding(12)

                // Subtle loading indicator during async highlighting
                if isHighlighting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.top, 12)
                        .padding(.trailing, 8)
                        .transition(.opacity)
                }
            }
        }
        .liquidGlassSurface(cornerRadius: 12)
        .task(id: block.id) {
            isHighlighting = true
            let language = block.language?.string(in: source)
            highlighted = await highlighter.highlight(code: block.content.string(in: source), language: language)
            isHighlighting = false
        }
    }

    @ViewBuilder
    private var codeContent: some View {
        if let highlighted {
            Text(highlighted)
                .font(style.codeFont)
                .foregroundStyle(style.codeTextColor)
        } else {
            Text(block.content.string(in: source))
                .font(style.codeFont)
                .foregroundStyle(style.codeTextColor)
        }
    }
}
