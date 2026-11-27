import Foundation
import Darwin
import SwiftFastMarkdown

// MARK: - Memory & Resource Probes

struct MemorySnapshot {
    let sizeInUse: Int
    let blocksInUse: Int
    let physFootprint: UInt64

    static func capture() -> MemorySnapshot {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)

        var rusage = rusage_info_v4()
        let footprint: UInt64 = withUnsafeMutablePointer(to: &rusage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                if proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound) == 0 {
                    return ptr.pointee.ri_phys_footprint
                }
                return 0
            }
        }

        return MemorySnapshot(
            sizeInUse: Int(stats.size_in_use),
            blocksInUse: Int(stats.blocks_in_use),
            physFootprint: footprint
        )
    }
}

// MARK: - Statistics

struct BenchmarkResult {
    let name: String
    let samples: [Double]  // in milliseconds

    var median: Double {
        let sorted = samples.sorted()
        let mid = samples.count / 2
        if samples.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    var p95: Double { percentile(0.95) }
    var p99: Double { percentile(0.99) }
    var min: Double { samples.min() ?? 0 }
    var max: Double { samples.max() ?? 0 }
    var mean: Double { samples.reduce(0, +) / Double(samples.count) }

    private func percentile(_ p: Double) -> Double {
        let sorted = samples.sorted()
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
    }

    func report() {
        print("  \(name):")
        print("    median: \(String(format: "%.4f", median)) ms")
        print("    p95:    \(String(format: "%.4f", p95)) ms")
        print("    p99:    \(String(format: "%.4f", p99)) ms")
        print("    min:    \(String(format: "%.4f", min)) ms")
        print("    max:    \(String(format: "%.4f", max)) ms")
    }
}

// MARK: - Benchmark Runner

final class BenchmarkRunner {
    let iterations: Int
    let warmupIterations: Int

    init(iterations: Int = 100, warmupIterations: Int = 10) {
        self.iterations = iterations
        self.warmupIterations = warmupIterations
    }

    func measure(name: String, iterations overrideIterations: Int? = nil, _ block: () -> Void) -> BenchmarkResult {
        let count = overrideIterations ?? iterations
        // Warmup
        for _ in 0..<warmupIterations {
            block()
        }

        // Measure
        var samples: [Double] = []
        samples.reserveCapacity(count)

        for _ in 0..<count {
            let start = DispatchTime.now()
            block()
            let end = DispatchTime.now()

            let nanos = Double(end.uptimeNanoseconds - start.uptimeNanoseconds)
            samples.append(nanos / 1_000_000.0)  // Convert to ms
        }

        return BenchmarkResult(name: name, samples: samples)
    }

    func measureRetainedBytes<T>(count: Int = 20, _ factory: () -> T) -> (bytesPerItem: Int, blocksPerItem: Int) {
        // Warm up caches/zones
        _ = factory()
        var holder: [T] = []
        holder.reserveCapacity(count)
        let before = MemorySnapshot.capture()
        for _ in 0..<count {
            holder.append(factory())
        }
        let after = MemorySnapshot.capture()
        withExtendedLifetime(holder) {}
        let deltaBytes = max(0, after.sizeInUse - before.sizeInUse)
        let deltaBlocks = max(0, after.blocksInUse - before.blocksInUse)
        return (deltaBytes / count, deltaBlocks / count)
    }
}

// MARK: - Test Documents

enum TestDocuments {
    /// ~1KB simple document
    static let small = """
    # Hello World

    This is a **simple** paragraph with some *emphasis* and `inline code`.

    - Item one
    - Item two
    - Item three

    ```swift
    let x = 42
    ```

    > A blockquote with some text.
    """

    /// ~10KB document for performance target testing
    static var medium: String {
        var doc = "# Performance Test Document\n\n"

        // Generate ~10KB of varied content
        for i in 1...50 {
            doc += "## Section \(i)\n\n"
            doc += "This is paragraph \(i) with **bold**, *italic*, and `code` formatting. "
            doc += "It also includes a [link](https://example.com/\(i)) for good measure.\n\n"

            if i % 5 == 0 {
                doc += """
                | Column A | Column B | Column C |
                |----------|----------|----------|
                | Data \(i) | Value \(i) | Result \(i) |
                | More | Data | Here |

                """
            }

            if i % 7 == 0 {
                doc += """
                ```swift
                func example\(i)() {
                    let value = \(i)
                    print("Value: \\(value)")
                }
                ```

                """
            }

            if i % 3 == 0 {
                doc += """
                - [x] Task \(i) completed
                - [ ] Task \(i + 1) pending

                """
            }
        }

        return doc
    }

    /// ~50KB stress test document
    static var large: String {
        var doc = "# Large Document Stress Test\n\n"

        for i in 1...200 {
            doc += "## Section \(i): Lorem Ipsum\n\n"
            doc += String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 5)
            doc += "**Bold text** and *italic text* mixed with `inline code`.\n\n"

            if i % 10 == 0 {
                doc += """
                ```python
                def function_\(i)(x, y):
                    \"\"\"Docstring for function \(i).\"\"\"
                    result = x + y
                    for i in range(10):
                        result *= 2
                    return result
                ```

                """
            }
        }

        return doc
    }

    /// Entity-heavy document for EntityDecoder benchmarking
    static var entityHeavy: String {
        var doc = "# Entities &amp; Symbols &mdash; Benchmark\n\n"
        for i in 1...100 {
            doc += "Item \(i): Fish &amp; Chips &lt;5 &gt; 3&gt; &quot;quoted&quot; &nbsp; &#38; &#x26; &copy; 2026 &mdash; &hellip;\n\n"
        }
        return doc
    }
}

// MARK: - Benchmarks

func runBenchmarks() {
    print("=" * 60)
    print("SwiftFastMarkdown Benchmark Suite")
    print("=" * 60)
    print()

    let runner = BenchmarkRunner(iterations: 100, warmupIterations: 10)
    let parser = MarkdownParser()

    // Document sizes
    let smallData = Data(TestDocuments.small.utf8)
    let mediumDoc = TestDocuments.medium
    let mediumData = Data(mediumDoc.utf8)
    let largeDoc = TestDocuments.large
    let largeData = Data(largeDoc.utf8)
    let entityDoc = TestDocuments.entityHeavy
    let entityData = Data(entityDoc.utf8)

    print("Document sizes:")
    print("  Small:  \(smallData.count) bytes")
    print("  Medium: \(mediumData.count) bytes (~10KB target)")
    print("  Large:  \(largeData.count) bytes (~50KB stress)")
    print("  Entity: \(entityData.count) bytes (entity-heavy)")
    print()

    // MARK: - Parse Benchmarks
    print("-" * 60)
    print("PARSE BENCHMARKS")
    print("-" * 60)

    let parseSmall = runner.measure(name: "Parse ~1KB (small)") {
        _ = try? parser.parse(TestDocuments.small)
    }
    parseSmall.report()

    let parseMedium = runner.measure(name: "Parse ~10KB (medium)") {
        _ = try? parser.parse(mediumDoc)
    }
    parseMedium.report()
    checkTarget("10KB parse", parseMedium.median, target: 1.0, p95: parseMedium.p95, p95Target: 2.0)

    let parseMediumData = runner.measure(name: "Parse ~10KB (Data)") {
        _ = try? parser.parse(mediumData)
    }
    parseMediumData.report()

    let parseLarge = runner.measure(name: "Parse ~50KB (large)") {
        _ = try? parser.parse(largeDoc)
    }
    parseLarge.report()

    let parseEntities = runner.measure(name: "Parse entity-heavy (~10KB)") {
        _ = try? parser.parse(entityDoc)
    }
    parseEntities.report()
    print()

    // MARK: - Render Benchmarks (AttributedString)
    print("-" * 60)
    print("RENDER BENCHMARKS (AttributedString)")
    print("-" * 60)

    let mediumParsed = try! parser.parse(mediumDoc)
    let largeParsed = try! parser.parse(largeDoc)
    let style = MarkdownStyle.default
    let renderer = AttributedStringRenderer()

    let renderMedium = runner.measure(name: "Render ~10KB AttributedString") {
        _ = renderer.render(mediumParsed, style: style)
    }
    renderMedium.report()
    checkTarget("10KB render", renderMedium.median, target: 5.0, p95: renderMedium.p95, p95Target: 10.0)

    let renderLarge = runner.measure(name: "Render ~50KB AttributedString", iterations: 50) {
        _ = renderer.render(largeParsed, style: style)
    }
    renderLarge.report()

    // Inline render path (used by SwiftUI InlineText for every paragraph/heading/cell)
    let mediumParagraphSpans: [[MarkdownSpan]] = mediumParsed.blocks.compactMap { block in
        if case .paragraph(let p) = block { return p.spans }
        return nil
    }
    let renderInlineBatch = runner.measure(name: "RenderInline 50 paragraphs (SwiftUI InlineText path)") {
        for spans in mediumParagraphSpans {
            _ = renderer.renderInline(spans, source: mediumParsed.sourceData, style: style)
        }
    }
    renderInlineBatch.report()

    // Cached renderer hit + LRU churn (64 entries)
    let cachedRenderer = ThreadSafeCachedRenderer(maxCacheSize: 64)
    let cachedDocs: [MarkdownDocument] = (0..<64).map { i in
        try! parser.parse("# Doc \(i)\n\nParagraph **\(i)**")
    }
    for d in cachedDocs {
        _ = cachedRenderer.render(d, style: style)
    }
    let cacheChurn = runner.measure(name: "ThreadSafeCachedRenderer 64-doc hit sweep") {
        for d in cachedDocs {
            _ = cachedRenderer.render(d, style: style)
        }
    }
    cacheChurn.report()
    print()

    // MARK: - Incremental Parse Benchmarks
    print("-" * 60)
    print("INCREMENTAL PARSE BENCHMARKS")
    print("-" * 60)

    let chunkSize = 256
    let chunks = stride(from: 0, to: mediumDoc.utf8.count, by: chunkSize).map { start in
        let end = min(start + chunkSize, mediumDoc.utf8.count)
        let startIndex = mediumDoc.utf8.index(mediumDoc.utf8.startIndex, offsetBy: start)
        let endIndex = mediumDoc.utf8.index(mediumDoc.utf8.startIndex, offsetBy: end)
        return String(mediumDoc.utf8[startIndex..<endIndex])!
    }

    print("  Chunk size: \(chunkSize) bytes, Total chunks: \(chunks.count)")

    var chunkTimes: [Double] = []
    let incrementalResult = runner.measure(name: "Incremental parse ~10KB (256B chunks)") {
        let incrementalParser = IncrementalMarkdownParser()
        for chunk in chunks {
            let start = DispatchTime.now()
            _ = incrementalParser.append(chunk)
            let end = DispatchTime.now()
            chunkTimes.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
        }
    }
    incrementalResult.report()

    let perChunkResult = BenchmarkResult(name: "Per-chunk append (10KB / 256B)", samples: Array(chunkTimes.suffix(chunks.count)))
    perChunkResult.report()
    checkTarget("Streaming chunk", perChunkResult.median, target: 0.5, p95: perChunkResult.p95, p95Target: 1.0)

    // AI-token streaming stress test: ~50KB in 64B chunks
    let tokenChunkSize = 64
    let largeChunks = stride(from: 0, to: largeDoc.utf8.count, by: tokenChunkSize).map { start in
        let end = min(start + tokenChunkSize, largeDoc.utf8.count)
        let startIndex = largeDoc.utf8.index(largeDoc.utf8.startIndex, offsetBy: start)
        let endIndex = largeDoc.utf8.index(largeDoc.utf8.startIndex, offsetBy: end)
        return String(largeDoc.utf8[startIndex..<endIndex])!
    }
    print("  AI-token stress: ~50KB in \(tokenChunkSize)B chunks (\(largeChunks.count) chunks)")
    var largeChunkTimes: [Double] = []
    let incrementalLarge = runner.measure(name: "Incremental parse ~50KB (64B AI tokens)", iterations: 10) {
        let incrementalParser = IncrementalMarkdownParser()
        for chunk in largeChunks {
            let start = DispatchTime.now()
            _ = incrementalParser.append(chunk)
            let end = DispatchTime.now()
            largeChunkTimes.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
        }
        _ = incrementalParser.finalize()
    }
    incrementalLarge.report()
    let perTokenChunk = BenchmarkResult(name: "Per-token append (50KB / 64B)", samples: Array(largeChunkTimes.suffix(largeChunks.count)))
    perTokenChunk.report()
    print()

    // MARK: - SwiftUI Init Overhead Benchmark
    print("-" * 60)
    print("VIEW / FACTORY INIT OVERHEAD")
    print("-" * 60)

    let highlighterInit = runner.measure(name: "SyntaxHighlightingFactory.makeDefault()", iterations: 10) {
        _ = SyntaxHighlightingFactory.makeDefault()
    }
    highlighterInit.report()
    print()

    // MARK: - Memory & Bytes Footprint
    print("-" * 60)
    print("MEMORY & BYTES FOOTPRINT")
    print("-" * 60)

    let parseMem10K = runner.measureRetainedBytes(count: 20) {
        try! parser.parse(mediumDoc)
    }
    let parseMem50K = runner.measureRetainedBytes(count: 10) {
        try! parser.parse(largeDoc)
    }
    let renderMem10K = runner.measureRetainedBytes(count: 20) {
        renderer.render(mediumParsed, style: style)
    }
    let renderMem50K = runner.measureRetainedBytes(count: 10) {
        renderer.render(largeParsed, style: style)
    }

    let doc = try! parser.parse(largeDoc)
    let docMemory = MemoryLayout.size(ofValue: doc)
    let memSnap = MemorySnapshot.capture()
    print("  Document struct size:          \(docMemory) bytes")
    print("  Source data retained (50KB):   \(doc.sourceData.count) bytes")
    print("  Block count (50KB):            \(countBlocks(doc.blocks))")
    print("  Retained heap Parse 10KB:      \(parseMem10K.bytesPerItem) bytes (\(parseMem10K.blocksPerItem) allocs)")
    print("  Retained heap Parse 50KB:      \(parseMem50K.bytesPerItem) bytes (\(parseMem50K.blocksPerItem) allocs)")
    print("  Retained heap Render 10KB:     \(renderMem10K.bytesPerItem) bytes (\(renderMem10K.blocksPerItem) allocs)")
    print("  Retained heap Render 50KB:     \(renderMem50K.bytesPerItem) bytes (\(renderMem50K.blocksPerItem) allocs)")
    print("  Process phys footprint:        \(String(format: "%.2f", Double(memSnap.physFootprint) / (1024.0 * 1024.0))) MB")
    print()

    // MARK: - Summary
    print("=" * 60)
    print("SUMMARY - v1.0 Performance Targets + Hillclimb Metrics")
    print("=" * 60)
    printSummary(
        parseSmall: parseSmall,
        parseMedium: parseMedium,
        parseLarge: parseLarge,
        renderMedium: renderMedium,
        renderLarge: renderLarge,
        chunk10K: perChunkResult,
        inc10K: incrementalResult,
        inc50K: incrementalLarge,
        token50K: perTokenChunk,
        cacheChurn: cacheChurn,
        highlighterInit: highlighterInit,
        parseMem50K: parseMem50K.bytesPerItem,
        renderMem50K: renderMem50K.bytesPerItem
    )
}

func checkTarget(_ name: String, _ median: Double, target: Double, p95: Double, p95Target: Double) {
    let medianPass = median <= target
    let p95Pass = p95 <= p95Target
    let medianSymbol = medianPass ? "PASS" : "FAIL"
    let p95Symbol = p95Pass ? "PASS" : "FAIL"
    print("    Target check: median \(String(format: "%.4f", median))ms <= \(target)ms [\(medianSymbol)]")
    print("    Target check: p95 \(String(format: "%.4f", p95))ms <= \(p95Target)ms [\(p95Symbol)]")
}

func countBlocks(_ blocks: [MarkdownBlock]) -> Int {
    var count = 0
    for block in blocks {
        count += 1
        switch block {
        case .blockQuote(let q):
            count += countBlocks(q.blocks)
        case .list(let l):
            for item in l.items {
                count += countBlocks(item.blocks)
            }
        default:
            break
        }
    }
    return count
}

func printSummary(
    parseSmall: BenchmarkResult,
    parseMedium: BenchmarkResult,
    parseLarge: BenchmarkResult,
    renderMedium: BenchmarkResult,
    renderLarge: BenchmarkResult,
    chunk10K: BenchmarkResult,
    inc10K: BenchmarkResult,
    inc50K: BenchmarkResult,
    token50K: BenchmarkResult,
    cacheChurn: BenchmarkResult,
    highlighterInit: BenchmarkResult,
    parseMem50K: Int,
    renderMem50K: Int
) {
    print()
    print("  Parse 1KB:            median=\(String(format: "%.4f", parseSmall.median))ms  p95=\(String(format: "%.4f", parseSmall.p95))ms")
    print("  Parse 10KB:           median=\(String(format: "%.4f", parseMedium.median))ms  p95=\(String(format: "%.4f", parseMedium.p95))ms (target <1ms) \(parseMedium.median < 1.0 ? "PASS" : "FAIL")")
    print("  Parse 50KB:           median=\(String(format: "%.4f", parseLarge.median))ms  p95=\(String(format: "%.4f", parseLarge.p95))ms")
    print("  Render 10KB:          median=\(String(format: "%.4f", renderMedium.median))ms  p95=\(String(format: "%.4f", renderMedium.p95))ms (target <5ms) \(renderMedium.median < 5.0 ? "PASS" : "FAIL")")
    print("  Render 50KB:          median=\(String(format: "%.4f", renderLarge.median))ms  p95=\(String(format: "%.4f", renderLarge.p95))ms")
    print("  Inc 10KB (256B full): median=\(String(format: "%.4f", inc10K.median))ms  p95=\(String(format: "%.4f", inc10K.p95))ms")
    print("  Chunk 10KB (256B):    median=\(String(format: "%.4f", chunk10K.median))ms  p95=\(String(format: "%.4f", chunk10K.p95))ms (target <0.5ms) \(chunk10K.median < 0.5 ? "PASS" : "FAIL")")
    print("  Inc 50KB (64B full):  median=\(String(format: "%.4f", inc50K.median))ms  p95=\(String(format: "%.4f", inc50K.p95))ms")
    print("  Token 50KB (64B):     median=\(String(format: "%.4f", token50K.median))ms  p95=\(String(format: "%.4f", token50K.p95))ms")
    print("  Cache 64-hit sweep:   median=\(String(format: "%.4f", cacheChurn.median))ms  p95=\(String(format: "%.4f", cacheChurn.p95))ms")
    print("  Highlighter makeDef:  median=\(String(format: "%.4f", highlighterInit.median))ms  p95=\(String(format: "%.4f", highlighterInit.p95))ms")
    print("  Retained Parse 50KB:  \(parseMem50K) bytes")
    print("  Retained Render 50KB: \(renderMem50K) bytes")
    print()
}

// Helper for string repetition
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

// MARK: - Entry Point

if CommandLine.arguments.contains("--profile") {
    runProfileDiagnostics()
} else {
    runBenchmarks()
}

func runProfileDiagnostics() {
    print("=== RELEASE PROFILE DIAGNOSTICS ===")
    print("MemoryLayout<MarkdownBlock>: size=\(MemoryLayout<MarkdownBlock>.size) stride=\(MemoryLayout<MarkdownBlock>.stride)")
    print("MemoryLayout<MarkdownSpan>:  size=\(MemoryLayout<MarkdownSpan>.size) stride=\(MemoryLayout<MarkdownSpan>.stride)")
    print("MemoryLayout<TextContent>:   size=\(MemoryLayout<TextContent>.size) stride=\(MemoryLayout<TextContent>.stride)")
    print("MemoryLayout<BlockID>:       size=\(MemoryLayout<BlockID>.size) stride=\(MemoryLayout<BlockID>.stride)")
    print("MemoryLayout<ByteRange>:     size=\(MemoryLayout<ByteRange>.size) stride=\(MemoryLayout<ByteRange>.stride)")

    let parser = MarkdownParser()
    let mediumDoc = TestDocuments.medium
    let largeDoc = TestDocuments.large
    let mediumParsed = try! parser.parse(mediumDoc)
    let largeParsed = try! parser.parse(largeDoc)
    let style = MarkdownStyle.default

    // Measure AttributedString construction strategies on realistic 50KB doc (820 styled spans)
    var baseAttrs = AttributeContainer()
    baseAttrs.font = style.baseFont
    baseAttrs.foregroundColor = style.textColor
    var boldAttrs = baseAttrs
    boldAttrs.inlinePresentationIntent = .stronglyEmphasized

    // Build synthetic 77KB string + 820 disjoint ranges (~12 bytes each, spaced ~90 bytes apart)
    var textBytes: [UInt8] = []
    textBytes.reserveCapacity(80_000)
    var patches: [(Int, Int)] = []
    patches.reserveCapacity(820)
    for i in 0..<820 {
        let plain = "Lorem ipsum dolor sit amet, consectetur adipiscing elit section \(i) "
        textBytes.append(contentsOf: plain.utf8)
        let s = textBytes.count
        textBytes.append(contentsOf: "BoldSpanText".utf8)
        let e = textBytes.count
        patches.append((s, e))
        textBytes.append(0x0A)
    }

    let runner = BenchmarkRunner(iterations: 30, warmupIterations: 5)

    // Strategy 1: Single AttributedString(fullString, base) + setAttributes
    let s1 = runner.measure(name: "AttrStr S1: fullString + setAttributes (820 patches)") {
        let full = String(decoding: textBytes, as: UTF8.self)
        var res = AttributedString(full, attributes: baseAttrs)
        if #available(macOS 26, *) {
            var cursor = res.startIndex
            var curByte = 0
            for (s, e) in patches {
                let si = res.utf8.index(cursor, offsetBy: s - curByte)
                let ei = res.utf8.index(si, offsetBy: e - s)
                res[si..<ei].setAttributes(boldAttrs)
                cursor = ei
                curByte = e
            }
        }
    }
    s1.report()

    // Strategy 2: Forward append of AttributedString(slice, attributes:)
    let s2 = runner.measure(name: "AttrStr S2: forward append String(decoding: slice)") {
        var res = AttributedString()
        var pos = 0
        textBytes.withUnsafeBufferPointer { buf in
            for (s, e) in patches {
                if s > pos {
                    res.append(AttributedString(String(decoding: buf[pos..<s], as: UTF8.self), attributes: baseAttrs))
                }
                res.append(AttributedString(String(decoding: buf[s..<e], as: UTF8.self), attributes: boldAttrs))
                pos = e
            }
            if pos < buf.count {
                res.append(AttributedString(String(decoding: buf[pos..<buf.count], as: UTF8.self), attributes: baseAttrs))
            }
        }
    }
    s2.report()

    // Strategy 3: Single fullString + forward append of Substring
    let s3 = runner.measure(name: "AttrStr S3: fullString + forward append Substring") {
        let full = String(decoding: textBytes, as: UTF8.self)
        var res = AttributedString()
        var strPos = full.utf8.startIndex
        var pos = 0
        for (s, e) in patches {
            if s > pos {
                let nextIdx = full.utf8.index(strPos, offsetBy: s - pos)
                res.append(AttributedString(full[strPos..<nextIdx], attributes: baseAttrs))
                strPos = nextIdx
            }
            let endIdx = full.utf8.index(strPos, offsetBy: e - s)
            res.append(AttributedString(full[strPos..<endIdx], attributes: boldAttrs))
            strPos = endIdx
            pos = e
        }
        if strPos < full.endIndex {
            res.append(AttributedString(full[strPos..<full.endIndex], attributes: baseAttrs))
        }
    }
    s3.report()

    // Strategy 4: Build AttributedString(fullString) + mutate via res.runs or mergeAttributes
    let s4 = runner.measure(name: "AttrStr S4: AttributedString(fullString) + AttributedString.Index(strIdx)") {
        let full = String(decoding: textBytes, as: UTF8.self)
        var res = AttributedString(full, attributes: baseAttrs)
        var strCursor = full.utf8.startIndex
        var curByte = 0
        for (s, e) in patches {
            let ss = full.utf8.index(strCursor, offsetBy: s - curByte)
            let se = full.utf8.index(ss, offsetBy: e - s)
            if let si = AttributedString.Index(ss, within: res),
               let ei = AttributedString.Index(se, within: res) {
                res[si..<ei].setAttributes(boldAttrs)
            }
            strCursor = se
            curByte = e
        }
    }
    s4.report()

    // Strategy 5: Reverse-order setAttributes (splitting only the FIRST run or LAST run?)
    let s5 = runner.measure(name: "AttrStr S5: fullString + REVERSE setAttributes (820 patches)") {
        let full = String(decoding: textBytes, as: UTF8.self)
        var res = AttributedString(full, attributes: baseAttrs)
        if #available(macOS 26, *) {
            var cursor = res.endIndex
            var curByte = textBytes.count
            for (s, e) in patches.reversed() {
                let ei = res.utf8.index(cursor, offsetBy: e - curByte)
                let si = res.utf8.index(ei, offsetBy: s - e)
                res[si..<ei].setAttributes(boldAttrs)
                cursor = si
                curByte = s
            }
        }
    }
    s5.report()

    // Measure actual current renderer on medium & large
    let renderer = AttributedStringRenderer()
    runner.measure(name: "Current Render 10KB") { _ = renderer.render(mediumParsed, style: style) }.report()
    runner.measure(name: "Current Render 50KB") { _ = renderer.render(largeParsed, style: style) }.report()

    // Measure array-copy overhead in 1214-chunk incremental 50KB
    let allBlocks = largeParsed.blocks
    let copyBench = runner.measure(name: "Copy growing stableBlocks 1214x (simulating buildDocument)", iterations: 10) {
        var stable: [MarkdownBlock] = []
        stable.reserveCapacity(allBlocks.count)
        for i in 0..<1214 {
            let target = (i * allBlocks.count) / 1214
            while stable.count < target {
                stable.append(allBlocks[stable.count])
            }
            var combined: [MarkdownBlock] = []
            combined.reserveCapacity(stable.count + 1)
            combined.append(contentsOf: stable)
            if let first = allBlocks.first {
                combined.append(first)
            }
            withExtendedLifetime(combined) {}
        }
    }
    copyBench.report()
}
