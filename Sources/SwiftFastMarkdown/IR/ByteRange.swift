import Foundation

@frozen
public struct ByteRange: Sendable, Equatable, Hashable {
    public let start: UInt32
    public let end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }

    @inlinable
    public var isEmpty: Bool {
        start >= end
    }

    @inlinable
    public var length: UInt32 {
        end > start ? end - start : 0
    }

    @inlinable
    public func clamped(to dataCount: Int) -> ByteRange {
        let max = UInt32(max(0, dataCount))
        return ByteRange(start: min(start, max), end: min(end, max))
    }

    @inlinable
    public func string(in data: Data) -> String {
        let safe = clamped(to: data.count)
        guard safe.start < safe.end else { return "" }
        return data.withUnsafeBytes { buffer in
            let slice = buffer[Int(safe.start)..<Int(safe.end)]
            return String(decoding: slice, as: UTF8.self)
        }
    }
}

@frozen
public struct ByteRangeSequence: Sendable, Equatable {
    public let ranges: [ByteRange]

    public init(_ ranges: [ByteRange]) {
        self.ranges = ranges
    }

    @inlinable
    public func string(in data: Data) -> String {
        guard !ranges.isEmpty else { return "" }
        var result = ""
        result.reserveCapacity(ranges.reduce(0) { $0 + Int($1.end - $1.start) })
        for range in ranges {
            result.append(range.string(in: data))
        }
        return result
    }
}
