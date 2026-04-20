import SwiftUI

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

    @StateObject private var viewModel: ChannelViewModel

    // Text pre-fill fed from nick-tap / mention
    @State private var prefillText: String = ""

    // Sheet state
    @State private var showMemberList = false
    @State private var showChannelMenu = false
    @State private var showTopicPopover = false
    @State private var tappedNick: String? = nil

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

        // Right: member count + menu
        ToolbarItemGroup(placement: .navigationBarTrailing) {
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

        Divider()

        Button(role: .destructive) {
            Task {
                guard let client = ircManager.getClient(for: serverId) else { return }
                try? await client.leave(channel: channelName)
            }
        } label: {
            Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }
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
