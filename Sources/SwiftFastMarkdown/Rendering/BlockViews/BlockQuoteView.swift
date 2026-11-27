import SwiftUI

struct BlockQuoteView: View {
    let block: BlockQuoteBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting
    let onToggleTask: ((ListItemBlock, Bool) -> Void)?
    var depth: Int = 1

    var body: some View {
        let content = HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(style.quoteStripeColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: CGFloat(style.blockSpacing) * 2.0) {
                ForEach(block.blocks) { child in
                    BlockContentView(
                        block: child,
                        source: source,
                        style: style,
                        highlighter: highlighter,
                        onToggleTask: onToggleTask,
                        depth: depth
                    )
                }
            }
        }
        .padding(12)

        if depth <= 4 {
            content.liquidGlassSurface(cornerRadius: 12)
        } else {
            content
        }
    }
}
