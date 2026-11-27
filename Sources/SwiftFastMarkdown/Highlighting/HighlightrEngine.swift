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
    public struct Configuration: Sendable, Hashable {
        public var theme: String
        public var fontName: String?
        public var fontSize: CGFloat?
        public var cacheSize: Int
        /// Maximum UTF-8 byte length of a code block sent to JavaScriptCore.
        /// Larger blocks fall back immediately to plain text to prevent actor starvation
        /// and unbounded cache growth. Defaults to 64 KiB.
        public var maxHighlightBytes: Int

        /// Default theme is "atom-one-dark" — validated against Highlightr's bundled themes
        /// (excluding unsafe themes such as "far"). Available themes come from `Highlightr().availableThemes()`.
        public init(
            theme: String = "atom-one-dark",
            fontName: String? = nil,
            fontSize: CGFloat? = nil,
            cacheSize: Int = 128,
            maxHighlightBytes: Int = 64 * 1024
        ) {
            self.theme = theme
            self.fontName = fontName
            self.fontSize = fontSize
            self.cacheSize = max(1, cacheSize)
            self.maxHighlightBytes = max(1, maxHighlightBytes)
        }
    }

    internal static let defaultTheme = "atom-one-dark"

    /// Grammars blocked from direct selection in Swift due to known upstream
    /// ReDoS advisories in bundled highlight.js 11.11.1 (e.g. CVE-2026-133937).
    /// Note: pinned Highlightr 2.3.0 / highlight.js 11.11.1 retains internal
    /// sub-language auto-detection for multi-language grammars such as `"http"`
    /// and its own `isUndefined` fallback.
    internal static let blockedLanguages: Set<String> = ["livescript", "ls"]

    /// Highlightr 2.3.0 CSS themes whose `.hljs` background uses a named CSS color
    /// without `#` (causing Highlightr's `Theme.init` to force-unwrap `nil`).
    internal static let unsafeThemes: Set<String> = ["far"]

    /// Common Markdown code-fence aliases mapped to canonical highlight.js language names
    /// (since `hljs.listLanguages()` returns canonical names only).
    internal static let languageAliases: [String: String] = [
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
        "py": "python", "py3": "python",
        "rb": "ruby",
        "sh": "bash", "zsh": "bash",
        "yml": "yaml",
        "md": "markdown", "mkdown": "markdown", "mkd": "markdown",
        "rs": "rust",
        "kt": "kotlin", "kts": "kotlin",
        "cs": "csharp", "c#": "csharp",
        "c++": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "h++": "cpp", "hh": "cpp",
        "h": "c",
        "objc": "objectivec", "obj-c": "objectivec", "mm": "objectivec",
        "html": "xml", "htm": "xml", "xhtml": "xml", "svg": "xml", "plist": "xml", "rss": "xml",
        "docker": "dockerfile",
        "golang": "go",
        "ps": "powershell", "ps1": "powershell", "pwsh": "powershell",
        "txt": "plaintext", "text": "plaintext",
        "pl": "perl", "pm": "perl",
        "erl": "erlang",
        "ex": "elixir", "exs": "elixir",
        "hs": "haskell",
        "fs": "fsharp", "f#": "fsharp",
        "tex": "latex",
        "patch": "diff",
        "toml": "ini",
        "console": "shell",
    ]

    private let highlighter: Highlightr
    /// Immutable validated theme allowlist exposed `nonisolated` so `HighlightrPool`
    /// can read it synchronously without actor reentrancy across `await`.
    internal nonisolated let availableThemeSet: Set<String>
    /// Normalized initial theme exposed `nonisolated` for atomic `HighlightrPool` registration.
    internal nonisolated let initialTheme: String
    private let allowedLanguageSet: Set<String>
    private var configuration: Configuration
    private var cache: LRUCache<HighlightKey, AttributedString>

    public init?(configuration: Configuration = Configuration()) {
        guard let engine = Highlightr() else {
            return nil
        }
        let themes = Set(engine.availableThemes()).subtracting(Self.unsafeThemes)
        let languages = Set(engine.supportedLanguages().map { $0.lowercased() }).subtracting(Self.blockedLanguages)

        var normalizedConfig = configuration
        normalizedConfig.theme = themes.contains(configuration.theme) ? configuration.theme : Self.defaultTheme
        normalizedConfig.cacheSize = max(1, configuration.cacheSize)
        normalizedConfig.maxHighlightBytes = max(1, configuration.maxHighlightBytes)

        self.highlighter = engine
        // Prevent Highlightr from catching illegal-token JS errors and silently
        // falling back to `hljs.highlightAuto` across all ~190 bundled grammars.
        engine.ignoreIllegals = true
        self.availableThemeSet = themes
        self.initialTheme = normalizedConfig.theme
        self.allowedLanguageSet = languages
        self.configuration = normalizedConfig
        self.cache = LRUCache(capacity: normalizedConfig.cacheSize)

        // Apply validated theme and font inline (cannot call actor-isolated methods from init in Swift 6)
        _ = engine.setTheme(to: normalizedConfig.theme)
        if let fontName = normalizedConfig.fontName,
           let fontSize = normalizedConfig.fontSize,
           let font = PlatformFont(name: fontName, size: fontSize) {
            engine.theme?.setCodeFont(font)
        } else if let fontSize = normalizedConfig.fontSize {
            let monoFont = PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            engine.theme?.setCodeFont(monoFont)
        }
    }

    /// Current active (validated) theme name.
    public var currentTheme: String {
        configuration.theme
    }

    public func highlight(code: String, language: String?) async -> AttributedString {
        guard !code.isEmpty else { return AttributedString() }
        // Respect Swift structured concurrency cancellation before synchronous JSC work.
        guard !Task.isCancelled else { return AttributedString(code) }
        // Bound code size sent to JavaScriptCore and stored in the LRU cache.
        guard code.utf8.count <= configuration.maxHighlightBytes else {
            return AttributedString(code)
        }
        // Require an explicitly supported, non-blocked language to avoid both
        // CVE-2026-133937 (livescript) and slow `hljs.highlightAuto` across ~190 grammars.
        guard let rawLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawLanguage.isEmpty else {
            return AttributedString(code)
        }
        let rawLower = rawLanguage.lowercased()
        guard !Self.blockedLanguages.contains(rawLower) else {
            return AttributedString(code)
        }
        // Prefer canonical highlight.js language names before alias lookup so an alias
        // never shadows a bundled canonical grammar (e.g. "shell" = Shell Session).
        let normalizedLanguage = allowedLanguageSet.contains(rawLower)
            ? rawLower
            : (Self.languageAliases[rawLower] ?? rawLower)
        guard allowedLanguageSet.contains(normalizedLanguage) else {
            return AttributedString(code)
        }

        let key = HighlightKey(theme: configuration.theme, language: normalizedLanguage, code: code)
        if let cached = cache.value(for: key) {
            return cached
        }

        guard !Task.isCancelled else { return AttributedString(code) }

        let highlighted = highlighter.highlight(code, as: normalizedLanguage)
        let attributed: AttributedString
        if let highlighted {
            attributed = AttributedString(highlighted)
        } else {
            attributed = AttributedString(code)
        }

        if !Task.isCancelled {
            cache.insert(attributed, for: key)
        }
        return attributed
    }

    public func setTheme(_ name: String) async {
        let themeName = availableThemeSet.contains(name) ? name : Self.defaultTheme
        guard configuration.theme != themeName else { return }

        configuration.theme = themeName
        cache.removeAll()
        applyThemeAndFont()
    }

    /// Clears all cached syntax-highlighted entries from this engine.
    public func clearCache() {
        cache.removeAll()
    }

    /// Exposes the complete validated theme allowlist for `HighlightrPool`.
    internal var allAvailableThemes: Set<String> {
        availableThemeSet
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
}
