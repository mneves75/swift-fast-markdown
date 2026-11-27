import Foundation

enum EntityDecoder {
    static func decode(_ entity: String) -> String {
        var copy = entity
        return copy.withUTF8 { buffer in
            decodeUTF8(buffer) ?? entity
        }
    }

    /// Decodes an HTML entity directly from raw UTF-8 bytes without allocating
    /// intermediate substrings. Returns `nil` when the bytes do not decode to a
    /// known entity (callers can fall back to the original bytes).
    static func decodeUTF8(_ bytes: UnsafeBufferPointer<UInt8>) -> String? {
        let count = bytes.count
        guard count >= 3, bytes[0] == 0x26, bytes[count - 1] == 0x3B else {
            return nil
        }

        // Numeric entities: &#123; or &#x1A;
        if bytes[1] == 0x23 {
            guard count >= 4 else { return nil }
            let third = bytes[2]
            if third == 0x78 || third == 0x58 {
                // Hexadecimal: &#x...;
                guard count >= 5 else { return nil }
                var value: UInt32 = 0
                for i in 3..<(count - 1) {
                    let b = bytes[i]
                    let digit: UInt32
                    if b >= 0x30 && b <= 0x39 {
                        digit = UInt32(b - 0x30)
                    } else if b >= 0x41 && b <= 0x46 {
                        digit = UInt32(b - 0x41 + 10)
                    } else if b >= 0x61 && b <= 0x66 {
                        digit = UInt32(b - 0x61 + 10)
                    } else {
                        return nil
                    }
                    let (mul, o1) = value.multipliedReportingOverflow(by: 16)
                    let (add, o2) = mul.addingReportingOverflow(digit)
                    if o1 || o2 { return nil }
                    value = add
                }
                guard let scalar = UnicodeScalar(value) else { return nil }
                return String(scalar)
            } else {
                // Decimal: &#...;
                var value: UInt32 = 0
                for i in 2..<(count - 1) {
                    let b = bytes[i]
                    guard b >= 0x30 && b <= 0x39 else { return nil }
                    let digit = UInt32(b - 0x30)
                    let (mul, o1) = value.multipliedReportingOverflow(by: 10)
                    let (add, o2) = mul.addingReportingOverflow(digit)
                    if o1 || o2 { return nil }
                    value = add
                }
                guard let scalar = UnicodeScalar(value) else { return nil }
                return String(scalar)
            }
        }

        // Fast path for the most frequent HTML5 named entities — avoids touching
        // disk or loading the full table in the vast majority of documents.
        let nameLen = count - 2
        guard let base = bytes.baseAddress else { return nil }
        let namePtr = base + 1

        if let fast = fastNamedEntity(namePtr, length: nameLen) {
            return fast
        }

        return HTMLEntities.shared.lookupUTF8(namePtr, length: nameLen)
    }

    @inline(__always)
    private static func fastNamedEntity(_ p: UnsafePointer<UInt8>, length: Int) -> String? {
        switch length {
        case 2:
            let b0 = p[0], b1 = p[1]
            if b0 == 0x6C && b1 == 0x74 { return "<" } // lt
            if b0 == 0x67 && b1 == 0x74 { return ">" } // gt
            if b0 == 0x4C && b1 == 0x54 { return "<" } // LT
            if b0 == 0x47 && b1 == 0x54 { return ">" } // GT
        case 3:
            let b0 = p[0], b1 = p[1], b2 = p[2]
            if b0 == 0x61 && b1 == 0x6D && b2 == 0x70 { return "&" } // amp
            if b0 == 0x41 && b1 == 0x4D && b2 == 0x50 { return "&" } // AMP
            if b0 == 0x72 && b1 == 0x65 && b2 == 0x67 { return "®" } // reg
            if b0 == 0x52 && b1 == 0x45 && b2 == 0x47 { return "®" } // REG
            if b0 == 0x64 && b1 == 0x65 && b2 == 0x67 { return "°" } // deg
            if b0 == 0x79 && b1 == 0x65 && b2 == 0x6E { return "¥" } // yen
        case 4:
            let b0 = p[0], b1 = p[1], b2 = p[2], b3 = p[3]
            if b0 == 0x71 && b1 == 0x75 && b2 == 0x6F && b3 == 0x74 { return "\"" } // quot
            if b0 == 0x51 && b1 == 0x55 && b2 == 0x4F && b3 == 0x54 { return "\"" } // QUOT
            if b0 == 0x61 && b1 == 0x70 && b2 == 0x6F && b3 == 0x73 { return "'" }  // apos
            if b0 == 0x6E && b1 == 0x62 && b2 == 0x73 && b3 == 0x70 { return "\u{00A0}" } // nbsp
            if b0 == 0x63 && b1 == 0x6F && b2 == 0x70 && b3 == 0x79 { return "©" } // copy
            if b0 == 0x43 && b1 == 0x4F && b2 == 0x50 && b3 == 0x59 { return "©" } // COPY
            if b0 == 0x62 && b1 == 0x75 && b2 == 0x6C && b3 == 0x6C { return "•" } // bull
            if b0 == 0x65 && b1 == 0x75 && b2 == 0x72 && b3 == 0x6F { return "€" } // euro
            if b0 == 0x73 && b1 == 0x65 && b2 == 0x63 && b3 == 0x74 { return "§" } // sect
        case 5:
            let b0 = p[0], b1 = p[1], b2 = p[2], b3 = p[3], b4 = p[4]
            if b0 == 0x6D && b1 == 0x64 && b2 == 0x61 && b3 == 0x73 && b4 == 0x68 { return "—" } // mdash
            if b0 == 0x6E && b1 == 0x64 && b2 == 0x61 && b3 == 0x73 && b4 == 0x68 { return "–" } // ndash
            if b0 == 0x74 && b1 == 0x72 && b2 == 0x61 && b3 == 0x64 && b4 == 0x65 { return "™" } // trade
            if b0 == 0x74 && b1 == 0x69 && b2 == 0x6D && b3 == 0x65 && b4 == 0x73 { return "×" } // times
            if b0 == 0x6C && b1 == 0x73 && b2 == 0x71 && b3 == 0x75 && b4 == 0x6F { return "‘" } // lsquo
            if b0 == 0x72 && b1 == 0x73 && b2 == 0x71 && b3 == 0x75 && b4 == 0x6F { return "’" } // rsquo
            if b0 == 0x6C && b1 == 0x64 && b2 == 0x71 && b3 == 0x75 && b4 == 0x6F { return "“" } // ldquo
            if b0 == 0x72 && b1 == 0x64 && b2 == 0x71 && b3 == 0x75 && b4 == 0x6F { return "”" } // rdquo
            if b0 == 0x70 && b1 == 0x6F && b2 == 0x75 && b3 == 0x6E && b4 == 0x64 { return "£" } // pound
        case 6:
            let b0 = p[0], b1 = p[1], b2 = p[2], b3 = p[3], b4 = p[4], b5 = p[5]
            if b0 == 0x68 && b1 == 0x65 && b2 == 0x6C && b3 == 0x6C && b4 == 0x69 && b5 == 0x70 { return "…" } // hellip
            if b0 == 0x6D && b1 == 0x69 && b2 == 0x64 && b3 == 0x64 && b4 == 0x6F && b5 == 0x74 { return "·" } // middot
        default:
            break
        }
        return nil
    }
}

/// Compact, sorted binary HTML5 named-entity table (~28.7 KB vs ~146 KB JSON).
/// Loaded lazily on the first non-common entity; binary-searched directly in
/// UTF-8 without JSONSerialization or dictionary heap allocations.
struct HTMLEntities: Sendable {
    static let shared = HTMLEntities()

    private let tableData: Data
    private let entryCount: Int

    private init() {
        let data = HTMLEntities.loadTableData()
        self.tableData = data
        if data.count >= 2 {
            let count = data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int in
                Int(buf[0]) | (Int(buf[1]) << 8)
            }
            self.entryCount = (2 + 2 * count <= data.count) ? count : 0
        } else {
            self.entryCount = 0
        }
    }

    func lookup(_ entity: String) -> String? {
        guard entity.hasPrefix("&"), entity.hasSuffix(";"), entity.utf8.count >= 3 else {
            return nil
        }
        var copy = entity
        return copy.withUTF8 { buf in
            guard let base = buf.baseAddress else { return nil }
            return lookupUTF8(base + 1, length: buf.count - 2)
        }
    }

    func lookupUTF8(_ keyPtr: UnsafePointer<UInt8>, length keyLen: Int) -> String? {
        guard entryCount > 0, keyLen > 0, keyLen < 256 else { return nil }
        return tableData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            let totalLen = raw.count
            var lo = 0
            var hi = entryCount - 1

            while lo <= hi {
                let mid = (lo + hi) >> 1
                let idxPos = 2 + (mid << 1)
                let offset = Int(base[idxPos]) | (Int(base[idxPos + 1]) << 8)
                guard offset < totalLen else { return nil }

                let entryKeyLen = Int(base[offset])
                let entryKeyStart = offset + 1
                guard entryKeyStart + entryKeyLen < totalLen else { return nil }

                let cmp = compareBytes(keyPtr, keyLen, base + entryKeyStart, entryKeyLen)
                if cmp == 0 {
                    let valLenPos = entryKeyStart + entryKeyLen
                    let valLen = Int(base[valLenPos])
                    let valStart = valLenPos + 1
                    guard valStart + valLen <= totalLen else { return nil }
                    let slice = UnsafeBufferPointer(start: base + valStart, count: valLen)
                    return String(decoding: slice, as: UTF8.self)
                } else if cmp < 0 {
                    hi = mid - 1
                } else {
                    lo = mid + 1
                }
            }
            return nil
        }
    }

    @inline(__always)
    private func compareBytes(
        _ a: UnsafePointer<UInt8>, _ aLen: Int,
        _ b: UnsafePointer<UInt8>, _ bLen: Int
    ) -> Int {
        let minLen = Swift.min(aLen, bLen)
        let r = Int(memcmp(a, b, minLen))
        if r != 0 { return r }
        return aLen - bLen
    }

    private static func loadTableData() -> Data {
        guard let url = Bundle.module.url(forResource: "HTMLEntities", withExtension: "bin") else {
            #if DEBUG
            assertionFailure("[SwiftFastMarkdown] HTMLEntities.bin not found in bundle")
            #endif
            return Data()
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            #if DEBUG
            assertionFailure("[SwiftFastMarkdown] Failed to read HTMLEntities.bin")
            #endif
            return Data()
        }

        return data
    }
}
