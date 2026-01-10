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

**Swift 6 Optimization Flags Applied:**
- `-Ounchecked`: Removes runtime safety checks (overflow, array bounds)
- `-disable-actor-data-race-checks`: Disables concurrency runtime overhead

| Metric | Result | Target | Status |
|--------|--------|--------|--------|
| Parse 10KB | 0.196ms | <1ms | ✅ 5.1x better |
| Render 10KB | 3.727ms | <5ms | ✅ 25% headroom |
| Chunk parse | 0.008ms | <0.5ms | ✅ 62x better |

**Build Command:**
```bash
swift build -c release
```

### Future Optimizations (Investigated)

| Optimization | Effort | Expected Impact | Notes |
|--------------|--------|-----------------|-------|
| SIMD/Vectorization | Medium | 5-15% | `-backend-option -vectorize-stmts` for C parser |
| LTO (Link-Time Optimization) | Low | 2-5% | `-enable-lto` for cross-module optimization |
| Profile-Guided Optimization (PGO) | High | 10-20% | Requires instrumented builds, real workloads |
| Swift 6 Embedded Mode | Low | 0% speed | Reduces binary size only |
| CoreText Bypass | High | 20-30% | Sacrifices SwiftUI AttributedString compatibility |

The **Render 10KB** metric is limited by Apple's `AttributedString` framework internals. Real gains require caching strategies or lower-level CoreText rendering.

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
