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
        let key = CacheKey(document: document, style: style)

        if let cached = cache[key.id] {
            // Check if style matches
            if cached.styleIdentifier == key.styleIdentifier {
                // Move to front (most recently used)
                if let index = lruOrder.firstIndex(of: key.id) {
                    lruOrder.remove(at: index)
                    lruOrder.append(key.id)
                }
                return cached.attributedString
            }
        }

        let result = renderer.render(document, style: style)
        let entry = CachedEntry(attributedString: result, styleIdentifier: key.styleIdentifier)

        // Add to cache
        cache[key.id] = entry
        lruOrder.append(key.id)

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

/// A single cache entry containing the rendered AttributedString and style info.
private struct CachedEntry {
    let attributedString: AttributedString
    let styleIdentifier: String
}

// MARK: - Cache Key

/// A cache key combining document identity and optional style identifier.
private struct CacheKey {
    let id: UUID
    let styleIdentifier: String

    init(document: MarkdownDocument, style: MarkdownStyle) {
        self.id = document.id
        self.styleIdentifier = Self.computeStyleIdentifier(style)
    }

    /// Computes a stable identifier for the style using all relevant properties.
    /// This ensures different styles produce different cache keys.
    private static func computeStyleIdentifier(_ style: MarkdownStyle) -> String {
        // Use description which provides stable string representation
        // for all Font, Color, and Int properties
        let fontDescriptions = style.headingFonts.map { "\($0)" }.joined(separator: ",")

        return [
            "baseFont:\(style.baseFont)",
            "codeFont:\(style.codeFont)",
            "headingFonts:[\(fontDescriptions)]",
            "linkColor:\(style.linkColor)",
            "textColor:\(style.textColor)",
            "codeTextColor:\(style.codeTextColor)",
            "codeBackgroundColor:\(style.codeBackgroundColor)",
            "quoteStripeColor:\(style.quoteStripeColor)",
            "blockSpacing:\(style.blockSpacing)",
            "listIndent:\(style.listIndent)"
        ].joined(separator: "|")
    }
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
        let key = CacheKey(document: document, style: style)

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key.id] {
            // Check if style matches
            if cached.styleIdentifier == key.styleIdentifier {
                // Move to front (MRU)
                if let index = lruOrder.firstIndex(of: key.id) {
                    lruOrder.remove(at: index)
                    lruOrder.append(key.id)
                }
                return cached.attributedString
            }
        }

        let result = renderer.render(document, style: style)
        let entry = CachedEntry(attributedString: result, styleIdentifier: key.styleIdentifier)

        cache[key.id] = entry
        lruOrder.append(key.id)

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
