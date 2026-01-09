import Foundation

public enum SyntaxHighlightingFactory {
    public static func makeDefault(configuration: HighlightrEngine.Configuration = .init()) -> any SyntaxHighlighting {
        if let engine = HighlightrEngine(configuration: configuration) {
            return engine
        }
        return PlainTextHighlighter()
    }
}
