import Foundation
import SwiftUI

public struct AttributedStringRenderer: Sendable {
    fileprivate static let thematicBreakUTF8: [UInt8] = Array(String(repeating: "—", count: 20).utf8)
    fileprivate static let blockQuotePrefixUTF8: [UInt8] = Array("› ".utf8)
    fileprivate static let bulletPrefixUTF8: [UInt8] = Array("• ".utf8)
    fileprivate static let cellSeparatorUTF8: [UInt8] = Array(" | ".utf8)

    /// Cached AttributeContainers for `MarkdownStyle.default`, avoiding
    /// repeated container construction on the overwhelmingly common default path.
    private static let defaultPalette = StylePalette(style: .default)

    /// Returns a URL only when the destination is safe to attach as a link.
    /// Scheme-less (relative) destinations are allowed.
    /// Markdown often comes from untrusted sources (LLM output, user input);
    /// anything else — javascript:, data:, file:, etc. — is rendered as plain text.
    static func safeLinkURL(_ destination: String) -> URL? {
        guard let url = URL(string: destination) else { return nil }
        guard let scheme = url.scheme else { return url }
        return isAllowedScheme(scheme) ? url : nil
    }

    @inline(__always)
    private static func isAllowedScheme(_ scheme: String) -> Bool {
        var s = scheme
        return s.withUTF8 { buf in
            switch buf.count {
            case 3: // tel
                return (buf[0] | 0x20) == 0x74 && (buf[1] | 0x20) == 0x65 && (buf[2] | 0x20) == 0x6C
            case 4: // http
                return (buf[0] | 0x20) == 0x68 && (buf[1] | 0x20) == 0x74 && (buf[2] | 0x20) == 0x74 && (buf[3] | 0x20) == 0x70
            case 5: // https
                return (buf[0] | 0x20) == 0x68 && (buf[1] | 0x20) == 0x74 && (buf[2] | 0x20) == 0x74 && (buf[3] | 0x20) == 0x70 && (buf[4] | 0x20) == 0x73
            case 6: // mailto
                return (buf[0] | 0x20) == 0x6D && (buf[1] | 0x20) == 0x61 && (buf[2] | 0x20) == 0x69 && (buf[3] | 0x20) == 0x6C && (buf[4] | 0x20) == 0x74 && (buf[5] | 0x20) == 0x6F
            default:
                return false
            }
        }
    }

    public init() {}

    public func render(_ document: MarkdownDocument, style: MarkdownStyle = .default) -> AttributedString {
        let blocks = document.blocks
        guard !blocks.isEmpty else { return AttributedString() }

        let palette = (style == .default) ? Self.defaultPalette : StylePalette(style: style)
        return document.sourceData.withUnsafeBytes { rawSource in
            var builder = SinglePassBuilder(
                rawSource: rawSource,
                style: style,
                palette: palette,
                baseAttributes: palette.base,
                estimatedCapacity: rawSource.count + (rawSource.count >> 3)
            )
            builder.emitDocument(blocks)
            return builder.finalize()
        }
    }

    public func renderInline(
        _ spans: [MarkdownSpan],
        source: Data,
        style: MarkdownStyle = .default,
        fontOverride: Font? = nil
    ) -> AttributedString {
        guard !spans.isEmpty else { return AttributedString() }

        let palette = (style == .default) ? Self.defaultPalette : StylePalette(style: style)
        let baseAttrs: AttributeContainer
        let baseTag: PatchStyle
        if let fontOverride, fontOverride != style.baseFont {
            var custom = palette.base
            custom.font = fontOverride
            baseAttrs = custom
            baseTag = .base
        } else {
            baseAttrs = palette.base
            baseTag = .base
        }

        // Ultra-fast single-leaf path (covers the majority of headings, table cells,
        // and plain paragraphs rendered via SwiftUI InlineText).
        if spans.count == 1 {
            switch spans[0] {
            case .text(let content):
                return AttributedString(content.string(in: source), attributes: baseAttrs)
            case .code(let content):
                return AttributedString(content.string(in: source), attributes: palette.code)
            case .html(let content):
                return AttributedString(content.string(in: source), attributes: baseAttrs)
            case .latexInline(let content), .latexDisplay(let content):
                return AttributedString(content.string(in: source), attributes: palette.latex)
            case .lineBreak:
                return AttributedString("\n", attributes: baseAttrs)
            case .softBreak:
                return AttributedString(" ", attributes: baseAttrs)
            default:
                break
            }
        }

        return source.withUnsafeBytes { rawSource in
            var builder = SinglePassBuilder(
                rawSource: rawSource,
                style: style,
                palette: palette,
                baseAttributes: baseAttrs,
                estimatedCapacity: 128
            )
            builder.emitSpans(spans, styleTag: baseTag, currentAttrs: baseAttrs)
            return builder.finalize()
        }
    }
}

// MARK: - Prebuilt Style Palette

/// Pre-constructed `AttributeContainer`s for a `MarkdownStyle`, eliminating
/// per-span attribute dictionary mutations during rendering.
private struct StylePalette: Sendable {
    let base: AttributeContainer
    let code: AttributeContainer
    let latex: AttributeContainer
    let strong: AttributeContainer
    let emphasis: AttributeContainer
    let strikethrough: AttributeContainer
    let underline: AttributeContainer
    let linkBase: AttributeContainer
    let headings: [AttributeContainer]

    init(style: MarkdownStyle) {
        var base = AttributeContainer()
        base.font = style.baseFont
        base.foregroundColor = style.textColor
        self.base = base

        var code = AttributeContainer()
        code.font = style.codeFont
        code.foregroundColor = style.codeTextColor
        code.backgroundColor = style.codeBackgroundColor
        self.code = code

        var latex = AttributeContainer()
        latex.font = style.codeFont
        latex.foregroundColor = style.codeTextColor
        self.latex = latex

        var strong = base
        strong.inlinePresentationIntent = .stronglyEmphasized
        self.strong = strong

        var emphasis = base
        emphasis.inlinePresentationIntent = .emphasized
        self.emphasis = emphasis

        var strikethrough = base
        strikethrough.strikethroughStyle = .single
        self.strikethrough = strikethrough

        var underline = base
        underline.underlineStyle = .single
        self.underline = underline

        var linkBase = base
        linkBase.foregroundColor = style.linkColor
        self.linkBase = linkBase

        self.headings = style.headingFonts.map { headingFont in
            var h = AttributeContainer()
            h.font = headingFont
            h.foregroundColor = style.textColor
            return h
        }
    }

    @inline(__always)
    func headingAttributes(level: Int) -> AttributeContainer {
        guard !headings.isEmpty else { return base }
        let idx = max(0, min(level - 1, headings.count - 1))
        return headings[idx]
    }
}

// MARK: - POD Run-Patch Representation (Zero ARC in Patch Array)

/// Compact POD style identifier stored inside `RunPatch`, avoiding ARC retain/
/// release of `AttributeContainer` for the 95%+ of spans matching a palette entry.
private enum PatchStyle: Equatable {
    case base
    case strong
    case emphasis
    case strikethrough
    case underline
    case code
    case latex
    case heading(Int)     // 0-based index into palette.headings
    case custom(Int)      // index into SinglePassBuilder.customContainers
}

private struct RunPatch {
    let startByte: Int
    let endByte: Int
    let style: PatchStyle
}

private struct SinglePassBuilder {
    let rawSource: UnsafeRawBufferPointer
    let style: MarkdownStyle
    let palette: StylePalette
    let baseAttributes: AttributeContainer

    private var utf8Bytes: [UInt8]
    private var patches: [RunPatch]
    private var customContainers: [AttributeContainer] = []
    private var hasUntrustedNonASCII: Bool = false

    init(
        rawSource: UnsafeRawBufferPointer,
        style: MarkdownStyle,
        palette: StylePalette,
        baseAttributes: AttributeContainer,
        estimatedCapacity: Int
    ) {
        self.rawSource = rawSource
        self.style = style
        self.palette = palette
        self.baseAttributes = baseAttributes
        self.utf8Bytes = []
        self.utf8Bytes.reserveCapacity(estimatedCapacity)
        self.patches = []
        self.patches.reserveCapacity(max(8, estimatedCapacity >> 6))
    }

    mutating func emitDocument(_ blocks: [MarkdownBlock]) {
        let blockCount = blocks.count
        let newlineCount = max(1, style.blockSpacing)
        for index in 0..<blockCount {
            emitBlock(blocks[index], indentLevel: 0)
            if index < blockCount - 1 {
                appendRepeatedASCII(0x0A, count: newlineCount)
            }
        }
    }

    private mutating func emitBlock(_ block: MarkdownBlock, indentLevel: Int) {
        switch block {
        case .paragraph(let paragraph):
            if indentLevel > 0 {
                appendRepeatedASCII(0x20, count: indentLevel)
            }
            emitSpans(paragraph.spans, styleTag: .base, currentAttrs: baseAttributes)

        case .heading(let heading):
            if indentLevel > 0 {
                appendRepeatedASCII(0x20, count: indentLevel)
            }
            if palette.headings.isEmpty {
                emitSpans(heading.spans, styleTag: .base, currentAttrs: baseAttributes)
            } else {
                let idx = max(0, min(heading.level - 1, palette.headings.count - 1))
                emitSpans(heading.spans, styleTag: .heading(idx), currentAttrs: palette.headings[idx])
            }

        case .codeBlock(let codeBlock):
            if indentLevel > 0 {
                appendRepeatedASCII(0x20, count: indentLevel)
            }
            let start = utf8Bytes.count
            appendTextContent(codeBlock.content)
            recordPatch(start: start, end: utf8Bytes.count, style: .code)

        case .blockQuote(let quote):
            let blocks = quote.blocks
            let count = blocks.count
            let nextIndent = indentLevel + style.listIndent
            for index in 0..<count {
                if indentLevel > 0 {
                    appendRepeatedASCII(0x20, count: indentLevel)
                }
                appendBytes(AttributedStringRenderer.blockQuotePrefixUTF8)
                emitBlock(blocks[index], indentLevel: nextIndent)
                if index < count - 1 {
                    utf8Bytes.append(0x0A)
                }
            }

        case .list(let list):
            let items = list.items
            let count = items.count
            let ordered = list.ordered
            let startNum = list.start
            let nextIndent = indentLevel + style.listIndent
            for index in 0..<count {
                if indentLevel > 0 {
                    appendRepeatedASCII(0x20, count: indentLevel)
                }
                if ordered {
                    appendDecimalInt(startNum + index)
                    utf8Bytes.append(0x2E) // '.'
                    utf8Bytes.append(0x20) // ' '
                } else {
                    appendBytes(AttributedStringRenderer.bulletPrefixUTF8)
                }
                let itemBlocks = items[index].blocks
                let blockCount = itemBlocks.count
                for blockIndex in 0..<blockCount {
                    emitBlock(itemBlocks[blockIndex], indentLevel: nextIndent)
                    if blockIndex < blockCount - 1 {
                        utf8Bytes.append(0x0A)
                    }
                }
                if index < count - 1 {
                    utf8Bytes.append(0x0A)
                }
            }

        case .table(let table):
            let totalRows = table.headerRows.count + table.bodyRows.count
            guard totalRows > 0 else { return }
            var rowCounter = 0
            for row in table.headerRows {
                emitTableRow(row, indentLevel: indentLevel)
                rowCounter += 1
                if rowCounter < totalRows {
                    utf8Bytes.append(0x0A)
                }
            }
            for row in table.bodyRows {
                emitTableRow(row, indentLevel: indentLevel)
                rowCounter += 1
                if rowCounter < totalRows {
                    utf8Bytes.append(0x0A)
                }
            }

        case .thematicBreak:
            appendBytes(AttributedStringRenderer.thematicBreakUTF8)

        case .htmlBlock(let html):
            if indentLevel > 0 {
                appendRepeatedASCII(0x20, count: indentLevel)
            }
            appendTextContent(html.content)
        }
    }

    @inline(__always)
    private mutating func emitTableRow(_ row: TableRow, indentLevel: Int) {
        if indentLevel > 0 {
            appendRepeatedASCII(0x20, count: indentLevel)
        }
        let cells = row.cells
        let cellCount = cells.count
        for cellIndex in 0..<cellCount {
            emitSpans(cells[cellIndex].spans, styleTag: .base, currentAttrs: baseAttributes)
            if cellIndex < cellCount - 1 {
                appendBytes(AttributedStringRenderer.cellSeparatorUTF8)
            }
        }
    }

    mutating func emitSpans(_ spans: [MarkdownSpan], styleTag: PatchStyle, currentAttrs: AttributeContainer) {
        for span in spans {
            emitSpan(span, styleTag: styleTag, currentAttrs: currentAttrs)
        }
    }

    private mutating func emitSpan(_ span: MarkdownSpan, styleTag: PatchStyle, currentAttrs: AttributeContainer) {
        switch span {
        case .text(let content):
            let start = utf8Bytes.count
            appendTextContent(content)
            if styleTag != .base {
                recordPatch(start: start, end: utf8Bytes.count, style: styleTag)
            }

        case .emphasis(let children):
            if styleTag == .base {
                emitSpans(children, styleTag: .emphasis, currentAttrs: palette.emphasis)
            } else {
                var derived = currentAttrs
                derived.inlinePresentationIntent = (derived.inlinePresentationIntent ?? []).union(.emphasized)
                let idx = registerCustom(derived)
                emitSpans(children, styleTag: .custom(idx), currentAttrs: derived)
            }

        case .strong(let children):
            if styleTag == .base {
                emitSpans(children, styleTag: .strong, currentAttrs: palette.strong)
            } else {
                var derived = currentAttrs
                derived.inlinePresentationIntent = (derived.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                let idx = registerCustom(derived)
                emitSpans(children, styleTag: .custom(idx), currentAttrs: derived)
            }

        case .strikethrough(let children):
            if styleTag == .base {
                emitSpans(children, styleTag: .strikethrough, currentAttrs: palette.strikethrough)
            } else {
                var derived = currentAttrs
                derived.strikethroughStyle = .single
                let idx = registerCustom(derived)
                emitSpans(children, styleTag: .custom(idx), currentAttrs: derived)
            }

        case .underline(let children):
            if styleTag == .base {
                emitSpans(children, styleTag: .underline, currentAttrs: palette.underline)
            } else {
                var derived = currentAttrs
                derived.underlineStyle = .single
                let idx = registerCustom(derived)
                emitSpans(children, styleTag: .custom(idx), currentAttrs: derived)
            }

        case .code(let content):
            let start = utf8Bytes.count
            appendTextContent(content)
            recordPatch(start: start, end: utf8Bytes.count, style: .code)

        case .link(let children, let destination, _):
            var derived = (styleTag == .base) ? palette.linkBase : currentAttrs
            if styleTag != .base {
                derived.foregroundColor = style.linkColor
            }
            if let destination, let url = AttributedStringRenderer.safeLinkURL(destination.string(in: rawSource)) {
                derived.link = url
            }
            let idx = registerCustom(derived)
            emitSpans(children, styleTag: .custom(idx), currentAttrs: derived)

        case .image(let alt, _, _):
            emitSpans(alt, styleTag: styleTag, currentAttrs: currentAttrs)

        case .lineBreak:
            let start = utf8Bytes.count
            utf8Bytes.append(0x0A)
            if styleTag != .base {
                recordPatch(start: start, end: utf8Bytes.count, style: styleTag)
            }

        case .softBreak:
            let start = utf8Bytes.count
            utf8Bytes.append(0x20)
            if styleTag != .base {
                recordPatch(start: start, end: utf8Bytes.count, style: styleTag)
            }

        case .html(let content):
            let start = utf8Bytes.count
            appendTextContent(content)
            if styleTag != .base {
                recordPatch(start: start, end: utf8Bytes.count, style: styleTag)
            }

        case .wikiLink(let target, let children):
            var derived = (styleTag == .base) ? palette.linkBase : currentAttrs
            if styleTag != .base {
                derived.foregroundColor = style.linkColor
            }
            if let url = AttributedStringRenderer.safeLinkURL(target.string(in: rawSource)) {
                derived.link = url
            }
            let idx = registerCustom(derived)
            emitSpans(children, styleTag: .custom(idx), currentAttrs: derived)

        case .latexInline(let content), .latexDisplay(let content):
            let start = utf8Bytes.count
            appendTextContent(content)
            recordPatch(start: start, end: utf8Bytes.count, style: .latex)
        }
    }

    @inline(__always)
    private mutating func registerCustom(_ container: AttributeContainer) -> Int {
        let idx = customContainers.count
        customContainers.append(container)
        return idx
    }

    @inline(__always)
    private func resolveAttributes(for style: PatchStyle) -> AttributeContainer {
        switch style {
        case .base:
            return baseAttributes
        case .strong:
            return palette.strong
        case .emphasis:
            return palette.emphasis
        case .strikethrough:
            return palette.strikethrough
        case .underline:
            return palette.underline
        case .code:
            return palette.code
        case .latex:
            return palette.latex
        case .heading(let idx):
            return palette.headings[idx]
        case .custom(let idx):
            return customContainers[idx]
        }
    }

    // MARK: - Low-Level UTF-8 Appenders

    @inline(__always)
    private mutating func recordPatch(start: Int, end: Int, style: PatchStyle) {
        guard end > start else { return }
        if let lastIdx = patches.indices.last,
           patches[lastIdx].endByte == start,
           patches[lastIdx].style == style {
            patches[lastIdx] = RunPatch(startByte: patches[lastIdx].startByte, endByte: end, style: style)
            return
        }
        patches.append(RunPatch(startByte: start, endByte: end, style: style))
    }

    @inline(__always)
    private mutating func appendTextContent(_ content: TextContent) {
        switch content {
        case .bytes(let range):
            appendByteRange(range)
        case .string(let value):
            if !value.isEmpty {
                var copy = value
                copy.withUTF8 { buf in
                    if !buf.isEmpty {
                        utf8Bytes.append(contentsOf: buf)
                    }
                }
            }
        case .sequence(let sequence):
            for range in sequence.ranges {
                appendByteRange(range)
            }
        }
    }

    @inline(__always)
    private mutating func appendByteRange(_ range: ByteRange) {
        let safe = range.clamped(to: rawSource.count)
        guard safe.start < safe.end, let base = rawSource.baseAddress else { return }
        let start = Int(safe.start)
        let len = Int(safe.end - safe.start)
        let ptr = base.advanced(by: start).assumingMemoryBound(to: UInt8.self)
        utf8Bytes.append(contentsOf: UnsafeBufferPointer(start: ptr, count: len))
        if !hasUntrustedNonASCII {
            var i = 0
            while i + 8 <= len {
                let word = UnsafeRawPointer(ptr + i).loadUnaligned(as: UInt64.self)
                if (word & 0x8080_8080_8080_8080) != 0 {
                    hasUntrustedNonASCII = true
                    return
                }
                i += 8
            }
            while i < len {
                if (ptr[i] & 0x80) != 0 {
                    hasUntrustedNonASCII = true
                    return
                }
                i += 1
            }
        }
    }

    @inline(__always)
    private mutating func appendBytes(_ bytes: [UInt8]) {
        utf8Bytes.append(contentsOf: bytes)
    }

    @inline(__always)
    private mutating func appendRepeatedASCII(_ byte: UInt8, count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            utf8Bytes.append(byte)
        }
    }

    @inline(__always)
    private mutating func appendDecimalInt(_ value: Int) {
        if value < 10 && value >= 0 {
            utf8Bytes.append(0x30 &+ UInt8(value))
            return
        }
        var n = value
        if n < 0 {
            utf8Bytes.append(0x2D)
            n = -n
        }
        var digits: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var count = 0
        withUnsafeMutableBytes(of: &digits) { buf in
            repeat {
                buf[count] = 0x30 &+ UInt8(n % 10)
                n /= 10
                count += 1
            } while n > 0
            for i in stride(from: count - 1, through: 0, by: -1) {
                utf8Bytes.append(buf[i])
            }
        }
    }

    // MARK: - Finalize to AttributedString

    func finalize() -> AttributedString {
        guard !utf8Bytes.isEmpty else { return AttributedString() }

        let offsetsExact = !hasUntrustedNonASCII || Self.isValidUTF8(utf8Bytes)

        if offsetsExact {
            let fullString = String(decoding: utf8Bytes, as: UTF8.self)
            var result = AttributedString(fullString, attributes: baseAttributes)
            guard !patches.isEmpty else { return result }

            if #available(iOS 26, macOS 26, *) {
                var cursor = result.startIndex
                var cursorByte = 0

                for patch in patches {
                    let startDelta = patch.startByte - cursorByte
                    let startIdx = startDelta == 0 ? cursor : result.utf8.index(cursor, offsetBy: startDelta)
                    let endIdx = result.utf8.index(startIdx, offsetBy: patch.endByte - patch.startByte)
                    result[startIdx..<endIdx].setAttributes(resolveAttributes(for: patch.style))
                    cursor = endIdx
                    cursorByte = patch.endByte
                }
            } else {
                var strCursor = fullString.utf8.startIndex
                var cursorByte = 0

                for patch in patches {
                    let startDelta = patch.startByte - cursorByte
                    let strStart = startDelta == 0 ? strCursor : fullString.utf8.index(strCursor, offsetBy: startDelta)
                    let strEnd = fullString.utf8.index(strStart, offsetBy: patch.endByte - patch.startByte)
                    if let startIdx = AttributedString.Index(strStart, within: result),
                       let endIdx = AttributedString.Index(strEnd, within: result) {
                        result[startIdx..<endIdx].setAttributes(resolveAttributes(for: patch.style))
                    }
                    strCursor = strEnd
                    cursorByte = patch.endByte
                }
            }
            return result
        }

        // Safe fallback for malformed UTF-8 inputs where replacement U+FFFD
        // characters alter byte lengths: decode slice-by-slice.
        var result = AttributedString()
        var pos = 0
        utf8Bytes.withUnsafeBufferPointer { buf in
            for patch in patches {
                if patch.startByte > pos {
                    let s = String(decoding: buf[pos..<patch.startByte], as: UTF8.self)
                    result.append(AttributedString(s, attributes: baseAttributes))
                }
                let s = String(decoding: buf[patch.startByte..<patch.endByte], as: UTF8.self)
                result.append(AttributedString(s, attributes: resolveAttributes(for: patch.style)))
                pos = patch.endByte
            }
            if pos < buf.count {
                let s = String(decoding: buf[pos..<buf.count], as: UTF8.self)
                result.append(AttributedString(s, attributes: baseAttributes))
            }
        }
        return result
    }

    private static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBufferPointer { buf in
            var i = 0
            let n = buf.count
            while i < n {
                let b0 = buf[i]
                if b0 < 0x80 {
                    i += 1
                    continue
                }
                if b0 >= 0xC2 && b0 <= 0xDF {
                    guard i + 1 < n, (buf[i + 1] & 0xC0) == 0x80 else { return false }
                    i += 2
                } else if b0 >= 0xE0 && b0 <= 0xEF {
                    guard i + 2 < n else { return false }
                    let b1 = buf[i + 1], b2 = buf[i + 2]
                    guard (b1 & 0xC0) == 0x80, (b2 & 0xC0) == 0x80 else { return false }
                    if b0 == 0xE0 && b1 < 0xA0 { return false }
                    if b0 == 0xED && b1 >= 0xA0 { return false }
                    i += 3
                } else if b0 >= 0xF0 && b0 <= 0xF4 {
                    guard i + 3 < n else { return false }
                    let b1 = buf[i + 1], b2 = buf[i + 2], b3 = buf[i + 3]
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
}
