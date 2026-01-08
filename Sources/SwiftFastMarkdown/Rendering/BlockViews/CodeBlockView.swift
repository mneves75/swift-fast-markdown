import SwiftUI

struct CodeBlockView: View {
    let block: CodeBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting

    @State private var highlighted: AttributedString?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Group {
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
            .padding(12)
        }
        .liquidGlassSurface(cornerRadius: 12)
        .task(id: block.id) {
            let language = block.language?.string(in: source)
            highlighted = await highlighter.highlight(code: block.content.string(in: source), language: language)
        }
    }
}
