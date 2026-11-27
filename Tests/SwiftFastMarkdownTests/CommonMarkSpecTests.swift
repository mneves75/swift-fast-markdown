import XCTest
@testable import SwiftFastMarkdown

/// Tests based on CommonMark 0.31 specification.
/// These tests verify core markdown parsing behavior.
final class CommonMarkSpecTests: XCTestCase {

    private var parser: MarkdownParser!

    override func setUp() {
        super.setUp()
        parser = MarkdownParser()
    }

    // MARK: - ATX Headings (Section 4.2)

    func testATXHeadingLevel1() throws {
        let doc = try parser.parse("# foo")
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .heading(let h) = doc.blocks[0] else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(h.level, 1)
    }

    func testATXHeadingLevel6() throws {
        let doc = try parser.parse("###### foo")
        guard case .heading(let h) = doc.blocks[0] else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(h.level, 6)
    }

    func testATXHeadingMoreThan6IsNotHeading() throws {
        let doc = try parser.parse("####### foo")
        // Should be a paragraph, not a heading
        guard case .paragraph = doc.blocks[0] else {
            return XCTFail("Expected paragraph for 7 hashes")
        }
    }

    func testATXHeadingRequiresSpace() throws {
        let doc = try parser.parse("#foo", options: .commonMark)
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .paragraph = doc.blocks[0] else {
            return XCTFail("Expected paragraph when ATX heading lacks separating space under CommonMark")
        }
    }

    // MARK: - Paragraphs (Section 4.8)

    func testSimpleParagraph() throws {
        let doc = try parser.parse("aaa\n\nbbb")
        XCTAssertEqual(doc.blocks.count, 2)
        guard case .paragraph = doc.blocks[0],
              case .paragraph = doc.blocks[1] else {
            return XCTFail("Expected two paragraphs")
        }
    }

    func testParagraphWithLineBreak() throws {
        let doc = try parser.parse("aaa\nbbb")
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        // Should have text and a soft break
        XCTAssertGreaterThan(p.spans.count, 1)
    }

    // MARK: - Emphasis and Strong (Section 6.4)

    func testSingleAsteriskEmphasis() throws {
        let doc = try parser.parse("*foo*")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .emphasis(let children) = p.spans[0] else {
            return XCTFail("Expected emphasis span")
        }
        if case .text(let content) = children[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "foo")
        }
    }

    func testDoubleAsteriskStrong() throws {
        let doc = try parser.parse("**foo**")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .strong(let children) = p.spans[0] else {
            return XCTFail("Expected strong span")
        }
        if case .text(let content) = children[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "foo")
        }
    }

    func testUnderscoreEmphasis() throws {
        let doc = try parser.parse("_foo_")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .emphasis = p.spans[0] else {
            return XCTFail("Expected emphasis span")
        }
    }

    func testNestedEmphasis() throws {
        let doc = try parser.parse("***foo***")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        let innerText: String?
        switch p.spans.first {
        case .emphasis(let children):
            if case .strong(let inner) = children.first, case .text(let t) = inner.first {
                innerText = t.string(in: doc.sourceData)
            } else { innerText = nil }
        case .strong(let children):
            if case .emphasis(let inner) = children.first, case .text(let t) = inner.first {
                innerText = t.string(in: doc.sourceData)
            } else { innerText = nil }
        default:
            innerText = nil
        }
        XCTAssertEqual(innerText, "foo")
    }

    // MARK: - Code Spans (Section 6.3)

    func testInlineCode() throws {
        let doc = try parser.parse("`foo`")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .code(let content) = p.spans[0] else {
            return XCTFail("Expected code span")
        }
        XCTAssertEqual(content.string(in: doc.sourceData), "foo")
    }

    func testInlineCodeWithBackticks() throws {
        let doc = try parser.parse("`` `foo` ``")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .code(let content) = p.spans[0] else {
            return XCTFail("Expected code span")
        }
        XCTAssertTrue(content.string(in: doc.sourceData).contains("`foo`"))
    }

    // MARK: - Fenced Code Blocks (Section 4.5)

    func testFencedCodeBlockWithBackticks() throws {
        let doc = try parser.parse("```\nfoo\n```")
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .codeBlock(let code) = doc.blocks[0] else {
            return XCTFail("Expected code block")
        }
        XCTAssertEqual(code.fence, "`")
    }

    func testFencedCodeBlockWithTildes() throws {
        let doc = try parser.parse("~~~\nfoo\n~~~")
        guard case .codeBlock(let code) = doc.blocks[0] else {
            return XCTFail("Expected code block")
        }
        XCTAssertEqual(code.fence, "~")
    }

    // MARK: - Links (Section 6.5)

    func testInlineLink() throws {
        let doc = try parser.parse("[link](/uri)")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .link(let children, let dest, _) = p.spans[0] else {
            return XCTFail("Expected link span")
        }
        XCTAssertEqual(dest?.string(in: doc.sourceData), "/uri")
        if case .text(let content) = children[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "link")
        }
    }

    func testInlineLinkWithTitle() throws {
        let doc = try parser.parse("[link](/uri \"title\")")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .link(_, let dest, let title) = p.spans[0] else {
            return XCTFail("Expected link span")
        }
        XCTAssertEqual(dest?.string(in: doc.sourceData), "/uri")
        XCTAssertEqual(title?.string(in: doc.sourceData), "title")
    }

    // MARK: - Images (Section 6.6)

    func testInlineImage() throws {
        let doc = try parser.parse("![foo](/url)")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        guard case .image(let alt, let src, _) = p.spans[0] else {
            return XCTFail("Expected image span")
        }
        XCTAssertEqual(src?.string(in: doc.sourceData), "/url")
        if case .text(let content) = alt[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "foo")
        }
    }

    // MARK: - Block Quotes (Section 5.1)

    func testBlockQuote() throws {
        let doc = try parser.parse("> foo")
        XCTAssertEqual(doc.blocks.count, 1)
        guard case .blockQuote(let quote) = doc.blocks[0] else {
            return XCTFail("Expected block quote")
        }
        XCTAssertEqual(quote.blocks.count, 1)
    }

    func testNestedBlockQuotes() throws {
        let doc = try parser.parse("> > foo")
        guard case .blockQuote(let outer) = doc.blocks[0] else {
            return XCTFail("Expected outer block quote")
        }
        guard case .blockQuote = outer.blocks[0] else {
            return XCTFail("Expected inner block quote")
        }
    }

    // MARK: - Lists (Section 5.2, 5.3)

    func testUnorderedList() throws {
        let doc = try parser.parse("- foo\n- bar")
        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list")
        }
        XCTAssertFalse(list.ordered)
        XCTAssertEqual(list.items.count, 2)
    }

    func testOrderedList() throws {
        let doc = try parser.parse("1. foo\n2. bar")
        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list")
        }
        XCTAssertTrue(list.ordered)
        XCTAssertEqual(list.start, 1)
        XCTAssertEqual(list.items.count, 2)
    }

    func testOrderedListStartingAt3() throws {
        let doc = try parser.parse("3. foo\n4. bar")
        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list")
        }
        XCTAssertEqual(list.start, 3)
    }

    func testNestedLists() throws {
        let doc = try parser.parse("- foo\n  - bar\n  - baz")
        guard case .list(let outer) = doc.blocks[0] else {
            return XCTFail("Expected list")
        }
        let firstItem = outer.items[0]
        let hasNestedList = firstItem.blocks.contains { block in
            if case .list(let inner) = block { return inner.items.count == 2 }
            return false
        }
        XCTAssertTrue(hasNestedList, "Expected nested 2-item list inside first list item")
    }

    // MARK: - Thematic Breaks (Section 4.1)

    func testThematicBreakDashes() throws {
        let doc = try parser.parse("---")
        guard case .thematicBreak = doc.blocks[0] else {
            return XCTFail("Expected thematic break")
        }
    }

    func testThematicBreakAsterisks() throws {
        let doc = try parser.parse("***")
        guard case .thematicBreak = doc.blocks[0] else {
            return XCTFail("Expected thematic break")
        }
    }

    func testThematicBreakUnderscores() throws {
        let doc = try parser.parse("___")
        guard case .thematicBreak = doc.blocks[0] else {
            return XCTFail("Expected thematic break")
        }
    }

    // MARK: - Hard Line Breaks (Section 6.7)

    func testHardLineBreakWithSpaces() throws {
        let doc = try parser.parse("foo  \nbar")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        let hasLineBreak = p.spans.contains { span in
            if case .lineBreak = span { return true }
            return false
        }
        XCTAssertTrue(hasLineBreak)
    }

    func testHardLineBreakWithBackslash() throws {
        let doc = try parser.parse("foo\\\nbar")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        let hasLineBreak = p.spans.contains { span in
            if case .lineBreak = span { return true }
            return false
        }
        XCTAssertTrue(hasLineBreak)
    }

    // MARK: - HTML Entities (Section 6.2)

    func testNamedEntity() throws {
        let doc = try parser.parse("&amp;")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        if case .text(let content) = p.spans[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "&")
        }
    }

    func testNumericEntity() throws {
        let doc = try parser.parse("&#38;")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        if case .text(let content) = p.spans[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "&")
        }
    }

    func testHexEntity() throws {
        let doc = try parser.parse("&#x26;")
        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }
        if case .text(let content) = p.spans[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "&")
        }
    }
}
