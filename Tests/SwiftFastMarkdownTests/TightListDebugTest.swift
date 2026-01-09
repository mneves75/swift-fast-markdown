import XCTest
@testable import SwiftFastMarkdown

final class TightListDebugTest: XCTestCase {
    
    func testTightVsLooseList() throws {
        // Tight list (no blank lines between items)
        let tightMarkdown = """
        - Item 1
        - Item 2
        """
        
        // Loose list (blank lines between items)
        let looseMarkdown = """
        - Item 1

        - Item 2
        """
        
        let parser = MD4CParser()
        
        print("=== TIGHT LIST (no blank lines) ===")
        let tightDoc = try parser.parse(tightMarkdown)
        printDocument(tightDoc)
        
        print("\n=== LOOSE LIST (blank lines) ===")
        let looseDoc = try parser.parse(looseMarkdown)
        printDocument(looseDoc)
        
        // Verify tight list has content
        if case .list(let tightList) = tightDoc.blocks.first {
            for item in tightList.items {
                XCTAssertFalse(item.blocks.isEmpty, "Tight list item should have blocks")
            }
        }
    }
    
    private func printDocument(_ doc: MarkdownDocument) {
        for (i, block) in doc.blocks.enumerated() {
            switch block {
            case .list(let list):
                print("[\(i)] List (tight: \(list.isTight), items: \(list.items.count))")
                for (j, item) in list.items.enumerated() {
                    print("  Item[\(j)]: blocks=\(item.blocks.count)")
                    for innerBlock in item.blocks {
                        if case .paragraph(let p) = innerBlock {
                            var text = ""
                            for span in p.spans {
                                if case .text(let content) = span {
                                    text += content.string(in: doc.sourceData)
                                }
                            }
                            print("    Paragraph: '\(text)'")
                        }
                    }
                }
            case .paragraph(let p):
                var text = ""
                for span in p.spans {
                    if case .text(let content) = span {
                        text += content.string(in: doc.sourceData)
                    }
                }
                print("[\(i)] Paragraph: '\(text)'")
            default:
                print("[\(i)] Other")
            }
        }
    }
}
