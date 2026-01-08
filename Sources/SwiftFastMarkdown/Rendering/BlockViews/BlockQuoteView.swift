import SwiftUI

struct BlockQuoteView: View {
    let block: BlockQuoteBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting
    let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                        onToggleTask: onToggleTask
                    )
                }
            }
        }
        .padding(12)
        .liquidGlassSurface(cornerRadius: 12)
    }
}
