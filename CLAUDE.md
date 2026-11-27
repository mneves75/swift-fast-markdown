# CLAUDE.md

Guidance for Claude Code (claude.ai/code) and other AI agents working in this
repository. See [AGENTS.md](AGENTS.md) for the tool-agnostic copy.

## What this is

**SwiftFastMarkdown** (v1.3.0) — a high-performance, SwiftUI-native Markdown parser and
renderer for iOS 18+ / macOS 15+. It wraps the vendored [md4c](https://github.com/mity/md4c)
C parser (CommonMark 0.31 + GFM) and renders to `AttributedString` and SwiftUI
views, with incremental parsing for streaming (AI chat) and an LRU render cache.

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build (default optimizations, no unsafe flags)
swift test                  # full test suite (118 tests — must stay green)
swift run -c release SwiftFastMarkdownBenchmarks   # performance benchmarks
```

There is no separate lint step; treat compiler warnings as signal.

## Architecture

Three layers, one direction of dependency (Parser → IR → Rendering):

```
Sources/SwiftFastMarkdown/
├── Parser/        MD4CParser (C FFI), IncrementalParser, EntityDecoder, ParseOptions
├── IR/            MarkdownBlock, MarkdownSpan, ByteRange, TextContent, BlockID, MarkdownDocument
├── Rendering/     AttributedStringRenderer, CachedAttributedStringRenderer,
│                  MarkdownView, StreamingMarkdownView, FastMarkdownText,
│                  BlockViews/ (per-block SwiftUI views), LiquidGlass/ (iOS 26 glass)
├── Highlighting/  SyntaxHighlighting protocol, HighlightrEngine (actor), LRUCache
├── Style/         MarkdownStyle (Hashable, Sendable)
└── Resources/     HTMLEntities.bin (compact sorted binary table, 28.7 KB), PrivacyInfo.xcprivacy

Sources/CMD4C/     vendored md4c.c / md4c.h (do not edit by hand — it's upstream)
```

Key design points:

- **Zero-copy IR**: blocks/spans hold `ByteRange` offsets into the source `Data`;
  strings are decoded lazily via `TextContent.string(in:)`. Don't materialize
  strings during parsing.
- **Pointer math goes through `MD4CParser.pointerRange`** — it uses unsigned
  pointer arithmetic and bounds checks. Do not reintroduce inline pointer
  arithmetic.
- **Incremental byte-range shifting** happens directly in `MD4CParser.parseSlice(..., baseOffset:startingOrdinal:scratch:)`.
  `MD4CParser.maxInputByteCount` (256 MiB) and `MD4CParser.maxNestingDepth` (64)
  protect C FFI size bounds and Swift ARC / renderer stack safety.
- **`IncrementalState` is `@unchecked Sendable`** behind a single `NSLock`
  protecting every read and mutation (no torn reads). `documentID` rotates on
  every mutating `append`/`finalize` so downstream caches never serve stale
  snapshots.
- **`HighlightrEngine` is an actor** isolating the non-Sendable Highlightr /
  JavaScriptCore engine behind a bounded LRU `HighlightrPool` (max 4 VMs,
  clearable via `SyntaxHighlightingFactory.clearSharedPool()`). Highlighting
  validates themes/languages, caps input size (`maxHighlightBytes`), and checks
  `Task.isCancelled`.

## Conventions / guardrails

- **Untrusted input.** Markdown is treated as untrusted. Link destinations are
  validated by `AttributedStringRenderer.safeLinkURL` (public) — only `http`/`https`
  (with non-empty host), `mailto`/`tel` (with non-empty body), and clean relative
  destinations become links. Protocol-relative `//host`, whitespace/control-obfuscated
  schemes, and RFC 3986 §4.2 first-segment colons are blocked. Route any new
  destination→URL path through that helper.
- **No `.unsafeFlags` in Package.swift.** SwiftPM refuses to resolve packages
  that use them as remote dependencies, and `-Ounchecked` would disable safety
  checks on untrusted input. Rely on SwiftPM's default release optimization.
- **AttributedString building**: `AttributedStringRenderer` uses a single-pass
  UTF-8 byte buffer (`SinglePassBuilder`), a prebuilt `StylePalette` of
  `AttributeContainer`s, and POD `RunPatch` spans applied monotonically onto a
  single `AttributedString(fullString, attributes: baseAttributes)`. Keep
  `safeLinkURL` on all link/wikiLink paths and preserve per-slice UTF-8 validation
  so malformed slices cannot splice across delimiters or misalign patch offsets.
- **Tests are the contract.** When fixing a bug, add a failing test first, then
  fix. Keep `swift test` green before committing.

## Public surface

Entry points: `MarkdownParser` (static), `IncrementalMarkdownParser` (streaming),
`MarkdownView` / `FastMarkdownText` / `StreamingMarkdownView` / `AsyncStreamMarkdownView`
(SwiftUI), `AttributedStringRenderer` / `CachedAttributedStringRenderer`
(AttributedString), `MarkdownStyle` (theming), `SyntaxHighlighting` +
`HighlightrEngine` (highlighting).

## Docs to keep in sync

When behavior or the public API changes, update: `README.md`, `HOWTO.md`,
`CHANGELOG.md` (Keep a Changelog + SemVer), and this file / `AGENTS.md`.
