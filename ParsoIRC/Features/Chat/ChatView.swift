import SwiftUI
import SafariServices

/// The main chat screen for a single channel or DM.
///
/// Layout:
/// ```
/// ┌─────────────────────────────────┐
/// │  ← #linux   "Topic text…"  👥 ⋯ │  ← NavigationBar
/// ├─────────────────────────────────┤
/// │                                 │
/// │        MessageListView          │
/// │                                 │
/// ├─────────────────────────────────┤
/// │  +  [Message #linux…]   [↑]    │  ← InputBarView
/// └─────────────────────────────────┘
/// ```
///
/// `ChatView` creates and owns a `ChannelViewModel` keyed on `serverId` +
/// `channelName`.  When either changes (e.g. the user switches channels from
/// the sidebar) SwiftUI recreates the view and therefore the view model,
/// which re-registers callbacks and re-loads history for the new channel.
struct ChatView: View {
    let serverId: String
    let channelName: String

    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: ChannelViewModel

    // Text pre-fill fed from nick-tap / mention
    @State private var prefillText: String = ""

    // Sheet state
    @State private var showMemberList = false
    @State private var showChannelMenu = false
    @State private var showTopicPopover = false
    @State private var showNickSheet = false
    @State private var tappedNick: String? = nil
    @State private var safariURL: URL? = nil

    init(serverId: String, channelName: String, ircManager: IRCClientManager) {
        self.serverId = serverId
        self.channelName = channelName
        // Init StateObject with the manager reference so ChannelViewModel can
        // call back into it.  Using _viewModel = StateObject(wrappedValue:) is
        // the correct way to pass dependencies to a @StateObject.
        _viewModel = StateObject(wrappedValue:
            ChannelViewModel(serverId: serverId, channelName: channelName, ircManager: ircManager)
        )
    }

    var body: some View {
        MessageListView(
            viewModel: viewModel,
            onTapNick: { nick in
                prefillText = "\(nick): "
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBarView(viewModel: viewModel, prefillText: $prefillText)
                .background(Color(.systemBackground))
        }
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .background(Color(.systemGroupedBackground))
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
            viewModel.markRead()
        }
        // Mark read when this channel is actively selected
        .onAppear { viewModel.markRead() }
        // Member list sheet
        .sheet(isPresented: $showMemberList) {
            MemberListView(
                members: viewModel.members,
                channelName: channelName,
                serverId: serverId,
                onMention: { nick in
                    showMemberList = false
                    prefillText = "\(nick): "
                },
                onDM: { nick, sid in
                    showMemberList = false
                    // Open or create DM channel, then navigate to it
                    let dm = ConversationsViewModel(ircManager: ircManager).openDM(with: nick, serverId: sid)
                    appState.selectedServerId = sid
                    appState.selectedChannelId = dm.id
                }
            )
            .environmentObject(ircManager)
        }
        // Nick identity sheet
        .sheet(isPresented: $showNickSheet) {
            if let server = try? DatabaseManager.shared.fetchServers().first(where: { $0.id == serverId }) {
                NickIdentitySheet(server: server)
                    .environmentObject(ircManager)
            }
        }
        // In-app Safari for rules URL
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Centre: topic subtitle (tappable)
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(channelName)
                    .font(.headline)
                if !viewModel.topic.isEmpty {
                    Button { showTopicPopover = true } label: {
                        Text(viewModel.topic)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to view full topic")
                }
            }
            .popover(isPresented: $showTopicPopover) {
                topicPopover
            }
        }

        // Right: rules (if URL in topic) + member count + menu
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Rules button — shown when the topic contains a URL
            if let url = viewModel.rulesURL {
                Button {
                    safariURL = url
                } label: {
                    Image(systemName: "book.closed")
                }
                .accessibilityLabel("Channel Rules")
            }

            Button {
                showMemberList = true
            } label: {
                Label(
                    viewModel.members.isEmpty ? "Members" : "\(viewModel.members.count)",
                    systemImage: "person.2"
                )
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
            }

            Menu {
                channelMenuContent
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuOrder(.fixed)
        }
    }

    // MARK: - Topic popover

    private var topicPopover: some View {
        NavigationStack {
            ScrollView {
                Text(viewModel.topic.isEmpty ? "No topic set." : viewModel.topic)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTopicPopover = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Channel menu

    @ViewBuilder
    private var channelMenuContent: some View {
        Button {
            prefillText = "/topic "
        } label: {
            Label("Set Topic", systemImage: "text.quote")
        }

        Button {
            Task {
                guard let client = ircManager.getClient(for: serverId) else { return }
                try? await client.names(channelName)
            }
        } label: {
            Label("Refresh Members", systemImage: "arrow.clockwise")
        }

        Button {
            showNickSheet = true
        } label: {
            Label("Change Nick…", systemImage: "person.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                guard let client = ircManager.getClient(for: serverId) else { return }
                try? await client.leave(channel: channelName)
                // Update the DB: clear joinedAt so the channel isn't auto-rejoined
                if let ch = try? DatabaseManager.shared.fetchChannels(forServer: serverId)
                    .first(where: { $0.name.lowercased() == channelName.lowercased() }) {
                    var updated = ch
                    updated.joinedAt = nil
                    try? DatabaseManager.shared.saveChannel(updated, serverId: serverId)
                }
                // Clear unread badge
                ircManager.clearUnread(channelId: viewModel.channelId)
                // Navigate back to server sidebar
                await MainActor.run { dismiss() }
            }
        } label: {
            Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }
}

// MARK: - URL identity for sheet(item:)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - UIViewControllerRepresentable Safari wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(
            serverId: "preview",
            channelName: "#linux",
            ircManager: IRCClientManager.shared
        )
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState.shared)
    }
}
