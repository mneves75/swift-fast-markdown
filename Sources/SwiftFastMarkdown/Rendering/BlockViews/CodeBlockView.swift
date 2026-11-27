import SwiftUI

struct CodeBlockView: View {
    struct HighlightTaskKey: Hashable {
        let blockID: BlockID
        let language: String?
        let code: String
    }

    let block: CodeBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting
    var depth: Int = 0

    @State private var highlighted: AttributedString?
    @State private var highlightedKey: HighlightTaskKey?
    @State private var isHighlighting = false

    private var currentKey: HighlightTaskKey {
        HighlightTaskKey(
            blockID: block.id,
            language: block.language?.string(in: source),
            code: block.content.string(in: source)
        )
    }

    var body: some View {
        let key = currentKey
        let scrollContent = ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 8) {
                codeContent(for: key)
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

        Group {
            if depth <= 4 {
                scrollContent.liquidGlassSurface(cornerRadius: 12)
            } else {
                scrollContent
            }
        }
        .task(id: key) {
            guard !key.code.isEmpty else {
                highlighted = AttributedString()
                highlightedKey = key
                isHighlighting = false
                return
            }
            if highlightedKey != key {
                highlighted = nil
            }
            isHighlighting = true
            let result = await highlighter.highlight(code: key.code, language: key.language)
            guard !Task.isCancelled else {
                isHighlighting = false
                return
            }
            highlighted = result
            highlightedKey = key
            isHighlighting = false
        }
    }

    @ViewBuilder
    private func codeContent(for key: HighlightTaskKey) -> some View {
        if let highlighted, highlightedKey == key {
            Text(highlighted)
                .font(style.codeFont)
                .foregroundStyle(style.codeTextColor)
        } else {
            Text(key.code)
                .font(style.codeFont)
                .foregroundStyle(style.codeTextColor)
        }
    }
}
