import SwiftUI

/// Navigation destination type for the app's NavigationStack.
enum NavDestination: Hashable {
    case channel(serverId: String, channelId: String, channelName: String)
    case dm(serverId: String, channelId: String, nick: String)
}

/// Root view of the app.
struct RootView: View {
    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @State private var navPath: [NavDestination] = []
    @State private var showSplash: Bool = true
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            NavigationStack(path: $navPath) {
                ServerSidebarView(
                    navPath: $navPath,
                    onSelectChannel: { serverId, channelId, channelName, isDM, nick in
                        let dest: NavDestination = isDM
                            ? .dm(serverId: serverId, channelId: channelId,
                                  nick: nick ?? channelName)
                            : .channel(serverId: serverId, channelId: channelId,
                                       channelName: channelName)
                        navPath = [dest]
                        appState.selectedServerId  = serverId
                        appState.selectedChannelId = channelId
                    }
                )
                .navigationDestination(for: NavDestination.self) { dest in
                    switch dest {
                    case .channel(let sid, _, let name):
                        ChatView(serverId: sid, channelName: name, ircManager: ircManager)
                    case .dm(let sid, _, let nick):
                        DirectMessageView(serverId: sid, nick: nick, ircManager: ircManager)
                    }
                }
            }
            // Inject the navigateToDM action so any view inside the stack
            // (ChatView, MemberListView, UserProfileSheet) can navigate to a
            // DM without holding a direct navPath binding.
            .environment(\.navigateToDM) { [self] nick, serverId in
                let dm = ircManager.openOrCreateDM(with: nick, serverId: serverId)
                navPath = [.dm(serverId: serverId, channelId: dm.id, nick: nick)]
                appState.selectedServerId  = serverId
                appState.selectedChannelId = dm.id
            }
            .opacity(showSplash ? 0 : 1)
            .onChange(of: networkMonitor.isConnected) { _, isNow in
                if isNow { reconnectDroppedServers() }
            }

            if showSplash {
                SplashScreenView(isPresented: $showSplash)
                    .zIndex(10)
            }
        }
        .onAppear(perform: checkFirstLaunch)
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: handleOnboardingDismiss) {
            OnboardingView(isPresented: $showOnboarding)
                .environmentObject(ircManager)
                .environmentObject(appState)
        }
    }

    // MARK: - First-launch logic

    private func checkFirstLaunch() {
        let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
        if servers.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                showOnboarding = true
            }
        }
    }

    private func handleOnboardingDismiss() {
        Task {
            let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
            for server in servers where server.autoConnect {
                try? await ircManager.connect(to: server)
            }
        }
    }

    // MARK: - Network restore

    private func reconnectDroppedServers() {
        Task {
            let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
            for server in servers {
                let state = ircManager.connectionState(for: server.id)
                if state == .disconnected {
                    try? await ircManager.connect(to: server)
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState.shared)
        .environmentObject(NetworkMonitor())
        .environmentObject(DebugLogManager.shared)
}
