import XCTest
@testable import SwiftFastMarkdown

final class ParserTests: XCTestCase {
    func testParsesHeadingAndEmphasis() throws {
        let input = "# Hello *world*"
        let document = try MarkdownParser().parse(input)
        XCTAssertEqual(document.blocks.count, 1)
        guard case .heading(let heading) = document.blocks[0] else {
            return XCTFail("Expected heading block")
        }
        XCTAssertEqual(heading.level, 1)
        XCTAssertEqual(heading.spans.count, 2)
        guard case .text(let firstText) = heading.spans[0] else {
            return XCTFail("Expected leading text span")
        }
        XCTAssertEqual(firstText.string(in: document.sourceData), "Hello ")
        guard case .emphasis(let emphasisSpans) = heading.spans[1] else {
            return XCTFail("Expected emphasis span")
        }
        XCTAssertEqual(emphasisSpans.count, 1)
        if case .text(let innerText) = emphasisSpans[0] {
            XCTAssertEqual(innerText.string(in: document.sourceData), "world")
        } else {
            XCTFail("Expected emphasis text")
        }
    }

    func testParsesCodeBlockLanguage() throws {
        let input = "```swift\nlet value = 1\n```"
        let document = try MarkdownParser().parse(input)
        XCTAssertEqual(document.blocks.count, 1)
        guard case .codeBlock(let block) = document.blocks[0] else {
            return XCTFail("Expected code block")
        }
        let language = block.language?.string(in: document.sourceData)
        XCTAssertEqual(language, "swift")
        let content = block.content.string(in: document.sourceData)
        XCTAssertTrue(content.contains("let value = 1"))
    }

    func testDecodesEntitiesInText() throws {
        let input = "Fish &amp; Chips"
        let document = try MarkdownParser().parse(input)
        XCTAssertEqual(document.blocks.count, 1)
        guard case .paragraph(let paragraph) = document.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        let text = paragraph.spans.compactMap { span -> String? in
            if case .text(let content) = span {
                return content.string(in: document.sourceData)
            }
            return nil
        }.joined()
        XCTAssertEqual(text, "Fish & Chips")
    }
}
