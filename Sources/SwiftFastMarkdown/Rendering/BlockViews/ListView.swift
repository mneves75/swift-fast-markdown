import SwiftUI

struct ListView: View {
    let block: ListBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting
    let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(style.blockSpacing)) {
            ForEach(Array(block.items.enumerated()), id: \ .element.id) { index, item in
                ListItemView(
                    index: index,
                    list: block,
                    item: item,
                    source: source,
                    style: style,
                    highlighter: highlighter,
                    onToggleTask: onToggleTask
                )
            }
        }
    }
}

struct ListItemView: View {
    let index: Int
    let list: ListBlock
    let item: ListItemBlock
    let source: Data
    let style: MarkdownStyle
    let highlighter: any SyntaxHighlighting
    let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if item.isTask {
                Button {
                    onToggleTask?(item, !item.isChecked)
                } label: {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isChecked ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(listMarker)
                    .font(style.baseFont)
                    .foregroundStyle(style.textColor)
            }

            VStack(alignment: .leading, spacing: CGFloat(style.blockSpacing)) {
                ForEach(item.blocks) { block in
                    BlockContentView(
                        block: block,
                        source: source,
                        style: style,
                        highlighter: highlighter,
                        onToggleTask: onToggleTask
                    )
                }
            }
        }
        .padding(.leading, CGFloat(style.listIndent) * 4.0)
    }

    private var listMarker: String {
        if list.ordered {
            return "\(list.start + index)."
        }
        return "•"
    }
}
