# SwiftFastMarkdown

A high-performance, SwiftUI-native markdown parser and renderer for iOS 18+ and macOS 15+.

Built with [Carmack-level rigor](https://www.youtube.com/watch?v=I845O57ZSy4): measurable claims, testable contracts, no magic.

## Features

- **Blazing Fast**: md4c-based parser achieves sub-millisecond parsing for typical documents
- **Zero-Copy IR**: ByteRange references into source data minimize allocations
- **SwiftUI Native**: First-class SwiftUI views with stable identity for efficient diffing
- **Streaming Support**: Incremental single-buffer parser that stabilizes completed top-level prefixes at blank-line boundaries before newline-terminated paragraphs, headings, block quotes, and tables (linear amortized parsing on typical multi-block streams; retaining prior `MarkdownDocument` snapshots across appends uses Swift Copy-on-Write)
- **Render Caching**: CachedAttributedStringRenderer for near-instant repeated renders
- **GFM Extensions**: Tables, task lists, strikethrough, autolinks via md4c flags
- **Syntax Highlighting**: Pluggable protocol with thread-safe highlight.js implementation
- **iOS 26 Liquid Glass**: Native glass effects with iOS 18 material fallback
- **Safe by default**: strict link validation (`safeLinkURL`), AST depth/size caps, per-slice UTF-8 sanitization, NUL entity sanitization, bounded Highlightr pool, no unsafe build flags
- **118 Tests**: Comprehensive test coverage including CommonMark/GFM spec compliance, streaming CoW immutability, and security regression tests

## Performance

Built with SwiftPM's default release optimizations (`-O` for Swift, `-O2` for
C) — **no `.unsafeFlags`**, so the package is consumable as a remote SwiftPM
dependency and keeps bounds/overflow checks for untrusted input.

| Operation | Median | p95 | Target (median) | Status |
|-----------|-------:|----:|-----------------|--------|
| Parse ~1KB (178 B) | 0.005 ms | 0.006 ms | — | — |
| Parse ~10KB (10,232 B) | 0.138 ms | 0.481 ms | < 1 ms | ✅ 7.2× better |
| Parse large (77.6 KB / 77,644 B) | 0.309 ms | 4.160 ms | — | — |
| Parse entity-heavy (11.2 KB) | 0.146 ms | 7.214 ms | — | — |
| Render ~10KB → AttributedString | 0.867 ms | 6.027 ms | < 5 ms | ✅ 5.8× better |
| Render large (77.6 KB) → AttributedString | 9.584 ms | 107.911 ms | — | 199 KB retained |
| RenderInline (50 paragraphs) | 0.446 ms | 5.021 ms | — | — |
| Streaming chunk append (256 B) | 0.008 ms | 0.010 ms | < 0.5 ms | ✅ 62× better |
| AI-token stream large (77.6 KB, 1,214 × 64 B) | 2.876 ms | 4.725 ms | — | 1.7 µs/token |
| `SyntaxHighlightingFactory.makeDefault()` | < 0.001 ms | < 0.001 ms | — | Bounded lazy pool |

100 iterations + 10 warmup per operation (50 for 77.6 KB render; 10 for 77.6 KB
token stream and `SyntaxHighlightingFactory.makeDefault()`), Apple Silicon
release build. Reproduce with:

```bash
swift run -c release SwiftFastMarkdownBenchmarks
```

Render time scales linearly with document size and `AttributedString` run count
via single-pass UTF-8 assembly and prebuilt style palettes — for live content
prefer the incremental/streaming path (`StreamingMarkdownView` /
`AsyncStreamMarkdownView`), whose per-token append runs in single-digit
microseconds.

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
- Benchmarks show all v1.0 targets pass with wide headroom on SwiftPM's default
  release optimization, so the safety trade was buying almost nothing.

### Where the speed comes from

| Technique | Impact |
|-----------|--------|
| Flat LIFO `ScratchStack` (`moveInitialize`) + contiguous `ByteRange` coalescing | 14.9× faster 77.6 KB parse, zero O(n²) array copies, zero ARC churn |
| Single-pass UTF-8 builder + prebuilt `StylePalette` + POD `RunPatch` | 12.3× faster 10KB render, 5× smaller retained `AttributedString` heap |
| Single-buffer `IncrementalMarkdownParser` + `md4c`-backed stabilization + in-place CoW `cachedBlocks` | 12.2× faster 77.6 KB AI-token streaming (1.7 µs/token) with `md4c` block-structure parity |
| Compact binary `HTMLEntities.bin` (28.7 KB vs 146 KB JSON) + zero-alloc fast path | 5.1× smaller resource, 5.3× faster entity-heavy parse |
| Lazy shared `HighlightrPool` + O(1) `LRUCache` in cached renderers | Zero main-thread JSContext stall on SwiftUI view init (16× lower process RAM) |

## Quick Start

```swift
import SwiftFastMarkdown

// Simple rendering
let document = try MarkdownParser().parse("# Hello **World**")
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
    .package(url: "https://github.com/mneves75/swift-fast-markdown.git", from: "1.3.0")
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
│                   SwiftFastMarkdown v1.3.0                  │
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
- `IncrementalMarkdownParser` - Internal locking via a single `NSLock` for all state reads and mutations
- `HighlightrEngine` - Actor isolating the non-Sendable Highlightr/JavaScriptCore engine
- `LRUCache` - Internal data structure synchronized via actor isolation (`CachedAttributedStringRenderer`, `HighlightrEngine`) and `NSLock` (`ThreadSafeCachedRenderer`)

## Security

Markdown is frequently untrusted (LLM output, user-submitted text), so the
parser and renderers enforce defense-in-depth by default:

- **Strict link validation (`AttributedStringRenderer.safeLinkURL`)**: only
  `http`/`https` (with non-empty host), `mailto`/`tel` (with non-empty body),
  and clean relative paths/fragments/queries become tappable links. Protocol-relative
  `//host`, whitespace/control-obfuscated schemes, RFC 3986 §4.2 first-segment
  colons, `javascript:`, `data:`, and `file:` render as plain text.
- **Bounded parsing and rendering**: `MD4CParser` caps input size at 256 MiB
  (`maxInputByteCount`) and AST nesting depth at 64 (`maxNestingDepth`),
  preventing 32-bit C truncation, ARC destruction stack overflows, and O(D²)
  indentation amplification.
- **Per-slice UTF-8 and NUL sanitization**: `SinglePassBuilder` validates
  non-ASCII slices individually (preventing cross-delimiter UTF-8 splicing), and
  `EntityDecoder` replaces `&#0;`/`&#x0;`, surrogates, and out-of-range numeric
  entities with `U+FFFD` per CommonMark 0.31 §6.2.
- **Hardened syntax highlighting**: `HighlightrEngine` validates themes, blocks
  `livescript`/`ls` (CVE-2026-133937), requires an explicit allowlisted language
  (mapping common aliases like `js`/`ts`/`py` and skipping direct `language: nil`
  or unknown-language `highlightAuto` calls while setting `ignoreIllegals = true`;
  pinned `Highlightr 2.3.0` / `highlight.js 11.11.1` retains internal sub-language
  auto-detection for multi-language grammars like `http` and its own `isUndefined`
  fallback), enforces a configurable input byte cap (`maxHighlightBytes`,
  default 64 KiB), checks `Task.isCancelled`,
  and pools at most 4 JSC VMs (clearable via `SyntaxHighlightingFactory.clearSharedPool()`).
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
