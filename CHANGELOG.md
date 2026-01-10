# Changelog

All notable changes to SwiftFastMarkdown will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
