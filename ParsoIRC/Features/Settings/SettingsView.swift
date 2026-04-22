import SwiftUI

/// Root settings screen.
///
/// Sections:
///   Servers          – list saved servers, tap to edit, swipe to delete
///   Identity         – global nick / realname
///   Appearance       – font size, message density
///   Notifications    – enable/style/preview/poll interval
///   Connection       – auto-reconnect toggle
///   Safety           – blocked users list, contact support
///   Demo Mode        – exit demo mode (only shown in demo mode)
///   Developer        – debug terminal
///   About            – version, licenses
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ircManager: IRCClientManager
    @Environment(\.dismiss) private var dismiss

    @State private var servers: [Server] = []
    @State private var showAddServer = false
    @State private var editingServer: Server? = nil
    @State private var showExitDemoAlert = false
    @State private var showDeleteAccountAlert = false

    var body: some View {
        NavigationStack {
            Form {
                serversSection
                identitySection
                appearanceSection
                notificationsSection
                connectionSection
                safetySection
                if appState.isDemoMode {
                    demoModeSection
                }
                accountSection
                developerSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { loadServers() }
        .sheet(isPresented: $showAddServer, onDismiss: loadServers) {
            AddServerSheet(existingServer: nil) { _ in }
                .environmentObject(appState)
        }
        .sheet(item: $editingServer, onDismiss: loadServers) { server in
            AddServerSheet(existingServer: server) { _ in }
                .environmentObject(appState)
        }
        .alert("Exit Demo Mode", isPresented: $showExitDemoAlert) {
            Button("Exit Demo", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    appState.resetAllUserData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all your local data and return you to the setup screen. Are you sure?")
        }
        .alert("Delete All Data?", isPresented: $showDeleteAccountAlert) {
            Button("Delete Everything", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    appState.resetAllUserData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all servers, messages, settings, and your account from this device and return you to the setup screen. This cannot be undone.")
        }
    }

    // MARK: - Servers section

    private var serversSection: some View {
        Section {
            ForEach(servers) { server in
                Button {
                    editingServer = server
                } label: {
                    HStack(spacing: 12) {
                        ConnectionDot(state: ircManager.connectionState(for: server.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("\(server.host):\(server.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        ircManager.disconnect(from: server.id)
                        try? DatabaseManager.shared.deleteServer(id: server.id)
                        loadServers()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    Button {
                        let state = ircManager.connectionState(for: server.id)
                        if state == .connected || state == .connecting {
                            ircManager.disconnect(from: server.id)
                        } else {
                            Task { try? await ircManager.connect(to: server) }
                        }
                    } label: {
                        let state = ircManager.connectionState(for: server.id)
                        let isConnected = state == .connected || state == .connecting
                        Label(isConnected ? "Disconnect" : "Connect",
                              systemImage: isConnected ? "wifi.slash" : "wifi")
                    }
                    .tint(.blue)
                }
            }

            Button {
                showAddServer = true
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            Text("Servers")
        }
    }

    // MARK: - Identity section

    private var identitySection: some View {
        Section {
            NavigationLink {
                IdentitySettingsView()
                    .environmentObject(appState)
            } label: {
                HStack {
                    Label("Identity", systemImage: "person.circle")
                    Spacer()
                    Text(appState.globalNickname.isEmpty ? "Not set" : appState.globalNickname)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Appearance section

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label("Appearance", systemImage: "textformat.size")
            }
        }
    }

    // MARK: - Notifications section

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
        }
    }

    // MARK: - Connection section

    private var connectionSection: some View {
        Section {
            NavigationLink {
                ConnectionSettingsView()
                    .environmentObject(ircManager)
            } label: {
                Label("Connection", systemImage: "network")
            }
        }
    }

    // MARK: - Safety section

    private var safetySection: some View {
        Section {
            NavigationLink {
                BlockedUsersView()
            } label: {
                Label("Blocked Users", systemImage: "person.fill.xmark")
            }

            Button {
                let subject = "Parso IRC Support"
                let encodedSubject = subject
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
                if let url = URL(string: "mailto:info@parso.guru?subject=\(encodedSubject)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Contact Support", systemImage: "envelope")
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            Text("Safety")
        }
    }

    // MARK: - Demo Mode section

    private var demoModeSection: some View {
        Section {
            Button(role: .destructive) {
                showExitDemoAlert = true
            } label: {
                Label("Exit Demo Mode", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Demo Mode")
        } footer: {
            Text("Exits the demo and returns to the setup screen. All local data will be deleted.")
        }
    }

    // MARK: - Account section (always visible)

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAccountAlert = true
            } label: {
                Label("Delete All Data & Account", systemImage: "person.crop.circle.badge.minus")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Permanently removes all servers, messages, and settings from this device and returns you to the setup screen.")
        }
    }

    // MARK: - Developer section

    @ViewBuilder
    private var developerSection: some View {
        #if DEBUG
        Section {
            NavigationLink("Debug Terminal") {
                DebugTerminalView()
                    .environmentObject(DebugLogManager.shared)
                    .environmentObject(ircManager)
            }
        } header: {
            Text("Developer")
        }
        #else
        EmptyView()
        #endif
    }

    // MARK: - About section

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Build") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                    .foregroundStyle(.secondary)
            }
            Link(destination: URL(string: "https://github.com/johnarleyburns/parso-irc-ios-app")!) {
                Label("Source on GitHub", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func loadServers() {
        servers = (try? DatabaseManager.shared.fetchServers()) ?? []
    }
}

// MARK: - Identity sub-screen

private struct IdentitySettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var nick: String = ""
    @State private var realName: String = ""

    var body: some View {
        Form {
            Section {
                TextField("Nickname", text: $nick)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: nick) { _, n in appState.globalNickname = n }
                TextField("Real Name", text: $realName)
                    .onChange(of: realName) { _, r in appState.globalRealName = r }
            } header: {
                Text("Global defaults (used when not overridden per-server)")
            } footer: {
                Text("You can override these on each server individually.")
                    .font(.caption)
            }
        }
        .navigationTitle("Identity")
        .onAppear {
            nick = appState.globalNickname
            realName = appState.globalRealName
        }
    }
}

// MARK: - Connection sub-screen

private struct ConnectionSettingsView: View {
    @EnvironmentObject private var ircManager: IRCClientManager
    @AppStorage("autoReconnect") private var autoReconnect = true

    var body: some View {
        Form {
            Section {
                Toggle("Auto-reconnect on disconnect", isOn: $autoReconnect)
                    .tint(.accentColor)
            } footer: {
                Text("Parso IRC will automatically attempt to reconnect using exponential backoff (up to 5 attempts).")
                    .font(.caption)
            }
        }
        .navigationTitle("Connection")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
        .environmentObject(IRCClientManager.shared)
}
