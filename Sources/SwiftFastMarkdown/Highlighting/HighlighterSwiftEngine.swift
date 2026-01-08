import Foundation
import SwiftUI
@preconcurrency import Highlighter

/// Syntax highlighter using highlight.js via the HighlighterSwift package.
///
/// ## Thread Safety
/// JavaScriptCore (used by Highlighter) requires thread-affinity: all operations
/// must occur on the same thread where the JSContext was created. This actor
/// uses a dedicated serial DispatchQueue to ensure thread-safe access.
///
/// The actor serializes method calls, and the internal queue ensures all
/// Highlighter operations execute on a consistent thread.
public actor HighlighterSwiftEngine: SyntaxHighlighting {
    public struct Configuration: Sendable {
        public var theme: String
        public var fontName: String?
        public var fontSize: CGFloat?
        public var cacheSize: Int

        public init(theme: String = "default", fontName: String? = nil, fontSize: CGFloat? = nil, cacheSize: Int = 128) {
            self.theme = theme
            self.fontName = fontName
            self.fontSize = fontSize
            self.cacheSize = cacheSize
        }
    }

    private let wrapper: ThreadSafeHighlighterWrapper
    private var configuration: Configuration
    private var cache: LRUCache<HighlightKey, AttributedString>

    public init?(configuration: Configuration = Configuration()) {
        guard let wrapper = ThreadSafeHighlighterWrapper(configuration: configuration) else {
            return nil
        }
        self.wrapper = wrapper
        self.configuration = configuration
        self.cache = LRUCache(capacity: configuration.cacheSize)
    }

    public func highlight(code: String, language: String?) async -> AttributedString {
        let key = HighlightKey(theme: configuration.theme, language: language, codeHash: code.hashValue)
        if let cached = cache.value(for: key) {
            return cached
        }

        // Perform highlighting on dedicated thread for JavaScriptCore safety
        let highlighted = await wrapper.highlight(code: code, language: language)
        let attributed: AttributedString
        if let highlighted {
            attributed = AttributedString(highlighted)
        } else {
            attributed = AttributedString(code)
        }

        cache.insert(attributed, for: key)
        return attributed
    }

    public func setTheme(_ name: String) async {
        configuration.theme = name
        cache.removeAll()
        await wrapper.setTheme(name, fontName: configuration.fontName, fontSize: configuration.fontSize)
    }
}

// MARK: - Thread-Safe Wrapper

/// Wraps Highlighter with a dedicated serial queue for JavaScriptCore thread-affinity.
///
/// JavaScriptCore's JSContext must be accessed from the thread on which it was created.
/// This wrapper ensures all Highlighter operations occur on a single, dedicated thread.
private final class ThreadSafeHighlighterWrapper: @unchecked Sendable {
    private let queue: DispatchQueue
    private let highlighter: Highlighter

    init?(configuration: HighlighterSwiftEngine.Configuration) {
        self.queue = DispatchQueue(label: "com.swiftfastmarkdown.highlighter", qos: .userInitiated)

        // Create Highlighter synchronously on the dedicated queue thread
        var engine: Highlighter?
        queue.sync {
            engine = Highlighter()
        }

        guard let highlighter = engine else { return nil }
        self.highlighter = highlighter

        // Set initial theme on the same thread
        queue.sync {
            _ = highlighter.setTheme(
                configuration.theme,
                withFont: configuration.fontName,
                ofSize: configuration.fontSize
            )
        }
    }

    func highlight(code: String, language: String?) async -> NSAttributedString? {
        await withCheckedContinuation { continuation in
            queue.async { [highlighter] in
                let result = highlighter.highlight(code, as: language)
                continuation.resume(returning: result)
            }
        }
    }

    func setTheme(_ name: String, fontName: String?, fontSize: CGFloat?) async {
        await withCheckedContinuation { continuation in
            queue.async { [highlighter] in
                _ = highlighter.setTheme(name, withFont: fontName, ofSize: fontSize)
                continuation.resume()
            }
        }
    }
}

// MARK: - Cache Key

private struct HighlightKey: Hashable {
    let theme: String
    let language: String?
    let codeHash: Int
}
