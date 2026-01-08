import SwiftUI

public struct MarkdownStyle: Sendable {
    public var baseFont: Font
    public var codeFont: Font
    public var headingFonts: [Font]
    public var linkColor: Color
    public var textColor: Color
    public var codeTextColor: Color
    public var codeBackgroundColor: Color
    public var quoteStripeColor: Color
    public var blockSpacing: Int
    public var listIndent: Int

    public init(
        baseFont: Font,
        codeFont: Font,
        headingFonts: [Font],
        linkColor: Color,
        textColor: Color,
        codeTextColor: Color,
        codeBackgroundColor: Color,
        quoteStripeColor: Color,
        blockSpacing: Int,
        listIndent: Int
    ) {
        self.baseFont = baseFont
        self.codeFont = codeFont
        self.headingFonts = headingFonts
        self.linkColor = linkColor
        self.textColor = textColor
        self.codeTextColor = codeTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.quoteStripeColor = quoteStripeColor
        self.blockSpacing = blockSpacing
        self.listIndent = listIndent
    }

    public static let `default` = MarkdownStyle(
        baseFont: .system(.body),
        codeFont: .system(.body, design: .monospaced),
        headingFonts: [
            .system(.largeTitle, design: .default).weight(.bold),
            .system(.title, design: .default).weight(.bold),
            .system(.title2, design: .default).weight(.semibold),
            .system(.title3, design: .default).weight(.semibold),
            .system(.headline, design: .default).weight(.semibold),
            .system(.subheadline, design: .default).weight(.semibold)
        ],
        linkColor: .blue,
        textColor: .primary,
        codeTextColor: .primary,
        codeBackgroundColor: Color.gray.opacity(0.15),
        quoteStripeColor: .secondary,
        blockSpacing: 2,
        listIndent: 2
    )
}
