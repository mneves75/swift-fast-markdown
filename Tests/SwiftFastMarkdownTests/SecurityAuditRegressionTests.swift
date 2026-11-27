import Foundation
import SwiftUI
import Testing
@testable import SwiftFastMarkdown

struct SecurityAuditRegressionTests {

    // MARK: - 1. LRUCache retain cycle & negative capacity

    private final class LeakProbe {
        let label: String
        init(_ label: String) { self.label = label }
    }

    @Test func lruCacheReleasesNodesOnRemoveAllAndScopeExit() {
        weak var weakA: LeakProbe?
        weak var weakB: LeakProbe?

        do {
            var cache = LRUCache<Int, LeakProbe>(capacity: 4)
            let a = LeakProbe("a")
            let b = LeakProbe("b")
            weakA = a
            weakB = b
            cache.insert(a, for: 1)
            cache.insert(b, for: 2)
            cache.removeAll()
        }

        #expect(weakA == nil, "LRUCache.removeAll() leaked node/value A via strong prev/next cycle")
        #expect(weakB == nil, "LRUCache.removeAll() leaked node/value B via strong prev/next cycle")

        weak var weakC: LeakProbe?
        weak var weakD: LeakProbe?

        do {
            var cache = LRUCache<Int, LeakProbe>(capacity: 4)
            let c = LeakProbe("c")
            let d = LeakProbe("d")
            weakC = c
            weakD = d
            cache.insert(c, for: 1)
            cache.insert(d, for: 2)
        }

        #expect(weakC == nil, "LRUCache deallocation leaked node/value C via strong prev/next cycle")
        #expect(weakD == nil, "LRUCache deallocation leaked node/value D via strong prev/next cycle")

        // Negative or zero capacity must clamp to 1 without trapping in reserveCapacity
        var negCache = LRUCache<Int, String>(capacity: -5)
        #expect(negCache.capacity == 1)
        negCache.insert("ok", for: 1)
        #expect(negCache.value(for: 1) == "ok")
    }

    // MARK: - 2. EntityDecoder numeric NUL & invalid code point sanitization (CommonMark §6.2)

    @Test func entityDecoderSanitizesZeroAndInvalidNumericEntities() throws {
        #expect(EntityDecoder.decode("&#0;") == "\u{FFFD}")
        #expect(EntityDecoder.decode("&#000;") == "\u{FFFD}")
        #expect(EntityDecoder.decode("&#x0;") == "\u{FFFD}")
        #expect(EntityDecoder.decode("&#X0;") == "\u{FFFD}")
        #expect(EntityDecoder.decode("&#x0000;") == "\u{FFFD}")
        #expect(EntityDecoder.decode("&#xD800;") == "\u{FFFD}")
        #expect(EntityDecoder.decode("&#x110000;") == "\u{FFFD}")

        let doc = try MarkdownParser().parse("a&#0;b&#x0;c")
        let rendered = String(AttributedStringRenderer().render(doc).characters)
        #expect(!rendered.unicodeScalars.contains("\u{0000}"), "Rendered text must never contain NUL from numeric entities")
        #expect(rendered == "a\u{FFFD}b\u{FFFD}c")
    }

    // MARK: - 3. safeLinkURL hardening

    @Test func safeLinkURLBlocksProtocolRelativeWhitespaceControlsAndOpaqueHTTP() throws {
        let blocked = [
            "",
            "//evil.example/path",
            "///etc/passwd",
            " javascript:alert(1)",
            "\tfile:///etc/hosts",
            "java\tscript:alert(1)",
            "\u{01}javascript:alert(1)",
            "custom_scheme://action",
            "http:opaque",
            "https:",
            "mailto:",
            "tel:",
            "javascript:void(0)",
            "data:text/html,hi",
            "file:///etc/hosts",
        ]
        for dest in blocked {
            #expect(AttributedStringRenderer.safeLinkURL(dest) == nil, "Expected safeLinkURL to block: \(dest.debugDescription)")
        }

        let allowed = [
            "https://example.com/path?a=1",
            "http://example.com",
            "mailto:user@example.com",
            "tel:+15551234567",
            "/docs/getting-started",
            "relative/page.md",
            "#section-1",
            "?query=1",
        ]
        for dest in allowed {
            #expect(AttributedStringRenderer.safeLinkURL(dest) != nil, "Expected safeLinkURL to allow: \(dest)")
        }

        // Blocked link in Markdown must not attach a .link URL or linkColor
        let doc = try MarkdownParser().parse("[click](//evil.example/path) and [bad](javascript:alert(1))")
        let rendered = AttributedStringRenderer().render(doc)
        let links = rendered.runs.compactMap(\.link)
        #expect(links.isEmpty, "Blocked links must not attach AttributedString.link")
        #expect(!rendered.runs.contains { $0.foregroundColor == MarkdownStyle.default.linkColor }, "Blocked links must not receive linkColor")

        // Blocked link/wikiLink nested inside an allowed link (at normal depth AND past maxNestingDepth)
        // must clear both .link and linkColor.
        let nestedBlocked = MarkdownSpan.link(
            children: [
                .text(.string("outer ")),
                .link(children: [.text(.string("blocked"))], destination: .string("javascript:alert(1)"), title: nil),
                .wikiLink(target: .string("//evil.example"), children: [.text(.string("wiki"))])
            ],
            destination: .string("https://example.com"),
            title: nil
        )
        var deepSpan: MarkdownSpan = nestedBlocked
        for _ in 0..<70 {
            deepSpan = .emphasis([deepSpan])
        }
        for span in [nestedBlocked, deepSpan] {
            let out = AttributedStringRenderer().renderInline([span], source: Data())
            for run in out.runs {
                let slice = String(out[run.range].characters)
                if slice.contains("blocked") || slice.contains("wiki") {
                    #expect(run.link == nil, "Nested blocked link/wikiLink inherited outer .link")
                    #expect(run.foregroundColor != MarkdownStyle.default.linkColor, "Nested blocked link/wikiLink retained linkColor")
                }
            }
        }
    }

    // MARK: - 4. Cross-span malformed UTF-8 splicing & mid-scalar patch safety

    @Test func singlePassBuilderPreventsCrossSpanUTF8Splicing() throws {
        // [0xC3, '`', 0xA9, '`'] would splice into 'é' (U+00E9) if concatenated before validation
        let splicedTwoByte = Data([0xC3, 0x60, 0xA9, 0x60])
        let doc1 = try MarkdownParser().parse(splicedTwoByte)
        let out1 = String(AttributedStringRenderer().render(doc1).characters)
        #expect(out1 == "\u{FFFD}\u{FFFD}", "Split UTF-8 bytes must decode as independent U+FFFD, got: \(out1.debugDescription)")

        // [0xE2, 0x80, '`', 0xAE, '`'] would forge U+202E Right-to-Left Override
        let splicedRLO = Data([0xE2, 0x80, 0x60, 0xAE, 0x60])
        let doc2 = try MarkdownParser().parse(splicedRLO)
        let out2 = String(AttributedStringRenderer().render(doc2).characters)
        #expect(!out2.unicodeScalars.contains("\u{202E}"), "Must not synthesize U+202E RLO across delimiter")

        // Single-leaf renderInline must match whole-document render on ByteRangeSequence malformed UTF-8
        let codeSpanNewline = Data([0x60, 0xC3, 0x0A, 0xA9, 0x60])
        let doc3 = try MarkdownParser().parse(codeSpanNewline)
        let fullOut3 = String(AttributedStringRenderer().render(doc3).characters)
        if case .paragraph(let p) = doc3.blocks.first {
            let inlineOut3 = String(AttributedStringRenderer().renderInline(p.spans, source: doc3.sourceData).characters)
            #expect(inlineOut3 == fullOut3, "renderInline must match render on malformed ByteRangeSequence UTF-8")
            #expect(inlineOut3 == "\u{FFFD}\u{FFFD}")
        } else {
            Issue.record("Expected paragraph block")
        }
    }

    // MARK: - 5. Deeply nested Markdown bounded indent & stack safety

    @Test func deeplyNestedBlockQuotesBoundIndentAmplification() async throws {
        let depth = 1_500
        let nested = String(repeating: ">", count: depth) + "leaf"
        let doc = try MarkdownParser().parse(nested)

        // Render on a cooperative Swift Concurrency actor thread (512 KB stack)
        let cached = CachedAttributedStringRenderer(maxCacheSize: 4)
        let rendered = await cached.render(doc)
        let text = String(rendered.characters)
        #expect(text.contains("leaf"))
        // Uncapped O(D^2) indentation emits millions of spaces at depth 1500; capped stays linear
        #expect(text.utf8.count < 120_000, "Indent amplification must be bounded linearly, got \(text.utf8.count) bytes")
    }

    // MARK: - 6. IncrementalMarkdownParser fence/HTML boundary escape & CRLF stabilization

    @Test func incrementalParserPreservesCodeFenceAndHTMLBlockContainment() throws {
        let fixtures = [
            "```text\nsafe\n```not-closing\n[click](https://example.com)\n```\n",
            "```text\n    ```\n[click](https://example.com)\n```\n",
            "```text\r\nsafe\r\n```\t\r\n[click](https://example.com)\r\n```\r\n",
            "- ```\n  line1\n\n  [click](https://example.com)\n  ```\n",
            "- ```\n  line1\n      ```\n  [click](https://example.com)\n  ```\n",
            "<!--\ncomment\n\n[click](https://example.com)\n-->\n",
            "<scripture>\nbody\n\n[click](https://example.com)\n</script>\n",
        ]

        let fullParser = MarkdownParser()
        let renderer = AttributedStringRenderer()

        for fixture in fixtures {
            let fullDoc = try fullParser.parse(fixture)
            let fullLinks = renderer.render(fullDoc).runs.compactMap(\.link)
            #expect(fullLinks.isEmpty)

            let inc = IncrementalMarkdownParser()
            for line in fixture.split(separator: "\n", omittingEmptySubsequences: false) {
                _ = inc.append(String(line) + "\n")
            }
            let incDoc = inc.finalize()
            let incLinks = renderer.render(incDoc).runs.compactMap(\.link)
            #expect(incLinks.isEmpty, "IncrementalParser escaped verbatim block and emitted links: \(incLinks) for fixture: \(fixture.debugDescription)")
        }

        // Loose list containing an indented code fence OR empty '-' item must remain a single list block
        let looseLists = [
            "- item 1\n\n  ```swift\n  let x = 1\n  ```\n\n- item 2\n",
            "-\n\n- ```swift\n  let x = 1\n  ```\n",
        ]
        for looseList in looseLists {
            let fullLoose = try fullParser.parse(looseList)
            let incLooseParser = IncrementalMarkdownParser()
            for line in looseList.split(separator: "\n", omittingEmptySubsequences: false) {
                _ = incLooseParser.append(String(line) + "\n")
            }
            let incLoose = incLooseParser.finalize()
            #expect(incLoose.blocks.count == fullLoose.blocks.count, "List structure mismatch for: \(looseList.debugDescription)")
        }

        // Differential matrix: lists/blockquotes/HTML blocks with indented, dedented, tab-trailing,
        // and nested fences must match full MarkdownParser byte-for-byte in rendered text, block count, and link runs.
        var differentialCases = [
            "1. item\n\n   ```\n  body\n   ```\n\n- after\n\nend\n\nnext\n",
            "1. item\n\n    ```\n  body\n```\n\n- after\n\nend\n\nnext\n",
            "1. item\n\n ```\n  body\n    ```\n\n- after\n\nend\n\nnext\n",
            "- ```\n  child\n```\nouter\n\nfinal\n```\n\nTail\n\nLast\n",
            "- ```\n```\t\n```\nend code\n",
            "- ```\n```\t\n```\nend code\n\n[link](https://example.com)\n\nNext\n",
            "- ```\n``a\n```\nend code\n\n[link](https://example.com)\n",
            "- ```\n``` ```\n```\nend code\n\nNext\n",
            "- ```\n```\n  ```\nouter\n```\nTail\n",
            "> ```\n```\nend code\n\nNext\n",
            "> ```\n```\t\n```\nend code\n\nNext\n",
            "- - ```\n    child\n  ```\n  middle\n\n  end\n  ```\n\nTail\n\nLast\n",
            "- - ```\n  ```\t\n  ```\n  end\n\nTail\n",
            "- item\n\n  para\n\nNext para.\n\nThird para.\n",
            "- <pre>\n  inside\nouter\n```\n[notlink](https://example.com)\n</pre>\n\nstill code\n",
            // Exact adversarial cases from multi-thousand-case differential fuzzing:
            "- ```\n</style>\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "-     ```\n```\n\nalpha\n\nbeta\n\ngamma\n",
            "1. \t```\n  </pre>\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "> ```\n> > ```\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "> > ```\n> plain\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "> - ```\n> > ```\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "- > ```\n  ```\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "- - ```\n  > ```\n  \n  - child\n\n    continuation\n\nalpha\n\nbeta\n",
            "- ~~~\n</style>\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "- ````\n</style>\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "-\n  > ```\n  \n  - child\n\n    continuation\n\nalpha\n\nbeta\n",
            "- item\n\n  more\n  > ```\n  \n  - child\n\n    continuation\n\nalpha\n\nbeta\n",
            "- item\n\n    > ```\n```\n\n```\n\nalpha\n\nbeta\n",
            ">   - ```\n> > ```\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "- - <pre>\n</style>\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "> - <scripture>\n  > ```\n  ```\n\nalpha\n\n```\n\nbeta\n",
            "- > <style>\n    ```\n\n```\n\nalpha\n\nbeta\n",
        ]
        // Combinatorial matrix covering container openers × dedent/closing lines × follow-ups (300+ cases)
        let openers = [
            "- ```\n", "1. ```\n", "- - ```\n", "> ```\n", "  - ```\n",
            "-     ```\n", "> > ```\n", "- > ```\n", "- > <style>\n", "> - <scripture>\n",
        ]
        let midLines = [
            "```\n", "``` \n", "```\t\n", "```x\n", "  ```\n", "  ```\t\n",
            "``a\n", "~~~ \n", "</style>\n", "> > ```\n", "outer\n", "\n",
        ]
        let tails = [
            "```\nend code\n\n[a](https://example.com)\n\nLast\n",
            "  ```\n\nalpha\n\n```\n\nbeta\n",
            "```\n\nParagraph\n\nLast\n",
        ]
        for opener in openers {
            for mid in midLines {
                for tail in tails {
                    differentialCases.append(opener + mid + tail)
                }
            }
        }
        for md in differentialCases {
            let expectedDoc = try fullParser.parse(md)
            let expectedRendered = renderer.render(expectedDoc)
            let expectedText = String(expectedRendered.characters)
            let expectedLinks = expectedRendered.runs.compactMap(\.link)

            // Verify line-by-line and single-append incremental streaming match full parse
            let lineInc = IncrementalMarkdownParser()
            let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                if idx < lines.count - 1 {
                    _ = lineInc.append(String(line) + "\n")
                } else if !line.isEmpty {
                    _ = lineInc.append(String(line))
                }
            }
            let lineDoc = lineInc.finalize()
            let lineRendered = renderer.render(lineDoc)
            #expect(lineDoc.blocks.count == expectedDoc.blocks.count, "Linewise block count mismatch for: \(md.debugDescription)")
            #expect(String(lineRendered.characters) == expectedText, "Linewise text mismatch for: \(md.debugDescription)")
            #expect(lineRendered.runs.compactMap(\.link) == expectedLinks, "Linewise link mismatch for: \(md.debugDescription)")

            let singleInc = IncrementalMarkdownParser()
            _ = singleInc.append(md)
            let singleDoc = singleInc.finalize()
            let singleRendered = renderer.render(singleDoc)
            #expect(singleDoc.blocks.count == expectedDoc.blocks.count, "Single-append block count mismatch for: \(md.debugDescription)")
            #expect(String(singleRendered.characters) == expectedText, "Single-append text mismatch for: \(md.debugDescription)")
        }

        // List continuation followed by top-level paragraphs must stabilize before finalize()
        let listContParser = IncrementalMarkdownParser()
        _ = listContParser.append("- item\n\n  continuation\n\nNext para.\n\nThird para.\n")
        #expect(listContParser.stableBlockCount >= 1, "Top-level paragraphs after list continuation must stabilize")

        // Blockquote ending with an unclosed fence must not stall stabilization of later paragraphs
        let quoteFenceParser = IncrementalMarkdownParser()
        _ = quoteFenceParser.append("> ```\n> code\n\nParagraph 1.\n\nParagraph 2.\n")
        #expect(quoteFenceParser.stableBlockCount >= 1, "Paragraphs after blockquote with unclosed fence should stabilize")

        // CRLF blank lines must stabilize blocks before finalize()
        let crlfParser = IncrementalMarkdownParser()
        _ = crlfParser.append("Paragraph one.\r\n\r\nParagraph two.\r\n")
        #expect(crlfParser.stableBlockCount >= 1, "CRLF blank lines should stabilize completed blocks")
    }

    // MARK: - 7. IncrementalMarkdownParser documentID freshness with cached renderers

    @Test func incrementalDocumentSnapshotsDoNotPoisonCachedRenderers() async {
        let parser = IncrementalMarkdownParser()
        let cachedActor = CachedAttributedStringRenderer(maxCacheSize: 8)
        let cachedSync = ThreadSafeCachedRenderer(maxCacheSize: 8)

        let d1 = parser.append("Hello")
        let r1a = await cachedActor.render(d1)
        let r1s = cachedSync.render(d1)
        #expect(String(r1a.characters) == "Hello")
        #expect(String(r1s.characters) == "Hello")

        let d2 = parser.append(" world")
        let d3 = parser.finalize()
        #expect(d1.id != d2.id, "Mutated incremental snapshot must have a distinct document ID")

        let r3a = await cachedActor.render(d3)
        let r3s = cachedSync.render(d3)
        #expect(String(r3a.characters) == "Hello world")
        #expect(String(r3s.characters) == "Hello world")
    }

    // MARK: - 8. HighlightrEngine safety (theme validation, cancelled task, livescript/auto/size guard)

    @Test func highlightrEngineNormalizesInvalidThemeAndSkipsCancelledTasks() async {
        let engine = HighlightrEngine(configuration: .init(theme: "nonexistent-theme-xyz", maxHighlightBytes: 128))
        #expect(engine != nil)
        #expect(await engine!.currentTheme == HighlightrEngine.defaultTheme)

        // Unsafe Highlightr CSS theme ("far") must also normalize safely
        let safeFar = HighlightrEngine(configuration: .init(theme: "far"))
        #expect(safeFar != nil)
        #expect(await safeFar!.currentTheme == HighlightrEngine.defaultTheme)

        // Cancelled task should return plain text without blocking/caching
        let cancelledTask = Task<AttributedString, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            return await engine!.highlight(code: "let cancelled = 1", language: "swift")
        }
        let cancelledOut = await cancelledTask.value
        #expect(String(cancelledOut.characters) == "let cancelled = 1")

        // Blocked ReDoS grammar ("livescript"/"ls"), unknown language, and nil language fall back to plain text
        let lsOut = await engine!.highlight(code: "x = 1", language: "livescript")
        #expect(String(lsOut.characters) == "x = 1")
        let unknownOut = await engine!.highlight(code: "x = 1", language: "not-a-real-lang")
        #expect(String(unknownOut.characters) == "x = 1")
        let nilOut = await engine!.highlight(code: "x = 1", language: nil)
        #expect(String(nilOut.characters) == "x = 1")

        // Oversized code (> maxHighlightBytes) falls back to plain text immediately
        let oversized = String(repeating: "a", count: 256)
        let bigOut = await engine!.highlight(code: oversized, language: "swift")
        #expect(String(bigOut.characters) == oversized)

        // Common language aliases (e.g. "js" -> "javascript") must match canonical highlighting
        let jsCanonical = await engine!.highlight(code: "const x = 1;", language: "javascript")
        let jsAlias = await engine!.highlight(code: "const x = 1;", language: "js")
        #expect(jsAlias == jsCanonical, "Language alias 'js' must resolve to canonical 'javascript'")

        // HighlightrPool must preserve valid themes (e.g. "github" after warming "atom-one-dark")
        await SyntaxHighlightingFactory.clearSharedPool()
        let defaultProxy = SyntaxHighlightingFactory.makeDefault(configuration: .init(theme: "atom-one-dark"))
        let githubProxy = SyntaxHighlightingFactory.makeDefault(configuration: .init(theme: "github"))
        let pooledDarkOut = await defaultProxy.highlight(code: "let a = 1", language: "swift")
        let pooledGithubOut = await githubProxy.highlight(code: "let a = 1", language: "swift")
        #expect(pooledGithubOut != pooledDarkOut, "HighlightrPool must apply valid 'github' theme instead of clobbering to default")
        #expect(await SyntaxHighlightingFactory.sharedPoolCount() >= 2)

        // Shared pool clear API atomically evicts all pooled engines
        await SyntaxHighlightingFactory.clearSharedPool()
        #expect(await SyntaxHighlightingFactory.sharedPoolCount() == 0)
    }

    // MARK: - 9. ByteRange clamping & MD4CParser size ceiling

    @Test func byteRangeClampedAndParserSizeLimitsDoNotTrap() {
        let range = ByteRange(start: 0, end: 5)
        let over32 = Int(UInt32.max) + 1
        #expect(range.clamped(to: over32) == ByteRange(start: 0, end: 5))
        #expect(range.clamped(to: -10) == ByteRange(start: 0, end: 0))
        // Strictly below vendored CMD4C's ~2.67 GiB MD_TEMP_BUFFER 32-bit overflow threshold
        #expect(MD4CParser.maxInputByteCount < 2_000_000_000)
    }

    // MARK: - 10. HeadingView empty headingFonts & CodeBlockView distinct task key

    @MainActor
    @Test func headingViewEmptyFontsAndCodeBlockViewTaskKeyAreSafe() throws {
        var style = MarkdownStyle.default
        style.headingFonts = []
        let doc = try MarkdownParser().parse("# Hello")
        guard case .heading(let heading) = doc.blocks.first else {
            Issue.record("Expected heading block")
            return
        }
        let headingView = HeadingView(block: heading, source: doc.sourceData, style: style)
        _ = headingView.body

        // Identical BlockID across distinct code blocks must yield distinct HighlightTaskKey
        let docA = try MarkdownParser().parse("```swift\nlet secret = 1\n```")
        let docB = try MarkdownParser().parse("```swift\nlet public = 2\n```")
        guard case .codeBlock(let cbA) = docA.blocks.first,
              case .codeBlock(let cbB) = docB.blocks.first else {
            Issue.record("Expected code blocks")
            return
        }
        #expect(cbA.id == cbB.id)
        let keyA = CodeBlockView.HighlightTaskKey(blockID: cbA.id, language: cbA.language?.string(in: docA.sourceData), code: cbA.content.string(in: docA.sourceData))
        let keyB = CodeBlockView.HighlightTaskKey(blockID: cbB.id, language: cbB.language?.string(in: docB.sourceData), code: cbB.content.string(in: docB.sourceData))
        #expect(keyA != keyB)
    }
}
