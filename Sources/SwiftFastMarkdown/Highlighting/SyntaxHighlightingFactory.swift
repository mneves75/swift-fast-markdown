import Foundation

public enum SyntaxHighlightingFactory {
    public static func makeDefault(configuration: HighlighterSwiftEngine.Configuration = .init()) -> any SyntaxHighlighting {
        if let engine = HighlighterSwiftEngine(configuration: configuration) {
            return engine
        }
        return PlainTextHighlighter()
    }
}
