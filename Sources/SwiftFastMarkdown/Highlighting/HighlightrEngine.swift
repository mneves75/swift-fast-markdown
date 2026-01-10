import Foundation
import SwiftUI
import Highlightr

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#endif

// Note: Highlightr is NOT thread-safe, but we protect all access via actor isolation.
// We intentionally do NOT extend Highlightr to be Sendable - the actor provides
// the thread safety, not the type itself.

public actor HighlightrEngine: SyntaxHighlighting {
    public struct Configuration: Sendable {
        public var theme: String
        public var fontName: String?
        public var fontSize: CGFloat?
        public var cacheSize: Int

        /// Default theme is "atom-one-dark" - verified to exist in Highlightr's 89 bundled themes.
        /// Available themes can be checked via Highlightr().availableThemes()
        public init(
            theme: String = "atom-one-dark",
            fontName: String? = nil,
            fontSize: CGFloat? = nil,
            cacheSize: Int = 128
        ) {
            self.theme = theme
            self.fontName = fontName
            self.fontSize = fontSize
            self.cacheSize = cacheSize
        }
    }

    private let highlighter: Highlightr
    private var configuration: Configuration
    private var cache: LRUCache<HighlightKey, AttributedString>

    public init?(configuration: Configuration = Configuration()) {
        guard let engine = Highlightr() else {
            return nil
        }
        self.highlighter = engine
        self.configuration = configuration
        self.cache = LRUCache(capacity: configuration.cacheSize)

        // Apply theme and font inline (cannot call actor-isolated methods from init in Swift 6)
        _ = engine.setTheme(to: configuration.theme)
        if let fontName = configuration.fontName,
           let fontSize = configuration.fontSize,
           let font = PlatformFont(name: fontName, size: fontSize) {
            engine.theme?.setCodeFont(font)
        } else if let fontSize = configuration.fontSize {
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            engine.theme?.setCodeFont(monoFont)
        }
    }

    public func highlight(code: String, language: String?) async -> AttributedString {
        let key = HighlightKey(theme: configuration.theme, language: language, code: code)
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
        // Validate theme exists before applying
        let available = highlighter.availableThemes()
        let themeName = available.contains(name) ? name : "atom-one-dark"

        configuration.theme = themeName
        cache.removeAll()
        applyThemeAndFont()
    }

    private func applyThemeAndFont() {
        // setTheme returns Bool - log failure in debug builds
        let success = highlighter.setTheme(to: configuration.theme)
        #if DEBUG
        if !success {
            print("[HighlightrEngine] Warning: Failed to set theme '\(configuration.theme)'")
        }
        #endif

        // Apply font if configured
        if let fontName = configuration.fontName,
           let fontSize = configuration.fontSize,
           let font = PlatformFont(name: fontName, size: fontSize) {
            highlighter.theme?.setCodeFont(font)
        } else if let fontSize = configuration.fontSize {
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            highlighter.theme?.setCodeFont(monoFont)
        }
    }
}

private struct HighlightKey: Hashable {
    let theme: String
    let language: String?
    let code: String  // Full code content for collision-free comparison

    func hash(into hasher: inout Hasher) {
        hasher.combine(theme)
        hasher.combine(language)
        hasher.combine(code.hashValue)  // Use hash for performance
    }

    static func == (lhs: HighlightKey, rhs: HighlightKey) -> Bool {
        lhs.theme == rhs.theme &&
        lhs.language == rhs.language &&
        lhs.code == rhs.code  // Full comparison to prevent hash collisions
    }
}
