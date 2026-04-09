import SwiftUI
import UIKit

struct NickColorGenerator {
    private static let colors: [Color] = [
        Color(hex: "FF6B6B"),
        Color(hex: "4ECDC4"),
        Color(hex: "45B7D1"),
        Color(hex: "96CEB4"),
        Color(hex: "FFEAA7"),
        Color(hex: "DDA0DD"),
        Color(hex: "98D8C8"),
        Color(hex: "F7DC6F"),
        Color(hex: "BB8FCE"),
        Color(hex: "85C1E9"),
        Color(hex: "F8B500"),
        Color(hex: "00CED1"),
        Color(hex: "FF7256"),
        Color(hex: "DA70D6"),
        Color(hex: "20B2AA"),
        Color(hex: "FFA07A")
    ]
    
    static func color(for nick: String) -> Color {
        let hash = abs(nick.hashValue)
        let index = hash % colors.count
        return colors[index]
    }
    
    static func uiColor(for nick: String) -> UIColor {
        color(for: nick).uiColor()
    }
}

extension Color {
    func uiColor() -> UIColor {
        let components = NSColor(self).cgColor.components ?? [0, 0, 0, 1]
        return UIColor(red: components[0], green: components[1], blue: components[2], alpha: components.count > 3 ? components[3] : 1)
    }
}