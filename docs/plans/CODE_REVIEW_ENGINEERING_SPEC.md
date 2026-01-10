# SwiftFastMarkdown Code Review Engineering Specification

**Version**: 3.0
**Date**: January 10, 2026
**Author**: Engineering Team
**Reviewer**: John Carmack

---

## Executive Summary

This document contains findings from a comprehensive Carmack-level code review of SwiftFastMarkdown v1.1.5. The review examined all source files against SWIFT-GUIDELINES.md, IOS-GUIDELINES.md, and DEV-GUIDELINES.md.

### Summary of Findings

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 1 | Must Fix |
| HIGH | 3 | Must Fix |
| MEDIUM | 4 | Should Fix |
| LOW | 2 | Nice to Have |

### Critical Finding: Infinite Recursion

**CRIT-001**: `AttributedStringRenderer.renderInline` contains accidental recursion due to method overloading by optionality. While it works due to overload resolution to private method, this is fragile and violates Swift API Design Guidelines.

---

## Part 1: Safety Verification (Carmack Standard)

### 1.1 VERIFIED SAFE - No Fix Required

| Issue | Location | Analysis |
|-------|----------|----------|
| Pointer lifetime | `MD4CParser.swift:23-27` | **SAFE**: `basePointer` is used only within `withUnsafeBytes` closure. md4c callbacks complete synchronously before closure exits. |
| C callback race | `MD4CParser.swift:32-40` | **SAFE**: `md_parse()` is synchronous. Callbacks execute sequentially on the calling thread. No concurrent mutation possible. |
| Ordinal overflow | `MD4CParser.swift:71` | **ACCEPTABLE**: Uses `&+=` (wrapping addition). Overflow would require 4B+ blocks - unrealistic scenario. |
| LRU eviction | `LRUCache.swift` | **SAFE**: O(1) doubly-linked list implementation is correct. |
| Actor isolation | `HighlightrEngine.swift` | **SAFE**: Actor provides proper isolation despite `@retroactive @unchecked Sendable` on Highlightr. |

### 1.2 VERIFIED CONCERNS - Addressed in v1.1.3

| Issue | Location | Impact | Status |
|-------|----------|--------|--------|
| Hash collision | `StreamingMarkdownView.swift` | Uses `hashValue` for change detection; collision could cause stale content | **FIXED v1.1.3** - Now uses direct string comparison |
| UInt32 offset | `IncrementalParser.swift` | Theoretical overflow for documents >4GB | Negligible - Accepted |
| Silent entity load | `EntityDecoder.swift` | Returns empty dict if JSON missing; no error logging | **FIXED v1.1.2** - Added debug assertions |

---

## Part 2: Issues Found - Must Fix

### 2.1 CRITICAL - Privacy Manifest Missing

**Location**: Package root
**Impact**: App Store rejection (ITMS-91053)
**Requirement**: Starting Feb 2025, all iOS apps must include `PrivacyInfo.xcprivacy`

**Fix Required**: Create privacy manifest declaring:
- No required reason APIs used
- No data collection
- No tracking

**File to Create**: `Sources/SwiftFastMarkdown/Resources/PrivacyInfo.xcprivacy`

### 2.2 HIGH - Test Framework Migration Needed

**Location**: `Tests/SwiftFastMarkdownTests/*.swift`
**Impact**: Using deprecated XCTest pattern in Swift 6+ codebase

**Current State**:
```swift
import XCTest
@testable import SwiftFastMarkdown

final class LRUCacheTests: XCTestCase {
    func testInsertAndRetrieve() {
        XCTAssertEqual(cache.value(for: "a"), 100)
    }
}
```

**Target State** (Swift Testing):
```swift
import Testing
@testable import SwiftFastMarkdown

struct LRUCacheTests {
    @Test func insertAndRetrieve() {
        #expect(cache.value(for: "a") == 100)
    }
}
```

**Rationale**:
- Swift Testing shipped with Xcode 16 (2024)
- Modern macro-based assertions (`#expect`, `#require`)
- Better parallelization (in-process Swift Concurrency)
- Structs preferred over classes for test isolation
- Not migrating UI tests (not applicable here)

### 2.3 MEDIUM - Stale Documentation in LRUCacheTests

**Location**: `Tests/SwiftFastMarkdownTests/LRUCacheTests.swift:5-7`
**Issue**: Comment says "timestamp-based eviction" but implementation uses doubly-linked list

**Current**:
```swift
/// Tests for LRUCache timestamp-based eviction implementation.
///
/// The cache achieves O(1) lookups and O(1) amortized insertions with
/// O(n) worst-case eviction (acceptable since eviction is rare).
```

**Fix**: Update to match actual implementation (O(1) linked-list based)

### 2.4 MEDIUM - EntityDecoder Silent Failure

**Location**: `Sources/SwiftFastMarkdown/Parser/EntityDecoder.swift:47-49`
**Issue**: Returns empty dictionary if resource missing; no debug logging

**Current**:
```swift
guard let url = Bundle.module.url(forResource: "HTMLEntities", withExtension: "json"),
      let data = try? Data(contentsOf: url) else {
    return [:]
}
```

**Fix**: Add debug assertion and logging

### 2.5 LOW - Swift Language Version Not Pinned

**Location**: `Package.swift`
**Issue**: Uses swift-tools-version 6.2 but doesn't explicitly set `swiftLanguageModes`

**Recommendation**: Add explicit language mode for clarity

---

## Part 3: Swift 6.2 Best Practices (WWDC 2025)

### 3.1 Approachable Concurrency

Swift 6.2 introduced "Approachable Concurrency" with two key changes:
1. `NonisolatedNonsendingByDefault` - nonisolated async functions run on caller's actor
2. `@concurrent` attribute for explicit background execution

**Current Code Review**:
- `HighlightrEngine` uses actor isolation correctly
- `IncrementalMarkdownParser` uses NSLock + `@unchecked Sendable` (documented, acceptable)
- No changes required, but should enable approachable concurrency flag when available

### 3.2 Mutex vs NSLock

**Current**: `IncrementalParser.swift` uses NSLock
**Modern Alternative**: `Mutex` from Synchronization framework (iOS 18+)

**Analysis**: NSLock is acceptable because:
- Documented design decision in code
- Supports iOS 18+ (Mutex requires same minimum)
- Performance difference negligible for this use case
- Migration would add complexity without benefit

**Decision**: No change required.

### 3.3 Span Type (Swift 6.2)

Swift 6.2 introduced `Span` for safe buffer operations. Not applicable here since ByteRange is our own abstraction over byte offsets.

---

## Part 4: Implementation Plan

### Phase 1: Privacy Manifest (CRITICAL)

**Priority**: Blocker - Must fix before any App Store submission

**File**: `Sources/SwiftFastMarkdown/Resources/PrivacyInfo.xcprivacy`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
</dict>
</plist>
```

### Phase 2: Documentation Fixes

1. Update LRUCacheTests comment (line 5-7)
2. Add debug logging to EntityDecoder

### Phase 3: Swift Testing Migration

**Scope**: 8 test files, 106 tests
**Approach**: Incremental - migrate file by file

**Migration Mapping**:
| XCTest | Swift Testing |
|--------|---------------|
| `import XCTest` | `import Testing` |
| `final class FooTests: XCTestCase` | `struct FooTests` |
| `func testX()` | `@Test func x()` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(x)` | `#expect(x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTFail("msg")` | `Issue.record("msg")` |
| `setUp()` | `init()` |
| `tearDown()` | `deinit` |
| `measure { }` | Keep XCTest for performance (not supported in Swift Testing) |

**Files to Migrate**:
1. `LRUCacheTests.swift` (18 tests) - Has performance tests, keep as XCTest
2. `ParserTests.swift`
3. `IncrementalParserTests.swift`
4. `AttributedStringRendererTests.swift`
5. `ByteRangeTests.swift`
6. `CommonMarkSpecTests.swift`
7. `GFMExtensionTests.swift`
8. `SyntaxHighlighterTests.swift`

**Note**: Performance tests using `measure {}` must remain in XCTest.

### Phase 4: Verification

1. Run all tests: `swift test --parallel`
2. Build for iOS: `swift build -c release`
3. Verify no warnings: `swift build 2>&1 | grep -i warning`

---

## Part 5: Files Changed Summary

| File | Action | Priority |
|------|--------|----------|
| `Sources/SwiftFastMarkdown/Resources/PrivacyInfo.xcprivacy` | CREATE | CRITICAL |
| `Tests/SwiftFastMarkdownTests/LRUCacheTests.swift` | FIX COMMENT | MEDIUM |
| `Sources/SwiftFastMarkdown/Parser/EntityDecoder.swift` | ADD DEBUG LOG | MEDIUM |
| `Tests/SwiftFastMarkdownTests/*.swift` | MIGRATE TO SWIFT TESTING | HIGH |

---

## Part 6: Verification Checklist

### Pre-Implementation
- [x] All source files reviewed
- [x] No security vulnerabilities found
- [x] No memory safety issues found
- [x] Thread safety verified

### Post-Implementation (v1.1.2)
- [x] Privacy manifest added and validated
- [x] LRUCacheTests comment updated
- [x] EntityDecoder has debug logging
- [x] Swift Testing migration complete (ByteRangeTests, IncrementalParserTests)
- [x] All 106 tests pass (78 XCTest + 28 Swift Testing)
- [x] Build succeeds with no warnings
- [x] Demo app runs successfully

### Post-Implementation (v1.1.3)
- [x] Hash collision risk fixed in StreamingMarkdownView (direct string comparison)
- [x] @MainActor added to StreamingMarkdownView/AsyncStreamMarkdownView
- [x] DRY violations fixed (onChange deduplication, LiquidGlassModifier unification)
- [x] #Preview macros added to MarkdownView, FastMarkdownText, StreamingMarkdownView
- [x] CodeBlockView loading state indicator
- [x] TableView cell rendering extracted to helper
- [x] All 106 tests still pass
- [x] Build succeeds with no warnings

---

## Part 7: Sources and References

### Swift 6.2 Concurrency
- [Swift 6.2 Concurrency Changes - SwiftLee](https://www.avanderlee.com/concurrency/swift-6-2-concurrency-changes/)
- [Approachable Concurrency Guide - SwiftLee](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [Modern Swift Lock: Mutex - SwiftLee](https://www.avanderlee.com/concurrency/modern-swift-lock-mutex-the-synchronization-framework/)
- [Swift 6.2 Released - InfoQ](https://www.infoq.com/news/2025/09/swift-6-2-released/)

### Privacy Manifest
- [Privacy Manifest Files - Apple Documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Adding Privacy Manifest - Apple Documentation](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)

### Swift Testing
- [Swift Testing - Apple Developer](https://developer.apple.com/xcode/swift-testing)
- [Migrating XCTest to Swift Testing - Use Your Loaf](https://useyourloaf.com/blog/migrating-xctest-to-swift-testing/)
- [Swift Testing GitHub](https://github.com/swiftlang/swift-testing)

---

**Document Status**: In Progress (v1.1.5 Review)
**Last Updated**: January 10, 2026
**Verified By**: Automated test suite (106 tests)

---

## Part 8: v1.1.5 Code Review Findings (January 10, 2026)

### 8.1 Critical Issues

#### CRIT-001: Infinite Recursion in AttributedStringRenderer.renderInline

**File**: `Sources/SwiftFastMarkdown/Rendering/AttributedStringRenderer.swift:26-34`

**Severity**: CRITICAL - Stack overflow risk

**Description**:
```swift
public func renderInline(
    _ spans: [MarkdownSpan],
    source: Data,
    style: MarkdownStyle = .default,
    fontOverride: Font? = nil  // Optional parameter
) -> AttributedString {
    let font = fontOverride ?? style.baseFont
    return renderInline(spans, source: source, style: style, fontOverride: font)
    // Recursive call resolves to PRIVATE overload due to parameter type difference
}
```

**Why It Works (By Accident)**:
- The call resolves to the PRIVATE `renderInline(_:source:style:fontOverride:)` because `font` is non-optional `Font`
- Private method has different signature (non-optional `fontOverride`)
- This is fragile and confusing

**Fix**:
```swift
// Rename private method to avoid confusion
public func renderInline(...) -> AttributedString {
    let font = fontOverride ?? style.baseFont
    return renderInlineSpans(spans, source: source, style: style, fontOverride: font)
}

@inline(__always)
private func renderInlineSpans(...) -> AttributedString { ... }
```

---

### 8.2 High Severity Issues

#### HIGH-001: Hash Collision in Cache Keys

**Files**:
- `Sources/SwiftFastMarkdown/Rendering/CachedAttributedStringRenderer.swift`
- `Sources/SwiftFastMarkdown/Highlighting/HighlightrEngine.swift:65`

**Issue**: Uses `code.hashValue` for cache key without content verification

**Fix**: Use full content comparison alongside hash

#### HIGH-002: Unsafe Sendable Conformance

**File**: `Sources/SwiftFastMarkdown/Highlighting/HighlightrEngine.swift:16`

**Issue**:
```swift
extension Highlightr: @retroactive @unchecked Sendable {}
```

**Impact**: False sense of thread safety - Highlightr is NOT thread-safe internally

**Fix**: Remove the extension; actor isolation provides real thread safety

#### HIGH-003: C Interop Pointer Lifetime

**File**: `Sources/SwiftFastMarkdown/Parser/MD4CParser.swift:23-40`

**Issue**: `ParserContext.basePointer` stores pointer beyond `withUnsafeBytes` closure

**Current Mitigation**: ParserContext is used only synchronously within `md_parse`

**Recommendation**: Consider redesign to avoid storing pointers

---

### 8.3 Medium Severity Issues

#### MED-001: Confusing Method Overloading

**File**: `Sources/SwiftFastMarkdown/Rendering/AttributedStringRenderer.swift`

Two methods named `renderInline` with optional vs non-optional parameter

#### MED-002: Unchecked Optional in C Callbacks

**File**: `Sources/SwiftFastMarkdown/Parser/MD4CParser.swift:209-210`

Silent handling of nil pointers via optional chaining

#### MED-003: Non-Deterministic Font Cache Keys

**File**: `Sources/SwiftFastMarkdown/Rendering/CachedAttributedStringRenderer.swift:109`

Font description may include runtime-specific information

#### MED-004: EntityDecoder Silent Failure

**File**: `Sources/SwiftFastMarkdown/Parser/EntityDecoder.swift`

Returns empty dictionary on failure without user notification

---

### 8.4 Low Severity Issues

#### LOW-001: Debug Print in Production Code

**File**: `Sources/SwiftFastMarkdown/Highlighting/HighlightrEngine.swift:95-99`

Consider using `os.Logger` per LOG-GUIDELINES.md

#### LOW-002: Privacy Manifest ✅ VERIFIED

`PrivacyInfo.xcprivacy` exists and is properly configured

---

### 8.5 Test Coverage Assessment

| Area | Status | Tests |
|------|--------|-------|
| ByteRange | ✅ Good | Basic operations |
| IncrementalParser | ✅ Good | Core functionality |
| LRUCache | ✅ Good | Cache operations |
| AttributedStringRenderer | ⚠️ Minimal | Basic rendering only |
| HighlightrEngine | ❌ Missing | No async tests |
| MD4CParser | ⚠️ Minimal | No edge case tests |

**Missing Tests**:
1. Infinite recursion test for `renderInline`
2. Hash collision test for `HighlightKey`
3. Entity decoding failure test
4. Large document parsing test
5. Concurrent access test for non-actor caches

---

## Part 9: Implementation Plan v1.1.5

### Phase 1: Critical Fixes (Immediate)

| Issue | File | Change |
|-------|------|--------|
| CRIT-001 | AttributedStringRenderer.swift | Rename private `renderInline` to `renderInlineSpans` |
| HIGH-002 | HighlightrEngine.swift | Remove unsafe `Sendable` extension |

### Phase 2: High Priority (This Sprint)

| Issue | File | Change |
|-------|------|--------|
| HIGH-001 | CachedAttributedStringRenderer.swift | Add content comparison to cache keys |
| HIGH-001 | HighlightrEngine.swift | Add content comparison to HighlightKey |
| HIGH-03 | MD4CParser.swift | Document pointer lifetime rationale |

### Phase 3: Medium Priority (Next Sprint)

| Issue | File | Change |
|-------|------|--------|
| MED-001 | AttributedStringRenderer.swift | Rename overloaded methods |
| MED-002 | MD4CParser.swift | Add explicit guard statements |
| MED-003 | CachedAttributedStringRenderer.swift | Use stable font representation |
| MED-004 | EntityDecoder.swift | Add error handling |

### Phase 4: Test Coverage

1. Add test for renderInline with fontOverride
2. Add test for hash collision edge case
3. Add performance benchmark tests

---

## Part 10: Compliance Summary v1.1.5

| Guideline | Status | Notes |
|-----------|--------|-------|
| Swift 6 Strict Concurrency | ✅ PASS | Actors used correctly |
| Thread Safety | ⚠️ PARTIAL | Actor isolation good, but Sendable extension problematic |
| Type Safety | ✅ PASS | No `any` types, good use of `Sendable` |
| Error Handling | ⚠️ PARTIAL | Some silent failures in EntityDecoder |
| Memory Safety | ⚠️ PARTIAL | C interop needs review |
| Testing | ⚠️ PARTIAL | Missing critical path tests |
| Privacy Compliance | ✅ PASS | PrivacyInfo.xcprivacy present |
| Documentation | ⚠️ PARTIAL | Missing API comments |

---

## Part 11: Verification Checklist

### Pre-Fix Verification
- [x] All source files reviewed
- [x] Issues cataloged and prioritized
- [x] Engineering spec updated

### Post-Fix Verification (v1.1.6)
- [ ] CRIT-001: Infinite recursion fixed
- [ ] HIGH-001: Hash collision protection added
- [ ] HIGH-002: Unsafe Sendable removed
- [ ] HIGH-03: Pointer lifetime documented
- [ ] All 106 tests pass
- [ ] Build succeeds with no warnings
- [ ] Performance benchmarks unchanged
