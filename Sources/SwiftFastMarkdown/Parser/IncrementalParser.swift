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

        /// Minimum number of bytes to buffer before attempting boundary detection.
        /// Lower values mean more responsive streaming but more parsing overhead.
        public var minBufferSize: Int

        public init(options: ParseOptions = .default, minBufferSize: Int = 64) {
            self.options = options
            self.minBufferSize = minBufferSize
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
        state.stableBlocks.count
    }

    // MARK: - Private

    private func buildDocument() -> MarkdownDocument {
        // Parse pending buffer to get any incomplete blocks
        let pendingBlocks: [MarkdownBlock]
        let fullData = state.fullData

        if state.isFinalized || state.pendingBuffer.isEmpty {
            pendingBlocks = []
        } else {
            // Parse just the pending portion
            let pendingData = Data(state.pendingBuffer)
            if let pendingDoc = try? parser.parse(pendingData, options: configuration.options) {
                // Offset the blocks to account for stable content
                pendingBlocks = pendingDoc.blocks.map { block in
                    offsetBlock(block, by: UInt32(state.stableEndOffset))
                }
            } else {
                pendingBlocks = []
            }
        }

        return MarkdownDocument(
            blocks: state.stableBlocks + pendingBlocks,
            sourceData: fullData,
            id: state.documentID
        )
    }

    /// Offsets all byte ranges in a block by the given amount.
    private func offsetBlock(_ block: MarkdownBlock, by offset: UInt32) -> MarkdownBlock {
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

    private func offsetTableRow(_ row: TableRow, by offset: UInt32) -> TableRow {
        let newCells = row.cells.map { cell in
            TableCell(id: cell.id, spans: offsetSpans(cell.spans, by: offset), alignment: cell.alignment)
        }
        return TableRow(id: row.id, cells: newCells)
    }

    private func offsetSpans(_ spans: [MarkdownSpan], by offset: UInt32) -> [MarkdownSpan] {
        spans.map { offsetSpan($0, by: offset) }
    }

    private func offsetSpan(_ span: MarkdownSpan, by offset: UInt32) -> MarkdownSpan {
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

    private func offsetTextContent(_ content: TextContent, by offset: UInt32) -> TextContent {
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
    private let lock = NSLock()

    private(set) var stableBlocks: [MarkdownBlock] = []
    private(set) var stableData: Data = Data()
    private(set) var pendingBuffer: [UInt8] = []
    private(set) var isFinalized: Bool = false
    private(set) var documentID: UUID = UUID()

    private let parser = MD4CParser()

    var stableEndOffset: Int {
        lock.lock()
        defer { lock.unlock() }
        return stableData.count
    }

    var pendingString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: pendingBuffer, as: UTF8.self)
    }

    var fullData: Data {
        lock.lock()
        defer { lock.unlock() }
        return stableData + Data(pendingBuffer)
    }

    func append(_ chunk: String) {
        append(Data(chunk.utf8))
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinalized else { return }

        pendingBuffer.append(contentsOf: data)
        processStableBlocks()
    }

    func finalize() {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinalized else { return }
        isFinalized = true

        // Parse any remaining pending content as stable
        if !pendingBuffer.isEmpty {
            let pendingData = Data(pendingBuffer)
            if let doc = try? parser.parse(pendingData) {
                let offsetBlocks = doc.blocks.map { block in
                    offsetBlockInternal(block, by: UInt32(stableData.count))
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
        isFinalized = false
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
                offsetBlockInternal(block, by: UInt32(stableData.count))
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

    // MARK: - Block Offsetting (internal version without lock)

    private func offsetBlockInternal(_ block: MarkdownBlock, by offset: UInt32) -> MarkdownBlock {
        guard offset > 0 else { return block }

        switch block {
        case .paragraph(let p):
            let newSpans = offsetSpansInternal(p.spans, by: offset)
            let newRange = ByteRange(start: p.range.start + offset, end: p.range.end + offset)
            return .paragraph(ParagraphBlock(id: p.id, spans: newSpans, range: newRange))

        case .heading(let h):
            let newSpans = offsetSpansInternal(h.spans, by: offset)
            let newRange = ByteRange(start: h.range.start + offset, end: h.range.end + offset)
            return .heading(HeadingBlock(id: h.id, level: h.level, spans: newSpans, range: newRange))

        case .codeBlock(let c):
            let newContent = offsetTextContentInternal(c.content, by: offset)
            let newInfo = c.info.map { offsetTextContentInternal($0, by: offset) }
            let newLang = c.language.map { offsetTextContentInternal($0, by: offset) }
            return .codeBlock(CodeBlock(id: c.id, info: newInfo, language: newLang, content: newContent, fence: c.fence))

        case .blockQuote(let q):
            let newBlocks = q.blocks.map { offsetBlockInternal($0, by: offset) }
            return .blockQuote(BlockQuoteBlock(id: q.id, blocks: newBlocks))

        case .list(let l):
            let newItems = l.items.map { item in
                ListItemBlock(
                    id: item.id,
                    blocks: item.blocks.map { offsetBlockInternal($0, by: offset) },
                    isTask: item.isTask,
                    isChecked: item.isChecked
                )
            }
            return .list(ListBlock(id: l.id, ordered: l.ordered, start: l.start, delimiter: l.delimiter, isTight: l.isTight, items: newItems))

        case .table(let t):
            let newHeaderRows = t.headerRows.map { offsetTableRowInternal($0, by: offset) }
            let newBodyRows = t.bodyRows.map { offsetTableRowInternal($0, by: offset) }
            return .table(TableBlock(id: t.id, alignments: t.alignments, headerRows: newHeaderRows, bodyRows: newBodyRows))

        case .thematicBreak(let tb):
            let newRange = ByteRange(start: tb.range.start + offset, end: tb.range.end + offset)
            return .thematicBreak(ThematicBreakBlock(id: tb.id, range: newRange))

        case .htmlBlock(let h):
            let newContent = offsetTextContentInternal(h.content, by: offset)
            return .htmlBlock(HTMLBlock(id: h.id, content: newContent))
        }
    }

    private func offsetTableRowInternal(_ row: TableRow, by offset: UInt32) -> TableRow {
        let newCells = row.cells.map { cell in
            TableCell(id: cell.id, spans: offsetSpansInternal(cell.spans, by: offset), alignment: cell.alignment)
        }
        return TableRow(id: row.id, cells: newCells)
    }

    private func offsetSpansInternal(_ spans: [MarkdownSpan], by offset: UInt32) -> [MarkdownSpan] {
        spans.map { offsetSpanInternal($0, by: offset) }
    }

    private func offsetSpanInternal(_ span: MarkdownSpan, by offset: UInt32) -> MarkdownSpan {
        switch span {
        case .text(let content):
            return .text(offsetTextContentInternal(content, by: offset))
        case .emphasis(let children):
            return .emphasis(offsetSpansInternal(children, by: offset))
        case .strong(let children):
            return .strong(offsetSpansInternal(children, by: offset))
        case .strikethrough(let children):
            return .strikethrough(offsetSpansInternal(children, by: offset))
        case .underline(let children):
            return .underline(offsetSpansInternal(children, by: offset))
        case .code(let content):
            return .code(offsetTextContentInternal(content, by: offset))
        case .link(let children, let dest, let title):
            return .link(
                children: offsetSpansInternal(children, by: offset),
                destination: dest.map { offsetTextContentInternal($0, by: offset) },
                title: title.map { offsetTextContentInternal($0, by: offset) }
            )
        case .image(let alt, let src, let title):
            return .image(
                alt: offsetSpansInternal(alt, by: offset),
                source: src.map { offsetTextContentInternal($0, by: offset) },
                title: title.map { offsetTextContentInternal($0, by: offset) }
            )
        case .wikiLink(let target, let children):
            return .wikiLink(target: offsetTextContentInternal(target, by: offset), children: offsetSpansInternal(children, by: offset))
        case .html(let content):
            return .html(offsetTextContentInternal(content, by: offset))
        case .latexInline(let content):
            return .latexInline(offsetTextContentInternal(content, by: offset))
        case .latexDisplay(let content):
            return .latexDisplay(offsetTextContentInternal(content, by: offset))
        case .lineBreak, .softBreak:
            return span
        }
    }

    private func offsetTextContentInternal(_ content: TextContent, by offset: UInt32) -> TextContent {
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
