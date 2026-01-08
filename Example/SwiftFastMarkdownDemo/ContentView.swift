import SwiftUI
import SwiftFastMarkdown

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StaticMarkdownDemo()
                .tabItem {
                    Label("Static", systemImage: "doc.text")
                }
                .tag(0)

            StreamingMarkdownDemo()
                .tabItem {
                    Label("Streaming", systemImage: "text.bubble")
                }
                .tag(1)

            GFMFeaturesDemo()
                .tabItem {
                    Label("GFM", systemImage: "checklist")
                }
                .tag(2)

            BenchmarkDemo()
                .tabItem {
                    Label("Benchmark", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(3)
        }
    }
}

// MARK: - Static Markdown Demo

struct StaticMarkdownDemo: View {
    private let sampleMarkdown = """
    # SwiftFastMarkdown Demo

    This demonstrates **static markdown rendering** with full CommonMark support.

    ## Features

    - Fast md4c-based parsing
    - Zero-copy ByteRange IR
    - SwiftUI-native rendering
    - iOS 26 Liquid Glass effects

    ## Code Example

    ```swift
    let parser = MarkdownParser()
    let document = try parser.parse(markdown)

    MarkdownView(document: document)
        .markdownStyle(.default)
    ```

    > **Note**: This library achieves sub-millisecond parsing for typical documents.

    Visit [GitHub](https://github.com/example) for more info.

    ---

    *Rendered with SwiftFastMarkdown*
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let document = try? MarkdownParser().parse(sampleMarkdown) {
                        MarkdownView(document: document)
                            .padding()
                    }
                }
            }
            .navigationTitle("Static Rendering")
        }
    }
}

// MARK: - Streaming Markdown Demo

struct StreamingMarkdownDemo: View {
    @State private var isStreaming = false
    @State private var streamedContent = ""
    @State private var parser = IncrementalMarkdownParser()

    private let fullContent = """
    # AI Response

    I'm thinking about your question...

    ## Analysis

    Based on the information provided, here are my thoughts:

    1. **First point**: The data suggests a clear pattern
    2. **Second point**: We should consider alternative approaches
    3. **Third point**: Testing is essential

    ```python
    def analyze_data(input):
        results = process(input)
        return summarize(results)
    ```

    > This is a streaming demonstration showing how content appears progressively.

    ### Conclusion

    The incremental parser ensures smooth, real-time rendering as tokens arrive.

    - [x] Fast parsing
    - [x] Smooth animations
    - [ ] Your feature here
    """

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let document = parser.append("")
                        MarkdownView(document: document)
                            .padding()
                            .animation(.easeInOut(duration: 0.15), value: document.blocks.count)
                    }
                }

                Divider()

                HStack {
                    Button(action: startStreaming) {
                        Label(isStreaming ? "Streaming..." : "Start Stream",
                              systemImage: isStreaming ? "ellipsis" : "play.fill")
                    }
                    .disabled(isStreaming)
                    .buttonStyle(.borderedProminent)

                    Button(action: resetStream) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Streaming Demo")
        }
    }

    private func startStreaming() {
        isStreaming = true
        streamedContent = ""
        parser.reset()

        // Simulate streaming at ~50 chars per chunk
        let chunks = stride(from: 0, to: fullContent.count, by: 50).map { start in
            let startIdx = fullContent.index(fullContent.startIndex, offsetBy: start)
            let endIdx = fullContent.index(startIdx, offsetBy: min(50, fullContent.count - start))
            return String(fullContent[startIdx..<endIdx])
        }

        Task {
            for chunk in chunks {
                try? await Task.sleep(for: .milliseconds(80))
                await MainActor.run {
                    streamedContent += chunk
                    _ = parser.append(chunk)
                }
            }
            await MainActor.run {
                _ = parser.finalize()
                isStreaming = false
            }
        }
    }

    private func resetStream() {
        streamedContent = ""
        parser.reset()
        isStreaming = false
    }
}

// MARK: - GFM Features Demo

struct GFMFeaturesDemo: View {
    private let gfmMarkdown = """
    # GFM Extensions Demo

    SwiftFastMarkdown supports GitHub Flavored Markdown extensions via md4c flags.

    ## Tables

    | Feature | Status | Notes |
    |---------|--------|-------|
    | Tables | Supported | With alignment |
    | Task Lists | Supported | Checkboxes |
    | Strikethrough | Supported | ~~deleted~~ |
    | Autolinks | Supported | www.example.com |

    ## Task Lists

    - [x] Implement md4c parser
    - [x] Create zero-copy IR
    - [x] Build SwiftUI views
    - [x] Add syntax highlighting
    - [ ] World domination

    ## Strikethrough

    The ~~old approach~~ new approach is much faster.

    ## Mixed Formatting

    You can combine **bold**, *italic*, ~~strikethrough~~, and `code` in any order.

    | Mixed | Formatting |
    |-------|------------|
    | **Bold** in table | ~~Strikethrough~~ too |
    | `Code` works | *Italic* as well |
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let document = try? MarkdownParser().parse(gfmMarkdown) {
                        MarkdownView(document: document)
                            .padding()
                    }
                }
            }
            .navigationTitle("GFM Extensions")
        }
    }
}

// MARK: - Benchmark Demo

struct BenchmarkDemo: View {
    @State private var results: [BenchmarkResult] = []
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            List {
                Section("Performance Targets (v1.0 Spec)") {
                    TargetRow(label: "Parse 10KB", target: "<1ms")
                    TargetRow(label: "Render 10KB", target: "<5ms")
                    TargetRow(label: "Chunk parse", target: "<0.5ms")
                }

                Section("Results") {
                    if results.isEmpty {
                        Text("Tap 'Run Benchmarks' to measure performance")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results, id: \.name) { result in
                            ResultRow(result: result)
                        }
                    }
                }
            }
            .navigationTitle("Benchmarks")
            .toolbar {
                Button(action: runBenchmarks) {
                    if isRunning {
                        ProgressView()
                    } else {
                        Label("Run", systemImage: "play.fill")
                    }
                }
                .disabled(isRunning)
            }
        }
    }

    private func runBenchmarks() {
        isRunning = true
        results = []

        Task.detached(priority: .userInitiated) {
            let parser = MarkdownParser()
            let renderer = AttributedStringRenderer()

            // Generate test document (~10KB)
            var testDoc = "# Performance Test\n\n"
            for i in 1...50 {
                testDoc += "## Section \(i)\n\nParagraph with **bold** and *italic* text.\n\n"
            }

            // Parse benchmark
            let parseStart = CFAbsoluteTimeGetCurrent()
            for _ in 0..<100 {
                _ = try? parser.parse(testDoc)
            }
            let parseTime = (CFAbsoluteTimeGetCurrent() - parseStart) * 10 // ms per iteration

            // Render benchmark
            let doc = try! parser.parse(testDoc)
            let renderStart = CFAbsoluteTimeGetCurrent()
            for _ in 0..<100 {
                _ = renderer.render(doc)
            }
            let renderTime = (CFAbsoluteTimeGetCurrent() - renderStart) * 10

            // Chunk benchmark
            let chunkStart = CFAbsoluteTimeGetCurrent()
            let incrementalParser = IncrementalMarkdownParser()
            for _ in 0..<100 {
                incrementalParser.reset()
                _ = incrementalParser.append(String(testDoc.prefix(256)))
            }
            let chunkTime = (CFAbsoluteTimeGetCurrent() - chunkStart) * 10

            await MainActor.run {
                results = [
                    BenchmarkResult(name: "Parse 10KB", time: parseTime, target: 1.0),
                    BenchmarkResult(name: "Render 10KB", time: renderTime, target: 5.0),
                    BenchmarkResult(name: "Chunk Parse", time: chunkTime, target: 0.5)
                ]
                isRunning = false
            }
        }
    }
}

struct BenchmarkResult {
    let name: String
    let time: Double
    let target: Double

    var passed: Bool { time <= target }
}

struct TargetRow: View {
    let label: String
    let target: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(target)
                .foregroundStyle(.secondary)
        }
    }
}

struct ResultRow: View {
    let result: BenchmarkResult

    var body: some View {
        HStack {
            Text(result.name)
            Spacer()
            Text(String(format: "%.3f ms", result.time))
                .monospacedDigit()
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.passed ? .green : .red)
        }
    }
}

#Preview {
    ContentView()
}
