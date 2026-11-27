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
}

/// Process-wide pool of `HighlightrEngine` instances keyed by configuration,
/// so all views sharing a theme/font share one JavaScriptCore VM and one LRU
/// highlight cache without booting JSC until a code block is actually highlighted.
private actor HighlightrPool {
    static let shared = HighlightrPool()

    private var engines: [HighlightrEngine.Configuration: any SyntaxHighlighting] = [:]

    func engine(for configuration: HighlightrEngine.Configuration) -> any SyntaxHighlighting {
        if let existing = engines[configuration] {
            return existing
        }
        let created: any SyntaxHighlighting = HighlightrEngine(configuration: configuration) ?? PlainTextHighlighter()
        engines[configuration] = created
        return created
    }
}

/// Lightweight per-view proxy: ~O(1) nanosecond init, zero JSC boot until
/// `highlight(code:language:)` is invoked, and isolated `setTheme(_:)` so
/// changing one view's theme never mutates another view's configuration.
private actor LazySharedHighlighter: SyntaxHighlighting {
    private var configuration: HighlightrEngine.Configuration
    private var cachedEngine: (any SyntaxHighlighting)?

    init(configuration: HighlightrEngine.Configuration) {
        self.configuration = configuration
    }

    func highlight(code: String, language: String?) async -> AttributedString {
        guard !code.isEmpty else { return AttributedString() }
        let engine: any SyntaxHighlighting
        if let cachedEngine {
            engine = cachedEngine
        } else {
            let resolved = await HighlightrPool.shared.engine(for: configuration)
            self.cachedEngine = resolved
            engine = resolved
        }
        return await engine.highlight(code: code, language: language)
    }

    func setTheme(_ name: String) async {
        guard configuration.theme != name else { return }
        configuration.theme = name
        cachedEngine = nil
    }
}
