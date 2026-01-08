import XCTest
@testable import SwiftFastMarkdown

final class IncrementalParserTests: XCTestCase {

    // MARK: - Basic Functionality

    func testEmptyContent() {
        let parser = IncrementalMarkdownParser()
        let doc = parser.append("")
        XCTAssertTrue(doc.blocks.isEmpty)
    }

    func testSingleParagraph() {
        let parser = IncrementalMarkdownParser()
        let doc = parser.append("Hello world")
        let finalDoc = parser.finalize()

        XCTAssertEqual(finalDoc.blocks.count, 1)
        if case .paragraph = finalDoc.blocks[0] {
            // Success
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testMultipleParagraphs() {
        let parser = IncrementalMarkdownParser()
        _ = parser.append("First paragraph.\n\nSecond paragraph.")
        let doc = parser.finalize()

        XCTAssertEqual(doc.blocks.count, 2)
    }

    // MARK: - Streaming Correctness

    func testIncrementalEqualsFullParse() throws {
        let fullContent = """
        # Heading

        This is a paragraph with **bold** and *italic* text.

        - Item 1
        - Item 2
        - Item 3

        ```swift
        let x = 42
        ```

        Another paragraph.
        """

        // Full parse
        let fullDoc = try MarkdownParser().parse(fullContent)

        // Incremental parse with various chunk sizes
        let parser = IncrementalMarkdownParser()

        // Simulate streaming with different chunk sizes
        var offset = 0
        let chunkSizes = [5, 10, 3, 20, 15, 8, 100]
        var chunkIndex = 0

        while offset < fullContent.count {
            let chunkSize = chunkSizes[chunkIndex % chunkSizes.count]
            let endIndex = min(offset + chunkSize, fullContent.count)
            let startIdx = fullContent.index(fullContent.startIndex, offsetBy: offset)
            let endIdx = fullContent.index(fullContent.startIndex, offsetBy: endIndex)
            let chunk = String(fullContent[startIdx..<endIdx])

            _ = parser.append(chunk)
            offset = endIndex
            chunkIndex += 1
        }

        let incrementalDoc = parser.finalize()

        // Verify same number of blocks
        XCTAssertEqual(fullDoc.blocks.count, incrementalDoc.blocks.count,
                       "Block count mismatch: full=\(fullDoc.blocks.count), incremental=\(incrementalDoc.blocks.count)")

        // Verify block types match
        for (index, (fullBlock, incBlock)) in zip(fullDoc.blocks, incrementalDoc.blocks).enumerated() {
            XCTAssertTrue(blocksHaveSameType(fullBlock, incBlock),
                          "Block type mismatch at index \(index)")
        }
    }

    func testChunkedHeading() {
        let parser = IncrementalMarkdownParser()

        // Send heading character by character
        _ = parser.append("#")
        _ = parser.append(" ")
        _ = parser.append("H")
        _ = parser.append("e")
        _ = parser.append("l")
        _ = parser.append("l")
        _ = parser.append("o")
        _ = parser.append("\n")
        let doc = parser.finalize()

        XCTAssertEqual(doc.blocks.count, 1)
        if case .heading(let h) = doc.blocks[0] {
            XCTAssertEqual(h.level, 1)
        } else {
            XCTFail("Expected heading")
        }
    }

    func testFencedCodeBlockStreaming() {
        let parser = IncrementalMarkdownParser()

        _ = parser.append("```swift\n")
        var doc = parser.append("let x = 1\n")

        // Code block should not be finalized yet (no closing fence)
        // The parser should have pending content

        _ = parser.append("let y = 2\n")
        _ = parser.append("```\n")
        doc = parser.finalize()

        XCTAssertEqual(doc.blocks.count, 1)
        if case .codeBlock(let code) = doc.blocks[0] {
            let content = code.content.string(in: doc.sourceData)
            XCTAssertTrue(content.contains("let x = 1"))
            XCTAssertTrue(content.contains("let y = 2"))
        } else {
            XCTFail("Expected code block")
        }
    }

    // MARK: - Reset Behavior

    func testResetClearsState() {
        let parser = IncrementalMarkdownParser()
        _ = parser.append("Some content\n\nMore content")
        _ = parser.finalize()

        XCTAssertGreaterThan(parser.stableBlockCount, 0)

        parser.reset()

        XCTAssertEqual(parser.stableBlockCount, 0)
        XCTAssertTrue(parser.pendingContent.isEmpty)
    }

    // MARK: - Edge Cases

    func testEmptyLines() {
        let parser = IncrementalMarkdownParser()
        _ = parser.append("\n\n\n")
        let doc = parser.finalize()

        // Empty lines should produce no blocks
        XCTAssertTrue(doc.blocks.isEmpty)
    }

    func testOnlyWhitespace() {
        let parser = IncrementalMarkdownParser()
        _ = parser.append("   \t  \n  \t\t  ")
        let doc = parser.finalize()

        XCTAssertTrue(doc.blocks.isEmpty)
    }

    func testNestedBlockQuote() throws {
        let content = "> Level 1\n> > Level 2\n> > > Level 3"
        let parser = IncrementalMarkdownParser()
        _ = parser.append(content)
        let doc = parser.finalize()

        // Should have at least one block quote
        XCTAssertEqual(doc.blocks.count, 1)
        if case .blockQuote = doc.blocks[0] {
            // Success
        } else {
            XCTFail("Expected block quote")
        }
    }

    // MARK: - Helpers

    private func blocksHaveSameType(_ a: MarkdownBlock, _ b: MarkdownBlock) -> Bool {
        switch (a, b) {
        case (.paragraph, .paragraph),
             (.heading, .heading),
             (.codeBlock, .codeBlock),
             (.blockQuote, .blockQuote),
             (.list, .list),
             (.table, .table),
             (.thematicBreak, .thematicBreak),
             (.htmlBlock, .htmlBlock):
            return true
        default:
            return false
        }
    }
}
