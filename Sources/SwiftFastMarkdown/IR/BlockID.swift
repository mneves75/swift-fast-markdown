import Foundation

@frozen
public struct BlockID: Sendable, Hashable {
    public let kind: UInt8
    public let start: UInt32
    public let end: UInt32
    public let ordinal: UInt32

    public init(kind: UInt8, start: UInt32, end: UInt32, ordinal: UInt32) {
        self.kind = kind
        self.start = start
        self.end = end
        self.ordinal = ordinal
    }
}
