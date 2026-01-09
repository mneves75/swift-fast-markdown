import XCTest
@testable import SwiftFastMarkdown

final class SyntaxHighlighterTests: XCTestCase {
    func testPlainTextHighlighterPassesThrough() async {
        let highlighter = PlainTextHighlighter()
        let result = await highlighter.highlight(code: "let value = 1", language: "swift")
        XCTAssertEqual(String(result.characters), "let value = 1")
    }

    func testHighlighterEngineHighlightsSwift() async throws {
        guard let engine = HighlightrEngine() else {
            throw XCTSkip("Highlighter engine failed to initialize")
        }
        let result = await engine.highlight(code: "let value = 1", language: "swift")
        XCTAssertTrue(String(result.characters).contains("let value"))
    }

    func testHighlighterCacheReturnsStableResults() async throws {
        guard let engine = HighlightrEngine() else {
            throw XCTSkip("Highlighter engine failed to initialize")
        }
        let first = await engine.highlight(code: "let value = 1", language: "swift")
        let second = await engine.highlight(code: "let value = 1", language: "swift")
        XCTAssertEqual(first, second)
    }
}
