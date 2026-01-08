import Foundation

struct LRUCache<Key: Hashable, Value> {
    private(set) var capacity: Int
    private var storage: [Key: Value]
    private var order: [Key]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = [:]
        self.order = []
    }

    mutating func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        if storage[key] != nil {
            storage[key] = value
            touch(key)
            return
        }

        storage[key] = value
        order.append(key)
        trimIfNeeded()
    }

    mutating func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
    }

    private mutating func trimIfNeeded() {
        while order.count > capacity {
            let key = order.removeFirst()
            storage.removeValue(forKey: key)
        }
    }
}
