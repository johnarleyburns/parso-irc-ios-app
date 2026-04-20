import SwiftUI

/// Root view of the app.
///
/// Responsibilities:
/// - Shows SplashScreenView on every cold launch (2.5 s)
/// - Shows OnboardingView when no servers have been saved yet (first-ever launch)
/// - Otherwise shows the main NavigationSplitView with ServerSidebarView on the left
///   and ChatView on the right (Phase 2) when a server + channel are both selected.
///
/// The `selectedServerId` / `selectedChannelId` pair are the source of truth for
/// what the detail column displays.
struct RootView: View {
    @EnvironmentObject private var ircManager: IRCClientManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    // Navigation state – driven by the sidebar
    @State private var selectedServerId: String? = nil
    @State private var selectedChannelId: String? = nil

    // Sheet / overlay state
    @State private var showSplash: Bool = true
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            mainContent
                .opacity(showSplash ? 0 : 1)

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

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        NavigationSplitView {
            ServerSidebarView(
                selectedServerId: $selectedServerId,
                selectedChannelId: $selectedChannelId
            )
        } detail: {
            if let sid = selectedServerId,
               let cid = selectedChannelId,
               let channel = resolveChannel(serverId: sid, channelId: cid) {
                if channel.isDM {
                    DirectMessageView(
                        serverId: sid,
                        nick: channel.name,
                        ircManager: ircManager
                    )
                    .id("\(sid):\(cid)")
                } else {
                    ChatView(serverId: sid, channelName: channel.name, ircManager: ircManager)
                        .id("\(sid):\(cid)")
                }
            } else {
                detailPlaceholder
            }
        }
        .onChange(of: selectedServerId) { _, newVal in
            appState.selectedServerId = newVal
        }
        .onChange(of: selectedChannelId) { _, newVal in
            appState.selectedChannelId = newVal
        }
        .onChange(of: networkMonitor.isConnected) { _, isNow in
            if isNow { reconnectDroppedServers() }
        }
    }

    private func resolveChannel(serverId: String, channelId: String) -> Channel? {
        let channels = (try? DatabaseManager.shared.fetchChannels(forServer: serverId)) ?? []
        if let ch = channels.first(where: { $0.id == channelId }) { return ch }
        // Fallback: construct a minimal channel from the ID itself
        return Channel(id: channelId, serverId: serverId, name: channelId)
    }

    // MARK: - Detail placeholder (shown when no channel is selected)

    private var detailPlaceholder: some View {
        VStack(spacing: 24) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Select a channel")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a server and channel from the sidebar to start chatting.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
    }

    // MARK: - First-launch logic

    private func checkFirstLaunch() {
        let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
        if servers.isEmpty {
            // Delay slightly so splash shows first
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                showOnboarding = true
            }
        }
    }

    private func handleOnboardingDismiss() {
        // After onboarding, auto-connect servers with autoConnect = true
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
                if state == .disconnected || state == .failed(IRCError.maxReconnectAttemptsReached) {
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
