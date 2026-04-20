import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private let categoryIdentifier = "WATCH_CHANNEL"
    private let viewAction = "VIEW_CHANNEL"
    private let dismissAction = "DISMISS"
    private let snoozeAction = "SNOOZE"
    
    override private init() {
        super.init()
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            
            if granted {
                await setupNotificationCategories()
            }
            
            isAuthorized = granted
            return granted
        } catch {
            print("Notification authorization failed: \(error)")
            return false
        }
    }
    
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    private func setupNotificationCategories() async {
        let viewAction = UNNotificationAction(
            identifier: self.viewAction,
            title: "View",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: self.dismissAction,
            title: "Dismiss",
            options: [.destructive]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: self.snoozeAction,
            title: "Snooze 1h",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [viewAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    func sendWatchNotification(channel: Channel, message: Message) async {
        guard WatchManager.shared.canSendNotification() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "\(channel.name)"
        
        if WatchManager.shared.settings.showPreviewInNotification {
            content.body = "\(message.sender): \(message.content)"
        } else {
            content.body = "New activity in channel"
        }
        
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "channelId": channel.id,
            "serverId": channel.serverId,
            "channelName": channel.name
        ]
        
        let request = UNNotificationRequest(
            identifier: "watch-\(channel.id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            WatchManager.shared.recordNotificationSent()
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    /// Fires when the background refresh detects the user's nick was mentioned
    /// in a watched channel while the app was not in the foreground.
    func sendMentionNotification(channel: Channel, message: Message, count: Int) async {
        guard isAuthorized else { return }
        guard WatchManager.shared.canSendNotification() else { return }

        let content = UNMutableNotificationContent()
        content.title = count == 1
            ? "Mentioned in \(channel.name)"
            : "\(count) mentions in \(channel.name)"

        if WatchManager.shared.settings.showPreviewInNotification {
            content.body = "\(message.sender): \(IRCTextFormatter.stripped(message.content))"
        } else {
            content.body = "You were mentioned while away"
        }

        content.sound = .default
        content.badge = NSNumber(value: count)
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "channelId":   channel.id,
            "serverId":    channel.serverId,
            "channelName": channel.name
        ]

        let request = UNNotificationRequest(
            identifier: "mention-\(channel.id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            WatchManager.shared.recordNotificationSent()
        } catch {
            print("Failed to send mention notification: \(error)")
        }
    }

    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "Parso IRC notifications are working!"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        _ = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case viewAction, UNNotificationDefaultActionIdentifier:
            // App will open - handle in scene delegate
            break
        case snoozeAction:
            // Re-schedule the same notification 1 hour from now
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
            let snoozed = UNNotificationRequest(
                identifier: "snoozed-\(response.notification.request.identifier)",
                content: response.notification.request.content,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(snoozed)
        case dismissAction:
            break
        default:
            break
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        _ = await MainActor.run {
            Task {
                await handleNotificationResponse(response)
            }
        }
    }
}