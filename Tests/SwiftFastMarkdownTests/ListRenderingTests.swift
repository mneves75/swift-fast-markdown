import XCTest
@testable import SwiftFastMarkdown

final class ListRenderingTests: XCTestCase {
    
    func testListItemsHaveContent() throws {
        let markdown = """
        Health Summary:

        Activity:
        - Steps: 8,543
        - Calories: 2,100

        Heart:
        - Rate: 72 bpm
        """
        
        let parser = MD4CParser()
        let document = try parser.parse(markdown)
        
        print("=== Document Structure ===")
        print("Source data length: \(document.sourceData.count)")
        print("Block count: \(document.blocks.count)")
        
        // Find all lists and verify their items have content
        for (index, block) in document.blocks.enumerated() {
            switch block {
            case .list(let list):
                print("[\(index)] List with \(list.items.count) items")
                for (itemIndex, item) in list.items.enumerated() {
                    XCTAssertFalse(item.blocks.isEmpty, "List item \(itemIndex) should have blocks")
                    for innerBlock in item.blocks {
                        if case .paragraph(let p) = innerBlock {
                            XCTAssertFalse(p.spans.isEmpty, "Paragraph in list item should have spans")
                            for span in p.spans {
                                if case .text(let content) = span {
                                    let text = content.string(in: document.sourceData)
                                    print("  Item[\(itemIndex)] Text: '\(text)'")
                                    XCTAssertFalse(text.isEmpty, "Text content should not be empty")
                                }
                            }
                        }
                    }
                }
            case .paragraph(let p):
                var textContent = ""
                for span in p.spans {
                    if case .text(let content) = span {
                        textContent += content.string(in: document.sourceData)
                    }
                }
                print("[\(index)] Paragraph: '\(textContent)'")
            default:
                print("[\(index)] Other block")
            }
        }
        
        // Test AttributedString rendering
        let renderer = AttributedStringRenderer()
        let attributedString = renderer.render(document, style: .default)
        let fullText = String(attributedString.characters)
        
        print("\n=== Rendered AttributedString ===")
        print(fullText)
        
        // Verify list items appear in the rendered output
        XCTAssertTrue(fullText.contains("Steps"), "Rendered text should contain 'Steps'")
        XCTAssertTrue(fullText.contains("8,543"), "Rendered text should contain '8,543'")
        XCTAssertTrue(fullText.contains("Calories"), "Rendered text should contain 'Calories'")
        XCTAssertTrue(fullText.contains("Rate"), "Rendered text should contain 'Rate'")
    }
    
    func testBoldInListItems() throws {
        let markdown = """
        - **Steps**: 8,543
        - **Calories**: 2,100
        """
        
        let parser = MD4CParser()
        let document = try parser.parse(markdown)
        
        let renderer = AttributedStringRenderer()
        let attributedString = renderer.render(document, style: .default)
        let fullText = String(attributedString.characters)
        
        print("=== Bold in List Items ===")
        print(fullText)
        
        XCTAssertTrue(fullText.contains("Steps"), "Should contain 'Steps'")
        XCTAssertTrue(fullText.contains("8,543"), "Should contain '8,543'")
    }
}
