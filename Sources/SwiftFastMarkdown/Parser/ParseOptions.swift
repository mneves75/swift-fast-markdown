import Foundation
import CMD4C

public struct ParseOptions: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let permissiveATXHeaders = ParseOptions(rawValue: UInt32(MD_FLAG_PERMISSIVEATXHEADERS))
    public static let permissiveURLAutolinks = ParseOptions(rawValue: UInt32(MD_FLAG_PERMISSIVEURLAUTOLINKS))
    public static let permissiveEmailAutolinks = ParseOptions(rawValue: UInt32(MD_FLAG_PERMISSIVEEMAILAUTOLINKS))
    public static let permissiveWWWWAutolinks = ParseOptions(rawValue: UInt32(MD_FLAG_PERMISSIVEWWWAUTOLINKS))
    public static let tables = ParseOptions(rawValue: UInt32(MD_FLAG_TABLES))
    public static let strikethrough = ParseOptions(rawValue: UInt32(MD_FLAG_STRIKETHROUGH))
    public static let taskLists = ParseOptions(rawValue: UInt32(MD_FLAG_TASKLISTS))
    public static let hardSoftBreaks = ParseOptions(rawValue: UInt32(MD_FLAG_HARD_SOFT_BREAKS))
    public static let noHTMLBlocks = ParseOptions(rawValue: UInt32(MD_FLAG_NOHTMLBLOCKS))
    public static let noHTMLSpans = ParseOptions(rawValue: UInt32(MD_FLAG_NOHTMLSPANS))

    public static let gfmSubset: ParseOptions = [
        .permissiveURLAutolinks,
        .permissiveEmailAutolinks,
        .permissiveWWWWAutolinks,
        .tables,
        .strikethrough,
        .taskLists
    ]

    /// Strict CommonMark mode with no extensions.
    public static let commonMark: ParseOptions = []

    public static let `default`: ParseOptions = .gfmSubset
}
