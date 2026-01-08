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

    func testParsesTaskList() throws {
        let input = "- [x] Done\n- [ ] Todo"
        let document = try MarkdownParser().parse(input)
        XCTAssertEqual(document.blocks.count, 1)
        guard case .list(let list) = document.blocks[0] else {
            return XCTFail("Expected list block")
        }
        XCTAssertEqual(list.items.count, 2)
        XCTAssertTrue(list.items[0].isTask)
        XCTAssertTrue(list.items[0].isChecked)
        XCTAssertTrue(list.items[1].isTask)
        XCTAssertFalse(list.items[1].isChecked)
    }

    func testParsesTable() throws {
        let input = "| a | b |\n| - | - |\n| c | d |"
        let document = try MarkdownParser().parse(input)
        XCTAssertEqual(document.blocks.count, 1)
        guard case .table(let table) = document.blocks[0] else {
            return XCTFail("Expected table block")
        }
        XCTAssertEqual(table.headerRows.count, 1)
        XCTAssertEqual(table.bodyRows.count, 1)
        XCTAssertEqual(table.headerRows[0].cells.count, 2)
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
