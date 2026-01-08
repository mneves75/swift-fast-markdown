import Foundation

public protocol SyntaxHighlighting: Sendable {
    func highlight(code: String, language: String?) async -> AttributedString
    func setTheme(_ name: String) async
}

public struct PlainTextHighlighter: SyntaxHighlighting {
    public init() {}

    public func highlight(code: String, language: String?) async -> AttributedString {
        AttributedString(code)
    }

    public func setTheme(_ name: String) async {
        // No-op for plain text highlighter.
    }
}
