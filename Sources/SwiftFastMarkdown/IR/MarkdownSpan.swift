import Foundation

@frozen
public enum MarkdownSpan: Sendable, Equatable {
    case text(TextContent)
    case emphasis([MarkdownSpan])
    case strong([MarkdownSpan])
    case strikethrough([MarkdownSpan])
    case underline([MarkdownSpan])
    case code(TextContent)
    case link(children: [MarkdownSpan], destination: TextContent?, title: TextContent?)
    case image(alt: [MarkdownSpan], source: TextContent?, title: TextContent?)
    case lineBreak
    case softBreak
    case html(TextContent)
    case wikiLink(target: TextContent, children: [MarkdownSpan])
    case latexInline(TextContent)
    case latexDisplay(TextContent)
}
