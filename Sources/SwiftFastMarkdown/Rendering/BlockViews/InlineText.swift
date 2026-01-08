import SwiftUI

struct InlineText: View {
    let spans: [MarkdownSpan]
    let source: Data
    let style: MarkdownStyle
    let fontOverride: Font

    // Shared renderer instance - AttributedStringRenderer is stateless,
    // so a single static instance avoids allocation on every view creation.
    private static let sharedRenderer = AttributedStringRenderer()

    var body: some View {
        let attributed = Self.sharedRenderer.renderInline(spans, source: source, style: style, fontOverride: fontOverride)
        Text(attributed)
            .foregroundStyle(style.textColor)
    }
}
