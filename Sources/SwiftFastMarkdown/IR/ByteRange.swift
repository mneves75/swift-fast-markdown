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
        let maxVal = UInt32(clamping: dataCount)
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
                let (nextTotal, overflow) = totalBytes.addingReportingOverflow(Int(safe.end - safe.start))
                if overflow { return "" }
                totalBytes = nextTotal
            }
        }
        guard totalBytes > 0 else { return "" }

        // Concatenate all UTF-8 slices into a single contiguous buffer once,
        // validating non-ASCII slices individually so malformed UTF-8 halves
        // across disjoint ranges cannot splice into forged Unicode scalars.
        var bytes: [UInt8] = []
        bytes.reserveCapacity(totalBytes)
        for range in ranges {
            let safe = range.clamped(to: dataCount)
            if safe.start < safe.end {
                let slice = buffer[Int(safe.start)..<Int(safe.end)]
                if Self.isValidUTF8(slice) {
                    bytes.append(contentsOf: slice)
                } else {
                    var sanitized = String(decoding: slice, as: UTF8.self)
                    sanitized.withUTF8 { utf8 in
                        if !utf8.isEmpty {
                            bytes.append(contentsOf: utf8)
                        }
                    }
                }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    @usableFromInline
    internal static func isValidUTF8(_ slice: Slice<UnsafeRawBufferPointer>) -> Bool {
        var i = slice.startIndex
        let end = slice.endIndex
        while i < end {
            let b0 = slice[i]
            if b0 < 0x80 {
                i += 1
                continue
            }
            if b0 >= 0xC2 && b0 <= 0xDF {
                guard i + 1 < end, (slice[i + 1] & 0xC0) == 0x80 else { return false }
                i += 2
            } else if b0 >= 0xE0 && b0 <= 0xEF {
                guard i + 2 < end else { return false }
                let b1 = slice[i + 1], b2 = slice[i + 2]
                guard (b1 & 0xC0) == 0x80, (b2 & 0xC0) == 0x80 else { return false }
                if b0 == 0xE0 && b1 < 0xA0 { return false }
                if b0 == 0xED && b1 >= 0xA0 { return false }
                i += 3
            } else if b0 >= 0xF0 && b0 <= 0xF4 {
                guard i + 3 < end else { return false }
                let b1 = slice[i + 1], b2 = slice[i + 2], b3 = slice[i + 3]
                guard (b1 & 0xC0) == 0x80, (b2 & 0xC0) == 0x80, (b3 & 0xC0) == 0x80 else { return false }
                if b0 == 0xF0 && b1 < 0x90 { return false }
                if b0 == 0xF4 && b1 >= 0x90 { return false }
                i += 4
            } else {
                return false
            }
        }
        return true
    }
}
