import SwiftUI

/// A single channel row in the sidebar's server disclosure group.
///
/// Shows the channel name, an unread-count badge (when > 0), and a
/// mute indicator.  Provides swipe-to-leave and a long-press context menu.
struct ChannelRowView: View {
    let channel: Channel
    let serverId: String

    /// Called when the user taps this row. Provides (serverId, channelId) so
    /// the parent can set both selection bindings atomically — required for
    /// iPhone NavigationSplitView to navigate to the detail column.
    var onSelect: ((String, String) -> Void)?

    // Callback so the sidebar can refresh after leave
    var onLeave: (() -> Void)?

    @EnvironmentObject private var ircManager: IRCClientManager
    @State private var showLeaveConfirm = false

    // Live unread count from IRCClientManager (always up-to-date)
    private var unreadCount: Int { ircManager.unreadCounts[channel.id] ?? 0 }
    // Selection is derived from IRCClientManager's published unreadCounts observation
    // — the parent controls the actual selection state, so we read AppState instead.
    @EnvironmentObject private var appState: AppState
    private var isSelected: Bool { appState.selectedChannelId == channel.id }

    var body: some View {
        Button {
            onSelect?(serverId, channel.id)
            // Persist last-active channel
            try? DatabaseManager.shared.updateLastActiveChannel(
                serverId: serverId,
                channelName: channel.name
            )
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
            ? Color.accentColor.opacity(0.15)
            : Color.clear
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showLeaveConfirm = true
            } label: {
                Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Button {
                toggleMute()
            } label: {
                Label(
                    channel.isMuted ? "Unmute" : "Mute",
                    systemImage: channel.isMuted ? "bell" : "bell.slash"
                )
            }
            .tint(.indigo)
        }
        .contextMenu {
            contextMenuContent
        }
        .confirmationDialog(
            "Leave \(channel.name)?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Channel", role: .destructive) { leaveChannel() }
        } message: {
            Text("You will stop receiving messages from this channel.")
        }
    }

    // MARK: - Row label

    private var rowLabel: some View {
        HStack(spacing: 8) {
            // Channel name
            Text(channel.name)
                .font(.subheadline)
                .fontWeight(unreadCount > 0 ? .semibold : .regular)
                .foregroundStyle(unreadCount > 0 ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            // Mute icon
            if channel.isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Unread badge
            if unreadCount > 0 && !channel.isMuted {
                Text(unreadCount < 100 ? "\(unreadCount)" : "99+")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onSelect?(serverId, channel.id)
        } label: {
            Label("Open", systemImage: "bubble.left")
        }

        Divider()

        Button {
            toggleMute()
        } label: {
            Label(
                channel.isMuted ? "Unmute Channel" : "Mute Channel",
                systemImage: channel.isMuted ? "bell" : "bell.slash"
            )
        }

        Button {
            markAsRead()
        } label: {
            Label("Mark as Read", systemImage: "checkmark.circle")
        }

        Button {
            UIPasteboard.general.string = channel.name
        } label: {
            Label("Copy Channel Name", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            showLeaveConfirm = true
        } label: {
            Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    // MARK: - Actions

    private func leaveChannel() {
        Task {
            guard let client = ircManager.getClient(for: serverId) else { return }
            try? await client.leave(channel: channel.name)
            // Remove from DB
            // (In Phase 2 ChannelViewModel will handle the PART echo;
            //  for now we eagerly remove from the sidebar.)
            onLeave?()
        }
    }

    private func toggleMute() {
        var updated = channel
        updated.isMuted.toggle()
        try? DatabaseManager.shared.saveChannel(updated, serverId: serverId)
        onLeave?()   // triggers sidebar refresh
    }

    private func markAsRead() {
        ircManager.clearUnread(channelId: channel.id)
    }
}

#Preview {
    List {
        ChannelRowView(
            channel: Channel(name: "#linux"),
            serverId: "preview"
        )
        ChannelRowView(
            channel: Channel(name: "#muted", isMuted: true),
            serverId: "preview"
        )
    }
    .environmentObject(IRCClientManager.shared)
    .environmentObject(AppState.shared)
}
