# AGENTS.md

Tool-agnostic guidance for AI coding agents working in this repository. The
canonical, fuller version lives in [CLAUDE.md](CLAUDE.md); this file mirrors the
essentials for agents that look for `AGENTS.md`.

## Project

**SwiftFastMarkdown** — high-performance, SwiftUI-native Markdown parser and
renderer (iOS 18+ / macOS 15+). Wraps the vendored md4c C parser
(CommonMark 0.31 + GFM); renders to `AttributedString` and SwiftUI views; has an
incremental parser for streaming and an LRU render cache.

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build
swift test                  # full test suite — keep green
swift run -c release SwiftFastMarkdownBenchmarks   # benchmarks
```

## Layout (Parser → IR → Rendering)

- `Sources/SwiftFastMarkdown/Parser/` — md4c FFI, incremental parser, entity decoder
- `Sources/SwiftFastMarkdown/IR/` — zero-copy `ByteRange`-based block/span model
- `Sources/SwiftFastMarkdown/Rendering/` — AttributedString + SwiftUI renderers
- `Sources/SwiftFastMarkdown/Highlighting/` — `SyntaxHighlighting`, `HighlightrEngine` (actor), `LRUCache`
- `Sources/SwiftFastMarkdown/Style/` — `MarkdownStyle`
- `Sources/CMD4C/` — vendored md4c (upstream; do not hand-edit)

## Guardrails

- **Treat Markdown as untrusted.** Route any destination→URL conversion through
  `AttributedStringRenderer.safeLinkURL` (allows only `http`/`https`/`mailto`/`tel`
  and relative links).
- **No `.unsafeFlags`** in `Package.swift` (breaks remote SwiftPM consumption;
  `-Ounchecked` disables safety checks on untrusted input).
- **Pointer math** goes through `MD4CParser.pointerRange` (bounds-checked).
- **Byte-range offsetting** lives once in `BlockOffsetter` — don't duplicate it.
- **Read `IncrementalState` via `snapshot()`** (single lock, no torn reads).
- **AttributedString**: append to one accumulator, reuse cached static constants,
  avoid `a + b` concatenation in hot paths.
- **Bug fixes start with a failing test.** Keep `swift test` green.

## Keep docs in sync

On public-API or behavior changes, update `README.md`, `HOWTO.md`,
`CHANGELOG.md` (Keep a Changelog + SemVer), `CLAUDE.md`, and this file.
