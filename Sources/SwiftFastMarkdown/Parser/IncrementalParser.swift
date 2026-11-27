import Foundation
import Darwin

/// An incremental markdown parser that efficiently processes streaming content.
///
/// This parser maintains a single append-only source buffer, scans only newly
/// completed lines for block boundaries via SIMD `memchr` (O(chunk) per append,
/// O(n) total), reuses scratch parser buffers across chunks, and updates the
/// pending tail of `cachedBlocks` in place (protected by Swift Array CoW when
/// callers retain earlier `MarkdownDocument` snapshots).
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

    private let state: IncrementalState

    public init(configuration: Configuration = Configuration()) {
        self.state = IncrementalState(options: configuration.options)
    }

    /// Appends a chunk of markdown content and returns the updated document.
    ///
    /// - Parameter chunk: The new markdown content to append.
    /// - Returns: The current document state including stable and pending blocks.
    public func append(_ chunk: String) -> MarkdownDocument {
        state.appendAndBuild(chunk)
    }

    /// Appends a chunk of markdown content as raw bytes.
    ///
    /// - Parameter data: The new markdown content as Data.
    /// - Returns: The current document state.
    public func append(_ data: Data) -> MarkdownDocument {
        state.appendAndBuild(data)
    }

    /// Signals that no more content will be appended and finalizes the document.
    ///
    /// - Returns: The final parsed document.
    public func finalize() -> MarkdownDocument {
        state.finalizeAndBuild()
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
/// Key performance invariants:
/// - Single append-only `sourceData: Data` buffer (zero `stable + pending` copies).
/// - Single `cachedBlocks: [MarkdownBlock]` array whose prefix `0..<stableCount`
///   holds finalized blocks and whose suffix `stableCount...` is replaced in
///   place on each token — O(1) when uniquely referenced, and automatically
///   CoW-isolated if the caller retains a prior `MarkdownDocument`.
/// - Reusable `MD4CParser.ReusableScratch` eliminates per-chunk parser buffer
///   allocations.
/// - Incremental `memchr` line scanner inspects each incoming byte at most once.
private final class IncrementalState: @unchecked Sendable {
    struct Snapshot {
        let blocks: [MarkdownBlock]
        let sourceData: Data
        let stableCount: Int
        let stableEndOffset: Int
        let isFinalized: Bool
        let documentID: UUID
    }

    private let lock = NSLock()
    private let options: ParseOptions
    private let parser = MD4CParser()
    private let scratch = MD4CParser.ReusableScratch()

    // All mutable state below is only accessed while holding `lock`.
    private var cachedBlocks: [MarkdownBlock] = []
    private var stableCount: Int = 0
    private var sourceData: Data = Data()
    private var stableEndOffset: Int = 0
    private var lastOrdinal: UInt32 = 0
    private var finalized: Bool = false
    private var documentID: UUID = UUID()

    // Incremental line-scanner cursor state (each byte scanned at most once).
    private var scanOffset: Int = 0
    private var inFencedBlock: Bool = false
    private var fenceChar: UInt8 = 0
    private var fenceLength: Int = 0
    private var sawLineSinceStable: Bool = false

    init(options: ParseOptions) {
        self.options = options
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            blocks: cachedBlocks,
            sourceData: sourceData,
            stableCount: stableCount,
            stableEndOffset: stableEndOffset,
            isFinalized: finalized,
            documentID: documentID
        )
    }

    var stableBlockCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stableCount
    }

    var pendingString: String {
        lock.lock()
        defer { lock.unlock() }
        guard stableEndOffset < sourceData.count else { return "" }
        return sourceData.withUnsafeBytes { raw in
            let slice = raw[stableEndOffset..<raw.count]
            return String(decoding: slice, as: UTF8.self)
        }
    }

    func appendAndBuild(_ chunk: String) -> MarkdownDocument {
        lock.lock()
        defer { lock.unlock() }

        guard !finalized else {
            return MarkdownDocument(blocks: cachedBlocks, sourceData: sourceData, id: documentID)
        }

        if !chunk.isEmpty {
            var copy = chunk
            copy.withUTF8 { buf in
                if let base = buf.baseAddress, !buf.isEmpty {
                    sourceData.append(base, count: buf.count)
                }
            }
            updateBlocksLocked()
        }

        return MarkdownDocument(blocks: cachedBlocks, sourceData: sourceData, id: documentID)
    }

    func appendAndBuild(_ data: Data) -> MarkdownDocument {
        lock.lock()
        defer { lock.unlock() }

        guard !finalized else {
            return MarkdownDocument(blocks: cachedBlocks, sourceData: sourceData, id: documentID)
        }

        if !data.isEmpty {
            sourceData.append(data)
            updateBlocksLocked()
        }

        return MarkdownDocument(blocks: cachedBlocks, sourceData: sourceData, id: documentID)
    }

    func finalizeAndBuild() -> MarkdownDocument {
        lock.lock()
        defer { lock.unlock() }

        if !finalized {
            finalized = true
            // Drop any previous pending tail blocks before committing final tail
            if cachedBlocks.count > stableCount {
                cachedBlocks.removeSubrange(stableCount..<cachedBlocks.count)
            }
            if stableEndOffset < sourceData.count {
                let start = stableEndOffset
                let length = sourceData.count - start
                let parsed: (blocks: [MarkdownBlock], lastOrdinal: UInt32)? = sourceData.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return nil
                    }
                    let slice = UnsafeBufferPointer(start: base + start, count: length)
                    return try? parser.parseSlice(
                        slice,
                        baseOffset: UInt32(start),
                        startingOrdinal: lastOrdinal,
                        options: options,
                        scratch: scratch
                    )
                }
                if let parsed {
                    cachedBlocks.append(contentsOf: parsed.blocks)
                    stableCount = cachedBlocks.count
                    lastOrdinal = parsed.lastOrdinal
                    stableEndOffset = sourceData.count
                    scanOffset = sourceData.count
                    inFencedBlock = false
                    fenceChar = 0
                    fenceLength = 0
                    sawLineSinceStable = false
                }
            }
        }

        return MarkdownDocument(blocks: cachedBlocks, sourceData: sourceData, id: documentID)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        cachedBlocks.removeAll(keepingCapacity: true)
        stableCount = 0
        sourceData.removeAll(keepingCapacity: true)
        stableEndOffset = 0
        lastOrdinal = 0
        finalized = false
        documentID = UUID()
        scanOffset = 0
        inFencedBlock = false
        fenceChar = 0
        fenceLength = 0
        sawLineSinceStable = false
    }

    // MARK: - Incremental Stabilization + In-Place Pending Tail Update

    private func updateBlocksLocked() {
        // 1. Remove previous pending tail blocks in O(pendingBlocks)
        if cachedBlocks.count > stableCount {
            cachedBlocks.removeSubrange(stableCount..<cachedBlocks.count)
        }

        // 2. Advance incremental line scanner and commit newly stabilized blocks
        if let boundary = findNewBoundaryLocked(), boundary > stableEndOffset {
            let start = stableEndOffset
            let length = boundary - start
            let parsed: (blocks: [MarkdownBlock], lastOrdinal: UInt32)? = sourceData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return nil
                }
                let slice = UnsafeBufferPointer(start: base + start, count: length)
                return try? parser.parseSlice(
                    slice,
                    baseOffset: UInt32(start),
                    startingOrdinal: lastOrdinal,
                    options: options,
                    scratch: scratch
                )
            }
            if let parsed {
                cachedBlocks.append(contentsOf: parsed.blocks)
                stableCount = cachedBlocks.count
                lastOrdinal = parsed.lastOrdinal
                stableEndOffset = boundary
                sawLineSinceStable = (scanOffset > boundary)
            }
        }

        // 3. Parse only the remaining pending tail and append directly onto cachedBlocks
        let totalCount = sourceData.count
        if stableEndOffset < totalCount {
            let start = stableEndOffset
            let length = totalCount - start
            let pending: [MarkdownBlock]? = sourceData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return nil
                }
                let slice = UnsafeBufferPointer(start: base + start, count: length)
                return try? parser.parseSlice(
                    slice,
                    baseOffset: UInt32(start),
                    startingOrdinal: lastOrdinal,
                    options: options,
                    scratch: scratch
                ).blocks
            }
            if let pending, !pending.isEmpty {
                cachedBlocks.append(contentsOf: pending)
            }
        }
    }

    /// Scans only newly completed lines (terminated by `0x0A`) from `scanOffset`
    /// using `memchr`, so every byte in the stream is inspected at most once.
    private func findNewBoundaryLocked() -> Int? {
        guard scanOffset < sourceData.count else { return nil }

        return sourceData.withUnsafeBytes { raw -> Int? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            let totalCount = raw.count
            var lastBoundary: Int?

            while scanOffset < totalCount {
                let remaining = totalCount - scanOffset
                guard let found = memchr(base + scanOffset, 0x0A, remaining) else {
                    break
                }

                let nlPos = UnsafeRawPointer(found) - UnsafeRawPointer(base)
                let nextLineStart = nlPos + 1

                var firstNonWS = scanOffset
                while firstNonWS < nlPos {
                    let b = base[firstNonWS]
                    if b != 0x20 && b != 0x09 { break }
                    firstNonWS += 1
                }

                if firstNonWS == nlPos {
                    if !inFencedBlock && sawLineSinceStable {
                        lastBoundary = nextLineStart
                    }
                    sawLineSinceStable = true
                } else {
                    let firstByte = base[firstNonWS]
                    if !inFencedBlock && (firstByte == 0x60 || firstByte == 0x7E) {
                        var len = 0
                        var p = firstNonWS
                        while p < nlPos && base[p] == firstByte {
                            len += 1
                            p += 1
                        }
                        if len >= 3 {
                            inFencedBlock = true
                            fenceChar = firstByte
                            fenceLength = len
                        }
                    } else if inFencedBlock && firstByte == fenceChar {
                        var len = 0
                        var p = firstNonWS
                        while p < nlPos && base[p] == fenceChar {
                            len += 1
                            p += 1
                        }
                        if len >= fenceLength {
                            inFencedBlock = false
                            fenceChar = 0
                            fenceLength = 0
                            lastBoundary = nextLineStart
                        }
                    }
                    sawLineSinceStable = true
                }

                scanOffset = nextLineStart
            }

            return lastBoundary
        }
    }
}
