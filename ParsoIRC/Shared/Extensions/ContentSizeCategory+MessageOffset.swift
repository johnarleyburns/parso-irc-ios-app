import SwiftUI

/// Maps each SwiftUI `ContentSizeCategory` to a point-size offset relative
/// to the `.large` default (the system baseline).
///
/// The offsets mirror Apple's Body text style size table from the Human
/// Interface Guidelines.  Using an offset (rather than an absolute size)
/// means the app's manual slider value and the system Larger Text setting
/// are additive — both preferences are respected simultaneously.
///
/// Usage in a View:
/// ```swift
/// @AppStorage("messageFontSize") var base: Double = 15
/// @Environment(\.sizeCategory) var sizeCategory
///
/// var effectiveSize: CGFloat {
///     CGFloat(base) + CGFloat(sizeCategory.messageBodyOffset)
/// }
/// ```
extension ContentSizeCategory {
    /// Point-size offset to add to the app's base message font size so that
    /// the body bubble text responds correctly to iOS Accessibility → Larger Text.
    ///
    /// Values are the differences between each category's Body size and the
    /// `.large` (default) Body size of 17pt.
    var messageBodyOffset: Int {
        switch self {
        case .extraSmall:                        return -3  // 14pt body
        case .small:                             return -2  // 15pt body
        case .medium:                            return -1  // 16pt body
        case .large:                             return  0  // 17pt body (system default)
        case .extraLarge:                        return  2  // 19pt body
        case .extraExtraLarge:                   return  4  // 21pt body
        case .extraExtraExtraLarge:              return  6  // 23pt body
        case .accessibilityMedium:               return 11  // 28pt body
        case .accessibilityLarge:                return 16  // 33pt body
        case .accessibilityExtraLarge:           return 23  // 40pt body
        case .accessibilityExtraExtraLarge:      return 30  // 47pt body
        case .accessibilityExtraExtraExtraLarge: return 36  // 53pt body
        @unknown default:                        return  0
        }
    }
}
