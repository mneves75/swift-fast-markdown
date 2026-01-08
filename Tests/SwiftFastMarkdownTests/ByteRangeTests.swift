import XCTest
@testable import SwiftFastMarkdown

/// Tests for ByteRange and zero-copy string extraction.
final class ByteRangeTests: XCTestCase {

    // MARK: - ByteRange Basic Operations

    func testByteRangeEquality() {
        let a = ByteRange(start: 0, end: 10)
        let b = ByteRange(start: 0, end: 10)
        let c = ByteRange(start: 0, end: 11)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testByteRangeIsEmpty() {
        let empty = ByteRange(start: 5, end: 5)
        let nonEmpty = ByteRange(start: 5, end: 10)

        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(nonEmpty.isEmpty)
    }

    func testByteRangeLength() {
        let range = ByteRange(start: 10, end: 25)
        XCTAssertEqual(range.length, 15 as UInt32)
    }

    // MARK: - String Extraction

    func testStringExtractionFromData() {
        let data = Data("Hello, World!".utf8)
        let range = ByteRange(start: 0, end: 5)

        XCTAssertEqual(range.string(in: data), "Hello")
    }

    func testStringExtractionMiddle() {
        let data = Data("Hello, World!".utf8)
        let range = ByteRange(start: 7, end: 12)

        XCTAssertEqual(range.string(in: data), "World")
    }

    func testStringExtractionEmptyRange() {
        let data = Data("Hello".utf8)
        let range = ByteRange(start: 2, end: 2)

        XCTAssertEqual(range.string(in: data), "")
    }

    func testStringExtractionOutOfBounds() {
        let data = Data("Hello".utf8)
        let range = ByteRange(start: 0, end: 100)

        // Should handle gracefully (empty or truncated)
        let result = range.string(in: data)
        XCTAssertTrue(result.isEmpty || result.count <= 5)
    }

    func testStringExtractionUnicode() {
        let data = Data("Hello 🌍 World".utf8)
        let range = ByteRange(start: 0, end: UInt32(data.count))

        let result = range.string(in: data)
        XCTAssertTrue(result.contains("🌍"))
    }

    // MARK: - ByteRangeSequence

    func testByteRangeSequenceEmpty() {
        let seq = ByteRangeSequence([])
        let data = Data("Hello".utf8)

        XCTAssertEqual(seq.string(in: data), "")
    }

    func testByteRangeSequenceSingleRange() {
        let seq = ByteRangeSequence([ByteRange(start: 0, end: 5)])
        let data = Data("Hello World".utf8)

        XCTAssertEqual(seq.string(in: data), "Hello")
    }

    func testByteRangeSequenceMultipleRanges() {
        // "Hello World"
        //  01234 56789A
        let seq = ByteRangeSequence([
            ByteRange(start: 0, end: 5),   // "Hello"
            ByteRange(start: 6, end: 11)   // "World"
        ])
        let data = Data("Hello World".utf8)

        XCTAssertEqual(seq.string(in: data), "HelloWorld")
    }

    // MARK: - TextContent

    func testTextContentBytes() {
        let data = Data("Hello".utf8)
        let content = TextContent.bytes(ByteRange(start: 0, end: 5))

        XCTAssertEqual(content.string(in: data), "Hello")
    }

    func testTextContentString() {
        let data = Data("Ignored".utf8)
        let content = TextContent.string("Direct string")

        // String variant ignores data
        XCTAssertEqual(content.string(in: data), "Direct string")
    }

    func testTextContentSequence() {
        let data = Data("ABCDEFGHIJ".utf8)
        let seq = ByteRangeSequence([
            ByteRange(start: 0, end: 3),   // "ABC"
            ByteRange(start: 5, end: 8)    // "FGH"
        ])
        let content = TextContent.sequence(seq)

        XCTAssertEqual(content.string(in: data), "ABCFGH")
    }

    // MARK: - Stable ID Tests

    func testBlockIDUniqueness() {
        let id1 = BlockID(kind: 1, start: 0, end: 10, ordinal: 1)
        let id2 = BlockID(kind: 1, start: 0, end: 10, ordinal: 2)
        let id3 = BlockID(kind: 1, start: 0, end: 10, ordinal: 1)

        XCTAssertNotEqual(id1, id2) // Different ordinal
        XCTAssertEqual(id1, id3)    // Same values
    }

    func testBlockIDHashable() {
        let id1 = BlockID(kind: 1, start: 0, end: 10, ordinal: 1)
        let id2 = BlockID(kind: 1, start: 0, end: 10, ordinal: 1)

        var set = Set<BlockID>()
        set.insert(id1)
        set.insert(id2)

        XCTAssertEqual(set.count, 1) // Same ID should not duplicate
    }

    // MARK: - Parser Integration

    func testParsedBlocksHaveValidRanges() throws {
        let input = "# Heading\n\nParagraph with **bold** text."
        let doc = try MarkdownParser().parse(input)

        for block in doc.blocks {
            validateBlockRanges(block, sourceLength: UInt32(doc.sourceData.count))
        }
    }

    func testParsedSpansHaveValidRanges() throws {
        let input = "Text with *emphasis* and `code` inside."
        let doc = try MarkdownParser().parse(input)

        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }

        for span in p.spans {
            validateSpanRanges(span, source: doc.sourceData)
        }
    }

    // MARK: - Helpers

    private func validateBlockRanges(_ block: MarkdownBlock, sourceLength: UInt32) {
        switch block {
        case .paragraph(let p):
            if !p.range.isEmpty {
                XCTAssertLessThanOrEqual(p.range.end, sourceLength)
            }
        case .heading(let h):
            if !h.range.isEmpty {
                XCTAssertLessThanOrEqual(h.range.end, sourceLength)
            }
        case .blockQuote(let q):
            for child in q.blocks {
                validateBlockRanges(child, sourceLength: sourceLength)
            }
        case .list(let l):
            for item in l.items {
                for child in item.blocks {
                    validateBlockRanges(child, sourceLength: sourceLength)
                }
            }
        default:
            break
        }
    }

    private func validateSpanRanges(_ span: MarkdownSpan, source: Data) {
        switch span {
        case .text(let content):
            // Extracting string should not crash
            _ = content.string(in: source)
        case .code(let content):
            _ = content.string(in: source)
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            for child in children {
                validateSpanRanges(child, source: source)
            }
        case .link(let children, let dest, let title):
            for child in children {
                validateSpanRanges(child, source: source)
            }
            if let dest { _ = dest.string(in: source) }
            if let title { _ = title.string(in: source) }
        default:
            break
        }
    }
}
