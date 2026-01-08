# SwiftFastMarkdown

A high-performance, SwiftUI-native markdown parser and renderer for iOS 18+ and macOS 15+.

Built with [Carmack-level rigor](https://www.youtube.com/watch?v=I845O57ZSy4): measurable claims, testable contracts, no magic.

## Features

- **Blazing Fast**: md4c-based parser achieves sub-millisecond parsing for typical documents
- **Zero-Copy IR**: ByteRange references into source data minimize allocations
- **SwiftUI Native**: First-class SwiftUI views with stable identity for efficient diffing
- **Streaming Support**: Incremental O(n) parser for real-time AI chat interfaces
- **GFM Extensions**: Tables, task lists, strikethrough, autolinks via md4c flags
- **Syntax Highlighting**: Pluggable protocol with thread-safe highlight.js implementation
- **iOS 26 Liquid Glass**: Native glass effects with iOS 18 material fallback
- **106 Tests**: Comprehensive test coverage including CommonMark spec compliance

## Performance

| Metric | Result | Target | Status |
|--------|--------|--------|--------|
| Parse 10KB | 0.249ms | <1ms | ✅ 4x better |
| Render 10KB | 3.699ms | <5ms | ✅ 26% headroom |
| Chunk parse | 0.009ms | <0.5ms | ✅ 55x better |

## Quick Start

```swift
import SwiftFastMarkdown

// Simple rendering
let document = MarkdownParser.parse("# Hello **World**")
MarkdownView(document: document)

// Streaming for AI chat
StreamingMarkdownView(content: $streamingContent, isStreaming: true)
```

See [HOWTO.md](HOWTO.md) for comprehensive usage guide.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mneves/swift-fast-markdown.git", from: "1.0.1")
]
```

## Core Components

| Component | Purpose |
|-----------|---------|
| `MarkdownParser` | Static document parsing |
| `IncrementalMarkdownParser` | Streaming/chunked parsing |
| `MarkdownView` | Rich SwiftUI rendering |
| `FastMarkdownText` | Lightweight AttributedString rendering |
| `StreamingMarkdownView` | Real-time streaming with binding |
| `AsyncStreamMarkdownView` | AsyncSequence-based streaming |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   SwiftFastMarkdown v1.0.1                  │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Rendering                                         │
│  ├── MarkdownView (rich, block-level views)                 │
│  ├── FastMarkdownText (AttributedString fast path)          │
│  ├── StreamingMarkdownView (real-time streaming)            │
│  └── Liquid Glass (iOS 26) / Material (iOS 18) fallback     │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: IR (Intermediate Representation)                  │
│  ├── MarkdownDocument (Sendable, Equatable)                 │
│  ├── MarkdownBlock (stable IDs for SwiftUI diffing)         │
│  └── ByteRange (zero-copy string extraction)                │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Parser                                            │
│  ├── md4c (CommonMark 0.31 + GFM extensions)                │
│  └── Push-model callbacks → Swift IR builder                │
└─────────────────────────────────────────────────────────────┘
```

## GFM Extensions

| Extension | Example | Status |
|-----------|---------|--------|
| Tables | `\| A \| B \|` | ✅ |
| Task Lists | `- [x] Done` | ✅ |
| Strikethrough | `~~deleted~~` | ✅ |
| Autolinks | `www.example.com` | ✅ |

## Thread Safety

All public APIs are thread-safe:

- `MarkdownParser` - Stateless, safe for concurrent use
- `IncrementalMarkdownParser` - Internal locking via NSLock
- `HighlighterSwiftEngine` - Actor with dedicated queue for JavaScriptCore thread-affinity
- `LRUCache` - Wrapped in actor for thread-safe access

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.0+
- Xcode 16.0+

## Documentation

- [HOWTO.md](HOWTO.md) - Comprehensive usage guide with examples
- [CHANGELOG.md](CHANGELOG.md) - Version history and release notes

## Acknowledgments

Special thanks to [Thomas Ricouard (@Dimillian)](https://x.com/Dimillian) for his excellent [Swift/SwiftUI Skills](https://github.com/Dimillian/Skills) that helped ensure this library follows best practices for SwiftUI performance, Liquid Glass implementation, Swift concurrency, and UI patterns.

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
