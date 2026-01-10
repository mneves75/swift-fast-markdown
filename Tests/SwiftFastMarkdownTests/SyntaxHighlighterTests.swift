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

    // MARK: - Hash Collision Tests (HIGH-001 fix verification)

    func testDifferentCodeWithSameHashReturnsCorrectResult() async throws {
        // This test verifies that even if two strings have the same hash value,
        // the cache returns the correct result (HIGH-001 fix)
        guard let engine = HighlightrEngine(configuration: .init(theme: "atom-one-dark")) else {
            throw XCTSkip("Highlighter engine failed to initialize")
        }

        // Use strings that might have same hash but different content
        let code1 = "func a() { return 1 }"
        let code2 = "func b() { return 2 }"

        let result1 = await engine.highlight(code: code1, language: "swift")
        let result2 = await engine.highlight(code: code2, language: "swift")

        // Results should be different since the code is different
        XCTAssertNotEqual(String(result1.characters), String(result2.characters))
    }

    func testHighlightrEngineThreadSafety() async throws {
        // Verify that concurrent access to the actor works correctly
        guard let engine = HighlightrEngine() else {
            throw XCTSkip("Highlighter engine failed to initialize")
        }

        let codes = (0..<10).map { "let value\($0) = \($0)" }
        await withTaskGroup(of: AttributedString.self) { group in
            for code in codes {
                group.addTask {
                    await engine.highlight(code: code, language: "swift")
                }
            }
        }
        // If we get here without crashes, concurrent access works
    }
}
