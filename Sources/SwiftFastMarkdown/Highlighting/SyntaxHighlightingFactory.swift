import Foundation

public enum SyntaxHighlightingFactory {
    /// Returns a lightweight, thread-safe highlighter whose underlying
    /// JavaScriptCore / Highlightr engine is initialized lazily off the main
    /// thread on first code-block highlight and shared across views with the
    /// same configuration.
    ///
    /// Previously, each call eagerly booted a new JavaScriptCore VM (~70–350 ms
    /// and ~10+ MB RAM), which caused severe main-thread stalls whenever
    /// SwiftUI re-evaluated view initializers with default arguments.
    public static func makeDefault(
        configuration: HighlightrEngine.Configuration = .init()
    ) -> any SyntaxHighlighting {
        LazySharedHighlighter(configuration: configuration)
    }

    /// Evicts all pooled JavaScriptCore `HighlightrEngine` instances and their
    /// cached syntax-highlighted code blocks (useful on account switch, logout,
    /// or memory pressure).
    public static func clearSharedPool() async {
        await HighlightrPool.shared.clear()
    }
}

/// Bounded process-wide LRU pool of `HighlightrEngine` instances keyed by
/// validated configuration (max 4 VMs), so views sharing a theme/font share one
/// JavaScriptCore VM while preventing unbounded VM/memory growth.
private actor HighlightrPool {
    static let shared = HighlightrPool()
    private static let maxPooledEngines = 4

    private var engines = LRUCache<HighlightrEngine.Configuration, any SyntaxHighlighting>(capacity: maxPooledEngines)
    private var knownThemes: Set<String>?

    /// Synchronous actor method (no internal `await` suspension points) so
    /// `clear()` can never race with an in-flight engine insertion.
    func engine(for configuration: HighlightrEngine.Configuration) -> any SyntaxHighlighting {
        var normalized = configuration
        if let knownThemes {
            normalized.theme = knownThemes.contains(configuration.theme) ? configuration.theme : HighlightrEngine.defaultTheme
        }
        if let existing = engines.value(for: normalized) {
            return existing
        }

        if let created = HighlightrEngine(configuration: normalized) {
            if knownThemes == nil {
                knownThemes = created.availableThemeSet
            }
            normalized.theme = created.initialTheme
            // If normalization mapped an invalid theme onto an already-pooled default VM, reuse it!
            if let existingAfterNormalize = engines.value(for: normalized) {
                return existingAfterNormalize
            }
            engines.insert(created, for: normalized)
            return created
        }

        let fallback: any SyntaxHighlighting = PlainTextHighlighter()
        engines.insert(fallback, for: normalized)
        return fallback
    }

    func clear() {
        engines.removeAll()
        knownThemes = nil
    }

    /// Exposed for testing pool capacity and `clearSharedPool()` eviction.
    internal var pooledEngineCount: Int {
        engines.count
    }
}

extension SyntaxHighlightingFactory {
    /// Internal test hook exposing the current number of pooled engines.
    internal static func sharedPoolCount() async -> Int {
        await HighlightrPool.shared.pooledEngineCount
    }
}

/// Lightweight per-view proxy: ~O(1) nanosecond init, zero JSC boot until
/// `highlight(code:language:)` is invoked, and isolated `setTheme(_:)` so
/// changing one view's theme never mutates another view's configuration.
/// Intentionally holds no strong engine reference so `clearSharedPool()` and
/// pool LRU eviction immediately release unused JavaScriptCore VMs.
private actor LazySharedHighlighter: SyntaxHighlighting {
    private var configuration: HighlightrEngine.Configuration

    init(configuration: HighlightrEngine.Configuration) {
        self.configuration = configuration
    }

    func highlight(code: String, language: String?) async -> AttributedString {
        guard !code.isEmpty else { return AttributedString() }
        guard !Task.isCancelled else { return AttributedString(code) }
        let engine = await HighlightrPool.shared.engine(for: configuration)
        guard !Task.isCancelled else { return AttributedString(code) }
        return await engine.highlight(code: code, language: language)
    }

    func setTheme(_ name: String) async {
        guard configuration.theme != name else { return }
        configuration.theme = name
    }
}
