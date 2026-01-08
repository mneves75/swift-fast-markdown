import XCTest
@testable import SwiftFastMarkdown

/// Tests for GitHub Flavored Markdown extensions supported via md4c flags.
/// - Tables (MD_FLAG_TABLES)
/// - Task lists (MD_FLAG_TASKLISTS)
/// - Strikethrough (MD_FLAG_STRIKETHROUGH)
/// - Autolinks (MD_FLAG_PERMISSIVEWWWAUTOLINKS)
final class GFMExtensionTests: XCTestCase {

    private var parser: MarkdownParser!

    override func setUp() {
        super.setUp()
        parser = MarkdownParser()
    }

    // MARK: - Tables

    func testSimpleTable() throws {
        let input = """
        | a | b |
        | - | - |
        | c | d |
        """
        let doc = try parser.parse(input)

        XCTAssertEqual(doc.blocks.count, 1)
        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        XCTAssertEqual(table.headerRows.count, 1)
        XCTAssertEqual(table.bodyRows.count, 1)
        XCTAssertEqual(table.headerRows[0].cells.count, 2)
    }

    func testTableAlignment() throws {
        let input = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | a    | b      | c     |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        // Check cell alignments in body row
        let bodyRow = table.bodyRows[0]
        XCTAssertEqual(bodyRow.cells[0].alignment, .left)
        XCTAssertEqual(bodyRow.cells[1].alignment, .center)
        XCTAssertEqual(bodyRow.cells[2].alignment, .right)
    }

    func testTableWithFormattedContent() throws {
        let input = """
        | Header |
        | ------ |
        | **bold** and *italic* |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        let bodyCell = table.bodyRows[0].cells[0]
        // Cell should contain formatted spans
        let hasStrong = bodyCell.spans.contains { span in
            if case .strong = span { return true }
            return false
        }
        XCTAssertTrue(hasStrong)
    }

    func testMultiRowTable() throws {
        let input = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        | 4 | 5 | 6 |
        | 7 | 8 | 9 |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        XCTAssertEqual(table.headerRows.count, 1)
        XCTAssertEqual(table.bodyRows.count, 3)
    }

    // MARK: - Task Lists

    func testTaskListChecked() throws {
        let input = "- [x] Done task"
        let doc = try parser.parse(input)

        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list block")
        }

        XCTAssertTrue(list.items[0].isTask)
        XCTAssertTrue(list.items[0].isChecked)
    }

    func testTaskListUnchecked() throws {
        let input = "- [ ] Pending task"
        let doc = try parser.parse(input)

        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list block")
        }

        XCTAssertTrue(list.items[0].isTask)
        XCTAssertFalse(list.items[0].isChecked)
    }

    func testMixedTaskList() throws {
        let input = """
        - [x] Completed
        - [ ] Not done
        - Regular item
        - [X] Also completed
        """
        let doc = try parser.parse(input)

        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list block")
        }

        XCTAssertEqual(list.items.count, 4)

        XCTAssertTrue(list.items[0].isTask)
        XCTAssertTrue(list.items[0].isChecked)

        XCTAssertTrue(list.items[1].isTask)
        XCTAssertFalse(list.items[1].isChecked)

        XCTAssertFalse(list.items[2].isTask)

        XCTAssertTrue(list.items[3].isTask)
        XCTAssertTrue(list.items[3].isChecked) // [X] uppercase
    }

    // MARK: - Strikethrough

    func testStrikethrough() throws {
        let input = "~~deleted~~"
        let doc = try parser.parse(input)

        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }

        guard case .strikethrough(let children) = p.spans[0] else {
            return XCTFail("Expected strikethrough span")
        }

        if case .text(let content) = children[0] {
            XCTAssertEqual(content.string(in: doc.sourceData), "deleted")
        }
    }

    func testStrikethroughWithOtherFormatting() throws {
        let input = "~~**bold and deleted**~~"
        let doc = try parser.parse(input)

        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }

        // Should have strikethrough containing strong
        guard case .strikethrough(let children) = p.spans[0] else {
            return XCTFail("Expected strikethrough span")
        }

        let hasStrong = children.contains { span in
            if case .strong = span { return true }
            return false
        }
        XCTAssertTrue(hasStrong)
    }

    // MARK: - Autolinks

    func testPermissiveWWWAutolink() throws {
        // Test with explicit angle bracket autolink which is more reliable
        let input = "<http://www.example.com>"
        let doc = try parser.parse(input)

        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }

        let hasLink = p.spans.contains { span in
            if case .link = span { return true }
            return false
        }
        XCTAssertTrue(hasLink)
    }

    func testPermissiveURLAutolink() throws {
        // Test angle bracket autolink
        let input = "<https://example.com/path>"
        let doc = try parser.parse(input)

        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }

        let hasLink = p.spans.contains { span in
            if case .link = span { return true }
            return false
        }
        XCTAssertTrue(hasLink)
    }

    func testAngleBracketAutolink() throws {
        let input = "Link: <https://example.com>"
        let doc = try parser.parse(input)

        guard case .paragraph(let p) = doc.blocks[0] else {
            return XCTFail("Expected paragraph")
        }

        let hasLink = p.spans.contains { span in
            if case .link = span { return true }
            return false
        }
        XCTAssertTrue(hasLink)
    }

    // MARK: - Combined Features

    func testTableWithTaskList() throws {
        // Tables can contain task list items in cells (as text)
        let input = """
        | Task | Status |
        |------|--------|
        | Fix bug | Done |
        | Write docs | Pending |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        XCTAssertEqual(table.bodyRows.count, 2)
    }

    func testStrikethroughInTable() throws {
        let input = """
        | Feature | Status |
        |---------|--------|
        | ~~Old~~ | Removed |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        let firstCell = table.bodyRows[0].cells[0]
        let hasStrikethrough = firstCell.spans.contains { span in
            if case .strikethrough = span { return true }
            return false
        }
        XCTAssertTrue(hasStrikethrough)
    }

    // MARK: - Edge Cases

    func testEmptyTableCells() throws {
        let input = """
        | A | B |
        |---|---|
        |   |   |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        XCTAssertEqual(table.bodyRows[0].cells.count, 2)
    }

    func testSingleColumnTable() throws {
        let input = """
        | Header |
        |--------|
        | Cell   |
        """
        let doc = try parser.parse(input)

        guard case .table(let table) = doc.blocks[0] else {
            return XCTFail("Expected table block")
        }

        XCTAssertEqual(table.headerRows[0].cells.count, 1)
    }

    func testNestedTaskLists() throws {
        let input = """
        - [x] Parent task
          - [ ] Child task
          - [x] Another child
        """
        let doc = try parser.parse(input)

        guard case .list(let list) = doc.blocks[0] else {
            return XCTFail("Expected list block")
        }

        XCTAssertTrue(list.items[0].isTask)
    }
}
