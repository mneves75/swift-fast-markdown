import Foundation
import SwiftUI

/// A cached AttributedString renderer for improved performance on repeated renders.
///
/// Uses an O(1) doubly-linked-list `LRUCache` to store rendered AttributedStrings,
/// keyed by document ID. This provides near-instant repeated renders for:
/// - SwiftUI previews that re-render the same document
/// - Documents that don't change between view updates
/// - Repeated rendering of the same content (e.g., in list views)
///
/// ## Thread Safety
/// This actor ensures thread-safe concurrent access to the cache.
public actor CachedAttributedStringRenderer {
    private let renderer: AttributedStringRenderer
    private var cache: LRUCache<UUID, CachedEntry>

    /// The current number of entries in the cache.
    public var cacheCount: Int { cache.count }

    /// Creates a cached renderer with the specified cache capacity.
    ///
    /// - Parameter maxCacheSize: Maximum number of entries to cache. Defaults to 64.
    public init(maxCacheSize: Int = 64) {
        self.renderer = AttributedStringRenderer()
        self.cache = LRUCache(capacity: maxCacheSize)
    }

    /// Renders a document, using the cache when possible.
    ///
    /// - Parameters:
    ///   - document: The markdown document to render.
    ///   - style: The style to apply during rendering.
    /// - Returns: The rendered AttributedString.
    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        if let cached = cache.value(for: document.id), cached.style == style {
            return cached.attributedString
        }

        let result = renderer.render(document, style: style)
        cache.insert(CachedEntry(attributedString: result, style: style), for: document.id)
        return result
    }

    /// Clears all cached entries.
    public func clearCache() {
        cache.removeAll()
    }

    /// Invalidates cached entry for a specific document.
    public func invalidate(documentId: UUID) {
        cache.removeValue(for: documentId)
    }
}

// MARK: - Cache Entry

/// A single cache entry containing the rendered AttributedString and the style
/// it was rendered with.
private struct CachedEntry {
    let attributedString: AttributedString
    let style: MarkdownStyle
}

// MARK: - Synchronous Thread-Safe Renderer

/// A thread-safe cached renderer for synchronous contexts.
///
/// Uses `NSLock` + O(1) `LRUCache` for thread safety instead of Swift concurrency.
/// Best used in benchmarks or non-async contexts.
public final class ThreadSafeCachedRenderer: @unchecked Sendable {
    private let renderer: AttributedStringRenderer
    private var cache: LRUCache<UUID, CachedEntry>
    private let lock = NSLock()

    /// Creates a thread-safe cached renderer.
    ///
    /// - Parameter maxCacheSize: Maximum number of entries to cache. Defaults to 32.
    public init(maxCacheSize: Int = 32) {
        self.renderer = AttributedStringRenderer()
        self.cache = LRUCache(capacity: maxCacheSize)
    }

    /// Renders a document with caching.
    ///
    /// - Parameters:
    ///   - document: The markdown document to render.
    ///   - style: The style to apply during rendering.
    /// - Returns: The rendered AttributedString.
    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        lock.lock()
        if let cached = cache.value(for: document.id), cached.style == style {
            lock.unlock()
            return cached.attributedString
        }
        lock.unlock()

        // Render outside the lock so concurrent callers aren't blocked on heavy docs.
        let result = renderer.render(document, style: style)

        lock.lock()
        cache.insert(CachedEntry(attributedString: result, style: style), for: document.id)
        lock.unlock()

        return result
    }

    /// Clears the cache.
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
