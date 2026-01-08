import Foundation
import SwiftUI
import Highlighter

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

    private var highlighter: Highlighter
    private var configuration: Configuration
    private var cache: LRUCache<HighlightKey, AttributedString>

    public init?(configuration: Configuration = Configuration()) {
        guard let engine = Highlighter() else {
            return nil
        }
        self.highlighter = engine
        self.configuration = configuration
        self.cache = LRUCache(capacity: configuration.cacheSize)
        _ = highlighter.setTheme(configuration.theme, withFont: configuration.fontName, ofSize: configuration.fontSize)
    }

    public func highlight(code: String, language: String?) async -> AttributedString {
        let key = HighlightKey(theme: configuration.theme, language: language, codeHash: code.hashValue)
        if let cached = cache.value(for: key) {
            return cached
        }

        let highlighted = highlighter.highlight(code, as: language)
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
        _ = highlighter.setTheme(name, withFont: configuration.fontName, ofSize: configuration.fontSize)
    }
}

private struct HighlightKey: Hashable {
    let theme: String
    let language: String?
    let codeHash: Int
}
