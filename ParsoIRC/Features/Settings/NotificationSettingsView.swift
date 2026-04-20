import SwiftUI

/// Notification settings — wraps `WatchManager` + `NotificationManager`.
struct NotificationSettingsView: View {

    @StateObject private var watchManager = WatchManager.shared
    @State private var isAuthorized = false
    @State private var showingPermissionAlert = false

    var body: some View {
        Form {
            // Authorization status banner
            if !isAuthorized {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications Disabled")
                                .font(.headline)
                            Text("Parso IRC needs permission to send notifications.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Enable") {
                            Task { await requestPermission() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Master toggle
            Section {
                Toggle("Enable Notifications", isOn: Binding(
                    get: { watchManager.settings.notificationsEnabled },
                    set: { watchManager.toggleNotifications($0) }
                ))
                .tint(.accentColor)
            } footer: {
                Text("Receive notifications for new messages in watched channels.")
                    .font(.caption)
            }

            if watchManager.settings.notificationsEnabled {
                // Preview
                Section {
                    Toggle("Show Message Preview", isOn: Binding(
                        get: { watchManager.settings.showPreviewInNotification },
                        set: { watchManager.togglePreview($0) }
                    ))
                    .tint(.accentColor)
                } footer: {
                    Text("When enabled, notification banners show the sender and message text.")
                        .font(.caption)
                }

                // Poll interval
                Section {
                    Stepper(
                        "Check every \(watchManager.settings.pollIntervalMinutes) min",
                        value: Binding(
                            get: { watchManager.settings.pollIntervalMinutes },
                            set: { watchManager.updatePollInterval($0) }
                        ),
                        in: 1...5
                    )
                } header: {
                    Text("Background Check Interval")
                } footer: {
                    Text("How often Parso IRC checks for new messages while in the background (1–5 minutes).")
                        .font(.caption)
                }

                // Test notification
                Section {
                    Button("Send Test Notification") {
                        Task { await NotificationManager.shared.sendTestNotification() }
                    }
                    .foregroundStyle(Color.accentColor)
                }

                // Last notification
                if let last = watchManager.lastNotificationSent {
                    Section {
                        LabeledContent("Last Sent", value: last.formattedDate() + " " + last.formattedTime())
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkPermission() }
    }

    private func checkPermission() async {
        await NotificationManager.shared.checkAuthorizationStatus()
        isAuthorized = NotificationManager.shared.isAuthorized
    }

    private func requestPermission() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        isAuthorized = granted
        if !granted { showingPermissionAlert = true }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
