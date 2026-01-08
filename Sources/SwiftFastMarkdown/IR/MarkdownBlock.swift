import Foundation

@frozen
public enum MarkdownBlock: Sendable, Equatable, Identifiable {
    case paragraph(ParagraphBlock)
    case heading(HeadingBlock)
    case codeBlock(CodeBlock)
    case blockQuote(BlockQuoteBlock)
    case list(ListBlock)
    case table(TableBlock)
    case thematicBreak(ThematicBreakBlock)
    case htmlBlock(HTMLBlock)

    public var id: BlockID {
        switch self {
        case .paragraph(let block):
            return block.id
        case .heading(let block):
            return block.id
        case .codeBlock(let block):
            return block.id
        case .blockQuote(let block):
            return block.id
        case .list(let block):
            return block.id
        case .table(let block):
            return block.id
        case .thematicBreak(let block):
            return block.id
        case .htmlBlock(let block):
            return block.id
        }
    }
}

@frozen
public struct ParagraphBlock: Sendable, Equatable {
    public let id: BlockID
    public let spans: [MarkdownSpan]
    public let range: ByteRange
}

@frozen
public struct HeadingBlock: Sendable, Equatable {
    public let id: BlockID
    public let level: Int
    public let spans: [MarkdownSpan]
    public let range: ByteRange
}

@frozen
public struct CodeBlock: Sendable, Equatable {
    public let id: BlockID
    public let info: TextContent?
    public let language: TextContent?
    public let content: TextContent
    public let fence: Character?
}

@frozen
public struct HTMLBlock: Sendable, Equatable {
    public let id: BlockID
    public let content: TextContent
}

@frozen
public struct BlockQuoteBlock: Sendable, Equatable {
    public let id: BlockID
    public let blocks: [MarkdownBlock]
}

@frozen
public struct ThematicBreakBlock: Sendable, Equatable {
    public let id: BlockID
    public let range: ByteRange
}

@frozen
public struct ListBlock: Sendable, Equatable {
    public let id: BlockID
    public let ordered: Bool
    public let start: Int
    public let delimiter: Character?
    public let isTight: Bool
    public let items: [ListItemBlock]
}

@frozen
public struct ListItemBlock: Sendable, Equatable, Identifiable {
    public let id: BlockID
    public let blocks: [MarkdownBlock]
    public let isTask: Bool
    public let isChecked: Bool
}

@frozen
public enum TableAlignment: Sendable, Equatable {
    case left
    case center
    case right
    case none
}

@frozen
public struct TableBlock: Sendable, Equatable {
    public let id: BlockID
    public let alignments: [TableAlignment]
    public let headerRows: [TableRow]
    public let bodyRows: [TableRow]
}

@frozen
public struct TableRow: Sendable, Equatable, Identifiable {
    public let id: BlockID
    public let cells: [TableCell]
}

@frozen
public struct TableCell: Sendable, Equatable, Identifiable {
    public let id: BlockID
    public let spans: [MarkdownSpan]
    public let alignment: TableAlignment
}

@frozen
public struct MarkdownDocument: Sendable, Equatable {
    public let blocks: [MarkdownBlock]
    public let sourceData: Data
    public let id: UUID

    public init(blocks: [MarkdownBlock], sourceData: Data, id: UUID = UUID()) {
        self.blocks = blocks
        self.sourceData = sourceData
        self.id = id
    }
}
