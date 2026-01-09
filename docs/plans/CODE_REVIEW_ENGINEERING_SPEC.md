# SwiftFastMarkdown Code Review Engineering Specification

**Version**: 2.0
**Date**: January 9, 2026
**Author**: Engineering Team
**Reviewer**: John Carmack

---

## Executive Summary

This document contains the findings from a comprehensive Carmack-level code review of SwiftFastMarkdown v1.1.1. The review examined all source files for bugs, anti-patterns, safety issues, and opportunities to adopt Swift 6.2+ best practices (WWDC 2025).

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

### 1.2 VERIFIED CONCERNS - Low Priority

| Issue | Location | Impact | Risk |
|-------|----------|--------|------|
| Hash collision | `StreamingMarkdownView.swift:99-101` | Uses `hashValue` for change detection; collision could cause stale content | Very Low |
| UInt32 offset | `IncrementalParser.swift` | Theoretical overflow for documents >4GB | Negligible |
| Silent entity load | `EntityDecoder.swift:47-49` | Returns empty dict if JSON missing; no error logging | Low |

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
- [ ] All source files reviewed
- [ ] No security vulnerabilities found
- [ ] No memory safety issues found
- [ ] Thread safety verified

### Post-Implementation
- [ ] Privacy manifest added and validated
- [ ] LRUCacheTests comment updated
- [ ] EntityDecoder has debug logging
- [ ] Swift Testing migration complete (where applicable)
- [ ] All 106+ tests pass
- [ ] Build succeeds with no warnings
- [ ] Demo app runs successfully

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

**Document Status**: Ready for Implementation
**Last Updated**: January 9, 2026
