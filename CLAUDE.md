# CLAUDE.md

Guidance for Claude Code (claude.ai/code) and other AI agents working in this
repository. See [AGENTS.md](AGENTS.md) for the tool-agnostic copy.

## What this is

**SwiftFastMarkdown** — a high-performance, SwiftUI-native Markdown parser and
renderer for iOS 18+ / macOS 15+. It wraps the vendored [md4c](https://github.com/mity/md4c)
C parser (CommonMark 0.31 + GFM) and renders to `AttributedString` and SwiftUI
views, with incremental parsing for streaming (AI chat) and an LRU render cache.

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build (default optimizations, no unsafe flags)
swift test                  # full test suite (must stay green)
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
└── Resources/     HTMLEntities.json, PrivacyInfo.xcprivacy

Sources/CMD4C/     vendored md4c.c / md4c.h (do not edit by hand — it's upstream)
```

Key design points:

- **Zero-copy IR**: blocks/spans hold `ByteRange` offsets into the source `Data`;
  strings are decoded lazily via `TextContent.string(in:)`. Don't materialize
  strings during parsing.
- **Pointer math goes through `MD4CParser.pointerRange`** — it has the bounds
  checks. `stringFromPointer` reuses it; do not reintroduce inline pointer
  arithmetic.
- **Byte-range offsetting** for incremental parsing lives in the single
  `BlockOffsetter` enum. There is no separate "internal" copy — don't fork it.
- **`IncrementalState` is `@unchecked Sendable`** behind an `NSLock`. Read its
  state through `snapshot()` only (one lock acquisition, no torn reads).
- **`HighlightrEngine` is an actor** isolating the non-Sendable Highlightr /
  JavaScriptCore engine. Highlighting is async and runs off the render path.

## Conventions / guardrails

- **Untrusted input.** Markdown is treated as untrusted. Link destinations are
  validated by `AttributedStringRenderer.safeLinkURL` — only `http`, `https`,
  `mailto`, `tel`, and relative destinations become links. If you add any new
  path that turns a destination into a `URL`/`.link`, route it through that
  helper.
- **No `.unsafeFlags` in Package.swift.** SwiftPM refuses to resolve packages
  that use them as remote dependencies, and `-Ounchecked` would disable safety
  checks on untrusted input. Rely on SwiftPM's default release optimization.
- **AttributedString building**: append to one accumulator; reuse the cached
  static constants (`newline`, `space`, `cellSeparator`, `thematicBreakString`)
  instead of allocating `AttributedString("\n")` in loops. Avoid `a + b`
  concatenation in hot paths.
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
