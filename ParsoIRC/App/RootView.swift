import SwiftUI

/// Root view of the app.
///
/// Responsibilities:
/// - Shows SplashScreenView on every cold launch (2.5 s)
/// - Shows OnboardingView when no servers have been saved yet (first-ever launch)
/// - Otherwise shows the main NavigationSplitView with ServerSidebarView on the left
///   and a placeholder "select a channel" detail on the right until Phase 2 lands
///
/// The `selectedServerId` / `selectedChannelId` pair are the source of truth for
/// what the detail column displays.  Phase 2's ChatView will read them from the
/// environment via AppState.
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
            detailPlaceholder
        }
        // Pass current selection into AppState so Phase-2 ChatView can read it
        .onChange(of: selectedServerId) { _, newVal in
            appState.selectedServerId = newVal
        }
        .onChange(of: selectedChannelId) { _, newVal in
            appState.selectedChannelId = newVal
        }
        // Reconnect on network restore
        .onChange(of: networkMonitor.isConnected) { _, isNow in
            if isNow { reconnectDroppedServers() }
        }
    }

    // MARK: - Detail placeholder (replaced by ChatView in Phase 2)

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
