# AGENTS.md

Tool-agnostic guidance for AI coding agents working in this repository. The
canonical, fuller version lives in [CLAUDE.md](CLAUDE.md); this file mirrors the
essentials for agents that look for `AGENTS.md`.

## Project

**SwiftFastMarkdown** (v1.3.0) — high-performance, SwiftUI-native Markdown parser and
renderer (iOS 18+ / macOS 15+). Wraps the vendored md4c C parser
(CommonMark 0.31 + GFM); renders to `AttributedString` and SwiftUI views; has an
incremental parser for streaming and an LRU render cache.

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build
swift test                  # full test suite (118 tests — keep green)
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
  `AttributedStringRenderer.safeLinkURL` (blocks protocol-relative `//host`,
  whitespace/control-obfuscated schemes, RFC 3986 §4.2 colons, and non-allowlisted schemes).
- **No `.unsafeFlags`** in `Package.swift` (breaks remote SwiftPM consumption;
  `-Ounchecked` disables safety checks on untrusted input).
- **Pointer math** goes through `MD4CParser.pointerRange` (unsigned, bounds-checked);
  keep `MD4CParser.maxInputByteCount` (256 MiB) and `maxNestingDepth` (64).
- **Incremental byte-range shifting** lives in `MD4CParser.parseSlice(..., baseOffset:startingOrdinal:scratch:)`
  with `md4c`-backed top-level block stabilization in `IncrementalState` (do not reintroduce `BlockOffsetter` or a duplicate CommonMark fence/HTML state machine).
- **Serialize all `IncrementalState` reads and mutations** under its single
  `NSLock` (no torn reads); rotate `documentID` on every mutating append/finalize.
- **AttributedString**: preserve the single-pass UTF-8 builder + per-slice UTF-8
  validation + prebuilt `StylePalette` + POD `RunPatch` pipeline.
- **Highlighting**: preserve theme/language allowlists, `maxHighlightBytes` cap,
  `Task.isCancelled` checks, and the bounded `HighlightrPool` (`clearSharedPool()`).
- **Bug fixes start with a failing test.** Keep `swift test` green.

## Keep docs in sync

On public-API or behavior changes, update `README.md`, `HOWTO.md`,
`CHANGELOG.md` (Keep a Changelog + SemVer), `CLAUDE.md`, and this file.
