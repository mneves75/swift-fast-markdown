# SwiftFastMarkdown

A high-performance, SwiftUI-native markdown parser and renderer for iOS 18+ and macOS 15+.

## Features

- **Blazing Fast**: md4c-based parser achieves sub-millisecond parsing for typical documents
- **Zero-Copy IR**: ByteRange references into source data minimize allocations
- **SwiftUI Native**: First-class SwiftUI views with proper identity for efficient diffing
- **Streaming Support**: Incremental O(n) parser for real-time AI chat interfaces
- **GFM Extensions**: Tables, task lists, strikethrough, autolinks via md4c flags
- **Syntax Highlighting**: Pluggable protocol with highlight.js default implementation
- **iOS 26 Liquid Glass**: Native glass effects with iOS 18 material fallback

## Performance

| Metric | Result | Target |
|--------|--------|--------|
| Parse 10KB | 0.249ms | <1ms |
| Render 10KB | 3.699ms | <5ms |
| Chunk parse | 0.009ms | <0.5ms |

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mneves/swift-fast-markdown.git", from: "1.0.0")
]
```

## Usage

### Static Rendering

```swift
import SwiftFastMarkdown

let parser = MarkdownParser()
let document = try parser.parse("""
# Hello World

This is **bold** and *italic* text.
""")

// SwiftUI View
MarkdownView(document: document)

// Or AttributedString for Text
let renderer = AttributedStringRenderer()
Text(renderer.render(document))
```

### Streaming (AI Chat)

```swift
let parser = IncrementalMarkdownParser()

// As tokens arrive from LLM
for chunk in tokenStream {
    let document = parser.append(chunk)
    // UI updates automatically with stable block IDs
}

let finalDocument = parser.finalize()
```

### Custom Styling

```swift
let style = MarkdownStyle(
    baseFont: .body,
    headingFonts: [.largeTitle, .title, .title2, .title3, .headline, .subheadline],
    codeFont: .system(.body, design: .monospaced),
    textColor: .primary,
    linkColor: .accentColor
)

MarkdownView(document: document, style: style)
```

## GFM Extensions

SwiftFastMarkdown supports GitHub Flavored Markdown extensions:

```markdown
| Feature | Status |
|---------|--------|
| Tables | Supported |
| Task Lists | Supported |

- [x] Completed task
- [ ] Pending task

~~Strikethrough text~~
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     SwiftFastMarkdown                       │
├─────────────────────────────────────────────────────────────┤
│  Rendering: MarkdownView, AttributedStringRenderer          │
├─────────────────────────────────────────────────────────────┤
│  IR: MarkdownDocument, ByteRange, Stable BlockID            │
├─────────────────────────────────────────────────────────────┤
│  Parser: md4c (CommonMark 0.31 + GFM flags)                 │
└─────────────────────────────────────────────────────────────┘
```

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.0+
- Xcode 16.0+

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
