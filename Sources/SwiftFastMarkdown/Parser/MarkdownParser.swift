import Foundation

public struct MarkdownParser {
    private let parser: MD4CParser

    public init(parser: MD4CParser = MD4CParser()) {
        self.parser = parser
    }

    public func parse(_ input: String, options: ParseOptions = .default) throws -> MarkdownDocument {
        try parser.parse(input, options: options)
    }

    public func parse(_ data: Data, options: ParseOptions = .default) throws -> MarkdownDocument {
        try parser.parse(data, options: options)
    }
}
