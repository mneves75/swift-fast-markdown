# Changelog

All notable changes to SwiftFastMarkdown will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-11-27

Major performance redesign and comprehensive security hardening release. All 118 tests pass (`72 XCTest + 46 Swift Testing`) and every v1.0 release median performance target passes with wide headroom (with p95 targets passing on an unloaded Apple Silicon host; heavy host CPU contention can cause OS scheduling spikes in p95).

### Security

- **Hardened `AttributedStringRenderer.safeLinkURL` (now `public`)**: blocks protocol-relative URLs (`//host`), ASCII whitespace/C0/DEL control-obfuscated schemes (`< javascript:...>`, `<\tfile://...>`), RFC 3986 §4.2 first-segment colons (`custom_scheme://action`), host-less `http:`/`https:`, and empty `mailto:`/`tel:` targets. Blocked links no longer receive `linkColor` or inherit an outer `.link`.
- **AST nesting depth cap (`MD4CParser.maxNestingDepth = 64`) & bounded rendering**: flattens deeply nested blockquotes, lists, and inline spans at parse time (preserving leaf text) while bounding `SinglePassBuilder` indent spaces (`maxIndentSpaces = 64`, eliminating O(D²) space amplification) and SwiftUI `BlockContentView` recursion (`maxNestingDepth = 32`, glass surface stacking capped at depth <= 4 across blockquotes, code blocks, and tables). Prevents stack-overflow crashes in Swift ARC value-witness destruction and renderers on 512 KB cooperative threads.
- **Per-slice UTF-8 validation in `SinglePassBuilder`**: validates non-ASCII `ByteRange` slices individually before appending so malformed UTF-8 halves separated by stripped Markdown delimiters cannot splice into forged Unicode scalars (such as U+202E RLO) or place `RunPatch` byte offsets mid-scalar.
- **CommonMark 0.31 §6.2 numeric entity sanitization**: `EntityDecoder.decodeUTF8` now enforces CommonMark 1–6 hex / 1–7 decimal digit bounds and replaces `&#0;` / `&#x0;` / surrogates / `> U+10FFFF` with `U+FFFD` (closing the `MD_TEXT_NULLCHAR` bypass), and `HTMLEntities.lookupUTF8` validates `offset >= headerEnd`.
- **`md4c`-backed streaming block stabilization**: `IncrementalMarkdownParser` now derives stabilization boundaries directly from `md4c`'s own top-level AST (stabilizing completed prefixes only at blank-line boundaries preceding a line-ending-terminated top-level `.paragraph`, `.heading`, `.blockQuote`, or `.table`), eliminating parallel scanner drift and guaranteeing block-structure parity across LF, CRLF, bare CR (`\r`), fenced code blocks, Type 1–5 HTML blocks, and nested containers so verbatim code/HTML cannot escape into active Markdown/links (note: cross-chunk link reference definitions require full-document parsing).
- **Input size ceiling (`MD4CParser.maxInputByteCount = 256 MiB`) & safe `UInt32` conversions**: throws `MarkdownParserError.inputTooLarge` before `md_parse` (mitigating both 32-bit `MD_SIZE` narrowing traps and vendored `CMD4C` ~2.67 GiB `MD_TEMP_BUFFER` 32-bit truncation without modifying upstream `Sources/CMD4C`), clamps `ByteRange.clamped(to:)` via `UInt32(clamping:)`, uses overflow-checked `ByteRangeSequence.string(in:)`, clears dangling `basePointer` on `ParserContext.clearTemporaryState()`, and uses unsigned pointer arithmetic in `pointerRange`.
- **`HighlightrEngine` & bounded `HighlightrPool`**: validates themes against the full `availableThemes()` allowlist (excluding unsafe CSS themes like `"far"`) in both `HighlightrEngine.init` and `HighlightrPool`, bounds the shared pool to an LRU of 4 engines with atomic registration (no `await` suspension race) and engine-less proxies (holding only their own `HighlightrEngine.Configuration`, never caching an engine reference) so eviction or `SyntaxHighlightingFactory.clearSharedPool()` drops pool references immediately (releasing engines once any in-flight highlight completes), checks `Task.isCancelled` before/after JSC work, caps highlighted code size (`Configuration.maxHighlightBytes`, default 64 KiB), sets `ignoreIllegals = true`, maps standard aliases (`js`, `ts`, `py`, etc.), and requires an explicitly allowlisted non-blocked language (blocking `livescript`/`ls` for highlight.js 11.11.1 CVE-2026-133937 and skipping direct `language: nil` / unknown-language `highlightAuto` calls; pinned `Highlightr 2.3.0` / `highlight.js 11.11.1` retains internal sub-language auto-detection for multi-language grammars like `http` and its own `isUndefined` fallback).

### Fixed

- **Tight list item labels dropped by `MD4CParser`**: md4c omits `MD_BLOCK_P` callbacks inside tight lists (`md4c.c:4850`); `MD4CParser` now opens and flushes an implicit paragraph frame whenever inline text or spans arrive directly inside a list item (or depth-flattened container), preserving tight list labels, nested tight list items, and non-zero `ListItemBlock.id` byte ranges (including tight task list items).
- **Permanent `LRUCache` retain cycle leak**: changed `LRUCache.Node.prev` to `weak` and unlinked nodes iteratively in `removeAll()`, eliminating permanent memory leaks on `clearCache()`, `setTheme(_:)`, and owner deallocation; clamped `reserveCapacity` to prevent traps on negative capacity.
- **Stale cached renders on incremental snapshots**: `IncrementalMarkdownParser` now rotates `MarkdownDocument.id` whenever content mutates (`append`/`finalize`), ensuring `CachedAttributedStringRenderer`, `ThreadSafeCachedRenderer`, and `FastMarkdownText` always render updated snapshots.
- **`CodeBlockView` stale state on `BlockID` collisions**: keyed `.task(id:)` on `(blockID, language, code)` and scoped `MarkdownView` with `.id(document.id)` so document swaps and non-prefix resets never display stale highlighted code.
- **`HeadingView` empty `headingFonts` crash**: falls back to `style.baseFont` when `style.headingFonts` is empty, matching `AttributedStringRenderer`.
- **`StreamingMarkdownView` lifecycle edge cases**: tracks `lastParsedContent` and `parserFinalized` to prevent desync on `onChange`-before-`onAppear` or post-`finalize()` updates.
- **`SinglePassBuilder.appendDecimalInt` `Int.min` overflow**: uses `value.magnitude` (`UInt`).

### Performance

- **`MD4CParser` single-pass flat-buffer redesign**: replaced per-append `blocks + [block]` / `ranges + [range]` O(n²) array copies with LIFO `ScratchStack<T>` (`moveInitialize` into exact-capacity arrays, zero ARC churn), O(1) incremental byte-range tracking on stack frames (eliminating post-order `computeRange`/`rangeFromBlocks` re-walks), contiguous `ByteRange` coalescing for text/code/HTML spans, and `ReusableScratch` for streaming.
- **`AttributedStringRenderer` single-pass UTF-8 + POD `RunPatch` redesign**: assembles text once in a contiguous UTF-8 buffer, initializes one `AttributedString(fullString, attributes: baseAttributes)`, and applies only non-base styled spans from a prebuilt `StylePalette` via monotonic UTF-8 indexing (retained Render large-fixture 77.6 KB heap `990 KB -> 199 KB`, 5.0× smaller).
- **`IncrementalMarkdownParser` single-buffer streaming**: replaced dual `stableData + pendingData` concatenations with one append-only `sourceData: Data`, single-parse `md4c`-backed stabilization (stabilizing completed prefixes at blank-line boundaries before newline-terminated top-level paragraphs, headings, block quotes, or tables — linear amortized parsing on typical multi-block streams when prior `MarkdownDocument` snapshots are not retained across appends, whereas retaining prior snapshots triggers Swift Copy-on-Write buffer copies and consecutive non-stabilizing blocks stay pending until a stabilizing block arrives or `finalize()` is called), direct `MD4CParser.parseSlice(..., baseOffset:startingOrdinal:scratch:)`, and in-place pending tail updates on `cachedBlocks`. Also fixed stabilized chunks ignoring `Configuration.options` and ensured monotonic `BlockID.ordinal` across chunks.
- **`EntityDecoder` & compact binary `HTMLEntities.bin`**: replaced the 145.9 KB `HTMLEntities.json` + `JSONSerialization` load with a 28.7 KB sorted binary table (5.08× smaller, zero-alloc binary search in UTF-8) plus inline fast-path decoding for common named and numeric entities.
- **Lazy shared `SyntaxHighlightingFactory` pool**: `makeDefault()` returns a lightweight lazy actor proxy backed by a bounded LRU `HighlightrPool` keyed by validated `HighlightrEngine.Configuration` (now `Hashable`), eliminating ~72–357 ms main-thread JavaScriptCore VM stalls on SwiftUI view init and cutting benchmark process footprint from `197.2 MB` to `12.2 MB` (16.2× smaller) while preserving per-instance `setTheme(_:)` isolation.
- **O(1) `LRUCache` in cached renderers**: migrated `CachedAttributedStringRenderer` and `ThreadSafeCachedRenderer` (now `@unchecked Sendable`) from O(n) `[UUID]` arrays to the doubly-linked-list `LRUCache` with new O(1) `removeValue(for:)`, moving uncached renders outside the lock in `ThreadSafeCachedRenderer`.
- **SwiftUI views & Demo app lag fixes**: eliminated eager re-parsing in `StreamingMarkdownView.init`, replaced Unicode-normalized `hasPrefix` + `dropFirst` with SIMD `memcmp` UTF-8 suffix slicing, rewired `AsyncStreamMarkdownView` to stream chunks directly into `IncrementalMarkdownParser`, switched iOS 26/macOS 26 wrapping to native `SwiftUI.GlassEffectContainer` (removing `.compositingGroup()` full-document rasterization), updated `FastMarkdownText` to re-render on style changes, and eliminated per-body parsing/global animation in `Example/SwiftFastMarkdownDemo`.

### Changed

- Removed dead `BlockOffsetter` enum (superseded by direct `baseOffset` shifting in `MD4CParser.parseSlice`).
- Hardened `.gitignore` with nested SwiftPM registry and secret-file patterns.
- Agent enforcement: `.claude/settings.json` refuses edits to the vendored md4c sources in `Sources/CMD4C/` and adds a Stop gate on `swift test`.
- Pruned 17 redundant/unasserted tests and strengthened 7 weak tests across the suite while adding 10 security regression tests (118 passing tests total).

## [1.2.0] - 2026-06-09

Full security, architecture, and performance review. All 114 tests pass; all
v1.0 performance targets still pass after removing the unsafe build flags.

### Security

- **Link scheme validation**: `javascript:`, `data:`, `file:` and other unsafe
  schemes are no longer attached as tappable links. Allowed: `http`, `https`,
  `mailto`, `tel`, and scheme-less (relative) destinations. Markdown often
  comes from untrusted sources (LLM output, user input).
- **Removed all unsafe build flags** (`-Ounchecked`,
  `-disable-actor-data-race-checks`, `-O3`, `-ffast-math`): they disabled
  bounds/overflow checks in a parser of untrusted input — and `.unsafeFlags`
  made the package impossible to consume as a remote SwiftPM dependency.
  Benchmarks confirm all performance targets still pass without them.
- Unified `stringFromPointer` with `pointerRange` in `MD4CParser` so all
  pointer→offset math shares the same bounds checks.

### Fixed

- **Data race in `IncrementalMarkdownParser.buildDocument()`**: state was read
  through a mix of locked and unlocked accessors, allowing torn reads during
  concurrent streaming. All reads now go through a single-lock `snapshot()`.
- **LRU bookkeeping drift in cached renderers**: re-rendering the same document
  with a different style appended a duplicate id to the LRU order without
  removing the stale one, skewing eviction counting.

### Performance

- `AttributedStringRenderer`: removed intermediate `AttributedString + AttributedString`
  concatenations and per-call allocations of `"\n"`, `" "`, `" | "` and
  thematic-break strings (now cached static constants). Render 10KB median
  stays ~3.4ms — without `-Ounchecked`.
- `CachedAttributedStringRenderer`: `MarkdownStyle` is now `Hashable`; the
  per-render string-built style identifier was replaced by direct equality.
- `IncrementalParser`: snapshot skips the `stableData + pendingData`
  concatenation when nothing is pending.

### Changed

- `MarkdownStyle` now conforms to `Hashable`.
- `StreamingMarkdownView`: removed redundant `lastProcessedContent` state
  (`onChange(of:)` already fires only on real changes).
- `IncrementalParser`: ~110 lines of duplicated byte-range offset logic
  consolidated into the internal `BlockOffsetter`.

### Removed

- `IncrementalMarkdownParser.Configuration.minBufferSize`: documented a
  buffering behavior that was never implemented (parameter was never read).

### Documentation

- Refreshed the README performance table with full release-mode benchmark
  numbers (median + p95 across 1KB/10KB/50KB parse and render, plus streaming
  chunk append), measured as the quietest of 3 runs on Apple Silicon (M4 Pro).
- Verified the README renders correctly on GitHub via the GitHub render API:
  the performance table renders as a real `<table>` with right-aligned numeric
  columns, the `<` in the target thresholds is safely escaped (not interpreted
  as HTML), and the `→`/`×`/✅ glyphs display as intended.

## [1.1.5] - 2026-01-10

### Performance

- Apply Swift 6 optimization flags (-Ounchecked, -disable-actor-data-race-checks)
- Apply C optimization (-O3, -ffast-math) for md4c parser
- LTO disabled for Swift 6.2 compatibility (3.9% improvement in testing)
- Achieves 5.2x better than target for parse (0.191ms vs 1ms)
- Achieves 62x better than target for chunk parse (0.008ms vs 0.5ms)

### Cached Rendering

- CachedAttributedStringRenderer with actor-based thread-safe LRU cache
- ThreadSafeCachedRenderer class using NSLock
- 64-entry cache with O(1) lookup
- Near-instant cached renders (~0.001ms) vs fresh renders (~3.7ms)

### Critical Fixes (Code Review)

- **CRIT-001: Infinite Recursion in AttributedStringRenderer**: Fixed accidental recursion in `renderInline` method
  - Public method was calling itself with resolved optional parameter
  - Resolved to private overload due to type difference (fragile pattern)
  - Renamed private method to `renderInlineSpans` for clarity
  - Prevents potential stack overflow from API misuse
- **HIGH-001: Hash Collision Protection**: Added content comparison to cache keys
  - `HighlightKey` now stores full code string, not just hash
  - Prevents incorrect cache hits from hash collisions
- **HIGH-002: Unsafe Sendable Removed**: Removed `@unchecked Sendable` extension from `Highlightr`
  - `Highlightr` is NOT thread-safe internally
  - Actor isolation provides real thread safety

### Code Improvements

- `@inline(__always)` on hot path functions
- Style fingerprint includes all properties for correct cache keys
- Benchmarks entry point fixed (@main attribute conflict)

### Tests Added

- `testRenderInlineWithFontOverride`: Verifies renderInline with custom font
- `testRenderInlineWithoutFontOverride`: Verifies default font behavior
- `testDifferentCodeWithSameHashReturnsCorrectResult`: Verifies hash collision protection
- `testHighlightrEngineThreadSafety`: Verifies concurrent actor access

### Engineering Spec

- Updated `docs/plans/CODE_REVIEW_ENGINEERING_SPEC.md` to v3.0

### Performance

| Metric | Result | Target | Improvement |
|--------|--------|--------|-------------|
| Parse 10KB | 0.191ms | <1ms | 5.2x (23% better than v1.0) |
| Render 10KB | ~3.7ms | <5ms | 25% headroom |
| Chunk parse | 0.008ms | <0.5ms | 62x (11% better than v1.0) |

### Future Optimizations (Investigated)

1. **LTO (Link-Time Optimization)**: 3-4% potential - ⚠️ Breaks Swift 6.2 build (known toolchain issue)
2. **SIMD/Vectorization**: Not applicable - md4c is a state-machine parser (character-by-character), not data-parallel
3. **Profile-Guided Optimization (PGO)**: 10-20% potential - Requires instrumented builds and real-world workloads
4. **Swift 6 Embedded Mode**: 0% speed - Reduces binary size only, no performance benefit
5. **CoreText Bypass**: 20-30% potential - Requires lower-level CoreText rendering, sacrifices SwiftUI compatibility

## [1.1.4] - 2026-01-09

### Fixed

- **iOS Simulator Crash**: Fixed assertion failure in `MD4CParser.pointerRange()`
  - Crash occurred when md4c passed pointers outside the original buffer on iOS
  - Added bounds validation to prevent integer overflow when computing byte offsets
  - The parser now gracefully handles edge cases where text pointers are invalid
  - Enables SwiftUI demo app to run successfully on iOS Simulator

## [1.1.3] - 2026-01-09

### Added

- **#Preview Macros**: Added SwiftUI previews to all public views
  - `MarkdownView`: Rich document preview with code blocks and formatting
  - `FastMarkdownText`: Simple AttributedString-based preview
  - `StreamingMarkdownView`: Live streaming and static content previews
  - Uses `@Previewable` for stateful preview bindings

- **CodeBlockView Loading State**: Visual feedback during syntax highlighting
  - Shows subtle `ProgressView` indicator while highlighting computes
  - Transitions smoothly when highlighting completes

### Changed

- **StreamingMarkdownView Refactor**: Eliminated DRY violations and improved safety
  - Replaced hash-based change detection with direct string comparison (prevents hash collisions)
  - Added `@MainActor` annotation for Swift 6 concurrency compliance
  - Extracted `wrappedContentStack` to eliminate duplicated `onChange` modifier

- **LiquidGlassSurface Unification**: Single parameterized modifier replaces two near-identical structs
  - `LiquidGlassModifier<M: ShapeStyle>` accepts configurable fallback material and border opacity
  - API unchanged: `liquidGlassSurface()` and `liquidGlassProminentSurface()` still work
  - Eliminates ~30 lines of duplicated code

- **TableView Cell Extraction**: DRY refactor for cell rendering
  - Extracted `cellView(for:isHeader:)` helper method
  - Unifies header and body cell rendering logic

### Fixed

- **Hash Collision Risk**: StreamingMarkdownView now uses direct string comparison
  - Previous `hashValue` comparison could silently skip updates on collision
  - New approach guarantees correct change detection

## [1.1.2] - 2026-01-09

### Added

- **Privacy Manifest**: Added `PrivacyInfo.xcprivacy` for App Store compliance
  - Required for iOS 17+ submissions (ITMS-91053 warning prevention)
  - Declares no tracking, no collected data types, no accessed API categories
  - Ensures smooth App Store review process

- **Engineering Spec**: Carmack-level code review at `docs/plans/CODE_REVIEW_ENGINEERING_SPEC.md`
  - Safety verification of pointer lifetime, C callback race conditions, ordinal overflow
  - Identified and resolved issues with documentation, logging, and test modernization

### Changed

- **Test Migration**: Migrated 2 test files to Swift Testing framework
  - `ByteRangeTests.swift`: 14 tests using `@Test`, `#expect`, `#require`
  - `IncrementalParserTests.swift`: 10 tests using Swift Testing patterns
  - `LRUCacheTests.swift` retained XCTest for `measure {}` performance tests
  - Total: 78 XCTest + 28 Swift Testing = 106 tests

### Fixed

- **Documentation**: Fixed stale comment in `LRUCacheTests.swift`
  - Updated docstring to accurately describe doubly-linked list implementation
  - Removed incorrect reference to timestamp-based eviction

- **Debug Logging**: Added assertions to `EntityDecoder.swift`
  - `#if DEBUG` assertionFailure for missing `HTMLEntities.json` resource
  - `#if DEBUG` assertionFailure for failed JSON parsing
  - Silent production behavior preserved, but debug builds surface issues immediately

## [1.1.1] - 2026-01-09

### Added

- **Demo App**: Comprehensive 6-tab demo showcasing 100% of markdown features
  - All Features tab: Tests all 22 block types and inline spans (H1-H6, bold, italic, strikethrough, code, links, lists, tables, quotes, thematic breaks, Unicode edge cases)
  - Editor tab: Live split-view markdown editing with real-time preview
  - Cross-platform support for iOS 18+ and macOS 15+
  - SwiftUI best practices: #Preview macros, dark mode, accessibility testing

- **Engineering Spec**: Carmack-level documentation at `docs/plans/DEMO_APP_ENGINEERING_SPEC.md`
  - Code review findings with safety verification
  - Feature gap analysis (73% → 100% coverage)
  - Implementation phases and verification checklist

### Fixed

- **iOS Compatibility**: Replaced HighlighterSwift with Highlightr
  - HighlighterSwift was macOS-only due to AppKit dependencies
  - Highlightr provides cross-platform syntax highlighting for iOS/macOS

- **SwiftUI Colors**: Fixed cross-platform color resolution in EditorDemo
  - Uses conditional compilation for UIColor (iOS) vs native SwiftUI colors (macOS)

## [1.0.1] - 2026-01-08

### Fixed

- **Critical**: Fixed JavaScriptCore thread-safety in `HighlighterSwiftEngine`
  - JSContext requires thread-affinity (all operations must occur on the thread where it was created)
  - Added `ThreadSafeHighlighterWrapper` using dedicated serial DispatchQueue
  - The actor serializes method calls while the internal queue ensures thread-safe Highlighter access

- **Performance**: Removed global `.animation()` modifier from `StreamingMarkdownView`
  - Global animation on LazyVStack caused layout recalculation on every block change
  - Individual blocks retain `.transition()` for efficient enter/exit animations
  - Significantly reduces frame drops during rapid streaming updates

- **Performance**: Rewrote `LRUCache` with true O(1) complexity
  - Previous timestamp-based implementation had O(n) eviction
  - Now uses canonical doubly-linked list + dictionary implementation
  - All operations (lookup, insert, evict) are O(1)

- **Correctness**: Removed `.interactive()` from non-interactive Liquid Glass surfaces
  - `LiquidGlassSurface` now uses `.glassEffect(.regular)` without interactive flag
  - Interactive glass should only be applied to tappable/focusable elements

- **Performance**: Added static shared renderer in `InlineText`
  - `AttributedStringRenderer` is stateless; sharing eliminates per-view allocation

- **Correctness**: Added `GlassEffectContainer` to `MarkdownView` and `StreamingMarkdownView`
  - Required for proper glass blending between code blocks, quotes, and tables on iOS 26+

### Added

- Comprehensive `LRUCacheTests` test suite (18 new tests)
- Design documentation for thread-safety decisions (NSLock vs Mutex rationale)

### Changed

- Test suite expanded from 88 to 106 tests

## [1.0.0] - 2026-01-08

### Added

- Initial release of SwiftFastMarkdown
- md4c-based CommonMark 0.31 parser with GFM extensions
- Zero-copy ByteRange IR for efficient memory usage
- Stable block IDs for SwiftUI diffing optimization
- `MarkdownParser` for static document parsing
- `IncrementalMarkdownParser` for O(n) streaming parsing
- `MarkdownView` SwiftUI component for rich rendering
- `FastMarkdownText` for simple AttributedString-based rendering
- `AttributedStringRenderer` for programmatic rendering
- `StreamingMarkdownView` for real-time AI chat interfaces
- Syntax highlighting via pluggable `SyntaxHighlighting` protocol
- HighlighterSwift integration with LRU cache
- iOS 26 Liquid Glass effects with iOS 18 material fallback
- GFM extensions: tables, task lists, strikethrough, autolinks
- Comprehensive test suite (88 tests)
- Benchmark harness with median/p95/p99 reporting
- Demo app showcasing all features

### Performance

- Parse 10KB: 0.249ms median (target <1ms)
- Render 10KB: 3.699ms median (target <5ms)
- Chunk parse: 0.009ms median (target <0.5ms)
