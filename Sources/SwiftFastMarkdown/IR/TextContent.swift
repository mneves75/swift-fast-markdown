import Foundation

@frozen
public enum TextContent: Sendable, Equatable {
    case bytes(ByteRange)
    case string(String)
    case sequence(ByteRangeSequence)

    @inlinable
    public func string(in data: Data) -> String {
        switch self {
        case .bytes(let range):
            return range.string(in: data)
        case .string(let value):
            return value
        case .sequence(let ranges):
            return ranges.string(in: data)
        }
    }
}
