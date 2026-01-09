import SwiftUI

/// A SwiftUI view that renders streaming markdown content in real-time.
///
/// This view is optimized for AI chat interfaces where content arrives incrementally.
/// It uses `IncrementalMarkdownParser` to efficiently parse only new content and
/// leverages stable block IDs for minimal view updates.
///
/// ## Example Usage
///
/// ```swift
/// struct ChatView: View {
///     @State private var streamingContent = ""
///
///     var body: some View {
///         StreamingMarkdownView(
///             content: $streamingContent,
///             style: .default,
///             isStreaming: true
///         )
///     }
/// }
/// ```
@MainActor
public struct StreamingMarkdownView: View {
    @Binding private var content: String
    private let style: MarkdownStyle
    private let highlighter: any SyntaxHighlighting
    private let isStreaming: Bool
    private let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    @State private var parser: IncrementalMarkdownParser
    @State private var document: MarkdownDocument
    /// Tracks the last processed content to avoid redundant reparsing.
    /// Note: Using direct string comparison instead of hashValue to prevent
    /// hash collisions from causing missed updates.
    @State private var lastProcessedContent: String = ""

    public init(
        content: Binding<String>,
        style: MarkdownStyle = .default,
        highlighter: any SyntaxHighlighting = SyntaxHighlightingFactory.makeDefault(),
        isStreaming: Bool = true,
        onToggleTask: ((ListItemBlock, Bool) -> Void)? = nil
    ) {
        self._content = content
        self.style = style
        self.highlighter = highlighter
        self.isStreaming = isStreaming
        self.onToggleTask = onToggleTask

        let initialParser = IncrementalMarkdownParser()
        let initialDoc = initialParser.append(content.wrappedValue)
        self._parser = State(initialValue: initialParser)
        self._document = State(initialValue: initialDoc)
    }

    public var body: some View {
        wrappedContentStack
            .onChange(of: content) { oldValue, newValue in
                updateDocument(from: oldValue, to: newValue)
            }
    }

    /// Wraps contentStack in GlassEffectContainer on iOS 26+ for proper glass blending
    /// between code blocks, block quotes, and tables with glass surfaces.
    @ViewBuilder
    private var wrappedContentStack: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: CGFloat(style.blockSpacing) * 4.0) {
                contentStack
            }
        } else {
            contentStack
        }
    }

    @ViewBuilder
    private var contentStack: some View {
        LazyVStack(alignment: .leading, spacing: CGFloat(style.blockSpacing) * 4.0) {
            ForEach(document.blocks) { block in
                BlockContentView(
                    block: block,
                    source: document.sourceData,
                    style: style,
                    highlighter: highlighter,
                    onToggleTask: onToggleTask
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Show streaming indicator for incomplete content
            if isStreaming && !content.isEmpty {
                StreamingIndicator()
            }
        }
        // Note: Intentionally no global .animation() modifier here.
        // Global animation on LazyVStack causes layout recalculation on every
        // block change during streaming, leading to frame drops. Individual
        // blocks use .transition() for enter/exit animations which is more
        // efficient and doesn't affect sibling blocks.
    }

    private func updateDocument(from oldValue: String, to newValue: String) {
        // Direct string comparison prevents hash collision edge cases where
        // different content could produce the same hashValue, causing missed updates.
        guard newValue != lastProcessedContent else { return }
        lastProcessedContent = newValue

        if newValue.isEmpty {
            // Content cleared - reset parser
            parser.reset()
            document = MarkdownDocument(blocks: [], sourceData: Data())
        } else if newValue.hasPrefix(oldValue) && !oldValue.isEmpty {
            // Content appended - incremental update
            let appendedContent = String(newValue.dropFirst(oldValue.count))
            document = parser.append(appendedContent)
        } else {
            // Content changed non-incrementally - full reparse
            parser.reset()
            document = parser.append(newValue)
        }

        // Finalize if not streaming
        if !isStreaming {
            document = parser.finalize()
        }
    }
}

// MARK: - Streaming Indicator

private struct StreamingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding(.leading, 4)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Convenience Initializers

extension StreamingMarkdownView {
    /// Creates a streaming view from static content (non-streaming mode).
    public init(
        staticContent: String,
        style: MarkdownStyle = .default,
        highlighter: any SyntaxHighlighting = SyntaxHighlightingFactory.makeDefault(),
        onToggleTask: ((ListItemBlock, Bool) -> Void)? = nil
    ) {
        self.init(
            content: .constant(staticContent),
            style: style,
            highlighter: highlighter,
            isStreaming: false,
            onToggleTask: onToggleTask
        )
    }
}

// MARK: - AsyncStream Support

/// A view that renders markdown from an AsyncStream of content chunks.
@MainActor
public struct AsyncStreamMarkdownView<S: AsyncSequence>: View where S.Element == String {
    private let stream: S
    private let style: MarkdownStyle
    private let highlighter: any SyntaxHighlighting
    private let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    @State private var content: String = ""
    @State private var isStreaming: Bool = true

    public init(
        stream: S,
        style: MarkdownStyle = .default,
        highlighter: any SyntaxHighlighting = SyntaxHighlightingFactory.makeDefault(),
        onToggleTask: ((ListItemBlock, Bool) -> Void)? = nil
    ) {
        self.stream = stream
        self.style = style
        self.highlighter = highlighter
        self.onToggleTask = onToggleTask
    }

    public var body: some View {
        StreamingMarkdownView(
            content: $content,
            style: style,
            highlighter: highlighter,
            isStreaming: isStreaming,
            onToggleTask: onToggleTask
        )
        .task {
            do {
                for try await chunk in stream {
                    content += chunk
                }
            } catch {
                // Stream ended or errored
            }
            isStreaming = false
        }
    }
}

// MARK: - Previews

@available(iOS 18, macOS 15, *)
#Preview("StreamingMarkdownView") {
    @Previewable @State var content = """
    # Streaming Demo

    This demonstrates **real-time** markdown rendering.

    ```swift
    let view = StreamingMarkdownView(content: $content)
    ```

    > Perfect for AI chat interfaces!
    """

    ScrollView {
        StreamingMarkdownView(content: $content, isStreaming: false)
            .padding()
    }
}

@available(iOS 18, macOS 15, *)
#Preview("StreamingMarkdownView - Static") {
    ScrollView {
        StreamingMarkdownView(
            staticContent: "Hello **world**! This uses the static initializer."
        )
        .padding()
    }
}
