import Foundation
import SwiftUI
import Testing
@testable import SwiftFastMarkdown

struct PerformanceOptimizationRegressionTests {

    // MARK: - IncrementalMarkdownParser CoW & Correctness

    @Test func incrementalRetainedSnapshotsAreImmutableUnderCoW() {
        let parser = IncrementalMarkdownParser()
        let renderer = AttributedStringRenderer()

        let doc1 = parser.append("# Title\n\nFirst para")
        let snap1Text = String(renderer.render(doc1).characters)

        let doc2 = parser.append(" continued\n\nSecond para")
        let snap2Text = String(renderer.render(doc2).characters)

        let doc3 = parser.finalize()
        let snap3Text = String(renderer.render(doc3).characters)

        // Prior snapshots must remain untouched by subsequent in-place appends
        #expect(String(renderer.render(doc1).characters) == snap1Text)
        #expect(snap1Text.contains("First para"))
        #expect(!snap1Text.contains("continued"))

        #expect(String(renderer.render(doc2).characters) == snap2Text)
        #expect(snap2Text.contains("First para continued"))
        #expect(snap2Text.contains("Second para"))

        #expect(snap3Text == snap2Text)
    }

    @Test func incrementalHonorsCustomParseOptionsOnStabilizedBlocks() throws {
        let input = "| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter table."
        let fullDoc = try MarkdownParser().parse(input, options: .commonMark)

        let inc = IncrementalMarkdownParser(configuration: .init(options: .commonMark))
        _ = inc.append("| a | b |\n| - | - |\n")
        _ = inc.append("| 1 | 2 |\n\n")
        _ = inc.append("After table.")
        let incDoc = inc.finalize()

        #expect(incDoc.blocks.count == fullDoc.blocks.count)
        for block in incDoc.blocks {
            if case .table = block {
                Issue.record("Table should not be parsed when ParseOptions.commonMark is configured")
            }
        }
    }

    @Test func incrementalAssignsUniqueMonotonicBlockIDsAcrossChunks() {
        let parser = IncrementalMarkdownParser()
        _ = parser.append("---\n\n")
        _ = parser.append("---\n\n")
        _ = parser.append("---\n")
        let doc = parser.finalize()

        #expect(doc.blocks.count == 3)
        let uniqueIDs = Set(doc.blocks.map(\.id))
        #expect(uniqueIDs.count == 3)
    }

    @Test func incrementalHandlesSplitBlankLineAndSplitClosingFence() throws {
        let full = "Para 1\n\n```swift\nlet a = 1\n```\n\nPara 2"
        let expected = try MarkdownParser().parse(full)

        let parser = IncrementalMarkdownParser()
        let chunks = ["Para 1\n", "\n``", "`swift\nlet a = 1\n``", "`\n", "\nPara 2"]
        for chunk in chunks {
            _ = parser.append(chunk)
        }
        let actual = parser.finalize()

        #expect(actual.blocks.count == expected.blocks.count)
        let renderer = AttributedStringRenderer()
        #expect(String(renderer.render(actual).characters) == String(renderer.render(expected).characters))
    }

    // MARK: - EntityDecoder (Fast Path, Binary Table, Numeric & Bad Inputs)

    @Test func entityDecoderHandlesFastPathAndBinaryTableAndBadInputs() {
        // Fast-path common entities
        #expect(EntityDecoder.decode("&amp;") == "&")
        #expect(EntityDecoder.decode("&lt;") == "<")
        #expect(EntityDecoder.decode("&gt;") == ">")
        #expect(EntityDecoder.decode("&quot;") == "\"")
        #expect(EntityDecoder.decode("&apos;") == "'")
        #expect(EntityDecoder.decode("&nbsp;") == "\u{00A0}")
        #expect(EntityDecoder.decode("&mdash;") == "—")
        #expect(EntityDecoder.decode("&hellip;") == "…")

        // Uncommon entities from compact binary HTMLEntities.bin
        #expect(EntityDecoder.decode("&AElig;") == "Æ")
        #expect(EntityDecoder.decode("&forall;") == "∀")
        #expect(EntityDecoder.decode("&Tab;") == "\t")
        #expect(EntityDecoder.decode("&NewLine;") == "\n")

        // Numeric decimal & hex
        #expect(EntityDecoder.decode("&#38;") == "&")
        #expect(EntityDecoder.decode("&#x26;") == "&")
        #expect(EntityDecoder.decode("&#x1F680;") == "🚀")

        // Bad / malformed inputs must return unchanged without crashing
        #expect(EntityDecoder.decode("&notarealentity;") == "&notarealentity;")
        #expect(EntityDecoder.decode("&#99999999999999999999999;") == "&#99999999999999999999999;")
        #expect(EntityDecoder.decode("&#;") == "&#;")
        #expect(EntityDecoder.decode("&#x;") == "&#x;")
        #expect(EntityDecoder.decode("&amp") == "&amp")
        #expect(EntityDecoder.decode("") == "")
    }

    // MARK: - AttributedStringRenderer Parity & Malformed UTF-8 Fallback

    @Test func rendererHandlesMalformedUTF8WithoutCrashing() throws {
        // "Hi " + invalid UTF-8 [0xFF, 0xFE] + " **bold** and `code`"
        var bytes = Array("Hi ".utf8)
        bytes.append(contentsOf: [0xFF, 0xFE])
        bytes.append(contentsOf: Array(" **bold** and `code`".utf8))
        let data = Data(bytes)

        let doc = try MarkdownParser().parse(data)
        let rendered = AttributedStringRenderer().render(doc)
        let text = String(rendered.characters)

        #expect(text.contains("Hi "))
        #expect(text.contains("bold"))
        #expect(text.contains("code"))
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(rendered.runs.contains { $0.backgroundColor != nil })
    }

    @Test func rendererHandlesNestedFormattingAndNonContiguousCodeBlock() throws {
        let md = """
        # Heading *italic*

        ***bold italic*** and [**bold link**](https://example.com)

        >     indented line 1
        >     indented line 2
        """
        let doc = try MarkdownParser().parse(md)
        let rendered = AttributedStringRenderer().render(doc)
        let text = String(rendered.characters)

        #expect(text.contains("Heading italic"))
        #expect(text.contains("bold italic"))
        #expect(text.contains("bold link"))
        #expect(text.contains("indented line 1"))
        #expect(text.contains("indented line 2"))

        let hasBoldItalic = rendered.runs.contains {
            let intent = $0.inlinePresentationIntent ?? []
            return intent.contains(.stronglyEmphasized) && intent.contains(.emphasized)
        }
        #expect(hasBoldItalic)

        let linkURLs = rendered.runs.compactMap(\.link)
        #expect(linkURLs.first?.absoluteString == "https://example.com")
    }

    // MARK: - LRUCache.removeValue & ThreadSafeCachedRenderer

    @Test func lruCacheRemoveValueMaintainsIntegrity() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.insert(3, for: "c") // order: c -> b -> a

        #expect(cache.removeValue(for: "b") == 2) // middle
        #expect(cache.count == 2)
        #expect(cache.value(for: "b") == nil)

        #expect(cache.removeValue(for: "c") == 3) // head
        #expect(cache.count == 1)

        #expect(cache.removeValue(for: "a") == 1) // tail (last remaining)
        #expect(cache.count == 0)
        #expect(cache.removeValue(for: "missing") == nil)

        cache.insert(10, for: "x")
        #expect(cache.value(for: "x") == 10)
    }

    @Test func cachedRendererInvalidateRemovesOnlyTarget() async throws {
        let renderer = CachedAttributedStringRenderer(maxCacheSize: 4)
        let doc1 = try MarkdownParser().parse("One")
        let doc2 = try MarkdownParser().parse("Two")

        _ = await renderer.render(doc1)
        _ = await renderer.render(doc2)
        #expect(await renderer.cacheCount == 2)

        await renderer.invalidate(documentId: doc1.id)
        #expect(await renderer.cacheCount == 1)
    }

    // MARK: - SyntaxHighlightingFactory Lazy Shared Pool

    @Test func factoryDefaultHighlighterWorksAndIsolatesThemeChanges() async {
        let h1 = SyntaxHighlightingFactory.makeDefault()
        let h2 = SyntaxHighlightingFactory.makeDefault()

        let out1 = await h1.highlight(code: "let x = 1", language: "swift")
        #expect(String(out1.characters).contains("let x = 1"))

        await h1.setTheme("github")
        let out2 = await h2.highlight(code: "let y = 2", language: "swift")
        #expect(String(out2.characters).contains("let y = 2"))

        let emptyOut = await h1.highlight(code: "", language: "swift")
        #expect(emptyOut.characters.isEmpty)
    }

    // MARK: - StreamingMarkdownView UTF-8 Suffix Helper

    @Test @MainActor func fastUTF8SuffixHandlesASCIIUnicodeAndNonPrefixEdits() {
        #expect(StreamingMarkdownView.fastUTF8Suffix(of: "Hello world", afterPrefix: "Hello ") == "world")
        #expect(StreamingMarkdownView.fastUTF8Suffix(of: "🚀 Olá mundo!", afterPrefix: "🚀 Olá ") == "mundo!")
        #expect(StreamingMarkdownView.fastUTF8Suffix(of: "Hello", afterPrefix: "Hello") == "")
        #expect(StreamingMarkdownView.fastUTF8Suffix(of: "Hi", afterPrefix: "Hello") == nil)
        #expect(StreamingMarkdownView.fastUTF8Suffix(of: "Changed world", afterPrefix: "Hello ") == nil)
        #expect(StreamingMarkdownView.fastUTF8Suffix(of: "Anything", afterPrefix: "") == nil)
    }
}
