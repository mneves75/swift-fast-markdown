import XCTest
import SwiftUI
@testable import SwiftFastMarkdown

final class AttributedStringRendererTests: XCTestCase {
    func testRendersPlainText() throws {
        let document = try MarkdownParser().parse("Hello world")
        let rendered = AttributedStringRenderer().render(document)
        XCTAssertEqual(String(rendered.characters), "Hello world")
    }

    func testRendersLinkAttributes() throws {
        let document = try MarkdownParser().parse("[OpenAI](https://openai.com)")
        let rendered = AttributedStringRenderer().render(document)
        let linkRuns = rendered.runs.compactMap { run -> URL? in
            run.link
        }
        XCTAssertEqual(linkRuns.first?.absoluteString, "https://openai.com")
    }

    func testRendersInlineCodeWithBackground() throws {
        let document = try MarkdownParser().parse("Use `code` here")
        let rendered = AttributedStringRenderer().render(document)
        let codeRuns = rendered.runs.filter { run in
            run.backgroundColor != nil
        }
        XCTAssertFalse(codeRuns.isEmpty)
    }

    // MARK: - renderInline Tests

    func testRenderInlineWithFontOverride() throws {
        let renderer = AttributedStringRenderer()
        let document = try MarkdownParser().parse("**bold** and *italic*")
        guard case .paragraph(let para) = document.blocks.first else {
            XCTFail("Expected paragraph block")
            return
        }

        // Test that renderInline works with fontOverride (CRIT-001 fix verification)
        let customFont = Font.system(size: 20).bold()
        let rendered = renderer.renderInline(para.spans, source: document.sourceData, style: .default, fontOverride: customFont)

        // Verify rendering completed without infinite recursion
        XCTAssertFalse(rendered.characters.isEmpty)
    }

    func testRenderInlineWithoutFontOverride() throws {
        let renderer = AttributedStringRenderer()
        let document = try MarkdownParser().parse("Regular text")
        guard case .paragraph(let para) = document.blocks.first else {
            XCTFail("Expected paragraph block")
            return
        }

        // Test default font behavior
        let rendered = renderer.renderInline(para.spans, source: document.sourceData, style: .default)

        XCTAssertFalse(rendered.characters.isEmpty)
        XCTAssertEqual(String(rendered.characters), "Regular text")
    }
}
