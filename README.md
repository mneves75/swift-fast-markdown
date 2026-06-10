# SwiftFastMarkdown

A high-performance, SwiftUI-native markdown parser and renderer for iOS 18+ and macOS 15+.

Built with [Carmack-level rigor](https://www.youtube.com/watch?v=I845O57ZSy4): measurable claims, testable contracts, no magic.

## Features

- **Blazing Fast**: md4c-based parser achieves sub-millisecond parsing for typical documents
- **Zero-Copy IR**: ByteRange references into source data minimize allocations
- **SwiftUI Native**: First-class SwiftUI views with stable identity for efficient diffing
- **Streaming Support**: Incremental O(n) parser for real-time AI chat interfaces
- **Render Caching**: CachedAttributedStringRenderer for near-instant repeated renders
- **GFM Extensions**: Tables, task lists, strikethrough, autolinks via md4c flags
- **Syntax Highlighting**: Pluggable protocol with thread-safe highlight.js implementation
- **iOS 26 Liquid Glass**: Native glass effects with iOS 18 material fallback
- **Safe by default**: link schemes validated, no unsafe build flags
- **114 Tests**: Comprehensive test coverage including CommonMark spec compliance

## Performance

Built with SwiftPM's default release optimizations (`-O` for Swift, `-O2` for
C) — **no `.unsafeFlags`**, so the package is consumable as a remote SwiftPM
dependency and keeps bounds/overflow checks for untrusted input.

| Operation | Median | p95 | Target (median) | Status |
|-----------|-------:|----:|-----------------|--------|
| Parse ~1KB | 0.004 ms | 0.005 ms | — | — |
| Parse ~10KB | 0.215 ms | 0.238 ms | < 1 ms | ✅ 4.7× better |
| Parse ~50KB | 1.19 ms | 1.27 ms | — | — |
| Render ~10KB → AttributedString | 3.30 ms | 3.53 ms | < 5 ms | ✅ 34% headroom |
| Render ~50KB → AttributedString | 11.4 ms | 12.2 ms | — | — |
| Streaming chunk append (256 B) | 0.009 ms | 0.014 ms | < 0.5 ms | ✅ 55× better |

100 iterations + 10 warmup per operation, quietest of 3 release runs on Apple
Silicon (M4 Pro). Reproduce with:

```bash
swift run -c release SwiftFastMarkdownBenchmarks
```

Render time scales with document size and `AttributedString` allocation, and its
tail is sensitive to system memory pressure — for large or live content prefer
the incremental/streaming path (`StreamingMarkdownView`), whose per-chunk append
stays in the single-digit microseconds.

**Build Command:**
```bash
swift build -c release
```

### Why no unsafe flags

Earlier releases applied `-Ounchecked`, `-disable-actor-data-race-checks`,
`-O3` and `-ffast-math`. These were removed in 1.2.0 because:

- `.unsafeFlags` makes a package **impossible to consume** as a remote SwiftPM
  dependency (SwiftPM refuses to resolve it).
- `-Ounchecked` disables bounds and overflow traps — unacceptable for a parser
  whose input is frequently untrusted (LLM output, user text).
- Benchmarks show all v1.0 targets still pass on SwiftPM's default release
  optimization, so the safety trade was buying almost nothing.

### Where the speed comes from

| Technique | Impact |
|-----------|--------|
| Zero-copy `ByteRange` IR | Minimal allocation during parse |
| Cached static `AttributedString` constants | No per-line-break allocations |
| O(n) incremental parser | Sub-millisecond chunk appends |
| `CachedAttributedStringRenderer` | Near-instant repeated renders |

## Quick Start

```swift
import SwiftFastMarkdown

// Simple rendering
let document = MarkdownParser.parse("# Hello **World**")
MarkdownView(document: document)

// Streaming for AI chat
StreamingMarkdownView(content: $streamingContent, isStreaming: true)

// Cached rendering for repeated renders (SwiftUI previews, etc.)
let cachedRenderer = CachedAttributedStringRenderer()
let attributed = await cachedRenderer.render(document, style: .default)
```

See [HOWTO.md](HOWTO.md) for comprehensive usage guide.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mneves75/swift-fast-markdown.git", from: "1.2.0")
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
│                   SwiftFastMarkdown v1.2.0                  │
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
- `IncrementalMarkdownParser` - Internal locking via NSLock, single-snapshot reads
- `HighlightrEngine` - Actor isolating the non-Sendable Highlightr/JavaScriptCore engine
- `LRUCache` - Wrapped in actor for thread-safe access

## Security

Markdown is frequently untrusted (LLM output, user-submitted text), so the
renderer treats it that way:

- **Link schemes are validated.** Only `http`, `https`, `mailto`, `tel`, and
  relative (scheme-less) destinations become tappable links. `javascript:`,
  `data:`, `file:`, etc. render as plain text.
- **No unsafe build flags**, so bounds and overflow checks stay enabled in the
  parser's hot paths.

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 26.0+

## Documentation

- [HOWTO.md](HOWTO.md) - Comprehensive usage guide with examples
- [CHANGELOG.md](CHANGELOG.md) - Version history and release notes

## Acknowledgments

Special thanks to [Thomas Ricouard (@Dimillian)](https://x.com/Dimillian) for his excellent [Swift/SwiftUI Skills](https://github.com/Dimillian/Skills) that helped ensure this library follows best practices for SwiftUI performance, Liquid Glass implementation, Swift concurrency, and UI patterns.

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
