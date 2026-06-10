import Foundation

/// An incremental markdown parser that efficiently processes streaming content.
///
/// This parser maintains state between chunks and only re-parses content that
/// hasn't yet reached a stable block boundary. This achieves O(n) incremental
/// updates vs O(n²) for naive re-parsing.
///
/// ## Algorithm
///
/// 1. Append new chunk to `pendingBuffer`
/// 2. Scan for block boundaries:
///    - Blank lines (paragraph end)
///    - Fenced code block close (```)
///    - List item completion
///    - Heading (always single line)
/// 3. For each detected complete block:
///    - Parse block content with md4c
///    - Assign stable ID
///    - Append to `stableBlocks`
///    - Remove from `pendingBuffer`
/// 4. Return Document(stableBlocks + parse(pendingBuffer))
///
/// ## Correctness Invariant
///
/// For any document D split into chunks C1, C2, ..., Cn:
/// ```
/// IncrementalParse(IncrementalParse(...IncrementalParse(empty, C1), C2)..., Cn) == Parse(D)
/// ```
public final class IncrementalMarkdownParser: Sendable {
    /// Configuration for incremental parsing behavior.
    public struct Configuration: Sendable {
        /// Parse options passed to md4c.
        public var options: ParseOptions

        public init(options: ParseOptions = .default) {
            self.options = options
        }
    }

    private let configuration: Configuration
    private let parser: MD4CParser

    // State is managed through isolated instances
    private let state: IncrementalState

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.parser = MD4CParser()
        self.state = IncrementalState()
    }

    /// Appends a chunk of markdown content and returns the updated document.
    ///
    /// - Parameter chunk: The new markdown content to append.
    /// - Returns: The current document state including stable and pending blocks.
    public func append(_ chunk: String) -> MarkdownDocument {
        state.append(chunk)
        return buildDocument()
    }

    /// Appends a chunk of markdown content as raw bytes.
    ///
    /// - Parameter data: The new markdown content as Data.
    /// - Returns: The current document state.
    public func append(_ data: Data) -> MarkdownDocument {
        state.append(data)
        return buildDocument()
    }

    /// Signals that no more content will be appended and finalizes the document.
    ///
    /// - Returns: The final parsed document.
    public func finalize() -> MarkdownDocument {
        state.finalize()
        return buildDocument()
    }

    /// Resets the parser to its initial state.
    public func reset() {
        state.reset()
    }

    /// Returns the current pending buffer content (for debugging).
    public var pendingContent: String {
        state.pendingString
    }

    /// Returns the count of stable blocks parsed so far.
    public var stableBlockCount: Int {
        state.stableBlockCount
    }

    // MARK: - Private

    private func buildDocument() -> MarkdownDocument {
        // Take one consistent snapshot of the state; reading individual
        // properties separately could interleave with a concurrent append().
        let snapshot = state.snapshot()

        // Parse pending buffer to get any incomplete blocks
        let pendingBlocks: [MarkdownBlock]
        if snapshot.isFinalized || snapshot.pendingData.isEmpty {
            pendingBlocks = []
        } else if let pendingDoc = try? parser.parse(snapshot.pendingData, options: configuration.options) {
            // Offset the blocks to account for stable content
            pendingBlocks = pendingDoc.blocks.map { block in
                BlockOffsetter.offsetBlock(block, by: UInt32(snapshot.stableEndOffset))
            }
        } else {
            pendingBlocks = []
        }

        return MarkdownDocument(
            blocks: snapshot.stableBlocks + pendingBlocks,
            sourceData: snapshot.fullData,
            id: snapshot.documentID
        )
    }
}

// MARK: - Byte Range Offsetting

/// Pure functions that shift every byte range in a parsed block by a fixed
/// offset, so blocks parsed from a buffer slice line up with the full document.
enum BlockOffsetter {
    static func offsetBlock(_ block: MarkdownBlock, by offset: UInt32) -> MarkdownBlock {
        guard offset > 0 else { return block }

        switch block {
        case .paragraph(let p):
            let newSpans = offsetSpans(p.spans, by: offset)
            let newRange = ByteRange(start: p.range.start + offset, end: p.range.end + offset)
            return .paragraph(ParagraphBlock(id: p.id, spans: newSpans, range: newRange))

        case .heading(let h):
            let newSpans = offsetSpans(h.spans, by: offset)
            let newRange = ByteRange(start: h.range.start + offset, end: h.range.end + offset)
            return .heading(HeadingBlock(id: h.id, level: h.level, spans: newSpans, range: newRange))

        case .codeBlock(let c):
            let newContent = offsetTextContent(c.content, by: offset)
            let newInfo = c.info.map { offsetTextContent($0, by: offset) }
            let newLang = c.language.map { offsetTextContent($0, by: offset) }
            return .codeBlock(CodeBlock(id: c.id, info: newInfo, language: newLang, content: newContent, fence: c.fence))

        case .blockQuote(let q):
            let newBlocks = q.blocks.map { offsetBlock($0, by: offset) }
            return .blockQuote(BlockQuoteBlock(id: q.id, blocks: newBlocks))

        case .list(let l):
            let newItems = l.items.map { item in
                ListItemBlock(
                    id: item.id,
                    blocks: item.blocks.map { offsetBlock($0, by: offset) },
                    isTask: item.isTask,
                    isChecked: item.isChecked
                )
            }
            return .list(ListBlock(id: l.id, ordered: l.ordered, start: l.start, delimiter: l.delimiter, isTight: l.isTight, items: newItems))

        case .table(let t):
            let newHeaderRows = t.headerRows.map { offsetTableRow($0, by: offset) }
            let newBodyRows = t.bodyRows.map { offsetTableRow($0, by: offset) }
            return .table(TableBlock(id: t.id, alignments: t.alignments, headerRows: newHeaderRows, bodyRows: newBodyRows))

        case .thematicBreak(let tb):
            let newRange = ByteRange(start: tb.range.start + offset, end: tb.range.end + offset)
            return .thematicBreak(ThematicBreakBlock(id: tb.id, range: newRange))

        case .htmlBlock(let h):
            let newContent = offsetTextContent(h.content, by: offset)
            return .htmlBlock(HTMLBlock(id: h.id, content: newContent))
        }
    }

    private static func offsetTableRow(_ row: TableRow, by offset: UInt32) -> TableRow {
        let newCells = row.cells.map { cell in
            TableCell(id: cell.id, spans: offsetSpans(cell.spans, by: offset), alignment: cell.alignment)
        }
        return TableRow(id: row.id, cells: newCells)
    }

    private static func offsetSpans(_ spans: [MarkdownSpan], by offset: UInt32) -> [MarkdownSpan] {
        spans.map { offsetSpan($0, by: offset) }
    }

    private static func offsetSpan(_ span: MarkdownSpan, by offset: UInt32) -> MarkdownSpan {
        switch span {
        case .text(let content):
            return .text(offsetTextContent(content, by: offset))
        case .emphasis(let children):
            return .emphasis(offsetSpans(children, by: offset))
        case .strong(let children):
            return .strong(offsetSpans(children, by: offset))
        case .strikethrough(let children):
            return .strikethrough(offsetSpans(children, by: offset))
        case .underline(let children):
            return .underline(offsetSpans(children, by: offset))
        case .code(let content):
            return .code(offsetTextContent(content, by: offset))
        case .link(let children, let dest, let title):
            return .link(
                children: offsetSpans(children, by: offset),
                destination: dest.map { offsetTextContent($0, by: offset) },
                title: title.map { offsetTextContent($0, by: offset) }
            )
        case .image(let alt, let src, let title):
            return .image(
                alt: offsetSpans(alt, by: offset),
                source: src.map { offsetTextContent($0, by: offset) },
                title: title.map { offsetTextContent($0, by: offset) }
            )
        case .wikiLink(let target, let children):
            return .wikiLink(target: offsetTextContent(target, by: offset), children: offsetSpans(children, by: offset))
        case .html(let content):
            return .html(offsetTextContent(content, by: offset))
        case .latexInline(let content):
            return .latexInline(offsetTextContent(content, by: offset))
        case .latexDisplay(let content):
            return .latexDisplay(offsetTextContent(content, by: offset))
        case .lineBreak, .softBreak:
            return span
        }
    }

    private static func offsetTextContent(_ content: TextContent, by offset: UInt32) -> TextContent {
        switch content {
        case .bytes(let range):
            return .bytes(ByteRange(start: range.start + offset, end: range.end + offset))
        case .sequence(let seq):
            let newRanges = seq.ranges.map { ByteRange(start: $0.start + offset, end: $0.end + offset) }
            return .sequence(ByteRangeSequence(newRanges))
        case .string:
            return content
        }
    }
}

// MARK: - Internal State

/// Thread-safe state container for incremental parsing.
///
/// ## Design Note: NSLock vs Swift 6 Mutex
/// We use NSLock + @unchecked Sendable rather than Swift 6's Synchronization.Mutex
/// because:
/// 1. NSLock is battle-tested and correct
/// 2. The lock pattern here is simple and verifiable by inspection
/// 3. Mutex would require restructuring into Mutex<MutableState> wrapper pattern
/// 4. Both approaches provide the same runtime behavior (os_unfair_lock underneath)
///
/// The @unchecked Sendable is appropriate because we manually verify that all
/// mutable state access is protected by the lock.
private final class IncrementalState: @unchecked Sendable {
    /// A consistent view of the parser state, captured under a single lock
    /// acquisition so concurrent appends can never produce torn reads.
    struct Snapshot {
        let stableBlocks: [MarkdownBlock]
        let pendingData: Data
        let stableEndOffset: Int
        let fullData: Data
        let isFinalized: Bool
        let documentID: UUID
    }

    private let lock = NSLock()

    // All mutable state below is only accessed while holding `lock`.
    private var stableBlocks: [MarkdownBlock] = []
    private var stableData: Data = Data()
    private var pendingBuffer: [UInt8] = []
    private var finalized: Bool = false
    private var documentID: UUID = UUID()

    private let parser = MD4CParser()

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let pendingData = Data(pendingBuffer)
        return Snapshot(
            stableBlocks: stableBlocks,
            pendingData: pendingData,
            stableEndOffset: stableData.count,
            // Skip the concatenation when there is nothing pending (common
            // right after a block boundary stabilizes).
            fullData: pendingData.isEmpty ? stableData : stableData + pendingData,
            isFinalized: finalized,
            documentID: documentID
        )
    }

    var stableBlockCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stableBlocks.count
    }

    var pendingString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: pendingBuffer, as: UTF8.self)
    }

    func append(_ chunk: String) {
        append(Data(chunk.utf8))
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard !finalized else { return }

        pendingBuffer.append(contentsOf: data)
        processStableBlocks()
    }

    func finalize() {
        lock.lock()
        defer { lock.unlock() }

        guard !finalized else { return }
        finalized = true

        // Parse any remaining pending content as stable
        if !pendingBuffer.isEmpty {
            let pendingData = Data(pendingBuffer)
            if let doc = try? parser.parse(pendingData) {
                let offsetBlocks = doc.blocks.map { block in
                    BlockOffsetter.offsetBlock(block, by: UInt32(stableData.count))
                }
                stableBlocks.append(contentsOf: offsetBlocks)
                stableData.append(pendingData)
                pendingBuffer.removeAll()
            }
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        stableBlocks.removeAll()
        stableData.removeAll()
        pendingBuffer.removeAll()
        finalized = false
        documentID = UUID()
    }

    // MARK: - Block Boundary Detection

    private func processStableBlocks() {
        // Find the last stable block boundary
        guard let boundaryIndex = findLastStableBoundary() else { return }

        // Extract stable content
        let stableContent = Array(pendingBuffer[0..<boundaryIndex])
        let stableContentData = Data(stableContent)

        // Parse stable content
        if let doc = try? parser.parse(stableContentData) {
            // Offset blocks to account for already-stable data
            let offsetBlocks = doc.blocks.map { block in
                BlockOffsetter.offsetBlock(block, by: UInt32(stableData.count))
            }
            stableBlocks.append(contentsOf: offsetBlocks)
            stableData.append(stableContentData)

            // Remove stable content from pending buffer
            pendingBuffer.removeFirst(boundaryIndex)
        }
    }

    /// Finds the index of the last stable block boundary in the pending buffer.
    ///
    /// A block boundary is detected at:
    /// - Double newline (blank line) outside of fenced code blocks
    /// - Closing fence (```) matching opening fence
    private func findLastStableBoundary() -> Int? {
        var lastBoundary: Int?
        var i = 0
        var inFencedBlock = false
        var fenceChar: UInt8 = 0
        var fenceLength = 0
        var atLineStart = true

        while i < pendingBuffer.count {
            let byte = pendingBuffer[i]

            // Check for fenced code block markers at line start
            if atLineStart && !inFencedBlock && (byte == 0x60 || byte == 0x7E) {
                let (isFence, length) = checkFence(at: i, char: byte)
                if isFence {
                    inFencedBlock = true
                    fenceChar = byte
                    fenceLength = length
                    i += length
                    // Skip to end of line
                    while i < pendingBuffer.count && pendingBuffer[i] != 0x0A {
                        i += 1
                    }
                    if i < pendingBuffer.count {
                        i += 1 // Skip newline
                    }
                    atLineStart = true
                    continue
                }
            } else if atLineStart && inFencedBlock && byte == fenceChar {
                // Inside fenced block, check for closing fence
                let (isFence, length) = checkFence(at: i, char: byte)
                if isFence && length >= fenceLength {
                    // Found closing fence
                    inFencedBlock = false
                    i += length
                    // Skip to end of line to mark boundary
                    while i < pendingBuffer.count && pendingBuffer[i] != 0x0A {
                        i += 1
                    }
                    if i < pendingBuffer.count {
                        i += 1 // Include newline
                        lastBoundary = i
                    }
                    atLineStart = true
                    continue
                }
            }

            // Check for blank line (double newline) outside fenced blocks
            if !inFencedBlock && byte == 0x0A {
                var j = i + 1
                // Skip whitespace
                while j < pendingBuffer.count && (pendingBuffer[j] == 0x20 || pendingBuffer[j] == 0x09) {
                    j += 1
                }
                if j < pendingBuffer.count && pendingBuffer[j] == 0x0A {
                    // Found blank line - stable boundary after the blank line
                    lastBoundary = j + 1
                }
            }

            // Track line starts
            if byte == 0x0A {
                atLineStart = true
            } else if byte != 0x20 && byte != 0x09 {
                atLineStart = false
            }

            i += 1
        }

        return lastBoundary
    }

    /// Checks if there's a valid fence starting at the given index.
    private func checkFence(at index: Int, char: UInt8) -> (isFence: Bool, length: Int) {
        var length = 0
        var i = index

        while i < pendingBuffer.count && pendingBuffer[i] == char {
            length += 1
            i += 1
        }

        // Fence must be at least 3 characters
        return (length >= 3, length)
    }
}
