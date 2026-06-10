import Foundation
import SwiftUI

/// A cached AttributedString renderer for improved performance on repeated renders.
///
/// Uses an LRU cache to store rendered AttributedStrings, keyed by document ID.
/// This provides significant speedup for:
/// - SwiftUI previews that re-render the same document
/// - Documents that don't change between view updates
/// - Repeated rendering of the same content (e.g., in list views)
///
/// ## Thread Safety
/// This actor ensures thread-safe concurrent access to the cache.
public actor CachedAttributedStringRenderer {
    private let renderer: AttributedStringRenderer
    private var cache: [UUID: CachedEntry]
    private var lruOrder: [UUID]
    private let maxCacheSize: Int

    /// The current number of entries in the cache.
    public var cacheCount: Int { cache.count }

    /// Creates a cached renderer with the specified cache capacity.
    ///
    /// - Parameter maxCacheSize: Maximum number of entries to cache. Defaults to 64.
    public init(maxCacheSize: Int = 64) {
        self.renderer = AttributedStringRenderer()
        self.maxCacheSize = maxCacheSize
        self.cache = [:]
        self.lruOrder = []
        self.cache.reserveCapacity(maxCacheSize)
    }

    /// Renders a document, using the cache when possible.
    ///
    /// - Parameters:
    ///   - document: The markdown document to render.
    ///   - style: The style to apply during rendering.
    /// - Returns: The rendered AttributedString.
    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        if let cached = cache[document.id], cached.style == style {
            // Move to front (most recently used)
            if let index = lruOrder.firstIndex(of: document.id) {
                lruOrder.remove(at: index)
                lruOrder.append(document.id)
            }
            return cached.attributedString
        }

        let result = renderer.render(document, style: style)
        // Replacing an entry (same document, new style) must not leave a stale
        // id in lruOrder, or eviction counting drifts from the real cache size.
        if cache.updateValue(CachedEntry(attributedString: result, style: style), forKey: document.id) != nil {
            lruOrder.removeAll { $0 == document.id }
        }
        lruOrder.append(document.id)

        // Evict oldest entry if over capacity
        if lruOrder.count > maxCacheSize {
            let evictId = lruOrder.removeFirst()
            cache.removeValue(forKey: evictId)
        }

        return result
    }

    /// Clears all cached entries.
    public func clearCache() {
        cache.removeAll()
        lruOrder.removeAll()
    }

    /// Invalidates cached entry for a specific document.
    public func invalidate(documentId: UUID) {
        cache.removeValue(forKey: documentId)
        lruOrder.removeAll { $0 == documentId }
    }
}

// MARK: - Cache Entry

/// A single cache entry containing the rendered AttributedString and the style
/// it was rendered with. MarkdownStyle is Hashable, so a direct equality check
/// replaces the previous string-based style identifier.
private struct CachedEntry {
    let attributedString: AttributedString
    let style: MarkdownStyle
}

// MARK: - Synchronous Thread-Safe Renderer

/// A thread-safe cached renderer for synchronous contexts.
///
/// Uses `NSLock` for thread safety instead of Swift concurrency.
/// Best used in benchmarks or non-async contexts.
public final class ThreadSafeCachedRenderer {
    private let renderer: AttributedStringRenderer
    private var cache: [UUID: CachedEntry]
    private var lruOrder: [UUID]
    private let lock = NSLock()
    private let maxCacheSize: Int

    /// Creates a thread-safe cached renderer.
    ///
    /// - Parameter maxCacheSize: Maximum number of entries to cache. Defaults to 32.
    public init(maxCacheSize: Int = 32) {
        self.renderer = AttributedStringRenderer()
        self.maxCacheSize = maxCacheSize
        self.cache = [:]
        self.lruOrder = []
        self.cache.reserveCapacity(maxCacheSize)
    }

    /// Renders a document with caching.
    ///
    /// - Parameters:
    ///   - document: The markdown document to render.
    ///   - style: The style to apply during rendering.
    /// - Returns: The rendered AttributedString.
    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[document.id], cached.style == style {
            // Move to front (MRU)
            if let index = lruOrder.firstIndex(of: document.id) {
                lruOrder.remove(at: index)
                lruOrder.append(document.id)
            }
            return cached.attributedString
        }

        let result = renderer.render(document, style: style)
        // Replacing an entry (same document, new style) must not leave a stale
        // id in lruOrder, or eviction counting drifts from the real cache size.
        if cache.updateValue(CachedEntry(attributedString: result, style: style), forKey: document.id) != nil {
            lruOrder.removeAll { $0 == document.id }
        }
        lruOrder.append(document.id)

        // Evict oldest entry if over capacity
        if lruOrder.count > maxCacheSize {
            let evictId = lruOrder.removeFirst()
            cache.removeValue(forKey: evictId)
        }

        return result
    }

    /// Clears the cache.
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        lruOrder.removeAll()
    }
}
