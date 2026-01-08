import Foundation

public enum SwiftFastMarkdown {
    public static func parse(_ input: String, options: ParseOptions = .default) throws -> MarkdownDocument {
        try MarkdownParser().parse(input, options: options)
    }

    public static func parse(_ data: Data, options: ParseOptions = .default) throws -> MarkdownDocument {
        try MarkdownParser().parse(data, options: options)
    }
}
