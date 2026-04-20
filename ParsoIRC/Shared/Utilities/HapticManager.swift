import SwiftUI
import UIKit

struct HapticManager {
    // Cached generators — created once, prepared before use to reduce latency
    private static let lightGenerator   = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator  = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator   = UIImpactFeedbackGenerator(style: .heavy)
    private static let notifyGenerator  = UINotificationFeedbackGenerator()
    private static let selectGenerator  = UISelectionFeedbackGenerator()

    static func lightImpact() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }
    
    static func mediumImpact() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }
    
    static func heavyImpact() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred()
    }
    
    static func successFeedback() {
        notifyGenerator.prepare()
        notifyGenerator.notificationOccurred(.success)
    }
    
    static func warningFeedback() {
        notifyGenerator.prepare()
        notifyGenerator.notificationOccurred(.warning)
    }
    
    static func errorFeedback() {
        notifyGenerator.prepare()
        notifyGenerator.notificationOccurred(.error)
    }
    
    static func selectionFeedback() {
        selectGenerator.prepare()
        selectGenerator.selectionChanged()
    }
}
