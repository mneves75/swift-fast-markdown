import SwiftUI

struct HeadingView: View {
    let block: HeadingBlock
    let source: Data
    let style: MarkdownStyle

    var body: some View {
        let index = max(0, min(block.level - 1, style.headingFonts.count - 1))
        let font = style.headingFonts[index]
        InlineText(spans: block.spans, source: source, style: style, fontOverride: font)
    }
}
