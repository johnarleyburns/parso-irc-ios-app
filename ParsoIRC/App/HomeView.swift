import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    @State private var searchText = ""
    @State private var showingAddServer = false
    @State private var showingAddChannel = false
    @State private var selectedServer: Server?
    @State private var expandedServers: Set<String> = []
    
    var body: some View {
        NavigationStack {
            List {
                if !connectedServers.isEmpty {
                    Section("Connected Servers") {
                        ForEach(connectedServers) { server in
                            ServerHomeCell(
                                server: server,
                                isExpanded: expandedServers.contains(server.id),
                                onTap: {
                                    withAnimation {
                                        if expandedServers.contains(server.id) {
                                            expandedServers.remove(server.id)
                                        } else {
                                            expandedServers.insert(server.id)
                                        }
                                    }
                                },
                                onChannelTap: { channel in
                                    appState.navigateToChannel(serverId: server.id, channelName: channel.name)
                                }
                            )
                        }
                    }
                }
                
                if !disconnectedServers.isEmpty {
                    Section("Other Servers") {
                        ForEach(disconnectedServers) { server in
                            ServerHomeCell(
                                server: server,
                                isExpanded: false,
                                onTap: {
                                    selectedServer = server
                                },
                                onChannelTap: { channel in
                                    appState.navigateToChannel(serverId: server.id, channelName: channel.name)
                                }
                            )
                        }
                    }
                }
                
                Section {
                    Button {
                        showingAddServer = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color.theme.sentBubble)
                            Text("Add Server")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Parso IRC")
            .searchable(text: $searchText, prompt: "Search channels")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(Color.theme.sentBubble)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                AddServerSheet()
            }
            .sheet(item: $selectedServer) { server in
                QuickConnectSheet(server: server, isFirstTime: false)
            }
        }
    }
    
    private var connectedServers: [Server] {
        appState.servers.filter { ircManager.isConnected(serverId: $0.id) }
    }
    
    private var disconnectedServers: [Server] {
        appState.servers.filter { !ircManager.isConnected(serverId: $0.id) }
    }
}

struct ServerHomeCell: View {
    let server: Server
    let isExpanded: Bool
    let onTap: () -> Void
    let onChannelTap: (Channel) -> Void
    
    @State private var connectionState: ConnectionState = .disconnected
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 40, height: 40)
                    
                    Text(String(server.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading) {
                    Text(server.name)
                        .font(.headline)
                    
                    Text(server.host)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            if isExpanded && !server.channels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(server.channels) { channel in
                        Button {
                            onChannelTap(channel)
                        } label: {
                            HStack {
                                Image(systemName: "number")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(channel.name)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .padding(.leading, 20)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch connectionState {
        case .connected:
            return Color.theme.online
        case .connecting:
            return Color.theme.away
        case .reconnecting:
            return Color.theme.away
        default:
            return Color.theme.offline
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(IRCClientManager.shared)
}
