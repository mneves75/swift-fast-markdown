import Foundation
import CMD4C

public enum MarkdownParserError: Error {
    case parsingFailed(Int32)
    /// Input exceeded `MD4CParser.maxInputByteCount` (guards against 32-bit `MD_SIZE`
    /// narrowing traps and vendored `CMD4C` 32-bit buffer-growth truncation).
    case inputTooLarge(Int)
}

public struct MD4CParser: Sendable {
    /// Maximum accepted Markdown input size in bytes (256 MiB).
    /// Keeps all `MD_SIZE` conversions and vendored `CMD4C` temporary buffer
    /// growth arithmetic (`1.5x`) strictly below the 32-bit `UInt32` overflow boundary.
    public static let maxInputByteCount: Int = 256 * 1024 * 1024

    /// Maximum container and inline-span AST nesting depth preserved during parsing.
    /// Deeper containers/spans are flattened in place (preserving all leaf text) so
    /// Swift ARC value-witness destruction, `Equatable`, and renderers cannot overflow
    /// a 512 KB cooperative thread stack on deeply nested untrusted input.
    public static let maxNestingDepth: Int = 64

    public init() {}

    public func parse(_ input: String, options: ParseOptions = .default) throws -> MarkdownDocument {
        let data = Data(input.utf8)
        return try parse(data, options: options)
    }

    public func parse(_ data: Data, options: ParseOptions = .default) throws -> MarkdownDocument {
        guard !data.isEmpty else {
            return MarkdownDocument(blocks: [], sourceData: data)
        }

        return try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.bindMemory(to: MD_CHAR.self).baseAddress else {
                return MarkdownDocument(blocks: [], sourceData: data)
            }
            let context = ParserContext(estimatedDataCount: data.count)
            let (blocks, _) = try parseBuffer(
                context: context,
                baseAddress: baseAddress,
                count: data.count,
                baseOffset: 0,
                startingOrdinal: 0,
                options: options
            )
            return MarkdownDocument(blocks: blocks, sourceData: data)
        }
    }

    /// Reusable scratch storage for repeated slice parses (e.g. streaming in
    /// `IncrementalMarkdownParser`). Not thread-safe; caller owns synchronization.
    internal final class ReusableScratch {
        fileprivate let context: ParserContext

        init() {
            self.context = ParserContext(estimatedDataCount: 512)
        }
    }

    /// Internal fast path for incremental parsing: parses a contiguous byte
    /// slice directly with a pre-applied `baseOffset`, monotonic `startingOrdinal`,
    /// and optional reusable scratch buffers (zero scratch allocations per chunk).
    internal func parseSlice(
        _ bytes: UnsafeBufferPointer<UInt8>,
        baseOffset: UInt32,
        startingOrdinal: UInt32,
        options: ParseOptions = .default,
        scratch: ReusableScratch? = nil
    ) throws -> (blocks: [MarkdownBlock], lastOrdinal: UInt32) {
        guard !bytes.isEmpty, let rawBase = bytes.baseAddress else {
            return ([], startingOrdinal)
        }
        let context = scratch?.context ?? ParserContext(estimatedDataCount: bytes.count)
        return try rawBase.withMemoryRebound(to: MD_CHAR.self, capacity: bytes.count) { mdBase in
            try parseBuffer(
                context: context,
                baseAddress: mdBase,
                count: bytes.count,
                baseOffset: baseOffset,
                startingOrdinal: startingOrdinal,
                options: options
            )
        }
    }

    private func parseBuffer(
        context: ParserContext,
        baseAddress: UnsafePointer<MD_CHAR>,
        count: Int,
        baseOffset: UInt32,
        startingOrdinal: UInt32,
        options: ParseOptions
    ) throws -> (blocks: [MarkdownBlock], lastOrdinal: UInt32) {
        guard count >= 0, count <= Self.maxInputByteCount, let mdSize = MD_SIZE(exactly: count) else {
            throw MarkdownParserError.inputTooLarge(count)
        }
        context.reset(
            basePointer: baseAddress,
            dataCount: count,
            baseOffset: baseOffset,
            startingOrdinal: startingOrdinal
        )
        defer { context.clearTemporaryState() }

        var parser = MD_PARSER()
        parser.abi_version = 0
        parser.flags = UInt32(options.rawValue)
        parser.enter_block = ParserContext.enterBlockCallback
        parser.leave_block = ParserContext.leaveBlockCallback
        parser.enter_span = ParserContext.enterSpanCallback
        parser.leave_span = ParserContext.leaveSpanCallback
        parser.text = ParserContext.textCallback
        parser.debug_log = nil
        parser.syntax = nil

        let result = md_parse(baseAddress, mdSize, &parser, Unmanaged.passUnretained(context).toOpaque())
        if result != 0 {
            throw MarkdownParserError.parsingFailed(Int32(result))
        }

        return (context.finishDocumentBlocks(), context.ordinal)
    }
}

// MARK: - Zero-ARC-Copy Scratch Stack

/// Manual LIFO scratch stack that moves elements into exact-capacity `[T]` via
/// `moveInitialize` — zero ARC retains/releases on pop, zero CoW sharing of
/// scratch storage, and leak-free `deinit` even if parsing throws.
private final class ScratchStack<T> {
    private var storage: UnsafeMutablePointer<T>
    private var capacity: Int
    private(set) var count: Int = 0

    init(initialCapacity: Int) {
        let cap = Swift.max(4, initialCapacity)
        self.capacity = cap
        self.storage = UnsafeMutablePointer<T>.allocate(capacity: cap)
    }

    deinit {
        if count > 0 {
            storage.deinitialize(count: count)
        }
        storage.deallocate()
    }

    @inline(__always)
    func append(_ element: T) {
        if count == capacity {
            grow()
        }
        storage.advanced(by: count).initialize(to: element)
        count += 1
    }

    @inline(__always)
    var lastElement: T? {
        count > 0 ? storage[count - 1] : nil
    }

    @inline(__always)
    func replaceLast(_ element: T) {
        precondition(count > 0, "ScratchStack.replaceLast called on empty stack")
        storage[count - 1] = element
    }

    @inline(__always)
    func takeArray(from start: Int) -> [T] {
        precondition(start >= 0 && start <= count, "ScratchStack.takeArray start out of bounds")
        let n = count - start
        if n <= 0 { return [] }
        let src = storage.advanced(by: start)
        let result = Array<T>(unsafeUninitializedCapacity: n) { dest, initializedCount in
            dest.baseAddress!.moveInitialize(from: src, count: n)
            initializedCount = n
        }
        count = start
        return result
    }

    @inline(__always)
    func popLast() -> T {
        precondition(count > 0, "ScratchStack.popLast called on empty stack")
        count -= 1
        return storage.advanced(by: count).move()
    }

    @inline(__always)
    func removeAllKeepingCapacity() {
        if count > 0 {
            storage.deinitialize(count: count)
            count = 0
        }
    }

    @inline(never)
    private func grow() {
        let (newCapacity, overflow) = capacity.multipliedReportingOverflow(by: 2)
        precondition(!overflow && newCapacity > capacity, "ScratchStack capacity overflow")
        let newStorage = UnsafeMutablePointer<T>.allocate(capacity: newCapacity)
        if count > 0 {
            newStorage.moveInitialize(from: storage, count: count)
        }
        storage.deallocate()
        storage = newStorage
        capacity = newCapacity
    }
}

// MARK: - Flat-Buffer Single-Pass Parser Context

/// Builds the Markdown IR in a single pass using flat, strictly-LIFO
/// `ScratchStack` buffers (zero O(n²) copies, zero ARC retain/release churn on
/// slice extraction, and O(1) incremental byte-range tracking on each frame).
private final class ParserContext {
    var basePointer: UnsafePointer<MD_CHAR>?
    var baseAddressUInt: UInt = 0
    var dataCount: Int = 0
    var baseOffset: UInt32 = 0
    var ordinal: UInt32 = 0

    // Frame stacks
    private var blockStack: [BlockFrame] = []
    private var tableSectionStack: [TableSection] = []
    private var spanStack: [SpanFrame] = []
    private var skippedContainers: [UInt32] = []
    private var skippedSpans: [UInt32] = []

    // Zero-ARC-copy LIFO child buffers
    private let blockChildren: ScratchStack<MarkdownBlock>
    private let listItems: ScratchStack<ListItemBlock>
    private let tableHeaderRows: ScratchStack<TableRow>
    private let tableBodyRows: ScratchStack<TableRow>
    private let tableCells: ScratchStack<TableCell>
    private let textRanges: ScratchStack<ByteRange>
    private let spanChildren: ScratchStack<MarkdownSpan>
    private let inlineCodeRanges: ScratchStack<ByteRange>

    init(estimatedDataCount: Int) {
        if estimatedDataCount >= 1024 {
            let estimatedBlocks = Swift.min(512, Swift.max(8, estimatedDataCount >> 7))
            self.blockChildren = ScratchStack(initialCapacity: estimatedBlocks)
            self.spanChildren = ScratchStack(initialCapacity: 32)
            self.blockStack.reserveCapacity(16)
            self.spanStack.reserveCapacity(8)
        } else {
            self.blockChildren = ScratchStack(initialCapacity: 8)
            self.spanChildren = ScratchStack(initialCapacity: 12)
            self.blockStack.reserveCapacity(8)
            self.spanStack.reserveCapacity(4)
        }
        self.listItems = ScratchStack(initialCapacity: 8)
        self.tableHeaderRows = ScratchStack(initialCapacity: 4)
        self.tableBodyRows = ScratchStack(initialCapacity: 8)
        self.tableCells = ScratchStack(initialCapacity: 8)
        self.textRanges = ScratchStack(initialCapacity: 8)
        self.inlineCodeRanges = ScratchStack(initialCapacity: 8)
    }

    func reset(
        basePointer: UnsafePointer<MD_CHAR>,
        dataCount: Int,
        baseOffset: UInt32,
        startingOrdinal: UInt32
    ) {
        clearTemporaryState()
        self.basePointer = basePointer
        self.baseAddressUInt = UInt(bitPattern: basePointer)
        self.dataCount = dataCount
        self.baseOffset = baseOffset
        self.ordinal = startingOrdinal
    }

    func clearTemporaryState() {
        basePointer = nil
        baseAddressUInt = 0
        dataCount = 0
        blockStack.removeAll(keepingCapacity: true)
        tableSectionStack.removeAll(keepingCapacity: true)
        spanStack.removeAll(keepingCapacity: true)
        skippedContainers.removeAll(keepingCapacity: true)
        skippedSpans.removeAll(keepingCapacity: true)
        blockChildren.removeAllKeepingCapacity()
        listItems.removeAllKeepingCapacity()
        tableHeaderRows.removeAllKeepingCapacity()
        tableBodyRows.removeAllKeepingCapacity()
        tableCells.removeAllKeepingCapacity()
        textRanges.removeAllKeepingCapacity()
        spanChildren.removeAllKeepingCapacity()
        inlineCodeRanges.removeAllKeepingCapacity()
    }

    func finishDocumentBlocks() -> [MarkdownBlock] {
        guard !blockStack.isEmpty, case .doc = blockStack[0].kind else {
            return []
        }
        return blockChildren.takeArray(from: 0)
    }

    @inline(__always)
    private func nextID(kind: BlockKind, range: ByteRange) -> BlockID {
        ordinal &+= 1
        return BlockID(kind: kind.rawValue, start: range.start, end: range.end, ordinal: ordinal)
    }

    /// Bounds-checked conversion of an md4c pointer + length into a `ByteRange`
    /// shifted by `baseOffset`. All pointer arithmetic flows through here.
    @inline(__always)
    private func pointerRange(_ text: UnsafePointer<MD_CHAR>?, size: MD_SIZE) -> ByteRange? {
        guard let text, basePointer != nil else { return nil }
        let textAddress = UInt(bitPattern: text)
        guard textAddress >= baseAddressUInt else { return nil }

        let offsetUInt = textAddress - baseAddressUInt
        guard offsetUInt <= UInt(dataCount) else { return nil }
        let offset = Int(offsetUInt)
        let sizeInt = Int(size)
        guard sizeInt <= dataCount - offset else { return nil }
        let end = offset + sizeInt

        guard let startU32 = UInt32(exactly: offset), let endU32 = UInt32(exactly: end) else {
            return nil
        }
        let (startWithBase, o1) = startU32.addingReportingOverflow(baseOffset)
        let (endWithBase, o2) = endU32.addingReportingOverflow(baseOffset)
        guard !o1, !o2 else { return nil }

        return ByteRange(start: startWithBase, end: endWithBase)
    }

    @inline(__always)
    private func attributeContent(_ attribute: MD_ATTRIBUTE) -> TextContent? {
        guard let range = pointerRange(attribute.text, size: attribute.size), !range.isEmpty else {
            return nil
        }
        return .bytes(range)
    }

    @inline(__always)
    private func recordRangeOnTopBlock(_ range: ByteRange) {
        guard !blockStack.isEmpty else { return }
        blockStack[blockStack.count - 1].include(range)
    }

    @inline(__always)
    private func propagateRangeToParent(_ frame: BlockFrame) {
        guard frame.hasRange, !blockStack.isEmpty else { return }
        blockStack[blockStack.count - 1].include(minStart: frame.minStart, maxEnd: frame.maxEnd)
    }

    @inline(__always)
    private func appendBlock(_ block: MarkdownBlock) {
        blockChildren.append(block)
    }

    @inline(__always)
    private func beginInlineBlock() {
        spanStack.append(SpanFrame(
            kind: .root,
            childStart: spanChildren.count,
            codeRangeStart: inlineCodeRanges.count
        ))
    }

    @inline(__always)
    private func endInlineBlock() -> [MarkdownSpan] {
        guard let frame = spanStack.popLast() else { return [] }
        return spanChildren.takeArray(from: frame.childStart)
    }

    /// Opens an implicit paragraph frame when md4c emits inline content directly
    /// inside a tight list item (`md4c.c:4850` omits `MD_BLOCK_P` for tight lists)
    /// or inside a depth-flattened container.
    @inline(__always)
    private func ensureImplicitParagraphIfNeeded() {
        guard spanStack.isEmpty, let top = blockStack.last else { return }
        switch top.kind {
        case .listItem, .blockQuote, .doc:
            beginInlineBlock()
            blockStack.append(BlockFrame(kind: .implicitParagraph, childStart: 0))
        default:
            break
        }
    }

    /// Flushes an active implicit paragraph frame into its enclosing block container.
    @inline(__always)
    private func closeImplicitParagraphIfNeeded() {
        guard let top = blockStack.last, case .implicitParagraph = top.kind else { return }
        _ = blockStack.popLast()
        let spans = endInlineBlock()
        let range = top.resolvedRange
        let id = nextID(kind: .paragraph, range: range)
        propagateRangeToParent(top)
        appendBlock(.paragraph(ParagraphBlock(id: id, spans: spans, range: range)))
    }

    @inline(__always)
    private func appendSpan(_ span: MarkdownSpan) {
        guard !spanStack.isEmpty else { return }
        spanChildren.append(span)
    }

    /// Appends a `.text(.bytes(range))` span, coalescing with the previous
    /// sibling span inside the same container when their byte ranges are
    /// strictly contiguous (`prev.end == range.start`).
    @inline(__always)
    private func appendInlineByteRange(_ range: ByteRange) {
        guard let frame = spanStack.last else { return }
        recordRangeOnTopBlock(range)
        if spanChildren.count > frame.childStart,
           case .text(.bytes(let prev)) = spanChildren.lastElement,
           prev.end == range.start {
            spanChildren.replaceLast(.text(.bytes(ByteRange(start: prev.start, end: range.end))))
            return
        }
        spanChildren.append(.text(.bytes(range)))
    }

    @inline(__always)
    private func appendCoalescedRange(to stack: ScratchStack<ByteRange>, startIndex: Int, range: ByteRange) {
        if stack.count > startIndex, let prev = stack.lastElement, prev.end == range.start {
            stack.replaceLast(ByteRange(start: prev.start, end: range.end))
            return
        }
        stack.append(range)
    }

    @inline(__always)
    private func makeTextContent(from stack: ScratchStack<ByteRange>, startIndex: Int) -> TextContent {
        let count = stack.count - startIndex
        if count <= 0 {
            return .sequence(ByteRangeSequence([]))
        }
        if count == 1 {
            return .bytes(stack.popLast())
        }
        return .sequence(ByteRangeSequence(stack.takeArray(from: startIndex)))
    }

    @inline(__always)
    private func characterFromMDChar(_ value: MD_CHAR) -> Character {
        Character(UnicodeScalar(UInt8(bitPattern: value)))
    }

    private func decodeEntity(_ text: UnsafePointer<MD_CHAR>?, size: MD_SIZE) -> String {
        guard let basePointer, let range = pointerRange(text, size: size) else { return "" }
        let start = Int(range.start - baseOffset)
        let length = Int(range.end - range.start)
        guard start >= 0, start + length <= dataCount else { return "" }
        return basePointer.advanced(by: start).withMemoryRebound(to: UInt8.self, capacity: length) { u8Ptr in
            let buf = UnsafeBufferPointer(start: u8Ptr, count: length)
            if let decoded = EntityDecoder.decodeUTF8(buf) {
                return decoded
            }
            return String(decoding: buf, as: UTF8.self)
        }
    }

    // MARK: - Callbacks

    static let enterBlockCallback: @convention(c) (MD_BLOCKTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, detail, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        if type != MD_BLOCK_DOC {
            context.closeImplicitParagraphIfNeeded()
        }

        switch type {
        case MD_BLOCK_DOC:
            context.blockStack.removeAll(keepingCapacity: true)
            context.blockChildren.removeAllKeepingCapacity()
            context.blockStack.append(BlockFrame(kind: .doc, childStart: 0))

        case MD_BLOCK_QUOTE:
            if !context.skippedContainers.isEmpty || context.blockStack.count >= MD4CParser.maxNestingDepth {
                context.skippedContainers.append(type.rawValue)
                return 0
            }
            context.blockStack.append(BlockFrame(kind: .blockQuote, childStart: context.blockChildren.count))

        case MD_BLOCK_UL:
            if !context.skippedContainers.isEmpty || context.blockStack.count >= MD4CParser.maxNestingDepth {
                context.skippedContainers.append(type.rawValue)
                return 0
            }
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_UL_DETAIL.self)
            let isTight = info?.pointee.is_tight != 0
            let mark = info?.pointee.mark ?? MD_CHAR(45)
            context.blockStack.append(BlockFrame(
                kind: .list(ordered: false, start: 1, delimiter: context.characterFromMDChar(mark), isTight: isTight),
                childStart: context.listItems.count
            ))

        case MD_BLOCK_OL:
            if !context.skippedContainers.isEmpty || context.blockStack.count >= MD4CParser.maxNestingDepth {
                context.skippedContainers.append(type.rawValue)
                return 0
            }
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_OL_DETAIL.self)
            let start = Int(info?.pointee.start ?? 1)
            let rawDelimiter = info?.pointee.mark_delimiter ?? MD_CHAR(46)
            let isTight = info?.pointee.is_tight != 0
            context.blockStack.append(BlockFrame(
                kind: .list(ordered: true, start: start, delimiter: context.characterFromMDChar(rawDelimiter), isTight: isTight),
                childStart: context.listItems.count
            ))

        case MD_BLOCK_LI:
            if !context.skippedContainers.isEmpty {
                context.skippedContainers.append(type.rawValue)
                return 0
            }
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_LI_DETAIL.self)
            let isTask = info?.pointee.is_task != 0
            let mark = info?.pointee.task_mark
            let isChecked = (mark == MD_CHAR(120) || mark == MD_CHAR(88))
            context.blockStack.append(BlockFrame(
                kind: .listItem(isTask: isTask, isChecked: isChecked),
                childStart: context.blockChildren.count
            ))

        case MD_BLOCK_HR:
            context.blockStack.append(BlockFrame(kind: .thematicBreak, childStart: 0))

        case MD_BLOCK_H:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_H_DETAIL.self)
            let level = Int(info?.pointee.level ?? 1)
            context.beginInlineBlock()
            context.blockStack.append(BlockFrame(kind: .heading(level: level), childStart: 0))

        case MD_BLOCK_P:
            context.beginInlineBlock()
            context.blockStack.append(BlockFrame(kind: .paragraph, childStart: 0))

        case MD_BLOCK_CODE:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_CODE_DETAIL.self)
            let infoAttr = info.map { context.attributeContent($0.pointee.info) } ?? nil
            let langAttr = info.map { context.attributeContent($0.pointee.lang) } ?? nil
            let fenceChar = info?.pointee.fence_char ?? 0
            let fence = fenceChar == 0 ? nil : context.characterFromMDChar(fenceChar)
            context.blockStack.append(BlockFrame(
                kind: .codeBlock(info: infoAttr, language: langAttr, fence: fence),
                childStart: context.textRanges.count
            ))

        case MD_BLOCK_HTML:
            context.blockStack.append(BlockFrame(
                kind: .htmlBlock,
                childStart: context.textRanges.count
            ))

        case MD_BLOCK_TABLE:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_TABLE_DETAIL.self)
            let columnCount = Int(info?.pointee.col_count ?? 0)
            let alignments = Array(repeating: TableAlignment.none, count: Swift.max(0, columnCount))
            context.blockStack.append(BlockFrame(
                kind: .table(alignments: alignments, bodyRowStart: context.tableBodyRows.count),
                childStart: context.tableHeaderRows.count
            ))

        case MD_BLOCK_THEAD:
            context.tableSectionStack.append(.header)

        case MD_BLOCK_TBODY:
            context.tableSectionStack.append(.body)

        case MD_BLOCK_TR:
            context.blockStack.append(BlockFrame(kind: .tableRow, childStart: context.tableCells.count))

        case MD_BLOCK_TH, MD_BLOCK_TD:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_TD_DETAIL.self)
            let alignment: TableAlignment
            switch info?.pointee.align {
            case MD_ALIGN_LEFT:
                alignment = .left
            case MD_ALIGN_CENTER:
                alignment = .center
            case MD_ALIGN_RIGHT:
                alignment = .right
            default:
                alignment = .none
            }
            context.beginInlineBlock()
            context.blockStack.append(BlockFrame(kind: .tableCell(alignment: alignment), childStart: 0))

        default:
            break
        }

        return 0
    }

    static let leaveBlockCallback: @convention(c) (MD_BLOCKTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, _, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        switch type {
        case MD_BLOCK_DOC:
            context.closeImplicitParagraphIfNeeded()

        case MD_BLOCK_QUOTE:
            context.closeImplicitParagraphIfNeeded()
            if context.skippedContainers.last == type.rawValue {
                context.skippedContainers.removeLast()
                return 0
            }
            guard let frame = context.blockStack.popLast(), case .blockQuote = frame.kind else { return 0 }
            let blocks = context.blockChildren.takeArray(from: frame.childStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .blockQuote, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.blockQuote(BlockQuoteBlock(id: id, blocks: blocks)))

        case MD_BLOCK_UL, MD_BLOCK_OL:
            if context.skippedContainers.last == type.rawValue {
                context.skippedContainers.removeLast()
                return 0
            }
            guard let frame = context.blockStack.popLast(),
                  case .list(let ordered, let start, let delimiter, let isTight) = frame.kind else { return 0 }
            let items = context.listItems.takeArray(from: frame.childStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .list, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.list(ListBlock(
                id: id,
                ordered: ordered,
                start: start,
                delimiter: delimiter,
                isTight: isTight,
                items: items
            )))

        case MD_BLOCK_LI:
            context.closeImplicitParagraphIfNeeded()
            if context.skippedContainers.last == type.rawValue {
                context.skippedContainers.removeLast()
                return 0
            }
            guard let frame = context.blockStack.popLast(),
                  case .listItem(let isTask, let isChecked) = frame.kind else { return 0 }
            let blocks = context.blockChildren.takeArray(from: frame.childStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .listItem, range: range)
            context.propagateRangeToParent(frame)
            context.listItems.append(ListItemBlock(id: id, blocks: blocks, isTask: isTask, isChecked: isChecked))

        case MD_BLOCK_HR:
            guard let frame = context.blockStack.popLast() else { return 0 }
            let range = ByteRange(start: context.baseOffset, end: context.baseOffset)
            let id = context.nextID(kind: .thematicBreak, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.thematicBreak(ThematicBreakBlock(id: id, range: range)))

        case MD_BLOCK_H:
            guard let frame = context.blockStack.popLast(),
                  case .heading(let level) = frame.kind else { return 0 }
            let spans = context.endInlineBlock()
            let range = frame.resolvedRange
            let id = context.nextID(kind: .heading, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.heading(HeadingBlock(id: id, level: level, spans: spans, range: range)))

        case MD_BLOCK_P:
            guard let frame = context.blockStack.popLast(),
                  case .paragraph = frame.kind else { return 0 }
            let spans = context.endInlineBlock()
            let range = frame.resolvedRange
            let id = context.nextID(kind: .paragraph, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.paragraph(ParagraphBlock(id: id, spans: spans, range: range)))

        case MD_BLOCK_CODE:
            guard let frame = context.blockStack.popLast(),
                  case .codeBlock(let info, let language, let fence) = frame.kind else { return 0 }
            let content = context.makeTextContent(from: context.textRanges, startIndex: frame.childStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .codeBlock, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.codeBlock(CodeBlock(id: id, info: info, language: language, content: content, fence: fence)))

        case MD_BLOCK_HTML:
            guard let frame = context.blockStack.popLast(),
                  case .htmlBlock = frame.kind else { return 0 }
            let content = context.makeTextContent(from: context.textRanges, startIndex: frame.childStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .htmlBlock, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.htmlBlock(HTMLBlock(id: id, content: content)))

        case MD_BLOCK_TABLE:
            guard let frame = context.blockStack.popLast(),
                  case .table(let alignments, let bodyRowStart) = frame.kind else { return 0 }
            let headerRows = context.tableHeaderRows.takeArray(from: frame.childStart)
            let bodyRows = context.tableBodyRows.takeArray(from: bodyRowStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .table, range: range)
            context.propagateRangeToParent(frame)
            context.appendBlock(.table(TableBlock(id: id, alignments: alignments, headerRows: headerRows, bodyRows: bodyRows)))

        case MD_BLOCK_THEAD, MD_BLOCK_TBODY:
            _ = context.tableSectionStack.popLast()

        case MD_BLOCK_TR:
            guard let frame = context.blockStack.popLast(),
                  case .tableRow = frame.kind else { return 0 }
            let cells = context.tableCells.takeArray(from: frame.childStart)
            let range = frame.resolvedRange
            let id = context.nextID(kind: .tableRow, range: range)
            let row = TableRow(id: id, cells: cells)
            context.propagateRangeToParent(frame)
            if context.tableSectionStack.last == .header {
                context.tableHeaderRows.append(row)
            } else {
                context.tableBodyRows.append(row)
            }

        case MD_BLOCK_TH, MD_BLOCK_TD:
            guard let frame = context.blockStack.popLast(),
                  case .tableCell(let alignment) = frame.kind else { return 0 }
            let spans = context.endInlineBlock()
            let range = frame.resolvedRange
            let id = context.nextID(kind: .tableCell, range: range)
            context.propagateRangeToParent(frame)
            context.tableCells.append(TableCell(id: id, spans: spans, alignment: alignment))

        default:
            break
        }

        return 0
    }

    static let enterSpanCallback: @convention(c) (MD_SPANTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, detail, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        context.ensureImplicitParagraphIfNeeded()

        if !context.skippedSpans.isEmpty || context.spanStack.count >= MD4CParser.maxNestingDepth {
            context.skippedSpans.append(type.rawValue)
            return 0
        }

        let kind: SpanKind
        switch type {
        case MD_SPAN_EM:
            kind = .emphasis
        case MD_SPAN_STRONG:
            kind = .strong
        case MD_SPAN_A:
            let info = detail?.assumingMemoryBound(to: MD_SPAN_A_DETAIL.self)
            let destination = info.map { context.attributeContent($0.pointee.href) } ?? nil
            let title = info.map { context.attributeContent($0.pointee.title) } ?? nil
            // Do not merge href/title ranges into the enclosing block range: reference links
            // (`[docs][ref]`) point to an earlier `[ref]: /docs` definition outside this block.
            kind = .link(destination: destination, title: title)
        case MD_SPAN_IMG:
            let info = detail?.assumingMemoryBound(to: MD_SPAN_IMG_DETAIL.self)
            let source = info.map { context.attributeContent($0.pointee.src) } ?? nil
            let title = info.map { context.attributeContent($0.pointee.title) } ?? nil
            kind = .image(source: source, title: title)
        case MD_SPAN_CODE:
            kind = .code
        case MD_SPAN_DEL:
            kind = .strikethrough
        case MD_SPAN_WIKILINK:
            let info = detail?.assumingMemoryBound(to: MD_SPAN_WIKILINK_DETAIL.self)
            let target = info.map { context.attributeContent($0.pointee.target) } ?? nil
            if case .bytes(let r) = target { context.recordRangeOnTopBlock(r) }
            kind = .wikiLink(target: target)
        case MD_SPAN_LATEXMATH:
            kind = .latexInline
        case MD_SPAN_LATEXMATH_DISPLAY:
            kind = .latexDisplay
        case MD_SPAN_U:
            kind = .underline
        default:
            kind = .emphasis
        }

        context.spanStack.append(SpanFrame(
            kind: kind,
            childStart: context.spanChildren.count,
            codeRangeStart: context.inlineCodeRanges.count
        ))
        return 0
    }

    static let leaveSpanCallback: @convention(c) (MD_SPANTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, _, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()
        if context.skippedSpans.last == type.rawValue {
            context.skippedSpans.removeLast()
            return 0
        }
        guard let frame = context.spanStack.popLast() else { return 0 }

        let children = context.spanChildren.takeArray(from: frame.childStart)

        let span: MarkdownSpan
        switch frame.kind {
        case .emphasis:
            span = .emphasis(children)
        case .strong:
            span = .strong(children)
        case .strikethrough:
            span = .strikethrough(children)
        case .underline:
            span = .underline(children)
        case .link(let destination, let title):
            span = .link(children: children, destination: destination, title: title)
        case .image(let source, let title):
            span = .image(alt: children, source: source, title: title)
        case .code:
            let content = context.resolveCodeSpanContent(codeRangeStart: frame.codeRangeStart, fallbackChildren: children)
            span = .code(content)
        case .wikiLink(let target):
            span = .wikiLink(target: target ?? .string(""), children: children)
        case .latexInline:
            let content = context.resolveCodeSpanContent(codeRangeStart: frame.codeRangeStart, fallbackChildren: children)
            span = .latexInline(content)
        case .latexDisplay:
            let content = context.resolveCodeSpanContent(codeRangeStart: frame.codeRangeStart, fallbackChildren: children)
            span = .latexDisplay(content)
        case .root:
            return 0
        }

        context.appendSpan(span)
        return 0
    }

    private func resolveCodeSpanContent(codeRangeStart: Int, fallbackChildren: [MarkdownSpan]) -> TextContent {
        if codeRangeStart < inlineCodeRanges.count {
            return makeTextContent(from: inlineCodeRanges, startIndex: codeRangeStart)
        }
        guard !fallbackChildren.isEmpty else { return .string("") }
        var text = ""
        for span in fallbackChildren {
            switch span {
            case .text(let content):
                switch content {
                case .bytes(let r):
                    let start = Int(r.start - baseOffset)
                    let length = Int(r.end - r.start)
                    if let basePointer, start >= 0, start + length <= dataCount {
                        basePointer.advanced(by: start).withMemoryRebound(to: UInt8.self, capacity: length) { ptr in
                            text += String(decoding: UnsafeBufferPointer(start: ptr, count: length), as: UTF8.self)
                        }
                    }
                case .string(let s):
                    text += s
                case .sequence(let seq):
                    for r in seq.ranges {
                        let start = Int(r.start - baseOffset)
                        let length = Int(r.end - r.start)
                        if let basePointer, start >= 0, start + length <= dataCount {
                            basePointer.advanced(by: start).withMemoryRebound(to: UInt8.self, capacity: length) { ptr in
                                text += String(decoding: UnsafeBufferPointer(start: ptr, count: length), as: UTF8.self)
                            }
                        }
                    }
                }
            case .softBreak, .lineBreak:
                text += "\n"
            default:
                break
            }
        }
        return .string(text)
    }

    static let textCallback: @convention(c) (MD_TEXTTYPE, UnsafePointer<MD_CHAR>?, MD_SIZE, UnsafeMutableRawPointer?) -> Int32 = { type, text, size, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        switch type {
        case MD_TEXT_NORMAL:
            context.ensureImplicitParagraphIfNeeded()
            if let range = context.pointerRange(text, size: size) {
                context.appendInlineByteRange(range)
            }

        case MD_TEXT_CODE:
            if let range = context.pointerRange(text, size: size) {
                if let topBlock = context.blockStack.last, case .codeBlock = topBlock.kind {
                    context.recordRangeOnTopBlock(range)
                    context.appendCoalescedRange(to: context.textRanges, startIndex: topBlock.childStart, range: range)
                } else {
                    context.ensureImplicitParagraphIfNeeded()
                    context.recordRangeOnTopBlock(range)
                    if let topSpan = context.spanStack.last, topSpan.isCodeLike {
                        context.appendCoalescedRange(to: context.inlineCodeRanges, startIndex: topSpan.codeRangeStart, range: range)
                    } else {
                        context.appendSpan(.code(.bytes(range)))
                    }
                }
            }

        case MD_TEXT_SOFTBR:
            context.ensureImplicitParagraphIfNeeded()
            context.appendSpan(.softBreak)

        case MD_TEXT_BR:
            context.ensureImplicitParagraphIfNeeded()
            context.appendSpan(.lineBreak)

        case MD_TEXT_ENTITY:
            context.ensureImplicitParagraphIfNeeded()
            if let range = context.pointerRange(text, size: size) {
                context.recordRangeOnTopBlock(range)
            }
            if !context.spanStack.isEmpty {
                let decoded = context.decodeEntity(text, size: size)
                context.appendSpan(.text(.string(decoded)))
            }

        case MD_TEXT_NULLCHAR:
            // Note: md4c passes a static C literal pointer for MD_TEXT_NULLCHAR rather than
            // a pointer inside the source buffer, so source byte ranges are unavailable for NUL-only items.
            context.ensureImplicitParagraphIfNeeded()
            if !context.spanStack.isEmpty {
                context.appendSpan(.text(.string("\u{FFFD}")))
            }

        case MD_TEXT_HTML:
            if let range = context.pointerRange(text, size: size) {
                if let topBlock = context.blockStack.last, case .htmlBlock = topBlock.kind {
                    context.recordRangeOnTopBlock(range)
                    context.appendCoalescedRange(to: context.textRanges, startIndex: topBlock.childStart, range: range)
                } else {
                    context.ensureImplicitParagraphIfNeeded()
                    context.recordRangeOnTopBlock(range)
                    context.appendSpan(.html(.bytes(range)))
                }
            }

        case MD_TEXT_LATEXMATH:
            context.ensureImplicitParagraphIfNeeded()
            if let range = context.pointerRange(text, size: size) {
                context.recordRangeOnTopBlock(range)
                if let topSpan = context.spanStack.last, topSpan.isLatexLike {
                    context.appendCoalescedRange(to: context.inlineCodeRanges, startIndex: topSpan.codeRangeStart, range: range)
                } else {
                    context.appendInlineByteRange(range)
                }
            }

        default:
            context.ensureImplicitParagraphIfNeeded()
            if let range = context.pointerRange(text, size: size) {
                context.appendInlineByteRange(range)
            }
        }

        return 0
    }
}

// MARK: - Compact Stack Frame Types

private enum BlockKind: UInt8 {
    case paragraph = 1
    case heading = 2
    case codeBlock = 3
    case blockQuote = 4
    case list = 5
    case listItem = 6
    case table = 7
    case tableRow = 8
    case tableCell = 9
    case thematicBreak = 10
    case htmlBlock = 11
}

private enum TableSection {
    case header
    case body
}

private enum BlockFrameKind {
    case doc
    case blockQuote
    case list(ordered: Bool, start: Int, delimiter: Character?, isTight: Bool)
    case listItem(isTask: Bool, isChecked: Bool)
    case paragraph
    case implicitParagraph
    case heading(level: Int)
    case codeBlock(info: TextContent?, language: TextContent?, fence: Character?)
    case htmlBlock
    case table(alignments: [TableAlignment], bodyRowStart: Int)
    case tableRow
    case tableCell(alignment: TableAlignment)
    case thematicBreak
}

private struct BlockFrame {
    let kind: BlockFrameKind
    let childStart: Int
    var minStart: UInt32 = 0
    var maxEnd: UInt32 = 0
    var hasRange: Bool = false

    @inline(__always)
    mutating func include(_ range: ByteRange) {
        if hasRange {
            if range.start < minStart { minStart = range.start }
            if range.end > maxEnd { maxEnd = range.end }
        } else {
            minStart = range.start
            maxEnd = range.end
            hasRange = true
        }
    }

    @inline(__always)
    mutating func include(minStart: UInt32, maxEnd: UInt32) {
        if hasRange {
            if minStart < self.minStart { self.minStart = minStart }
            if maxEnd > self.maxEnd { self.maxEnd = maxEnd }
        } else {
            self.minStart = minStart
            self.maxEnd = maxEnd
            hasRange = true
        }
    }

    @inline(__always)
    var resolvedRange: ByteRange {
        hasRange ? ByteRange(start: minStart, end: maxEnd) : ByteRange(start: 0, end: 0)
    }
}

private enum SpanKind {
    case root
    case emphasis
    case strong
    case link(destination: TextContent?, title: TextContent?)
    case image(source: TextContent?, title: TextContent?)
    case code
    case strikethrough
    case underline
    case wikiLink(target: TextContent?)
    case latexInline
    case latexDisplay
}

private struct SpanFrame {
    let kind: SpanKind
    let childStart: Int
    let codeRangeStart: Int

    @inline(__always)
    var isCodeLike: Bool {
        switch kind {
        case .code, .latexInline, .latexDisplay:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    var isLatexLike: Bool {
        switch kind {
        case .latexInline, .latexDisplay:
            return true
        default:
            return false
        }
    }
}
