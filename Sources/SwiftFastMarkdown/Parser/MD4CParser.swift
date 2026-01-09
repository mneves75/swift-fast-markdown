import Foundation
import CMD4C

public enum MarkdownParserError: Error {
    case parsingFailed(Int32)
}

public struct MD4CParser: Sendable {
    public init() {}

    public func parse(_ input: String, options: ParseOptions = .default) throws -> MarkdownDocument {
        let data = Data(input.utf8)
        return try parse(data, options: options)
    }

    public func parse(_ data: Data, options: ParseOptions = .default) throws -> MarkdownDocument {
        guard !data.isEmpty else {
            return MarkdownDocument(blocks: [], sourceData: data)
        }

        let context = ParserContext(sourceData: data)

        return try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.bindMemory(to: MD_CHAR.self).baseAddress else {
                return MarkdownDocument(blocks: [], sourceData: data)
            }
            context.basePointer = baseAddress

            var parser = MD_PARSER()
            parser.abi_version = 0
            parser.flags = UInt32(options.rawValue)
            parser.enter_block = ParserContext.enterBlockCallback
            parser.leave_block = ParserContext.leaveBlockCallback
            parser.enter_span = ParserContext.enterSpanCallback
            parser.leave_span = ParserContext.leaveSpanCallback
            parser.text = ParserContext.textCallback
            parser.debug_log = ParserContext.debugLogCallback
            parser.syntax = nil

            let result = md_parse(baseAddress, MD_SIZE(data.count), &parser, Unmanaged.passUnretained(context).toOpaque())
            if result != 0 {
                throw MarkdownParserError.parsingFailed(Int32(result))
            }

            return context.buildDocument()
        }
    }
}

private final class ParserContext {
    var basePointer: UnsafePointer<MD_CHAR>?
    let sourceData: Data
    private var blockStack: [BlockState] = []
    private var inlineStack: [SpanContainer] = []
    private var inlineRootStack: [Int] = []
    private var tableSectionStack: [TableSection] = []
    private var ordinal: UInt32 = 0

    init(sourceData: Data) {
        self.sourceData = sourceData
    }

    func buildDocument() -> MarkdownDocument {
        if case .doc(let blocks) = blockStack.first {
            return MarkdownDocument(blocks: blocks, sourceData: sourceData)
        }
        return MarkdownDocument(blocks: [], sourceData: sourceData)
    }

    private func nextID(kind: BlockKind, range: ByteRange) -> BlockID {
        ordinal &+= 1
        return BlockID(kind: kind.rawValue, start: range.start, end: range.end, ordinal: ordinal)
    }

    private func appendBlock(_ block: MarkdownBlock) {
        guard let last = blockStack.indices.last else {
            blockStack = [.doc(blocks: [block])]
            return
        }

        switch blockStack[last] {
        case .doc(let blocks):
            blockStack[last] = .doc(blocks: blocks + [block])
        case .blockQuote(let blocks):
            blockStack[last] = .blockQuote(blocks: blocks + [block])
        case .listItem(let isTask, let isChecked, let blocks, let hasImplicitParagraph):
            blockStack[last] = .listItem(isTask: isTask, isChecked: isChecked, blocks: blocks + [block], hasImplicitParagraph: hasImplicitParagraph)
        default:
            // If the current container cannot accept blocks, append to nearest parent.
            if let parentIndex = blockStack.lastIndex(where: { $0.acceptsChildBlocks }) {
                switch blockStack[parentIndex] {
                case .doc(let blocks):
                    blockStack[parentIndex] = .doc(blocks: blocks + [block])
                case .blockQuote(let blocks):
                    blockStack[parentIndex] = .blockQuote(blocks: blocks + [block])
                case .listItem(let isTask, let isChecked, let blocks, let hasImplicitParagraph):
                    blockStack[parentIndex] = .listItem(isTask: isTask, isChecked: isChecked, blocks: blocks + [block], hasImplicitParagraph: hasImplicitParagraph)
                default:
                    break
                }
            }
        }
    }

    private func beginInlineBlock() {
        inlineRootStack.append(inlineStack.count)
        inlineStack.append(SpanContainer(kind: .root))
    }

    private func endInlineBlock() -> [MarkdownSpan] {
        guard let rootIndex = inlineRootStack.popLast() else {
            return []
        }
        let root = inlineStack.removeLast()
        assert(rootIndex == inlineStack.count)
        return root.children
    }

    private func appendSpan(_ span: MarkdownSpan) {
        guard let lastIndex = inlineStack.indices.last else {
            return
        }
        inlineStack[lastIndex].children.append(span)
    }

    private func addInlineText(_ content: TextContent) {
        appendSpan(.text(content))
    }

    private func addInlineCode(_ content: TextContent) {
        appendSpan(.code(content))
    }

    private func addInlineHTML(_ content: TextContent) {
        appendSpan(.html(content))
    }

    private func currentInlineContainer() -> SpanContainer? {
        inlineStack.last
    }

    private func computeRange(from spans: [MarkdownSpan]) -> ByteRange {
        var minStart: UInt32?
        var maxEnd: UInt32?
        for span in spans {
            span.walkByteRanges { range in
                if minStart == nil || range.start < minStart! {
                    minStart = range.start
                }
                if maxEnd == nil || range.end > maxEnd! {
                    maxEnd = range.end
                }
            }
        }
        if let minStart, let maxEnd {
            return ByteRange(start: minStart, end: maxEnd)
        }
        return ByteRange(start: 0, end: 0)
    }

    private func pointerRange(_ text: UnsafePointer<MD_CHAR>?, size: MD_SIZE) -> ByteRange? {
        guard let basePointer, let text else {
            return nil
        }
        // md4c passes raw pointers into the original buffer; compute byte offsets from the base.
        let base = Int(bitPattern: basePointer)
        let ptr = Int(bitPattern: text)
        let offset = max(0, ptr - base)
        let end = offset + Int(size)
        guard end >= offset else { return nil }
        return ByteRange(start: UInt32(offset), end: UInt32(end))
    }

    private func attributeContent(_ attribute: MD_ATTRIBUTE) -> TextContent? {
        guard let range = pointerRange(attribute.text, size: attribute.size), !range.isEmpty else {
            return nil
        }
        return .bytes(range)
    }

    private func characterFromMDChar(_ value: MD_CHAR) -> Character {
        Character(UnicodeScalar(UInt8(bitPattern: value)))
    }

    /// Checks if the nearest parent list on the block stack is tight.
    /// Used to determine if list items need implicit paragraph handling.
    func isParentListTight() -> Bool {
        for state in blockStack.reversed() {
            if case .list(_, _, _, let isTight, _) = state {
                return isTight
            }
        }
        return false
    }

    // MARK: - Callbacks

    static let enterBlockCallback: @convention(c) (MD_BLOCKTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, detail, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        switch type {
        case MD_BLOCK_DOC:
            context.blockStack = [.doc(blocks: [])]
        case MD_BLOCK_QUOTE:
            context.blockStack.append(.blockQuote(blocks: []))
        case MD_BLOCK_UL:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_UL_DETAIL.self)
            let isTight = info?.pointee.is_tight != 0
            let mark = info?.pointee.mark ?? MD_CHAR(45)
            let list = BlockState.list(ordered: false, start: 1, delimiter: context.characterFromMDChar(mark), isTight: isTight, items: [])
            context.blockStack.append(list)
        case MD_BLOCK_OL:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_OL_DETAIL.self)
            let start = Int(info?.pointee.start ?? 1)
            let rawDelimiter = info?.pointee.mark_delimiter ?? MD_CHAR(46)
            let delimiter = context.characterFromMDChar(rawDelimiter)
            let isTight = info?.pointee.is_tight != 0
            let list = BlockState.list(ordered: true, start: start, delimiter: delimiter, isTight: isTight, items: [])
            context.blockStack.append(list)
        case MD_BLOCK_LI:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_LI_DETAIL.self)
            let isTask = info?.pointee.is_task != 0
            let mark = info?.pointee.task_mark
            let isChecked = (mark == MD_CHAR(120) || mark == MD_CHAR(88))

            // Check if parent list is tight - if so, md4c won't emit paragraph blocks
            // for list item content, so we need to collect inline content directly.
            let parentListIsTight = context.isParentListTight()
            if parentListIsTight {
                context.beginInlineBlock()
            }
            context.blockStack.append(.listItem(isTask: isTask, isChecked: isChecked, blocks: [], hasImplicitParagraph: parentListIsTight))
        case MD_BLOCK_HR:
            context.blockStack.append(.thematicBreak)
        case MD_BLOCK_H:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_H_DETAIL.self)
            let level = Int(info?.pointee.level ?? 1)
            context.beginInlineBlock()
            context.blockStack.append(.heading(level: level))
        case MD_BLOCK_P:
            context.beginInlineBlock()
            context.blockStack.append(.paragraph)
        case MD_BLOCK_CODE:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_CODE_DETAIL.self)
            let infoAttr = info.map { context.attributeContent($0.pointee.info) } ?? nil
            let langAttr = info.map { context.attributeContent($0.pointee.lang) } ?? nil
            let fenceChar = info?.pointee.fence_char
            let fence = fenceChar == 0 ? nil : context.characterFromMDChar(fenceChar!)
            context.blockStack.append(.codeBlock(info: infoAttr, language: langAttr, fence: fence, contentRanges: []))
        case MD_BLOCK_HTML:
            context.blockStack.append(.htmlBlock(contentRanges: []))
        case MD_BLOCK_TABLE:
            let info = detail?.assumingMemoryBound(to: MD_BLOCK_TABLE_DETAIL.self)
            let columnCount = Int(info?.pointee.col_count ?? 0)
            let alignments = Array(repeating: TableAlignment.none, count: max(0, columnCount))
            context.blockStack.append(.table(alignments: alignments, headerRows: [], bodyRows: []))
        case MD_BLOCK_THEAD:
            context.tableSectionStack.append(.header)
        case MD_BLOCK_TBODY:
            context.tableSectionStack.append(.body)
        case MD_BLOCK_TR:
            context.blockStack.append(.tableRow(cells: []))
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
            context.blockStack.append(.tableCell(alignment: alignment))
        default:
            break
        }

        return 0
    }

    static let leaveBlockCallback: @convention(c) (MD_BLOCKTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, _, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        switch type {
        case MD_BLOCK_QUOTE:
            guard case .blockQuote(let blocks) = context.blockStack.popLast() else { return 0 }
            let range = rangeFromBlocks(blocks)
            let id = context.nextID(kind: .blockQuote, range: range)
            context.appendBlock(.blockQuote(BlockQuoteBlock(id: id, blocks: blocks)))
        case MD_BLOCK_UL, MD_BLOCK_OL:
            guard case .list(let ordered, let start, let delimiter, let isTight, let items) = context.blockStack.popLast() else { return 0 }
            let range = rangeFromListItems(items)
            let id = context.nextID(kind: .list, range: range)
            let list = ListBlock(id: id, ordered: ordered, start: start, delimiter: delimiter, isTight: isTight, items: items)
            context.appendBlock(.list(list))
        case MD_BLOCK_LI:
            guard case .listItem(let isTask, let isChecked, var blocks, let hasImplicitParagraph) = context.blockStack.popLast() else { return 0 }

            // For tight lists, we started an implicit inline block to collect content.
            // Now wrap that content in a paragraph block.
            if hasImplicitParagraph {
                let spans = context.endInlineBlock()
                if !spans.isEmpty {
                    let paragraphRange = context.computeRange(from: spans)
                    let paragraphId = context.nextID(kind: .paragraph, range: paragraphRange)
                    let implicitParagraph = ParagraphBlock(id: paragraphId, spans: spans, range: paragraphRange)
                    blocks.append(.paragraph(implicitParagraph))
                }
            }

            let range = rangeFromBlocks(blocks)
            let id = context.nextID(kind: .listItem, range: range)
            let item = ListItemBlock(id: id, blocks: blocks, isTask: isTask, isChecked: isChecked)
            if let listIndex = context.blockStack.lastIndex(where: { if case .list = $0 { return true } else { return false } }) {
                if case .list(let ordered, let start, let delimiter, let isTight, let items) = context.blockStack[listIndex] {
                    context.blockStack[listIndex] = .list(ordered: ordered, start: start, delimiter: delimiter, isTight: isTight, items: items + [item])
                }
            }
        case MD_BLOCK_HR:
            _ = context.blockStack.popLast()
            let range = ByteRange(start: 0, end: 0)
            let id = context.nextID(kind: .thematicBreak, range: range)
            context.appendBlock(.thematicBreak(ThematicBreakBlock(id: id, range: range)))
        case MD_BLOCK_H:
            guard case .heading(let level) = context.blockStack.popLast() else { return 0 }
            let spans = context.endInlineBlock()
            let range = context.computeRange(from: spans)
            let id = context.nextID(kind: .heading, range: range)
            context.appendBlock(.heading(HeadingBlock(id: id, level: level, spans: spans, range: range)))
        case MD_BLOCK_P:
            guard case .paragraph = context.blockStack.popLast() else { return 0 }
            let spans = context.endInlineBlock()
            let range = context.computeRange(from: spans)
            let id = context.nextID(kind: .paragraph, range: range)
            context.appendBlock(.paragraph(ParagraphBlock(id: id, spans: spans, range: range)))
        case MD_BLOCK_CODE:
            guard case .codeBlock(let info, let language, let fence, let ranges) = context.blockStack.popLast() else { return 0 }
            let content = TextContent.sequence(ByteRangeSequence(ranges))
            let range = mergeRanges(ranges)
            let id = context.nextID(kind: .codeBlock, range: range)
            context.appendBlock(.codeBlock(CodeBlock(id: id, info: info, language: language, content: content, fence: fence)))
        case MD_BLOCK_HTML:
            guard case .htmlBlock(let ranges) = context.blockStack.popLast() else { return 0 }
            let content = TextContent.sequence(ByteRangeSequence(ranges))
            let range = mergeRanges(ranges)
            let id = context.nextID(kind: .htmlBlock, range: range)
            context.appendBlock(.htmlBlock(HTMLBlock(id: id, content: content)))
        case MD_BLOCK_TABLE:
            guard case .table(let alignments, let headerRows, let bodyRows) = context.blockStack.popLast() else { return 0 }
            let range = rangeFromTable(headerRows: headerRows, bodyRows: bodyRows)
            let id = context.nextID(kind: .table, range: range)
            context.appendBlock(.table(TableBlock(id: id, alignments: alignments, headerRows: headerRows, bodyRows: bodyRows)))
        case MD_BLOCK_THEAD, MD_BLOCK_TBODY:
            _ = context.tableSectionStack.popLast()
        case MD_BLOCK_TR:
            guard case .tableRow(let cells) = context.blockStack.popLast() else { return 0 }
            let range = rangeFromTableCells(cells)
            let id = context.nextID(kind: .tableRow, range: range)
            let row = TableRow(id: id, cells: cells)
            if let tableIndex = context.blockStack.lastIndex(where: { if case .table = $0 { return true } else { return false } }) {
                if case .table(let alignments, let headerRows, let bodyRows) = context.blockStack[tableIndex] {
                    switch context.tableSectionStack.last {
                    case .header:
                        context.blockStack[tableIndex] = .table(alignments: alignments, headerRows: headerRows + [row], bodyRows: bodyRows)
                    default:
                        context.blockStack[tableIndex] = .table(alignments: alignments, headerRows: headerRows, bodyRows: bodyRows + [row])
                    }
                }
            }
        case MD_BLOCK_TH, MD_BLOCK_TD:
            guard case .tableCell(let alignment) = context.blockStack.popLast() else { return 0 }
            let spans = context.endInlineBlock()
            let range = context.computeRange(from: spans)
            let id = context.nextID(kind: .tableCell, range: range)
            let cell = TableCell(id: id, spans: spans, alignment: alignment)
            if let rowIndex = context.blockStack.lastIndex(where: { if case .tableRow = $0 { return true } else { return false } }) {
                if case .tableRow(let cells) = context.blockStack[rowIndex] {
                    context.blockStack[rowIndex] = .tableRow(cells: cells + [cell])
                }
            }
        default:
            break
        }

        return 0
    }

    static let enterSpanCallback: @convention(c) (MD_SPANTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, detail, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        let container: SpanContainer
        switch type {
        case MD_SPAN_EM:
            container = SpanContainer(kind: .emphasis)
        case MD_SPAN_STRONG:
            container = SpanContainer(kind: .strong)
        case MD_SPAN_A:
            let info = detail?.assumingMemoryBound(to: MD_SPAN_A_DETAIL.self)
            let destination = info.map { context.attributeContent($0.pointee.href) } ?? nil
            let title = info.map { context.attributeContent($0.pointee.title) } ?? nil
            container = SpanContainer(kind: .link, destination: destination, title: title)
        case MD_SPAN_IMG:
            let info = detail?.assumingMemoryBound(to: MD_SPAN_IMG_DETAIL.self)
            let source = info.map { context.attributeContent($0.pointee.src) } ?? nil
            let title = info.map { context.attributeContent($0.pointee.title) } ?? nil
            container = SpanContainer(kind: .image, title: title, source: source)
        case MD_SPAN_CODE:
            container = SpanContainer(kind: .code)
        case MD_SPAN_DEL:
            container = SpanContainer(kind: .strikethrough)
        case MD_SPAN_WIKILINK:
            let info = detail?.assumingMemoryBound(to: MD_SPAN_WIKILINK_DETAIL.self)
            let target = info.map { context.attributeContent($0.pointee.target) } ?? nil
            container = SpanContainer(kind: .wikiLink, wikiTarget: target)
        case MD_SPAN_LATEXMATH:
            container = SpanContainer(kind: .latexInline)
        case MD_SPAN_LATEXMATH_DISPLAY:
            container = SpanContainer(kind: .latexDisplay)
        case MD_SPAN_U:
            container = SpanContainer(kind: .underline)
        default:
            container = SpanContainer(kind: .emphasis)
        }

        context.inlineStack.append(container)
        return 0
    }

    static let leaveSpanCallback: @convention(c) (MD_SPANTYPE, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { type, _, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()
        guard let container = context.inlineStack.popLast() else { return 0 }

        let span: MarkdownSpan
        switch container.kind {
        case .emphasis:
            span = .emphasis(container.children)
        case .strong:
            span = .strong(container.children)
        case .strikethrough:
            span = .strikethrough(container.children)
        case .underline:
            span = .underline(container.children)
        case .link:
            span = .link(children: container.children, destination: container.destination, title: container.title)
        case .image:
            span = .image(alt: container.children, source: container.source, title: container.title)
        case .code:
            let content = container.codeContent(from: context.sourceData)
            span = .code(content)
        case .wikiLink:
            let target = container.wikiTarget ?? .string("")
            span = .wikiLink(target: target, children: container.children)
        case .latexInline:
            let content = container.codeContent(from: context.sourceData)
            span = .latexInline(content)
        case .latexDisplay:
            let content = container.codeContent(from: context.sourceData)
            span = .latexDisplay(content)
        case .root:
            return 0
        }

        context.appendSpan(span)
        return 0
    }

    static let textCallback: @convention(c) (MD_TEXTTYPE, UnsafePointer<MD_CHAR>?, MD_SIZE, UnsafeMutableRawPointer?) -> Int32 = { type, text, size, userdata in
        guard let userdata else { return 0 }
        let context = Unmanaged<ParserContext>.fromOpaque(userdata).takeUnretainedValue()

        func appendInline(_ content: TextContent) {
            if context.inlineStack.isEmpty {
                return
            }
            context.addInlineText(content)
        }

        switch type {
        case MD_TEXT_NULLCHAR:
            appendInline(.string("\u{FFFD}"))
        case MD_TEXT_BR:
            context.appendSpan(.lineBreak)
        case MD_TEXT_SOFTBR:
            context.appendSpan(.softBreak)
        case MD_TEXT_ENTITY:
            let entity = context.stringFromPointer(text, size: size)
            let decoded = EntityDecoder.decode(entity)
            appendInline(.string(decoded))
        case MD_TEXT_CODE:
            if let range = context.pointerRange(text, size: size) {
                if let last = context.inlineStack.last, last.kind == .code || last.kind == .latexInline || last.kind == .latexDisplay {
                    context.inlineStack[context.inlineStack.count - 1].codeSegments.append(.bytes(range))
                } else if context.appendCodeBlockText(range) {
                    return 0
                } else {
                    context.addInlineCode(.bytes(range))
                }
            }
        case MD_TEXT_HTML:
            if let range = context.pointerRange(text, size: size) {
                if context.appendHTMLBlockText(range) {
                    return 0
                }
                context.addInlineHTML(.bytes(range))
            }
        case MD_TEXT_LATEXMATH:
            if let range = context.pointerRange(text, size: size) {
                if let last = context.inlineStack.last, last.kind == .latexInline || last.kind == .latexDisplay {
                    context.inlineStack[context.inlineStack.count - 1].codeSegments.append(.bytes(range))
                } else {
                    context.addInlineText(.bytes(range))
                }
            }
        default:
            if let range = context.pointerRange(text, size: size) {
                appendInline(.bytes(range))
            }
        }

        return 0
    }

    static let debugLogCallback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { _, _ in }

    private func stringFromPointer(_ text: UnsafePointer<MD_CHAR>?, size: MD_SIZE) -> String {
        guard let basePointer, let text else { return "" }
        let offset = Int(bitPattern: text) - Int(bitPattern: basePointer)
        guard offset >= 0 else { return "" }
        let end = offset + Int(size)
        guard end <= sourceData.count else { return "" }
        let slice = sourceData[offset..<end]
        return String(decoding: slice, as: UTF8.self)
    }

    private func appendCodeBlockText(_ range: ByteRange) -> Bool {
        guard let topIndex = blockStack.indices.last,
              case .codeBlock(let info, let language, let fence, let ranges) = blockStack[topIndex] else {
            return false
        }
        blockStack[topIndex] = .codeBlock(info: info, language: language, fence: fence, contentRanges: ranges + [range])
        return true
    }

    private func appendHTMLBlockText(_ range: ByteRange) -> Bool {
        guard let topIndex = blockStack.indices.last,
              case .htmlBlock(let ranges) = blockStack[topIndex] else {
            return false
        }
        blockStack[topIndex] = .htmlBlock(contentRanges: ranges + [range])
        return true
    }
}

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

private enum BlockState {
    case doc(blocks: [MarkdownBlock])
    case blockQuote(blocks: [MarkdownBlock])
    case list(ordered: Bool, start: Int, delimiter: Character?, isTight: Bool, items: [ListItemBlock])
    // hasImplicitParagraph: true when list item is in a tight list and needs
    // to collect inline content directly (md4c doesn't emit P blocks for tight lists)
    case listItem(isTask: Bool, isChecked: Bool, blocks: [MarkdownBlock], hasImplicitParagraph: Bool)
    case paragraph
    case heading(level: Int)
    case codeBlock(info: TextContent?, language: TextContent?, fence: Character?, contentRanges: [ByteRange])
    case htmlBlock(contentRanges: [ByteRange])
    case table(alignments: [TableAlignment], headerRows: [TableRow], bodyRows: [TableRow])
    case tableRow(cells: [TableCell])
    case tableCell(alignment: TableAlignment)
    case thematicBreak

    var acceptsChildBlocks: Bool {
        switch self {
        case .doc, .blockQuote, .listItem:
            return true
        default:
            return false
        }
    }
}

private enum SpanKind {
    case root
    case emphasis
    case strong
    case link
    case image
    case code
    case strikethrough
    case underline
    case wikiLink
    case latexInline
    case latexDisplay
}

private struct SpanContainer {
    let kind: SpanKind
    var children: [MarkdownSpan]
    var destination: TextContent?
    var title: TextContent?
    var source: TextContent?
    var wikiTarget: TextContent?
    var codeSegments: [TextContent]

    init(kind: SpanKind, destination: TextContent? = nil, title: TextContent? = nil, source: TextContent? = nil, wikiTarget: TextContent? = nil) {
        self.kind = kind
        self.children = []
        self.destination = destination
        self.title = title
        self.source = source
        self.wikiTarget = wikiTarget
        self.codeSegments = []
    }

    func codeContent(from data: Data) -> TextContent {
        if !codeSegments.isEmpty {
            return .sequence(ByteRangeSequence(codeSegments.compactMap { content in
                if case .bytes(let range) = content {
                    return range
                }
                return nil
            }))
        }

        let text = children.compactMap { span -> String? in
            switch span {
            case .text(let content):
                return content.string(in: data)
            case .softBreak:
                return "\n"
            case .lineBreak:
                return "\n"
            default:
                return nil
            }
        }.joined()
        return .string(text)
    }
}

private func rangeFromBlocks(_ blocks: [MarkdownBlock]) -> ByteRange {
    let ranges = blocks.compactMap { block -> ByteRange? in
        switch block {
        case .paragraph(let block):
            return block.range
        case .heading(let block):
            return block.range
        case .codeBlock(let block):
            if case .sequence(let ranges) = block.content {
                return mergeRanges(ranges.ranges)
            }
            return nil
        case .htmlBlock(let block):
            if case .sequence(let ranges) = block.content {
                return mergeRanges(ranges.ranges)
            }
            return nil
        case .blockQuote(let block):
            return rangeFromBlocks(block.blocks)
        case .list(let block):
            return rangeFromListItems(block.items)
        case .table(let block):
            return rangeFromTable(headerRows: block.headerRows, bodyRows: block.bodyRows)
        case .thematicBreak(let block):
            return block.range
        }
    }
    return mergeRanges(ranges)
}

private func rangeFromListItems(_ items: [ListItemBlock]) -> ByteRange {
    let ranges = items.compactMap { item in
        rangeFromBlocks(item.blocks)
    }
    return mergeRanges(ranges)
}

private func rangeFromTable(headerRows: [TableRow], bodyRows: [TableRow]) -> ByteRange {
    let rows = headerRows + bodyRows
    let ranges = rows.map { rangeFromTableCells($0.cells) }
    return mergeRanges(ranges)
}

private func rangeFromTableCells(_ cells: [TableCell]) -> ByteRange {
    let ranges = cells.map { cell in
        let spans = cell.spans
        var minStart: UInt32?
        var maxEnd: UInt32?
        for span in spans {
            span.walkByteRanges { range in
                if minStart == nil || range.start < minStart! { minStart = range.start }
                if maxEnd == nil || range.end > maxEnd! { maxEnd = range.end }
            }
        }
        if let minStart, let maxEnd {
            return ByteRange(start: minStart, end: maxEnd)
        }
        return ByteRange(start: 0, end: 0)
    }
    return mergeRanges(ranges)
}

private func mergeRanges(_ ranges: [ByteRange]) -> ByteRange {
    guard !ranges.isEmpty else { return ByteRange(start: 0, end: 0) }
    var minStart = ranges[0].start
    var maxEnd = ranges[0].end
    for range in ranges {
        if range.start < minStart { minStart = range.start }
        if range.end > maxEnd { maxEnd = range.end }
    }
    return ByteRange(start: minStart, end: maxEnd)
}

private extension MarkdownSpan {
    func walkByteRanges(_ visit: (ByteRange) -> Void) {
        switch self {
        case .text(let content):
            if case .bytes(let range) = content { visit(range) }
            if case .sequence(let sequence) = content {
                for range in sequence.ranges { visit(range) }
            }
        case .code(let content), .html(let content), .latexInline(let content), .latexDisplay(let content):
            if case .bytes(let range) = content { visit(range) }
            if case .sequence(let sequence) = content {
                for range in sequence.ranges { visit(range) }
            }
        case .emphasis(let children), .strong(let children), .strikethrough(let children), .underline(let children):
            children.forEach { $0.walkByteRanges(visit) }
        case .link(let children, let destination, let title):
            children.forEach { $0.walkByteRanges(visit) }
            if let destination {
                if case .bytes(let range) = destination { visit(range) }
                if case .sequence(let ranges) = destination { ranges.ranges.forEach(visit) }
            }
            if let title {
                if case .bytes(let range) = title { visit(range) }
                if case .sequence(let ranges) = title { ranges.ranges.forEach(visit) }
            }
        case .image(let alt, let source, let title):
            alt.forEach { $0.walkByteRanges(visit) }
            if let source {
                if case .bytes(let range) = source { visit(range) }
                if case .sequence(let ranges) = source { ranges.ranges.forEach(visit) }
            }
            if let title {
                if case .bytes(let range) = title { visit(range) }
                if case .sequence(let ranges) = title { ranges.ranges.forEach(visit) }
            }
        case .wikiLink(let target, let children):
            children.forEach { $0.walkByteRanges(visit) }
            if case .bytes(let range) = target { visit(range) }
            if case .sequence(let ranges) = target { ranges.ranges.forEach(visit) }
        case .lineBreak, .softBreak:
            break
        }
    }
}
