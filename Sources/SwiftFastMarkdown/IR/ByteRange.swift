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
        let maxVal = UInt32(Swift.max(0, dataCount))
        return ByteRange(start: Swift.min(start, maxVal), end: Swift.min(end, maxVal))
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

    @inlinable
    internal func string(in buffer: UnsafeRawBufferPointer) -> String {
        let safe = clamped(to: buffer.count)
        guard safe.start < safe.end else { return "" }
        let slice = buffer[Int(safe.start)..<Int(safe.end)]
        return String(decoding: slice, as: UTF8.self)
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
        if ranges.count == 1 {
            return ranges[0].string(in: data)
        }
        return data.withUnsafeBytes { buffer in
            string(in: buffer)
        }
    }

    @inlinable
    internal func string(in buffer: UnsafeRawBufferPointer) -> String {
        guard !ranges.isEmpty else { return "" }
        if ranges.count == 1 {
            return ranges[0].string(in: buffer)
        }
        let dataCount = buffer.count
        var totalBytes = 0
        for range in ranges {
            let safe = range.clamped(to: dataCount)
            if safe.start < safe.end {
                totalBytes += Int(safe.end - safe.start)
            }
        }
        guard totalBytes > 0, let srcBase = buffer.baseAddress else { return "" }

        // Concatenate all UTF-8 slices into a single contiguous buffer once,
        // avoiding per-range String allocations and repeated CoW appends.
        var bytes: [UInt8] = []
        bytes.reserveCapacity(totalBytes)
        for range in ranges {
            let safe = range.clamped(to: dataCount)
            if safe.start < safe.end {
                let len = Int(safe.end - safe.start)
                let ptr = srcBase.advanced(by: Int(safe.start)).assumingMemoryBound(to: UInt8.self)
                bytes.append(contentsOf: UnsafeBufferPointer(start: ptr, count: len))
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
