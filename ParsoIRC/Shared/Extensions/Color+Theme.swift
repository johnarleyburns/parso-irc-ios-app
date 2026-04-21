import SwiftUI

extension Color {
    static let theme = ThemeColors()
}

struct ThemeColors {
    let primary = Color("AccentColor")
    /// Outgoing message bubble colour.
    /// Uses a UIColor dynamic provider so it shifts correctly in dark mode.
    /// Light mode: #0058D0 — contrast ratio 6.35:1 white text (WCAG AA ✓ and AAA ✓)
    /// Dark mode:  #409CFF — iOS system blue on dark, ~4.8:1 on dark backgrounds ✓
    var sentBubble: Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.251, green: 0.612, blue: 1.0,   alpha: 1)  // #409CFF dark  ~4.8:1
                : UIColor(red: 0.0,   green: 0.345, blue: 0.816, alpha: 1)  // #0058D0 light  6.35:1
        })
    }
    let receivedBubbleDark = Color(hex: "3A3A3C")
    let receivedBubbleLight = Color(hex: "E5E5EA")
    let actionBubble = Color(hex: "5856D6")
    let systemMessage = Color.secondary
    let online = Color(hex: "30D158")
    let away = Color(hex: "FF9F0A")
    let offline = Color.gray
    let error = Color(hex: "FF453A")
    
    var receivedBubble: Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(receivedBubbleDark) : UIColor(receivedBubbleLight)
        })
    }
    
    var inputBarBackground: Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(receivedBubbleDark) : UIColor(receivedBubbleLight)
        })
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}