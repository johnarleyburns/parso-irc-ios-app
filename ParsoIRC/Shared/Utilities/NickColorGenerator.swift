import SwiftUI
import UIKit

struct NickColorGenerator {
    // Colors chosen for sufficient contrast on both light (E5E5EA) and dark (3A3A3C) bubbles
    private static let colors: [Color] = [
        Color(hex: "FF6B6B"),   // red
        Color(hex: "4ECDC4"),   // teal
        Color(hex: "45B7D1"),   // sky blue
        Color(hex: "DDA0DD"),   // plum
        Color(hex: "BB8FCE"),   // medium purple
        Color(hex: "85C1E9"),   // light blue
        Color(hex: "F8B500"),   // amber
        Color(hex: "00CED1"),   // dark turquoise
        Color(hex: "FF7256"),   // coral
        Color(hex: "DA70D6"),   // orchid
        Color(hex: "20B2AA"),   // light sea green
        Color(hex: "FFA07A"),   // light salmon
        Color(hex: "6495ED"),   // cornflower blue
        Color(hex: "BC8F8F"),   // rosy brown
        Color(hex: "3CB371"),   // medium sea green
        Color(hex: "CD853F"),   // peru
    ]
    
    /// Returns a stable, process-launch-invariant color for the given nick
    /// using a DJB2-style hash instead of Swift's non-deterministic `hashValue`.
    static func color(for nick: String) -> Color {
        let hash = nick.utf8.reduce(5381 as UInt) { ($0 &<< 5) &+ $0 &+ UInt($1) }
        return colors[Int(hash % UInt(colors.count))]
    }
    
    static func uiColor(for nick: String) -> UIColor {
        UIColor(color(for: nick))
    }
}

extension Color {
    func uiColor() -> UIColor {
        return UIColor(self)
    }
}
