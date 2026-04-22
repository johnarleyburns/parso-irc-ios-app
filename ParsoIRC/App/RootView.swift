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
            .opacity(showSplash ? 0 : 1)
            .onChange(of: networkMonitor.isConnected) { _, isNow in
                if isNow { reconnectDroppedServers() }
            }
            // ── Deferred launch logic — runs AFTER the splash finishes ──────
            // Waiting for showSplash → false guarantees the user sees the full
            // Parso IRC splash animation before any gate (EULA or onboarding)
            // appears on top of it.
            .onChange(of: showSplash) { _, isShowing in
                guard !isShowing else { return }
                handlePostSplash()
            }

            if showSplash {
                SplashScreenView(isPresented: $showSplash)
                    .zIndex(10)
            }
        }
        // Onboarding — initialPage:1 skips the marketing welcome page and
        // opens directly on the Identity (nick/user/password) screen, since
        // the EULA already served as the formal agreement/welcome gate.
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
                // Small delay so the EULA cover finishes its dismiss animation
                // before the onboarding cover begins its present animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showOnboarding = true
                }
            }
        }) {
            EULAView(isPresented: $showEULA)
        }
        // Reset to onboarding (triggered by "Exit Demo Mode" / "Delete Account")
        .onReceive(NotificationCenter.default.publisher(for: .resetToOnboarding)) { _ in
            ircManager.disconnectAll()
            navPath = []
            eulaAccepted = false
            showEULA = true
            showOnboarding = false
        }
    }

    // MARK: - Post-splash routing

    /// Called exactly once per launch, immediately after the splash animation
    /// completes.  Decides which gate (if any) to show before the main UI.
    private func handlePostSplash() {
        if !eulaAccepted {
            // First launch or after a data reset — show EULA first.
            // Onboarding follows in the EULA's onDismiss handler above.
            showEULA = true
        } else {
            // Returning user who already accepted the EULA.
            // Show onboarding only if no servers have been configured yet.
            let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
            if servers.isEmpty {
                showOnboarding = true
            }
            // Otherwise drop straight through to the main IRC sidebar.
        }
    }

    // MARK: - First-launch logic

    private func checkFirstLaunch() {
        // Intentionally empty — all first-launch routing is now driven by
        // handlePostSplash() which fires after the splash animation completes.
        // Keeping this method so .onAppear doesn't need to be removed.
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
