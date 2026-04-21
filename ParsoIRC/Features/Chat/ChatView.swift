import SwiftUI
import SafariServices

// MARK: - Navigation environment key
//
// Injected by RootView so any view inside the NavigationStack can trigger
// navigation to a DM without needing a direct navPath binding.

struct NavigateToDMKey: EnvironmentKey {
    static let defaultValue: ((String, String) -> Void)? = nil
}

extension EnvironmentValues {
    var navigateToDM: ((String, String) -> Void)? {
        get { self[NavigateToDMKey.self] }
        set { self[NavigateToDMKey.self] = newValue }
    }
}

/// The main chat screen for a single channel or DM.
struct ChatView: View {
    let serverId: String
    let channelName: String

    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigateToDM) private var navigateToDM

    @StateObject private var viewModel: ChannelViewModel

    @State private var prefillText: String = ""
    @State private var showMemberList = false
    @State private var showChannelMenu = false
    @State private var showTopicPopover = false
    @State private var showNickSheet = false
    @State private var tappedNick: String? = nil
    @State private var safariURL: URL? = nil

    init(serverId: String, channelName: String, ircManager: IRCClientManager) {
        self.serverId = serverId
        self.channelName = channelName
        _viewModel = StateObject(wrappedValue:
            ChannelViewModel(serverId: serverId, channelName: channelName,
                             ircManager: ircManager)
        )
    }

    var body: some View {
        MessageListView(
            viewModel: viewModel,
            onTapNick: { nick in prefillText = "\(nick): " }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBarView(viewModel: viewModel, prefillText: $prefillText)
                .background(Color(.systemBackground))
        }
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .background(Color(.systemGroupedBackground))
        .task { await viewModel.start() }
        .onDisappear {
            viewModel.stop()
            viewModel.markRead()
        }
        .onAppear { viewModel.markRead() }
        // Member list sheet — passes viewModel so the list is reactive
        .sheet(isPresented: $showMemberList) {
            MemberListView(
                viewModel: viewModel,
                channelName: channelName,
                serverId: serverId,
                onMention: { nick in
                    showMemberList = false
                    prefillText = "\(nick): "
                },
                onDM: { nick, sid in
                    showMemberList = false
                    // Create/find the DM channel in the DB via the manager
                    ircManager.openOrCreateDM(with: nick, serverId: sid)
                    // Navigate to the DM via the environment action injected by RootView
                    navigateToDM?(nick, sid)
                }
            )
            .environmentObject(ircManager)
        }
        .sheet(isPresented: $showNickSheet) {
            if let server = try? DatabaseManager.shared.fetchServers()
                .first(where: { $0.id == serverId }) {
                NickIdentitySheet(server: server)
                    .environmentObject(ircManager)
            }
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
            .popover(isPresented: $showTopicPopover) { topicPopover }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if let url = viewModel.rulesURL {
                Button { safariURL = url } label: {
                    Image(systemName: "book.closed")
                }
                .accessibilityLabel("Channel Rules")
            }

            Button { showMemberList = true } label: {
                Label(
                    viewModel.members.isEmpty ? "Members" : "\(viewModel.members.count)",
                    systemImage: "person.2"
                )
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
            }

            Menu { channelMenuContent } label: {
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
        Button { prefillText = "/topic " } label: {
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

        Button { showNickSheet = true } label: {
            Label("Change Nick…", systemImage: "person.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            Task {
                guard let client = ircManager.getClient(for: serverId) else { return }
                try? await client.leave(channel: channelName)
                if let ch = try? DatabaseManager.shared.fetchChannels(forServer: serverId)
                    .first(where: { $0.name.lowercased() == channelName.lowercased() }) {
                    var updated = ch
                    updated.joinedAt = nil
                    try? DatabaseManager.shared.saveChannel(updated, serverId: serverId)
                }
                ircManager.clearUnread(channelId: viewModel.channelId)
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
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
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
