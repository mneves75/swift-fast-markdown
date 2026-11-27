import SwiftUI

struct HeadingView: View {
    let block: HeadingBlock
    let source: Data
    let style: MarkdownStyle

    var body: some View {
        let font: Font
        if style.headingFonts.isEmpty {
            font = style.baseFont
        } else {
            let index = max(0, min(block.level - 1, style.headingFonts.count - 1))
            font = style.headingFonts[index]
        }
        return InlineText(spans: block.spans, source: source, style: style, fontOverride: font)
    }
}
