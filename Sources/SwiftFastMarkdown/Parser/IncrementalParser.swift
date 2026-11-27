import Foundation

/// Incremental Markdown parser optimized for streaming content (such as AI responses).
///
/// Instead of re-parsing the entire document on every chunk, `IncrementalMarkdownParser`:
/// 1. Appends incoming bytes into a single contiguous `sourceData: Data` buffer (bounded by `MD4CParser.maxInputByteCount`).
/// 2. Parses only the uncommitted pending suffix (`stableEndOffset ..< sourceData.count`) once via `MD4CParser.parseSlice(..., baseOffset:startingOrdinal:scratch:)`.
/// 3. Stabilizes completed top-level blocks directly from `md4c`'s own AST whenever a subsequent top-level block (`.paragraph`, `.heading`, `.blockQuote`, or `.table`) begins on a line immediately preceded by a blank line and terminated by a CommonMark §2.2 line ending (`\n`, `\r\n`, or bare `\r` followed by another byte) — guaranteeing block-structure parity with full `md4c` parsing across nested containers, fenced code blocks, and HTML blocks without maintaining a duplicate CommonMark state machine (note: link reference definitions spanning separate stabilized chunks require full-document parsing).
/// 4. Replaces only the uncommitted pending suffix in `cachedBlocks` in place (O(pendingBlocks) when uniquely referenced, CoW-isolated if the caller retains an earlier snapshot).
public final class IncrementalMarkdownParser: Sendable {

    /// Configuration for incremental parsing.
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

// MARK: - Internal State

/// Thread-safe state container for incremental parsing.
///
/// Key performance and soundness invariants:
/// - Single append-only `sourceData: Data` buffer (zero `stable + pending` copies),
///   bounded at `MD4CParser.maxInputByteCount`.
/// - Single `cachedBlocks: [MarkdownBlock]` array whose prefix `0..<stableCount`
///   holds finalized blocks and whose suffix `stableCount...` is replaced in
///   place on each chunk — O(pendingBlocks) when uniquely referenced, and
///   automatically CoW-isolated if the caller retains a prior `MarkdownDocument`.
/// - Reusable `MD4CParser.ReusableScratch` eliminates per-chunk parser buffer
///   allocations.
/// - Stabilization decisions are derived directly from `md4c`'s own parsed
///   top-level blocks at blank-line boundaries before a completed top-level
///   non-container-continuable block (`.paragraph`, `.heading`, `.blockQuote`,
///   or `.table`), preserving block-structure parity for CommonMark §4.5/§4.6/§5
///   fences, HTML blocks, and nested containers (cross-chunk link reference
///   definitions require full-document parsing).
private final class IncrementalState: @unchecked Sendable {
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

    init(options: ParseOptions) {
        self.options = options
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
            var appended = false
            copy.withUTF8 { buf in
                if let base = buf.baseAddress, !buf.isEmpty {
                    let remainingBudget = MD4CParser.maxInputByteCount - sourceData.count
                    guard remainingBudget > 0 else { return }
                    let toCopy = Swift.min(buf.count, remainingBudget)
                    sourceData.append(base, count: toCopy)
                    appended = true
                }
            }
            if appended {
                documentID = UUID()
                updateBlocksLocked()
            }
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
            let remainingBudget = MD4CParser.maxInputByteCount - sourceData.count
            if remainingBudget > 0 {
                if data.count <= remainingBudget {
                    sourceData.append(data)
                } else {
                    sourceData.append(data.prefix(remainingBudget))
                }
                documentID = UUID()
                updateBlocksLocked()
            }
        }

        return MarkdownDocument(blocks: cachedBlocks, sourceData: sourceData, id: documentID)
    }

    func finalizeAndBuild() -> MarkdownDocument {
        lock.lock()
        defer { lock.unlock() }

        if !finalized {
            finalized = true
            documentID = UUID()

            // Discard pending tail and parse any remaining uncommitted bytes once.
            if cachedBlocks.count > stableCount {
                cachedBlocks.removeSubrange(stableCount..<cachedBlocks.count)
            }

            if stableEndOffset < sourceData.count, let baseOffset = UInt32(exactly: stableEndOffset) {
                let start = stableEndOffset
                let length = sourceData.count - start
                let parsed: (blocks: [MarkdownBlock], lastOrdinal: UInt32)? = sourceData.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return nil
                    }
                    let slice = UnsafeBufferPointer(start: base + start, count: length)
                    return try? parser.parseSlice(
                        slice,
                        baseOffset: baseOffset,
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
    }

    // MARK: - Single-Parse md4c-Backed Stabilization

    private func updateBlocksLocked() {
        // 1. Remove previous pending tail blocks in O(pendingBlocks)
        if cachedBlocks.count > stableCount {
            cachedBlocks.removeSubrange(stableCount..<cachedBlocks.count)
        }

        let totalCount = sourceData.count
        guard stableEndOffset < totalCount, let baseOffset = UInt32(exactly: stableEndOffset) else {
            return
        }

        // 2. Parse only the uncommitted suffix once with md4c.
        let start = stableEndOffset
        let length = totalCount - start
        sourceData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            let slice = UnsafeBufferPointer(start: base + start, count: length)
            guard let parsed = try? parser.parseSlice(
                slice,
                baseOffset: baseOffset,
                startingOrdinal: lastOrdinal,
                options: options,
                scratch: scratch
            ) else {
                return
            }

            guard !parsed.blocks.isEmpty else { return }
            cachedBlocks.append(contentsOf: parsed.blocks)

            // 3. Stabilize prefix `0 ..< k` directly from md4c's own top-level blocks.
            //    We search backward for the latest block `k >= 1` whose first line is
            //    mathematically proven to start at column 0 right after a blank line
            //    and is already newline-terminated (so no future bytes can merge it
            //    back into `0 ..< k`).
            guard parsed.blocks.count >= 2 else { return }
            for k in stride(from: parsed.blocks.count - 1, through: 1, by: -1) {
                if let cut = Self.safeStabilizationCut(
                    before: parsed.blocks[k],
                    previous: parsed.blocks[k - 1],
                    in: base,
                    totalCount: totalCount,
                    minOffset: stableEndOffset
                ) {
                    stableCount += k
                    stableEndOffset = cut
                    lastOrdinal = parsed.lastOrdinal
                    break
                }
            }
        }
    }

    /// Returns the column-0 byte offset where `block` starts if and only if:
    /// 1. `block` is a top-level `.paragraph`, `.heading`, `.blockQuote`, or `.table`
    ///    (block kinds that cannot contain an unquoted blank line before their first text byte).
    /// 2. `block`'s first line is already terminated by a CommonMark §2.2 line ending
    ///    (`\n`, `\r\n`, or bare `\r` followed by another byte so split CRLF waits),
    ///    so subsequent chunks cannot turn an incomplete prefix like `"2"` into `"2. "`.
    /// 3. The line immediately preceding `cut` is blank (`0x20`/`0x09` only, LF/CRLF/bare-CR aware), which
    ///    guarantees `md4c` was at top-level blank state at `cut` (`n_containers == 0`, outside
    ///    every fenced code block, indented code block, HTML block, list, and blockquote).
    /// 4. For `.blockQuote`, `cut` begins with 0–3 columns of whitespace followed by `>`.
    @inline(__always)
    private static func safeStabilizationCut(
        before block: MarkdownBlock,
        previous: MarkdownBlock,
        in base: UnsafePointer<UInt8>,
        totalCount: Int,
        minOffset: Int
    ) -> Int? {
        let isBlockQuote: Bool
        switch block {
        case .paragraph, .heading, .table:
            isBlockQuote = false
        case .blockQuote:
            isBlockQuote = true
        case .codeBlock, .list, .htmlBlock, .thematicBreak:
            return nil
        }

        let blockID = block.id
        guard blockID.end > blockID.start else { return nil }
        let start = Int(blockID.start)
        guard start > minOffset && start < totalCount else { return nil }

        // First line of `block` must already end with a CommonMark §2.2 line ending
        // ('\n', "\r\n", or bare '\r' followed by another byte so split CRLF waits).
        var hasLineEnding = false
        var scan = start
        while scan < totalCount {
            let b = base[scan]
            if b == 0x0A {
                hasLineEnding = true
                break
            }
            if b == 0x0D && scan + 1 < totalCount {
                hasLineEnding = true
                break
            }
            scan += 1
        }
        guard hasLineEnding else { return nil }

        // Scan backward to column 0 of the line containing `start` (respecting '\n' and bare '\r').
        var cut = start
        while cut > minOffset && base[cut - 1] != 0x0A && base[cut - 1] != 0x0D {
            cut -= 1
        }
        guard cut > minOffset else { return nil }

        // Sanity check: `cut` must lie strictly past the previous block's recorded bytes.
        let prevID = previous.id
        if prevID.end > prevID.start && cut <= Int(prevID.end) {
            return nil
        }

        // Verify the line immediately before `cut` is blank (spaces/tabs only, LF/CRLF/bare-CR aware).
        var prevLineEnd = cut - 1 // points at '\n' or bare '\r'
        if base[prevLineEnd] == 0x0A && prevLineEnd > minOffset && base[prevLineEnd - 1] == 0x0D {
            prevLineEnd -= 1
        }
        var p = prevLineEnd
        while p > minOffset && base[p - 1] != 0x0A && base[p - 1] != 0x0D {
            p -= 1
            let b = base[p]
            if b != 0x20 && b != 0x09 {
                return nil
            }
        }

        // For blockquotes, confirm `cut` opens with 0–3 columns of indent + '>'.
        if isBlockQuote {
            var q = cut
            var cols = 0
            while q < start {
                let b = base[q]
                if b == 0x20 {
                    cols += 1
                    q += 1
                } else if b == 0x09 {
                    cols += 4 - (cols % 4)
                    q += 1
                } else {
                    break
                }
            }
            guard cols <= 3 && q < totalCount && base[q] == 0x3E else { return nil }
        }

        return cut
    }
}
