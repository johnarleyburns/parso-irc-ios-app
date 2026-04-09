import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("showTimestamps") private var showTimestamps = true
    @AppStorage("showJoinPart") private var showJoinPart = true
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("maxHistory") private var maxHistory = 1000
    
    @EnvironmentObject var appState: AppState
    
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
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}