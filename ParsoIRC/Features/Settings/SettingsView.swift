import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("showTimestamps") private var showTimestamps = true
    @AppStorage("showJoinPart") private var showJoinPart = true
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("maxHistory") private var maxHistory = 1000
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var watchManager: WatchManager
    @State private var showingNotificationPermissionAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    
                    Toggle("Show Timestamps", isOn: $showTimestamps)
                }
                
                Section("Chat") {
                    Toggle("Show Join/Part Messages", isOn: $showJoinPart)
                    
                    Picker("History per Channel", selection: $maxHistory) {
                        Text("100 messages").tag(100)
                        Text("500 messages").tag(500)
                        Text("1000 messages").tag(1000)
                        Text("5000 messages").tag(5000)
                    }
                }
                
                Section("Background Watch") {
                    Toggle("Enable Notifications", isOn: Binding(
                        get: { watchManager.settings.notificationsEnabled },
                        set: { newValue in
                            if newValue {
                                Task {
                                    let granted = await NotificationManager.shared.requestAuthorization()
                                    if !granted {
                                        showingNotificationPermissionAlert = true
                                    } else {
                                        watchManager.toggleNotifications(true)
                                    }
                                }
                            } else {
                                watchManager.toggleNotifications(false)
                            }
                        }
                    ))
                    
                    if watchManager.settings.notificationsEnabled {
                        Picker("Check Interval", selection: Binding(
                            get: { watchManager.settings.pollIntervalMinutes },
                            set: { watchManager.updatePollInterval($0) }
                        )) {
                            Text("1 minute").tag(1)
                            Text("2 minutes").tag(2)
                            Text("3 minutes").tag(3)
                            Text("4 minutes").tag(4)
                            Text("5 minutes").tag(5)
                        }
                        
                        Toggle("Show Message Preview", isOn: Binding(
                            get: { watchManager.settings.showPreviewInNotification },
                            set: { watchManager.togglePreview($0) }
                        ))
                        .help("Show sender and message preview in notifications")
                        
                        Button {
                            Task {
                                await NotificationManager.shared.sendTestNotification()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge")
                                Text("Test Notification")
                            }
                        }
                    }
                }
                
                Section("Connection") {
                    Toggle("Auto-reconnect", isOn: $autoReconnect)
                }
                
                Section("Account") {
                    HStack {
                        Text("Current Nickname")
                        Spacer()
                        Text(appState.currentNick.isEmpty ? "Not connected" : appState.currentNick)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Source Code", destination: URL(string: "https://github.com/jburns/parso-irc-ios-app")!)
                    
                    Link("Report an Issue", destination: URL(string: "https://github.com/jburns/parso-irc-ios-app/issues")!)
                }
                
                Section {
                    Button(role: .destructive) {
                        IRCClientManager.shared.disconnectAll()
                    } label: {
                        Text("Disconnect from all servers")
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Notifications Disabled", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable notifications in Settings to receive alerts for watched channels.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}