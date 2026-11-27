import Foundation

/// A Least Recently Used (LRU) cache with true O(1) operations.
///
/// Uses the canonical doubly-linked list + dictionary implementation
/// that provides O(1) complexity for all operations:
/// - `value(for:)`: O(1)
/// - `insert(_:for:)`: O(1)
/// - `removeAll()`: O(n)
///
/// ## Implementation
/// - Dictionary maps keys to nodes for O(1) lookup
/// - Doubly-linked list maintains access order for O(1) eviction
/// - Most recently used items are at the head
/// - Least recently used items are at the tail
///
/// ## Thread Safety
/// This cache is NOT thread-safe. For concurrent access, wrap it in an
/// actor (recommended) or protect with a lock.
struct LRUCache<Key: Hashable, Value> {
    private(set) var capacity: Int
    private var storage: [Key: Node]
    private var head: Node?
    private var tail: Node?

    /// Doubly-linked list node.
    /// Uses reference semantics (class) for O(1) pointer manipulation.
    private final class Node {
        let key: Key
        var value: Value
        weak var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    init(capacity: Int) {
        let clamped = max(1, capacity)
        self.capacity = clamped
        self.storage = [:]
        self.storage.reserveCapacity(clamped)
    }

    /// Retrieves a value from the cache and marks it as recently used.
    /// - Complexity: O(1)
    mutating func value(for key: Key) -> Value? {
        guard let node = storage[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    /// Inserts or updates a value in the cache.
    /// - Complexity: O(1)
    mutating func insert(_ value: Value, for key: Key) {
        if let existingNode = storage[key] {
            // Update existing entry - O(1)
            existingNode.value = value
            moveToHead(existingNode)
            return
        }

        // Create new node
        let newNode = Node(key: key, value: value)
        storage[key] = newNode
        addToHead(newNode)

        // Evict if over capacity - O(1)
        if storage.count > capacity {
            removeTail()
        }
    }

    /// Removes the entry for a specific key, if present.
    /// - Complexity: O(1)
    @discardableResult
    mutating func removeValue(for key: Key) -> Value? {
        guard let node = storage.removeValue(forKey: key) else { return nil }
        removeNode(node)
        return node.value
    }

    /// Removes all entries from the cache.
    /// - Complexity: O(n)
    mutating func removeAll() {
        var current = head
        while let node = current {
            let next = node.next
            node.prev = nil
            node.next = nil
            current = next
        }
        storage.removeAll(keepingCapacity: true)
        head = nil
        tail = nil
    }

    /// The number of entries currently in the cache.
    var count: Int {
        storage.count
    }

    // MARK: - Private Linked List Operations (all O(1))

    /// Adds a node to the head of the list.
    private mutating func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head

        if let oldHead = head {
            oldHead.prev = node
        }
        head = node

        if tail == nil {
            tail = node
        }
    }

    /// Removes a node from its current position in the list.
    private mutating func removeNode(_ node: Node) {
        let prevNode = node.prev
        let nextNode = node.next

        if let prev = prevNode {
            prev.next = nextNode
        } else {
            // Node was head
            head = nextNode
        }

        if let next = nextNode {
            next.prev = prevNode
        } else {
            // Node was tail
            tail = prevNode
        }

        node.prev = nil
        node.next = nil
    }

    /// Moves an existing node to the head (most recently used).
    private mutating func moveToHead(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        addToHead(node)
    }

    /// Removes the tail node (least recently used) and returns its key.
    private mutating func removeTail() {
        guard let tailNode = tail else { return }
        storage.removeValue(forKey: tailNode.key)
        removeNode(tailNode)
    }
}
