import SwiftUI

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
