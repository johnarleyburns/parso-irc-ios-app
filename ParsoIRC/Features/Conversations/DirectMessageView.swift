import SwiftUI

/// Direct message view — reuses ChatView's full message list + input bar
/// pointed at a private nick target rather than a #channel.
///
/// The nav title shows the remote nick; the toolbar shows a WHOIS button
/// instead of the member-list button used in channels.
struct DirectMessageView: View {
    let serverId: String
    let nick: String          // remote nick, e.g. "alice"

    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState

    @StateObject private var viewModel: ChannelViewModel
    @State private var prefillText: String = ""
    @State private var showProfile = false

    init(serverId: String, nick: String, ircManager: IRCClientManager) {
        self.serverId = serverId
        self.nick = nick
        // Re-use ChannelViewModel: DM target acts as channel name.
        // Messages addressed to `nick` (our current nick) are accepted
        // because ChannelViewModel checks both channel name and currentNick.
        _viewModel = StateObject(wrappedValue:
            ChannelViewModel(serverId: serverId, channelName: nick, ircManager: ircManager)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(viewModel: viewModel, onTapNick: { tapped in
                prefillText = "\(tapped): "
            })
            InputBarView(viewModel: viewModel, prefillText: $prefillText)
        }
        .navigationTitle(nick)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .background(Color(.systemGroupedBackground))
        .task { await viewModel.start() }
        .onDisappear {
            viewModel.stop()
            viewModel.markRead()
        }
        .onAppear { viewModel.markRead() }
        .sheet(isPresented: $showProfile) {
            UserProfileSheet(
                nick: nick,
                member: nil,
                serverId: serverId,
                onMention: { mentioned in
                    showProfile = false
                    prefillText = "\(mentioned): "
                }
            )
            .environmentObject(ircManager)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                showProfile = true
            } label: {
                VStack(spacing: 1) {
                    AvatarView(nick: nick, size: 28, showBorder: false)
                    Text(nick)
                        .font(.caption2)
                        .foregroundStyle(NickColorGenerator.color(for: nick))
                }
            }
            .buttonStyle(.plain)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showProfile = true
            } label: {
                Image(systemName: "person.circle")
            }
        }
    }
}

#Preview {
    NavigationStack {
        DirectMessageView(serverId: "preview", nick: "alice", ircManager: IRCClientManager.shared)
            .environmentObject(IRCClientManager.shared)
            .environmentObject(AppState.shared)
    }
}
