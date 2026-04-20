import SwiftUI

/// A single collapsible server section header in the sidebar.
/// Shows the server name, live connection-state dot, tappable nick subtitle,
/// and an options menu.
struct ServerRowView: View {
    let server: Server
    @Binding var isExpanded: Bool

    @EnvironmentObject private var ircManager: IRCClientManager

    @State private var showEditSheet = false
    @State private var showNickSheet = false
    @State private var showDisconnectConfirm = false
    @State private var showDeleteConfirm = false

    var onServerUpdated: (() -> Void)?

    private var connectionState: ConnectionState {
        ircManager.connectionState(for: server.id)
    }

    private var currentNick: String {
        ircManager.currentNicknames[server.id] ?? server.nickname
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Channels are rendered by the parent (ServerSidebarView)
        } label: {
            HStack(spacing: 10) {
                ConnectionDot(state: connectionState)

                // Server name + nick subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !currentNick.isEmpty {
                        Button {
                            showNickSheet = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                Text(currentNick)
                                    .font(.caption)
                            }
                            .foregroundStyle(
                                connectionState == .connected
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

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
        .sheet(isPresented: $showNickSheet, onDismiss: onServerUpdated) {
            NickIdentitySheet(server: server)
                .environmentObject(ircManager)
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
            showNickSheet = true
        } label: {
            Label("Change Nick…", systemImage: "person.badge.key")
        }

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isAnimating && !reduceMotion {
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
        .onAppear { pulse = isAnimating && !reduceMotion }
        .onChange(of: state) { _, new in
            pulse = (new == .connecting || new == .reconnecting) && !reduceMotion
        }
    }
}

#Preview {
    List {
        ServerRowView(
            server: Server.defaultNetworks[0],
            isExpanded: .constant(true)
        )
        .environmentObject(IRCClientManager.shared)
    }
}
