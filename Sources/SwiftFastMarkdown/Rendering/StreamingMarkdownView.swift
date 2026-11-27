import SwiftUI
import Darwin

/// A SwiftUI view that renders streaming markdown content in real-time.
///
/// This view is optimized for AI chat interfaces where content arrives incrementally.
/// It uses `IncrementalMarkdownParser` to efficiently parse only new content and
/// leverages stable block IDs for minimal view updates.
@MainActor
public struct StreamingMarkdownView: View {
    @Binding private var content: String
    private let style: MarkdownStyle
    private let highlighter: any SyntaxHighlighting
    private let isStreaming: Bool
    private let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    @State private var parser = IncrementalMarkdownParser()
    @State private var document = MarkdownDocument(blocks: [], sourceData: Data())
    @State private var initialized = false

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
    }

    public var body: some View {
        wrappedContentStack
            .onAppear {
                if !initialized {
                    initialized = true
                    if !content.isEmpty {
                        document = parser.append(content)
                        if !isStreaming {
                            document = parser.finalize()
                        }
                    }
                }
            }
            .onChange(of: content) { oldValue, newValue in
                initialized = true
                updateDocument(from: oldValue, to: newValue)
            }
            .onChange(of: isStreaming) { _, streaming in
                if !streaming && initialized {
                    document = parser.finalize()
                }
            }
    }

    /// Wraps contentStack in GlassEffectContainer on iOS 26+ for proper glass blending
    /// between code blocks, block quotes, and tables with glass surfaces.
    @ViewBuilder
    private var wrappedContentStack: some View {
        if #available(iOS 26, macOS 26, *) {
            SwiftUI.GlassEffectContainer(spacing: CGFloat(style.blockSpacing) * 4.0) {
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
    }

    private func updateDocument(from oldValue: String, to newValue: String) {
        if newValue.isEmpty {
            parser.reset()
            document = MarkdownDocument(blocks: [], sourceData: Data())
        } else if let suffix = Self.fastUTF8Suffix(of: newValue, afterPrefix: oldValue) {
            // Fast incremental append via SIMD memcmp + O(1) UTF-8 byte index
            // instead of O(n) Unicode-normalized String.hasPrefix + dropFirst.
            document = parser.append(suffix)
        } else {
            // Content changed non-incrementally - full reparse
            parser.reset()
            document = parser.append(newValue)
        }

        if !isStreaming {
            document = parser.finalize()
        }
    }

    /// Checks whether `newValue` starts with the exact UTF-8 bytes of `oldValue`
    /// using `memcmp`, and if so returns the appended suffix in O(1) index time.
    internal static func fastUTF8Suffix(of newValue: String, afterPrefix oldValue: String) -> String? {
        guard !oldValue.isEmpty else { return nil }
        let oldCount = oldValue.utf8.count
        let newCount = newValue.utf8.count
        guard newCount >= oldCount else { return nil }

        var oldCopy = oldValue
        var newCopy = newValue
        let matches: Bool = oldCopy.withUTF8 { oldBuf in
            newCopy.withUTF8 { newBuf in
                guard let oldPtr = oldBuf.baseAddress, let newPtr = newBuf.baseAddress else {
                    return oldBuf.isEmpty
                }
                return memcmp(oldPtr, newPtr, oldBuf.count) == 0
            }
        }
        guard matches else { return nil }
        let splitIndex = newValue.utf8.index(newValue.utf8.startIndex, offsetBy: oldCount)
        return String(newValue[splitIndex...])
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
///
/// Feeds incoming chunks directly into `IncrementalMarkdownParser` without
/// concatenating a growing full-document `String` or performing prefix diffs.
@MainActor
public struct AsyncStreamMarkdownView<S: AsyncSequence>: View where S.Element == String {
    private let stream: S
    private let style: MarkdownStyle
    private let highlighter: any SyntaxHighlighting
    private let onToggleTask: ((ListItemBlock, Bool) -> Void)?

    @State private var parser = IncrementalMarkdownParser()
    @State private var document = MarkdownDocument(blocks: [], sourceData: Data())
    @State private var isStreaming: Bool = true
    @State private var hasReceivedContent: Bool = false

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
        wrappedContentStack
            .task {
                do {
                    for try await chunk in stream {
                        if !chunk.isEmpty {
                            hasReceivedContent = true
                            document = parser.append(chunk)
                        }
                    }
                } catch {
                    // Stream ended or errored
                }
                document = parser.finalize()
                isStreaming = false
            }
    }

    @ViewBuilder
    private var wrappedContentStack: some View {
        if #available(iOS 26, macOS 26, *) {
            SwiftUI.GlassEffectContainer(spacing: CGFloat(style.blockSpacing) * 4.0) {
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

            if isStreaming && hasReceivedContent {
                StreamingIndicator()
            }
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
