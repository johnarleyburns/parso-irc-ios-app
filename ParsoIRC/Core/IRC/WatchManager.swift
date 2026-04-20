import Foundation
import BackgroundTasks
#if canImport(Combine)
import Combine
#endif

struct WatchSettings: Codable, Equatable {
    var pollIntervalMinutes: Int
    var notificationsEnabled: Bool
    var debounceSeconds: Int
    var showPreviewInNotification: Bool
    
    static let `default` = WatchSettings(
        pollIntervalMinutes: 5,
        notificationsEnabled: true,
        debounceSeconds: 60,
        showPreviewInNotification: true
    )
}

@MainActor
class WatchManager: ObservableObject {
    static let shared = WatchManager()

    static let backgroundTaskIdentifier = "com.parso.irc.refresh"
    
    @Published var settings: WatchSettings = .default
    @Published var lastNotificationSent: Date?
    @Published var isBackgroundTaskScheduled = false
    
    private let userDefaultsKey = "watch_settings"
    private let lastNotificationKey = "last_notification_sent"
    
    private init() {
        loadSettings()
    }
    
    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            settings = decoded
        }
        
        if let timestamp = UserDefaults.standard.object(forKey: lastNotificationKey) as? Date {
            lastNotificationSent = timestamp
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    func updatePollInterval(_ minutes: Int) {
        settings.pollIntervalMinutes = max(1, min(5, minutes))
        saveSettings()
    }
    
    func toggleNotifications(_ enabled: Bool) {
        settings.notificationsEnabled = enabled
        saveSettings()
    }
    
    func togglePreview(_ enabled: Bool) {
        settings.showPreviewInNotification = enabled
        saveSettings()
    }
    
    func recordNotificationSent() {
        lastNotificationSent = Date()
        UserDefaults.standard.set(lastNotificationSent, forKey: lastNotificationKey)
    }
    
    func canSendNotification() -> Bool {
        guard settings.notificationsEnabled else { return false }
        
        guard let lastSent = lastNotificationSent else { return true }
        
        return Date().timeIntervalSince(lastSent) >= Double(settings.debounceSeconds)
    }
    
    /// Schedules the next background app-refresh task at the configured poll interval.
    nonisolated func scheduleNextBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: WatchManager.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(
            (UserDefaults.standard.object(forKey: "watch_settings")
                .flatMap { try? JSONDecoder().decode(WatchSettings.self, from: $0 as! Data) }
                ?? WatchSettings.default
            ).pollIntervalMinutes * 60
        ))
        try? BGTaskScheduler.shared.submit(request)
        Task { @MainActor in self.isBackgroundTaskScheduled = true }
    }
}