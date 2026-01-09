import SwiftUI

/// A lightweight markdown text view that renders to `AttributedString`.
///
/// This view is simpler than `MarkdownView` and renders everything as a single
/// `Text` view. It's suitable for short markdown content where you don't need
/// rich block-level features like scrollable code blocks or interactive task lists.
public struct FastMarkdownText: View {
    private let document: MarkdownDocument
    private let style: MarkdownStyle
    private let renderer: AttributedStringRenderer

    @State private var attributed: AttributedString

    public init(document: MarkdownDocument, style: MarkdownStyle = .default, renderer: AttributedStringRenderer = AttributedStringRenderer()) {
        self.document = document
        self.style = style
        self.renderer = renderer
        _attributed = State(initialValue: AttributedString())
    }

    public var body: some View {
        Text(attributed)
            .task(id: document.id) {
                attributed = renderer.render(document, style: style)
            }
    }
}

// MARK: - Preview

@available(iOS 18, macOS 15, *)
#Preview("FastMarkdownText") {
    let sampleMarkdown = "Hello **world**! This is *italic* and `inline code`."

    if let doc = try? MarkdownParser().parse(sampleMarkdown) {
        FastMarkdownText(document: doc)
            .padding()
    }
}
