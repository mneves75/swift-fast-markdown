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
}
