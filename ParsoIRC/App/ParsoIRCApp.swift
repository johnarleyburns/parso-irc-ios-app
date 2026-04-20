import SwiftUI
import BackgroundTasks

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var debugLog = DebugLogManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ircManager)
                .environmentObject(appState)
                .environmentObject(debugLog)
                .environmentObject(networkMonitor)
                .task {
                    networkMonitor.startMonitoring()
                }
        }
        .backgroundTask(.appRefresh("com.parso.irc.refresh")) {
            await IRCClientManager.shared.pingAllServers()
            WatchManager.shared.scheduleNextBackgroundTask()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                ircManager.saveConnectedServerIds()
                WatchManager.shared.scheduleNextBackgroundTask()
            }
        }
    }
}

// MARK: - AppState

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentUser: User?
    @Published var isAuthenticated = false

    // Global IRC identity — used as the default for all servers unless
    // overridden per-server in AddServerSheet.
    @Published var globalNickname: String {
        didSet { UserDefaults.standard.set(globalNickname, forKey: "globalNickname") }
    }
    @Published var globalRealName: String {
        didSet { UserDefaults.standard.set(globalRealName, forKey: "globalRealName") }
    }

    // Currently selected server / channel — driven by RootView's NavigationSplitView.
    // Phase-2 ChatView will read these to know what to display.
    @Published var selectedServerId: String? = nil
    @Published var selectedChannelId: String? = nil

    init() {
        self.globalNickname = UserDefaults.standard.string(forKey: "globalNickname") ?? ""
        self.globalRealName = UserDefaults.standard.string(forKey: "globalRealName") ?? ""
    }
}