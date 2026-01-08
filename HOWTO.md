# SwiftFastMarkdown HOWTO Guide

A comprehensive guide to using SwiftFastMarkdown in your iOS and macOS applications.

## Table of Contents

1. [Installation](#installation)
2. [Basic Usage](#basic-usage)
3. [Streaming for AI Chat](#streaming-for-ai-chat)
4. [Custom Styling](#custom-styling)
5. [Syntax Highlighting](#syntax-highlighting)
6. [Task List Interactivity](#task-list-interactivity)
7. [iOS 26 Liquid Glass](#ios-26-liquid-glass)
8. [Performance Optimization](#performance-optimization)
9. [Advanced Topics](#advanced-topics)

---

## Installation

### Swift Package Manager

Add SwiftFastMarkdown to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mneves/swift-fast-markdown.git", from: "1.0.1")
]
```

Or in Xcode: File → Add Package Dependencies → paste the URL.

### Target Configuration

```swift
.target(
    name: "YourApp",
    dependencies: ["SwiftFastMarkdown"]
)
```

---

## Basic Usage

### Parsing and Rendering Static Content

```swift
import SwiftUI
import SwiftFastMarkdown

struct ContentView: View {
    let markdown = """
    # Welcome to SwiftFastMarkdown

    This is **bold**, *italic*, and `inline code`.

    ## Features

    - Fast md4c-based parsing
    - SwiftUI native rendering
    - iOS 26 Liquid Glass support
    """

    var body: some View {
        ScrollView {
            MarkdownView(
                document: MarkdownParser.parse(markdown)
            )
            .padding()
        }
    }
}
```

### Using FastMarkdownText for Simple Content

For documents without code blocks, tables, or images, `FastMarkdownText` provides a lighter-weight alternative:

```swift
struct SimpleMarkdownView: View {
    let document: MarkdownDocument

    var body: some View {
        FastMarkdownText(document: document)
    }
}
```

### Rendering to AttributedString

For use with standard SwiftUI `Text` or UIKit:

```swift
let document = MarkdownParser.parse("Hello **World**")
let renderer = AttributedStringRenderer()
let attributed = renderer.render(document, style: .default)

// In SwiftUI
Text(attributed)

// In UIKit
let label = UILabel()
label.attributedText = NSAttributedString(attributed)
```

---

## Streaming for AI Chat

SwiftFastMarkdown excels at real-time rendering of streaming content from LLMs.

### Using StreamingMarkdownView with Binding

```swift
struct ChatView: View {
    @State private var responseContent = ""
    @State private var isStreaming = false

    var body: some View {
        VStack {
            ScrollView {
                StreamingMarkdownView(
                    content: $responseContent,
                    isStreaming: isStreaming
                )
                .padding()
            }

            Button("Send Message") {
                Task {
                    await sendMessage()
                }
            }
        }
    }

    func sendMessage() async {
        isStreaming = true
        responseContent = ""

        // Simulate streaming tokens
        for token in ["Hello", " ", "**", "World", "**", "!"] {
            responseContent += token
            try? await Task.sleep(for: .milliseconds(100))
        }

        isStreaming = false
    }
}
```

### Using AsyncStreamMarkdownView

For AsyncSequence-based streaming (e.g., from OpenAI, Anthropic APIs):

```swift
struct AsyncChatView: View {
    let tokenStream: AsyncStream<String>

    var body: some View {
        AsyncStreamMarkdownView(stream: tokenStream)
            .padding()
    }
}

// Creating the stream
func createTokenStream() -> AsyncStream<String> {
    AsyncStream { continuation in
        Task {
            for try await chunk in api.streamCompletion(prompt: "...") {
                continuation.yield(chunk.text)
            }
            continuation.finish()
        }
    }
}
```

### Manual Incremental Parsing

For complete control over the parsing process:

```swift
class ChatViewModel: ObservableObject {
    @Published var document: MarkdownDocument
    private let parser = IncrementalMarkdownParser()

    init() {
        self.document = MarkdownDocument(blocks: [], sourceData: Data())
    }

    func appendToken(_ token: String) {
        document = parser.append(token)
    }

    func finishStreaming() {
        document = parser.finalize()
    }

    func reset() {
        parser.reset()
        document = MarkdownDocument(blocks: [], sourceData: Data())
    }
}
```

---

## Custom Styling

### Creating a Custom Style

```swift
let customStyle = MarkdownStyle(
    // Typography
    baseFont: .body,
    headingFonts: [
        .system(size: 32, weight: .bold),    // H1
        .system(size: 28, weight: .bold),    // H2
        .system(size: 24, weight: .semibold), // H3
        .system(size: 20, weight: .semibold), // H4
        .system(size: 18, weight: .medium),   // H5
        .system(size: 16, weight: .medium)    // H6
    ],
    codeFont: .system(.body, design: .monospaced),

    // Colors
    textColor: .primary,
    linkColor: .blue,
    codeBackgroundColor: Color(.systemGray6),
    blockQuoteColor: .secondary,

    // Spacing
    blockSpacing: 4,        // Base unit (multiplied by 4 for actual spacing)
    listIndent: 6,          // Base unit for list indentation
    codeBlockPadding: 4     // Base unit for code block padding
)

// Apply to view
MarkdownView(document: document, style: customStyle)
```

### Dark Mode Adaptive Style

```swift
struct AdaptiveMarkdownView: View {
    @Environment(\.colorScheme) var colorScheme
    let document: MarkdownDocument

    var style: MarkdownStyle {
        MarkdownStyle(
            textColor: colorScheme == .dark ? .white : .black,
            linkColor: colorScheme == .dark ? .cyan : .blue,
            codeBackgroundColor: colorScheme == .dark
                ? Color(.systemGray5)
                : Color(.systemGray6)
        )
    }

    var body: some View {
        MarkdownView(document: document, style: style)
    }
}
```

---

## Syntax Highlighting

### Default Highlighter (highlight.js)

The default syntax highlighter uses highlight.js via the HighlighterSwift package:

```swift
// Uses default highlighter automatically
MarkdownView(document: document)

// Or explicitly create
let highlighter = SyntaxHighlightingFactory.makeDefault()
MarkdownView(document: document, highlighter: highlighter)
```

### Configuring the Highlighter

```swift
// Create with custom configuration
if let highlighter = HighlighterSwiftEngine(
    configuration: .init(
        theme: "github-dark",     // highlight.js theme name
        fontName: "SF Mono",      // Optional custom font
        fontSize: 14,             // Optional font size
        cacheSize: 256            // LRU cache capacity
    )
) {
    MarkdownView(document: document, highlighter: highlighter)
}
```

### Available Themes

Common highlight.js themes include:
- `default`, `github`, `github-dark`
- `monokai`, `dracula`, `nord`
- `xcode`, `vs`, `vs2015`
- `atom-one-dark`, `atom-one-light`

### Custom Highlighter Implementation

Implement the `SyntaxHighlighting` protocol for custom highlighting:

```swift
public actor CustomHighlighter: SyntaxHighlighting {
    public func highlight(
        code: String,
        language: String?
    ) async -> AttributedString {
        var result = AttributedString(code)
        result.font = .system(.body, design: .monospaced)

        // Add custom highlighting logic here
        // For example, simple keyword highlighting:
        if language == "swift" {
            // Highlight Swift keywords
            let keywords = ["func", "var", "let", "class", "struct"]
            for keyword in keywords {
                // Apply styling to keywords...
            }
        }

        return result
    }
}
```

### Plain Text Fallback

For maximum performance without highlighting:

```swift
let plainHighlighter = PlainTextHighlighter()
MarkdownView(document: document, highlighter: plainHighlighter)
```

---

## Task List Interactivity

Handle task list checkbox toggling:

```swift
struct TaskListView: View {
    @State private var markdown: String

    init(markdown: String) {
        self._markdown = State(initialValue: markdown)
    }

    var body: some View {
        StreamingMarkdownView(
            content: $markdown,
            isStreaming: false,
            onToggleTask: { item, isChecked in
                // Update the markdown source
                updateTaskItem(item, isChecked: isChecked)
            }
        )
    }

    private func updateTaskItem(_ item: ListItemBlock, isChecked: Bool) {
        // Replace [ ] with [x] or vice versa at the item's position
        let range = item.range
        let oldMarker = isChecked ? "[ ]" : "[x]"
        let newMarker = isChecked ? "[x]" : "[ ]"

        // Update markdown string
        if let textRange = Range(
            NSRange(location: Int(range.start), length: Int(range.length)),
            in: markdown
        ) {
            let itemText = String(markdown[textRange])
            let updated = itemText.replacingOccurrences(of: oldMarker, with: newMarker)
            markdown.replaceSubrange(textRange, with: updated)
        }
    }
}
```

---

## iOS 26 Liquid Glass

SwiftFastMarkdown automatically uses iOS 26 Liquid Glass effects when available.

### Automatic Behavior

- **iOS 26+**: Code blocks, block quotes, and tables use `.glassEffect(.regular)`
- **iOS 18-25**: Falls back to `.ultraThinMaterial` or `.regularMaterial`

### Custom Glass Configuration

```swift
// The LiquidGlassSurface view handles availability automatically
struct CustomCodeBlock: View {
    let code: String

    var body: some View {
        Text(code)
            .padding()
            .background {
                // Automatic iOS version handling
                if #available(iOS 26, macOS 26, *) {
                    RoundedRectangle(cornerRadius: 12)
                        .glassEffect(.regular)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                }
            }
    }
}
```

### GlassEffectContainer

For proper glass blending between multiple glass elements:

```swift
// Already handled in MarkdownView and StreamingMarkdownView
// on iOS 26+, content is wrapped in GlassEffectContainer
if #available(iOS 26, macOS 26, *) {
    GlassEffectContainer(spacing: 16) {
        // Multiple glass elements blend properly
        codeBlock1
        codeBlock2
        blockQuote
    }
}
```

---

## Performance Optimization

### Choosing the Right Component

| Use Case | Component | Notes |
|----------|-----------|-------|
| Static content, simple | `FastMarkdownText` | Fastest, AttributedString only |
| Static content, rich | `MarkdownView` | Full block rendering |
| Streaming content | `StreamingMarkdownView` | Binding-based updates |
| AsyncSequence streaming | `AsyncStreamMarkdownView` | For async APIs |
| Custom integration | `IncrementalMarkdownParser` | Manual control |

### Optimizing Streaming Performance

```swift
// Good: Let SwiftUI handle diffing with stable IDs
StreamingMarkdownView(content: $content, isStreaming: true)

// The parser generates stable block IDs based on:
// - Block type
// - Byte range in source
// - Ordinal position
// This enables efficient diffing even during rapid updates
```

### Memory Considerations

```swift
// For very large documents, consider pagination
struct PaginatedMarkdownView: View {
    let document: MarkdownDocument
    let pageSize = 50
    @State private var visibleBlocks = 50

    var body: some View {
        LazyVStack {
            ForEach(document.blocks.prefix(visibleBlocks)) { block in
                BlockContentView(block: block, ...)
            }

            if visibleBlocks < document.blocks.count {
                Button("Load More") {
                    visibleBlocks += pageSize
                }
            }
        }
    }
}
```

### Highlighter Cache

The syntax highlighter uses an LRU cache. Adjust cache size based on your use case:

```swift
// Larger cache for apps with many unique code snippets
let highlighter = HighlighterSwiftEngine(
    configuration: .init(cacheSize: 512)
)

// Smaller cache for memory-constrained environments
let highlighter = HighlighterSwiftEngine(
    configuration: .init(cacheSize: 64)
)
```

---

## Advanced Topics

### Direct IR Access

Access the parsed document structure directly:

```swift
let document = MarkdownParser.parse(markdown)

for block in document.blocks {
    switch block {
    case .heading(let heading):
        print("Heading level \(heading.level)")

    case .codeBlock(let code):
        let content = code.codeRange.string(in: document.sourceData)
        print("Code (\(code.language ?? "plain")): \(content)")

    case .list(let list):
        print("List with \(list.items.count) items")

    case .table(let table):
        print("Table: \(table.header.count) columns")

    default:
        break
    }
}
```

### ByteRange Usage

Extract text efficiently without copying:

```swift
let document = MarkdownParser.parse("Hello **World**")

// Get text from a span's byte range
if case .paragraph(let para) = document.blocks.first,
   case .strong(let strong) = para.spans.first(where: {
       if case .strong = $0 { return true }
       return false
   }) {
    // Zero-copy string extraction
    let text = strong.textRange.string(in: document.sourceData)
    print(text) // "World"
}
```

### Custom Block Rendering

Create custom views for specific block types:

```swift
struct CustomMarkdownView: View {
    let document: MarkdownDocument

    var body: some View {
        LazyVStack(alignment: .leading) {
            ForEach(document.blocks) { block in
                switch block {
                case .codeBlock(let code):
                    // Custom code block with copy button
                    CustomCodeBlockView(code: code, source: document.sourceData)

                case .table(let table):
                    // Custom table with sorting
                    SortableTableView(table: table, source: document.sourceData)

                default:
                    // Default rendering for other blocks
                    BlockContentView(
                        block: block,
                        source: document.sourceData,
                        style: .default,
                        highlighter: SyntaxHighlightingFactory.makeDefault()
                    )
                }
            }
        }
    }
}
```

### Thread Safety Notes

All public APIs are designed for concurrent use:

```swift
// Safe: Parsing on background thread
Task.detached {
    let document = MarkdownParser.parse(largeMarkdown)
    await MainActor.run {
        self.document = document
    }
}

// Safe: IncrementalMarkdownParser uses internal locking
let parser = IncrementalMarkdownParser()
Task.detached {
    for chunk in chunks {
        let doc = parser.append(chunk)
        await MainActor.run {
            self.document = doc
        }
    }
}

// Safe: Highlighter is an actor with thread-safe JSContext access
let highlighter = HighlighterSwiftEngine(configuration: .init())
Task {
    let highlighted = await highlighter?.highlight(code: code, language: "swift")
}
```

---

## Common Patterns

### Chat Message View

```swift
struct ChatMessageView: View {
    let message: ChatMessage
    @State private var content: String

    init(message: ChatMessage) {
        self.message = message
        self._content = State(initialValue: message.content)
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
            }

            StreamingMarkdownView(
                content: $content,
                style: messageStyle,
                isStreaming: message.isStreaming
            )

            if message.role == .user {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding()
    }

    var messageStyle: MarkdownStyle {
        MarkdownStyle(
            textColor: message.role == .user ? .primary : .secondary
        )
    }
}
```

### Documentation Viewer

```swift
struct DocViewer: View {
    let markdownURL: URL
    @State private var document: MarkdownDocument?
    @State private var error: Error?

    var body: some View {
        Group {
            if let document {
                ScrollView {
                    MarkdownView(document: document)
                        .padding()
                }
            } else if let error {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let content = try String(contentsOf: markdownURL)
                document = MarkdownParser.parse(content)
            } catch {
                self.error = error
            }
        }
    }
}
```

---

## Troubleshooting

### Common Issues

**Q: Code blocks aren't syntax highlighted**
A: Ensure you're using `MarkdownView` (not `FastMarkdownText`) and the language is specified in the fence (e.g., ` ```swift `).

**Q: Streaming updates are slow**
A: Check that you're not wrapping `StreamingMarkdownView` in unnecessary animation modifiers. The view handles animations internally.

**Q: Glass effects don't appear on iOS 26**
A: Verify you're running on iOS 26+ simulator or device. Glass effects require the Liquid Glass runtime.

**Q: Memory usage is high**
A: For very large documents, consider:
- Using `FastMarkdownText` for simpler content
- Implementing pagination
- Reducing highlighter cache size

---

## Need Help?

- [GitHub Issues](https://github.com/mneves/swift-fast-markdown/issues)
- [CHANGELOG.md](CHANGELOG.md) for version history
- [README.md](README.md) for quick reference
