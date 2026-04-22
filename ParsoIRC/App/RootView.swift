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

    // EULA gate — shown once on first launch; re-shown after "Exit Demo Mode"
    @AppStorage("eulaAccepted") private var eulaAccepted: Bool = false
    @State private var showEULA: Bool = false

    /// Controls whether the main IRC sidebar is rendered at full opacity.
    /// Kept false until either:
    ///   - a returning user (EULA accepted + servers exist) passes the splash, OR
    ///   - onboarding is dismissed (new user finished setup).
    /// This eliminates the single-frame flash where the empty sidebar is visible
    /// between the EULA cover dismissing and the onboarding cover appearing.
    @State private var mainUIVisible: Bool = false

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
            .environment(\.navigateToDM) { [self] nick, serverId in
                let dm = ircManager.openOrCreateDM(with: nick, serverId: serverId)
                navPath = [.dm(serverId: serverId, channelId: dm.id, nick: nick)]
                appState.selectedServerId  = serverId
                appState.selectedChannelId = dm.id
            }
            // Hidden until the user has passed all first-launch gates.
            // Using opacity(0) keeps the view in the tree (so NavigationStack
            // state is preserved) but invisible to the user.
            .opacity(mainUIVisible ? 1 : 0)
            .onChange(of: networkMonitor.isConnected) { _, isNow in
                if isNow { reconnectDroppedServers() }
            }
            // Deferred launch logic — fires after the splash finishes.
            .onChange(of: showSplash) { _, isShowing in
                guard !isShowing else { return }
                handlePostSplash()
            }

            if showSplash {
                SplashScreenView(isPresented: $showSplash)
                    .zIndex(10)
            }
        }
        // Onboarding
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: handleOnboardingDismiss) {
            OnboardingView(isPresented: $showOnboarding, initialPage: eulaAccepted ? 1 : 0)
                .environmentObject(ircManager)
                .environmentObject(appState)
        }
        // EULA gate
        .fullScreenCover(isPresented: $showEULA, onDismiss: {
            guard eulaAccepted else { return }
            let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
            if servers.isEmpty {
                showOnboarding = true
                // mainUIVisible stays false until onboarding dismisses
            } else {
                // Returning user who just re-accepted EULA — show main UI
                mainUIVisible = true
            }
        }) {
            EULAView(isPresented: $showEULA)
        }
        // Reset to onboarding (triggered by "Exit Demo Mode" / "Delete Account")
        .onReceive(NotificationCenter.default.publisher(for: .resetToOnboarding)) { _ in
            ircManager.disconnectAll()
            navPath = []
            mainUIVisible = false
            eulaAccepted = false
            showEULA = true
            showOnboarding = false
        }
    }

    // MARK: - Post-splash routing

    private func handlePostSplash() {
        if !eulaAccepted {
            // First launch — show EULA. Onboarding and mainUIVisible are set
            // in the EULA onDismiss handler and handleOnboardingDismiss respectively.
            showEULA = true
        } else {
            let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
            if servers.isEmpty {
                // EULA accepted but no servers — show onboarding.
                showOnboarding = true
            } else {
                // Returning user with servers — go straight to main UI.
                mainUIVisible = true
            }
        }
    }

    // MARK: - First-launch logic

    private func checkFirstLaunch() {
        // Intentionally empty — routing is driven by handlePostSplash().
    }

    private func handleOnboardingDismiss() {
        // Reveal the main UI now that the user has completed setup.
        mainUIVisible = true
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
