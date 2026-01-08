# Changelog

All notable changes to SwiftFastMarkdown will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
