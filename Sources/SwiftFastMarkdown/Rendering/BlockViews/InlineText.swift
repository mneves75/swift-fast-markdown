import SwiftUI

struct InlineText: View {
    let spans: [MarkdownSpan]
    let source: Data
    let style: MarkdownStyle
    let fontOverride: Font

    private let renderer = AttributedStringRenderer()

    var body: some View {
        let attributed = renderer.renderInline(spans, source: source, style: style, fontOverride: fontOverride)
        Text(attributed)
            .foregroundStyle(style.textColor)
    }
}
