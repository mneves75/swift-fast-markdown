import Foundation
import SwiftFastMarkdown

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
        print("    median: \(String(format: "%.3f", median)) ms")
        print("    p95:    \(String(format: "%.3f", p95)) ms")
        print("    p99:    \(String(format: "%.3f", p99)) ms")
        print("    min:    \(String(format: "%.3f", min)) ms")
        print("    max:    \(String(format: "%.3f", max)) ms")
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

    func measure(name: String, _ block: () -> Void) -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            block()
        }

        // Measure
        var samples: [Double] = []
        samples.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = DispatchTime.now()
            block()
            let end = DispatchTime.now()

            let nanos = Double(end.uptimeNanoseconds - start.uptimeNanoseconds)
            samples.append(nanos / 1_000_000.0)  // Convert to ms
        }

        return BenchmarkResult(name: name, samples: samples)
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
}

// MARK: - Benchmarks

@main
struct SwiftFastMarkdownBenchmarks {
    static func main() {
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

        print("Document sizes:")
        print("  Small:  \(smallData.count) bytes")
        print("  Medium: \(mediumData.count) bytes (~10KB target)")
        print("  Large:  \(largeData.count) bytes (~50KB stress)")
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

        let parseLarge = runner.measure(name: "Parse ~50KB (large)") {
            _ = try? parser.parse(largeDoc)
        }
        parseLarge.report()
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

        let renderLarge = runner.measure(name: "Render ~50KB AttributedString") {
            _ = renderer.render(largeParsed, style: style)
        }
        renderLarge.report()
        print()

        // MARK: - Incremental Parse Benchmarks
        print("-" * 60)
        print("INCREMENTAL PARSE BENCHMARKS")
        print("-" * 60)

        // Simulate streaming: parse in chunks
        let chunkSize = 256
        let chunks = stride(from: 0, to: mediumDoc.utf8.count, by: chunkSize).map { start in
            let end = min(start + chunkSize, mediumDoc.utf8.count)
            let startIndex = mediumDoc.utf8.index(mediumDoc.utf8.startIndex, offsetBy: start)
            let endIndex = mediumDoc.utf8.index(mediumDoc.utf8.startIndex, offsetBy: end)
            return String(mediumDoc.utf8[startIndex..<endIndex])!
        }

        print("  Chunk size: \(chunkSize) bytes, Total chunks: \(chunks.count)")

        var chunkTimes: [Double] = []
        let incrementalResult = runner.measure(name: "Incremental parse ~10KB (full)") {
            let incrementalParser = IncrementalMarkdownParser()
            for chunk in chunks {
                let start = DispatchTime.now()
                _ = incrementalParser.append(chunk)
                let end = DispatchTime.now()
                chunkTimes.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
            }
        }
        incrementalResult.report()

        // Per-chunk statistics (from last iteration)
        if !chunkTimes.isEmpty {
            let perChunkResult = BenchmarkResult(name: "Per-chunk append + render", samples: Array(chunkTimes.suffix(chunks.count)))
            perChunkResult.report()
            checkTarget("Streaming chunk", perChunkResult.median, target: 0.5, p95: perChunkResult.p95, p95Target: 1.0)
        }
        print()

        // MARK: - Memory Snapshot
        print("-" * 60)
        print("MEMORY USAGE (approximate)")
        print("-" * 60)

        // Force a parse and measure retained size
        let doc = try! parser.parse(largeDoc)
        let docMemory = MemoryLayout.size(ofValue: doc)
        print("  Document struct size: \(docMemory) bytes")
        print("  Source data retained: \(doc.sourceData.count) bytes")
        print("  Block count: \(countBlocks(doc.blocks))")
        print()

        // MARK: - Summary
        print("=" * 60)
        print("SUMMARY - v1.0 Performance Targets")
        print("=" * 60)
        printSummary(parseMedium, renderMedium, chunkTimes.isEmpty ? nil : BenchmarkResult(name: "chunk", samples: Array(chunkTimes.suffix(chunks.count))))
    }

    static func checkTarget(_ name: String, _ median: Double, target: Double, p95: Double, p95Target: Double) {
        let medianPass = median <= target
        let p95Pass = p95 <= p95Target
        let medianSymbol = medianPass ? "PASS" : "FAIL"
        let p95Symbol = p95Pass ? "PASS" : "FAIL"
        print("    Target check: median \(String(format: "%.3f", median))ms <= \(target)ms [\(medianSymbol)]")
        print("    Target check: p95 \(String(format: "%.3f", p95))ms <= \(p95Target)ms [\(p95Symbol)]")
    }

    static func countBlocks(_ blocks: [MarkdownBlock]) -> Int {
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

    static func printSummary(_ parse: BenchmarkResult, _ render: BenchmarkResult, _ chunk: BenchmarkResult?) {
        print()
        print("  Parse 10KB:   median=\(String(format: "%.3f", parse.median))ms (target <1ms)    \(parse.median < 1.0 ? "PASS" : "FAIL")")
        print("  Render 10KB:  median=\(String(format: "%.3f", render.median))ms (target <5ms)    \(render.median < 5.0 ? "PASS" : "FAIL")")
        if let chunk = chunk {
            print("  Chunk parse:  median=\(String(format: "%.3f", chunk.median))ms (target <0.5ms)  \(chunk.median < 0.5 ? "PASS" : "FAIL")")
        }
        print()
    }
}

// Helper for string repetition
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
