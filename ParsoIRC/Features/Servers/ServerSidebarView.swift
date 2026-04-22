import SwiftUI

/// Left-column sidebar (root of the NavigationStack) that shows saved servers
/// and their joined channels.
struct ServerSidebarView: View {
    @Binding var navPath: [NavDestination]
    var onSelectChannel: (String, String, String, Bool, String?) -> Void

    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState

    @State private var servers: [Server] = []
    @State private var expandedServers: Set<String> = []
    @StateObject private var conversationsVM = ConversationsViewModel(
        ircManager: IRCClientManager.shared)

    // Sheet state
    @State private var showAddServer = false
    @State private var showSettings = false
    @State private var channelBrowserServerId: String? = nil
    @State private var newMessageServerId: String? = nil
    @State private var newMessageNick: String = ""

    var body: some View {
        List {
            ForEach(servers) { server in
                serverSection(for: server)
            }
        }
        .listStyle(.insetGrouped)
            .navigationTitle("Parso IRC")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) { addServerFooter }
            .sheet(isPresented: $showAddServer, onDismiss: reloadServers) {
                AddServerSheet(existingServer: nil) { newServer in
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
            .onChange(of: ircManager.connectionStates) { _, _ in reloadServers() }
            .onChange(of: ircManager.currentNicknames) { _, _ in reloadServers() }
            .onChange(of: ircManager.dmChannelIds) { _, _ in reloadServers() }
            .onChange(of: ircManager.channelMembershipVersion) { _, _ in reloadServers() }
            .alert("New Direct Message", isPresented: Binding(
                get: { newMessageServerId != nil },
                set: { if !$0 { newMessageServerId = nil; newMessageNick = "" } }
            )) {
                TextField("Nickname", text: $newMessageNick)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Open") {
                    guard let sid = newMessageServerId,
                          !newMessageNick.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let nick = newMessageNick.trimmingCharacters(in: .whitespaces)
                    let dm = ircManager.openOrCreateDM(with: nick, serverId: sid)
                    newMessageServerId = nil
                    newMessageNick = ""
                    onSelectChannel(sid, dm.id, nick, true, nick)
                }
                Button("Cancel", role: .cancel) {
                    newMessageServerId = nil
                    newMessageNick = ""
                }
            } message: {
                Text("Enter the nickname you want to message.")
            }
    }

    // MARK: - Server section

    @ViewBuilder
    private func serverSection(for server: Server) -> some View {
        Section {
            ServerRowView(
                server: server,
                isExpanded: Binding(
                    get: { expandedServers.contains(server.id) },
                    set: { expanded in
                        if expanded {
                            expandedServers.insert(server.id)
                        } else {
                            expandedServers.remove(server.id)
                        }
                    }
                ),
                onServerUpdated: reloadServers
            )
            .environmentObject(ircManager)

            if expandedServers.contains(server.id) {
                ForEach(server.channels.filter { $0.joinedAt != nil }) { channel in
                    ChannelRowView(
                        channel: channel,
                        serverId: server.id,
                        onSelect: { sid, cid in
                            onSelectChannel(sid, cid, channel.name, false, nil)
                        },
                        onLeave: reloadServers
                    )
                    .environmentObject(ircManager)
                    .environmentObject(appState)
                }
                .onMove { indices, dest in
                    reorderChannels(for: server, from: indices, to: dest)
                }

                let dms = conversationsVM.conversations.filter {
                    $0.serverId == server.id
                }
                if !dms.isEmpty {
                    dmSeparatorRow
                    ForEach(dms) { dm in
                        dmRow(dm)
                    }
                    .onDelete { indices in
                        indices.forEach {
                            conversationsVM.deleteConversation(dms[$0])
                        }
                        reloadServers()
                    }
                }

                joinChannelRow(server: server)
                newMessageRow(server: server)
            }
        }
    }

    // MARK: - DM section separator

    private var dmSeparatorRow: some View {
        HStack {
            VStack { Divider() }
            Text("Messages")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize()
            VStack { Divider() }
        }
        .listRowBackground(Color.clear)
        .padding(.vertical, 2)
    }

    // MARK: - DM row

    private func dmRow(_ dm: Channel) -> some View {
        let isActive = appState.selectedChannelId == dm.id
        let unread = ircManager.unreadCounts[dm.id] ?? 0
        return Button {
            onSelectChannel(dm.serverId, dm.id, dm.name, true, dm.name)
        } label: {
            HStack(spacing: 10) {
                AvatarView(nick: dm.name, size: 26)

                Text(dm.name)
                    .font(.subheadline)
                    .fontWeight(unread > 0 ? .semibold : .regular)
                    .foregroundStyle(unread > 0 ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                if unread > 0 {
                    Text(unread < 100 ? "\(unread)" : "99+")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .accessibilityLabel("\(unread) unread messages")
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
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
            ChannelBrowserSheet(server: server, onJoined: { name in
                reloadServers()
                if let ch = (try? DatabaseManager.shared.fetchChannels(forServer: server.id))?
                    .first(where: { $0.name == name }) {
                    onSelectChannel(server.id, ch.id, name, false, nil)
                }
            })
            .environmentObject(ircManager)
        }
    }

    // MARK: - "New Message" row

    private func newMessageRow(server: Server) -> some View {
        Button {
            newMessageNick = ""
            newMessageServerId = server.id
        } label: {
            Label("New Message", systemImage: "plus.message")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Footer

    private var addServerFooter: some View {
        Button { showAddServer = true } label: {
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

    // MARK: - Data helpers

    private func reloadServers() {
        let loaded = (try? DatabaseManager.shared.fetchServers()) ?? []
        servers = loaded.map { server in
            var s = server
            s.isConnected = ircManager.connectionState(for: s.id) == .connected
            return s
        }
        for server in servers where server.isConnected {
            expandedServers.insert(server.id)
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
    NavigationStack {
        ServerSidebarView(
            navPath: .constant([]),
            onSelectChannel: { _, _, _, _, _ in }
        )
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState.shared)
    }
}
