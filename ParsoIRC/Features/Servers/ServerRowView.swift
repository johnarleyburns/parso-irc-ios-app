import SwiftUI

/// A single collapsible server section in the sidebar.
///
/// Shows the server name with a live connection-state indicator dot,
/// an options menu (⋯), and the list of joined channels underneath
/// when expanded.
struct ServerRowView: View {
    let server: Server
    @Binding var selectedChannelId: String?
    @Binding var isExpanded: Bool

    @EnvironmentObject private var ircManager: IRCClientManager

    @State private var showEditSheet = false
    @State private var showDisconnectConfirm = false
    @State private var showDeleteConfirm = false

    // Callback so the sidebar can reload its list after edit/delete
    var onServerUpdated: (() -> Void)?

    private var connectionState: ConnectionState {
        ircManager.connectionState(for: server.id)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Channels are rendered by the parent (ServerSidebarView) so they
            // appear indented as list rows — we just provide the header here.
        } label: {
            HStack(spacing: 10) {
                // Status dot
                ConnectionDot(state: connectionState)

                // Server name
                Text(server.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Options menu
                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuOrder(.fixed)
            }
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $showEditSheet, onDismiss: onServerUpdated) {
            AddServerSheet(existingServer: server) { _ in }
                .environmentObject(AppState.shared)
        }
        .confirmationDialog(
            "Disconnect from \(server.name)?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                ircManager.disconnect(from: server.id)
            }
        }
        .confirmationDialog(
            "Remove \(server.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Server", role: .destructive) {
                ircManager.disconnect(from: server.id)
                try? DatabaseManager.shared.deleteServer(id: server.id)
                onServerUpdated?()
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if connectionState == .connected || connectionState == .connecting {
            Button {
                showDisconnectConfirm = true
            } label: {
                Label("Disconnect", systemImage: "wifi.slash")
            }
        } else {
            Button {
                Task { try? await ircManager.connect(to: server) }
            } label: {
                Label("Connect", systemImage: "wifi")
            }
        }

        Divider()

        Button {
            showEditSheet = true
        } label: {
            Label("Edit Server", systemImage: "pencil")
        }

        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Remove Server", systemImage: "trash")
        }
    }
}

// MARK: - Connection state indicator dot

struct ConnectionDot: View {
    let state: ConnectionState

    private var color: Color {
        switch state {
        case .connected:    return Color(.systemGreen)
        case .connecting:   return Color(.systemYellow)
        case .reconnecting: return Color(.systemOrange)
        case .failed:       return Color(.systemRed)
        case .disconnected: return Color(.systemGray3)
        }
    }

    private var isAnimating: Bool {
        state == .connecting || state == .reconnecting
    }

    @State private var pulse = false

    var body: some View {
        ZStack {
            if isAnimating {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.6 : 1.0)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear { pulse = isAnimating }
        .onChange(of: state) { _, new in pulse = new == .connecting || new == .reconnecting }
    }
}

#Preview {
    List {
        ServerRowView(
            server: Server.defaultNetworks[0],
            selectedChannelId: .constant(nil),
            isExpanded: .constant(true)
        )
        .environmentObject(IRCClientManager.shared)
    }
}
