import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    @State private var showingAddServer = false
    @State private var serverToEdit: Server?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.servers) { server in
                    ServerCell(
                        server: server,
                        connectionState: ircManager.connectionStatesPublisher[server.id] ?? .disconnected
                    )
                    .accessibilityIdentifier("server-\(server.id)")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        connectToServer(server)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteServer(server)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            serverToEdit = server
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddServer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addServerButton")
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if appState.servers.contains(where: { ircManager.connectionStatesPublisher[$0.id] == .connected }) {
                        Button("Disconnect All") {
                            ircManager.disconnectAll()
                        }
                        .foregroundColor(.red)
                        .accessibilityIdentifier("disconnectAllButton")
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                AddServerSheet()
            }
            .sheet(item: $serverToEdit) { server in
                AddServerSheet(server: server)
            }
            .refreshable {
                await reconnectAllServers()
            }
        }
    }
    
    private func connectToServer(_ server: Server) {
        Task {
            do {
                try await ircManager.connect(to: server)
            } catch {
                print("Connection failed: \(error)")
            }
        }
    }
    
    private func deleteServer(_ server: Server) {
        ircManager.disconnect(from: server.id)
        
        Task {
            do {
                try DatabaseManager.shared.deleteServer(id: server.id)
                await MainActor.run {
                    appState.servers.removeAll { $0.id == server.id }
                }
            } catch {
                print("Failed to delete server: \(error)")
            }
        }
    }
    
    private func reconnectAllServers() async {
        for server in appState.servers where server.autoConnect {
            do {
                try await ircManager.connect(to: server)
            } catch {
                print("Failed to reconnect to \(server.name): \(error)")
            }
        }
    }
}

struct ServerCell: View {
    let server: Server
    let connectionState: ConnectionState
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(serverIconColor)
                    .frame(width: 44, height: 44)
                
                Text(String(server.name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(server.channels.count) channels")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var serverIconColor: Color {
        switch connectionState {
        case .connected:
            return Color.theme.online
        case .connecting, .reconnecting:
            return Color.theme.away
        case .failed:
            return Color.theme.error
        case .disconnected:
            return Color.theme.offline
        }
    }
    
    private var statusColor: Color {
        switch connectionState {
        case .connected:
            return Color.theme.online
        case .connecting, .reconnecting:
            return Color.theme.away
        case .failed:
            return Color.theme.error
        case .disconnected:
            return Color.theme.offline
        }
    }
    
    private var statusText: String {
        switch connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        case .disconnected:
            return "Disconnected"
        }
    }
}

#Preview {
    ServerListView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}