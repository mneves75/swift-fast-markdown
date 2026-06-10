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

    // MARK: - Link Scheme Validation

    func testBlocksJavascriptScheme() throws {
        let document = try MarkdownParser().parse("[click](javascript:alert(1))")
        let rendered = AttributedStringRenderer().render(document)
        let linkRuns = rendered.runs.compactMap(\.link)
        XCTAssertTrue(linkRuns.isEmpty, "javascript: URLs must not become tappable links")
    }

    func testBlocksDataAndFileSchemes() {
        XCTAssertNil(AttributedStringRenderer.safeLinkURL("data:text/html,<script>1</script>"))
        XCTAssertNil(AttributedStringRenderer.safeLinkURL("file:///etc/passwd"))
        XCTAssertNil(AttributedStringRenderer.safeLinkURL("JAVASCRIPT:alert(1)"))
    }

    func testAllowsSafeSchemes() {
        XCTAssertNotNil(AttributedStringRenderer.safeLinkURL("https://example.com"))
        XCTAssertNotNil(AttributedStringRenderer.safeLinkURL("http://example.com"))
        XCTAssertNotNil(AttributedStringRenderer.safeLinkURL("mailto:a@b.com"))
        // Relative (scheme-less) destinations stay allowed.
        XCTAssertNotNil(AttributedStringRenderer.safeLinkURL("/docs/page"))
        XCTAssertNotNil(AttributedStringRenderer.safeLinkURL("#anchor"))
    }

    // MARK: - Cached Renderer

    func testCachedRendererStyleChangeDoesNotDuplicateLRUEntries() async throws {
        let renderer = CachedAttributedStringRenderer(maxCacheSize: 2)
        let document = try MarkdownParser().parse("# Title\n\nBody")

        var altStyle = MarkdownStyle.default
        altStyle.blockSpacing = 5

        // Same document rendered with two styles must keep a single cache slot.
        _ = await renderer.render(document, style: .default)
        _ = await renderer.render(document, style: altStyle)
        let count = await renderer.cacheCount
        XCTAssertEqual(count, 1)

        // Result must reflect the latest style, not a stale cache hit.
        let rendered = await renderer.render(document, style: altStyle)
        XCTAssertTrue(String(rendered.characters).contains("\n\n\n\n\n"))
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
