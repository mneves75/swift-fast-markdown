import XCTest
@testable import SwiftFastMarkdown

/// Tests for LRUCache timestamp-based eviction implementation.
///
/// The cache achieves O(1) lookups and O(1) amortized insertions with
/// O(n) worst-case eviction (acceptable since eviction is rare).
final class LRUCacheTests: XCTestCase {

    // MARK: - Basic Operations

    func testInsertAndRetrieve() {
        var cache = LRUCache<String, Int>(capacity: 3)

        cache.insert(100, for: "a")
        cache.insert(200, for: "b")

        XCTAssertEqual(cache.value(for: "a"), 100)
        XCTAssertEqual(cache.value(for: "b"), 200)
    }

    func testMissingKeyReturnsNil() {
        var cache = LRUCache<String, Int>(capacity: 3)

        cache.insert(100, for: "a")

        XCTAssertNil(cache.value(for: "missing"))
    }

    func testUpdateExistingKey() {
        var cache = LRUCache<String, Int>(capacity: 3)

        cache.insert(100, for: "a")
        cache.insert(200, for: "a")

        XCTAssertEqual(cache.value(for: "a"), 200)
        XCTAssertEqual(cache.count, 1)
    }

    // MARK: - Capacity and Eviction

    func testCapacityEnforced() {
        var cache = LRUCache<String, Int>(capacity: 2)

        cache.insert(100, for: "a")
        cache.insert(200, for: "b")
        cache.insert(300, for: "c")

        XCTAssertEqual(cache.count, 2)
        // "a" was least recently used, should be evicted
        XCTAssertNil(cache.value(for: "a"))
        XCTAssertEqual(cache.value(for: "b"), 200)
        XCTAssertEqual(cache.value(for: "c"), 300)
    }

    func testMinimumCapacity() {
        var cache = LRUCache<String, Int>(capacity: 0)

        // Capacity should be at least 1
        XCTAssertEqual(cache.capacity, 1)

        cache.insert(100, for: "a")
        XCTAssertEqual(cache.value(for: "a"), 100)
    }

    func testNegativeCapacity() {
        let cache = LRUCache<String, Int>(capacity: -5)

        // Capacity should be at least 1
        XCTAssertEqual(cache.capacity, 1)
    }

    // MARK: - LRU Eviction Order

    func testLRUEvictionOrder() {
        var cache = LRUCache<String, Int>(capacity: 3)

        // Insert a, b, c
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.insert(3, for: "c")

        // Access "a" to make it recently used
        _ = cache.value(for: "a")

        // Insert "d" - should evict "b" (least recently used)
        cache.insert(4, for: "d")

        XCTAssertNil(cache.value(for: "b"), "b should be evicted")
        XCTAssertEqual(cache.value(for: "a"), 1, "a should remain")
        XCTAssertEqual(cache.value(for: "c"), 3, "c should remain")
        XCTAssertEqual(cache.value(for: "d"), 4, "d should exist")
    }

    func testRepeatedAccessKeepsEntryFresh() {
        var cache = LRUCache<String, Int>(capacity: 2)

        cache.insert(1, for: "a")
        cache.insert(2, for: "b")

        // Keep accessing "a" to keep it fresh
        _ = cache.value(for: "a")
        _ = cache.value(for: "a")
        _ = cache.value(for: "a")

        // Insert "c" - should evict "b", not "a"
        cache.insert(3, for: "c")

        XCTAssertEqual(cache.value(for: "a"), 1, "a should remain due to access")
        XCTAssertNil(cache.value(for: "b"), "b should be evicted")
        XCTAssertEqual(cache.value(for: "c"), 3)
    }

    func testUpdateRefreshesTimestamp() {
        var cache = LRUCache<String, Int>(capacity: 2)

        cache.insert(1, for: "a")
        cache.insert(2, for: "b")

        // Update "a" to refresh its timestamp
        cache.insert(100, for: "a")

        // Insert "c" - should evict "b" since "a" was updated
        cache.insert(3, for: "c")

        XCTAssertEqual(cache.value(for: "a"), 100)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.value(for: "c"), 3)
    }

    // MARK: - RemoveAll

    func testRemoveAll() {
        var cache = LRUCache<String, Int>(capacity: 3)

        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.insert(3, for: "c")

        cache.removeAll()

        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.value(for: "a"))
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertNil(cache.value(for: "c"))
    }

    func testRemoveAllPreservesCapacity() {
        var cache = LRUCache<String, Int>(capacity: 5)

        cache.insert(1, for: "a")
        cache.removeAll()

        XCTAssertEqual(cache.capacity, 5)
    }

    // MARK: - Edge Cases

    func testSingleCapacityCache() {
        var cache = LRUCache<String, Int>(capacity: 1)

        cache.insert(1, for: "a")
        XCTAssertEqual(cache.value(for: "a"), 1)

        cache.insert(2, for: "b")
        XCTAssertNil(cache.value(for: "a"))
        XCTAssertEqual(cache.value(for: "b"), 2)
    }

    func testLargeCapacityCache() {
        var cache = LRUCache<Int, String>(capacity: 1000)

        for i in 0..<1000 {
            cache.insert("value-\(i)", for: i)
        }

        XCTAssertEqual(cache.count, 1000)
        XCTAssertEqual(cache.value(for: 0), "value-0")
        XCTAssertEqual(cache.value(for: 999), "value-999")

        // Insert one more to trigger eviction
        cache.insert("value-1000", for: 1000)
        XCTAssertEqual(cache.count, 1000)
    }

    func testRapidEvictions() {
        var cache = LRUCache<Int, Int>(capacity: 2)

        // Insert many items rapidly
        for i in 0..<100 {
            cache.insert(i, for: i)
        }

        XCTAssertEqual(cache.count, 2)
        // Only last 2 should remain
        XCTAssertEqual(cache.value(for: 99), 99)
        XCTAssertEqual(cache.value(for: 98), 98)
    }

    // MARK: - Value Types

    func testComplexValueType() {
        struct ComplexValue: Equatable {
            let id: Int
            let name: String
            let data: [Int]
        }

        var cache = LRUCache<String, ComplexValue>(capacity: 2)

        let value1 = ComplexValue(id: 1, name: "First", data: [1, 2, 3])
        let value2 = ComplexValue(id: 2, name: "Second", data: [4, 5, 6])

        cache.insert(value1, for: "key1")
        cache.insert(value2, for: "key2")

        XCTAssertEqual(cache.value(for: "key1"), value1)
        XCTAssertEqual(cache.value(for: "key2"), value2)
    }

    func testOptionalValueType() {
        var cache = LRUCache<String, Int?>(capacity: 2)

        cache.insert(nil, for: "nil-key")
        cache.insert(42, for: "value-key")

        // Note: value(for:) returns nil both for missing keys and nil values
        // This is a known limitation of this simple implementation
        XCTAssertEqual(cache.count, 2)
    }

    // MARK: - Thread Safety Note

    // Note: LRUCache is a value type (struct) with `mutating` methods.
    // Thread safety is the caller's responsibility. For concurrent access,
    // wrap in an actor or use locking.
    //
    // The SyntaxHighlightCache in SwiftFastMarkdown wraps this cache
    // in an actor for thread-safe access.

    // MARK: - Performance Characteristics

    func testAccessIsO1() {
        var cache = LRUCache<Int, Int>(capacity: 10_000)

        // Fill cache
        for i in 0..<10_000 {
            cache.insert(i * 2, for: i)
        }

        // Access should be O(1) - measure many accesses
        measure {
            for _ in 0..<100_000 {
                _ = cache.value(for: Int.random(in: 0..<10_000))
            }
        }
    }

    func testInsertWithoutEvictionIsO1() {
        measure {
            var cache = LRUCache<Int, Int>(capacity: 100_000)
            for i in 0..<100_000 {
                cache.insert(i, for: i)
            }
        }
    }
}
