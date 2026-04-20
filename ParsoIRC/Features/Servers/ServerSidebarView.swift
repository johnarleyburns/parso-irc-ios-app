import SwiftUI

/// Left-column sidebar that shows all saved servers and their joined channels,
/// plus a Direct Messages section below.
///
/// Structure:
/// ```
/// ┌──────────────────────────┐
/// │  Parso IRC          ⚙   │  ← nav title + settings gear
/// ├──────────────────────────┤
/// │ ● Libera.Chat       ⋯   │  ← ServerRowView (disclosure header)
/// │   #linux            3   │  ← ChannelRowView
/// │   #rust                 │
/// │   + Join a channel      │
/// ├──────────────────────────┤
/// │ Direct Messages         │  ← DM section (when non-empty)
/// │   alice                 │
/// ├──────────────────────────┤
/// │  + Add Server           │  ← footer button
/// └──────────────────────────┘
/// ```
struct ServerSidebarView: View {
    @Binding var selectedServerId: String?
    @Binding var selectedChannelId: String?

    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState

    @State private var servers: [Server] = []
    @State private var expandedServers: Set<String> = []
    @StateObject private var conversationsVM = ConversationsViewModel(ircManager: IRCClientManager.shared)

    // Sheet state
    @State private var showAddServer = false
    @State private var showSettings = false
    @State private var channelBrowserServerId: String? = nil

    var body: some View {
        List {
            ForEach(servers) { server in
                serverSection(for: server)
            }

            // Direct Messages section
            if !conversationsVM.conversations.isEmpty {
                Section("Direct Messages") {
                    ForEach(conversationsVM.conversations) { dm in
                        dmRow(dm)
                    }
                    .onDelete { indices in
                        indices.forEach { conversationsVM.deleteConversation(conversationsVM.conversations[$0]) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Parso IRC")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
        .safeAreaInset(edge: .bottom) {
            addServerFooter
        }
        .sheet(isPresented: $showAddServer, onDismiss: reloadServers) {
            AddServerSheet(existingServer: nil) { newServer in
                // Auto-connect when added
                Task { try? await ircManager.connect(to: newServer) }
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(ircManager)
        }
        .onAppear(perform: reloadAndConnect)
        // Refresh when IRCClientManager publishes state changes
        .onChange(of: ircManager.connectionStates) { _, _ in
            reloadServers()
        }
    }

    // MARK: - Server section

    @ViewBuilder
    private func serverSection(for server: Server) -> some View {
        Section {
            // Server header row (disclosure toggle + options menu)
            ServerRowView(
                server: server,
                selectedChannelId: $selectedChannelId,
                isExpanded: Binding(
                    get: { expandedServers.contains(server.id) },
                    set: { expanded in
                        if expanded { expandedServers.insert(server.id) }
                        else { expandedServers.remove(server.id) }
                    }
                ),
                onServerUpdated: reloadServers
            )
            .environmentObject(ircManager)

            // Channel rows (only when expanded)
            if expandedServers.contains(server.id) {
                ForEach(server.channels) { channel in
                    ChannelRowView(
                        channel: channel,
                        serverId: server.id,
                        onSelect: { sid, cid in
                            // Set both atomically so iPhone NavigationSplitView
                            // navigates to the detail column in a single update cycle.
                            selectedServerId = sid
                            selectedChannelId = cid
                        },
                        onLeave: reloadServers
                    )
                    .environmentObject(ircManager)
                    .environmentObject(appState)
                }
                .onMove { indices, dest in
                    reorderChannels(for: server, from: indices, to: dest)
                }

                // Join a channel button
                joinChannelRow(server: server)
            }
        }
    }

    // MARK: - "Join a channel" row

    private func joinChannelRow(server: Server) -> some View {
        Button {
            channelBrowserServerId = server.id
        } label: {
            Label("Join a channel", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .listRowBackground(Color.clear)
        .sheet(
            isPresented: Binding(
                get: { channelBrowserServerId == server.id },
                set: { if !$0 { channelBrowserServerId = nil } }
            ),
            onDismiss: reloadServers
        ) {
            ChannelBrowserSheet(server: server, onJoined: reloadServers)
                .environmentObject(ircManager)
        }
    }

    // MARK: - Footer

    private var addServerFooter: some View {
        Button {
            showAddServer = true
        } label: {
            Label("Add Server", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial)
    }

    // MARK: - DM row

    private func dmRow(_ dm: Channel) -> some View {
        let isSelected = appState.selectedChannelId == dm.id
        return Button {
            selectedServerId = dm.serverId
            selectedChannelId = dm.id
        } label: {
            HStack(spacing: 10) {
                AvatarView(nick: dm.name, size: 28)
                Text(dm.name)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                let unread = ircManager.unreadCounts[dm.id] ?? 0
                if unread > 0 {
                    Text(unread < 100 ? "\(unread)" : "99+")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    // MARK: - Data helpers

    private func reloadServers() {
        let loaded = (try? DatabaseManager.shared.fetchServers()) ?? []
        servers = loaded.map { server in
            var s = server
            s.isConnected = ircManager.connectionState(for: s.id) == .connected
            return s
        }
        for server in servers {
            if server.isConnected {
                expandedServers.insert(server.id)
            }
        }
        conversationsVM.loadConversations()
    }

    private func reloadAndConnect() {
        reloadServers()
        Task {
            let loaded = (try? DatabaseManager.shared.fetchServers()) ?? []
            let lastConnected = Set(ircManager.lastConnectedServerIds)
            let explicit = ircManager.explicitlyDisconnectedServerIds
            for server in loaded {
                let state = ircManager.connectionState(for: server.id)
                guard state == .disconnected else { continue }
                // Connect if: autoConnect flag is set, OR was connected last session
                // AND the user has not explicitly disconnected since then.
                let shouldConnect = server.autoConnect
                    || (lastConnected.contains(server.id) && !explicit.contains(server.id))
                if shouldConnect {
                    try? await ircManager.connect(to: server)
                }
            }
        }
    }

    private func reorderChannels(for server: Server, from indices: IndexSet, to dest: Int) {
        var channels = server.channels
        channels.move(fromOffsets: indices, toOffset: dest)
        var updated = server
        updated.channels = channels
        try? DatabaseManager.shared.saveServer(updated)
        reloadServers()
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitView {
        ServerSidebarView(
            selectedServerId: .constant(nil),
            selectedChannelId: .constant(nil)
        )
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState.shared)
    } detail: {
        Text("Select a channel")
    }
}
