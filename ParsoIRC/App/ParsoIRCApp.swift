import SwiftUI
import Combine
import BackgroundTasks
import UserNotifications
import Network

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var watchManager = WatchManager.shared
    @State private var networkMonitor = NetworkMonitor()
    @State private var showNetworkError = false
    
    @State private var showSplash = true
    @State private var showOnboarding = false
    @State private var showRegistration = false
    @State private var showLogin = false
    @State private var isAuthenticated = false
    
    init() {
        setupAppearance()
        registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashScreenView(isPresented: $showSplash)
                        .onDisappear {
                            if !appState.hasSeenOnboarding {
                                withAnimation {
                                    showOnboarding = true
                                }
                            } else if appState.currentUser != nil {
                                isAuthenticated = true
                            }
                        }
                } else if showOnboarding {
                    OnboardingView(
                        isPresented: $showOnboarding,
                        onSignUp: {
                            showOnboarding = false
                            showRegistration = true
                        },
                        onSkip: {
                            showOnboarding = false
                            isAuthenticated = true
                        },
                        onSignIn: {
                            showOnboarding = false
                            showLogin = true
                        }
                    )
                } else if showRegistration {
                    RegistrationView(isAuthenticated: $isAuthenticated)
                } else if showLogin {
                    LoginView(isAuthenticated: $isAuthenticated)
                } else if isAuthenticated {
                    MainTabView()
                        .environmentObject(ircManager)
                        .environmentObject(appState)
                        .environmentObject(watchManager)
                        .overlay(DebugToastView())
                }
            }
            .onAppear {
                networkMonitor.startMonitoring()
                loadInitialData()
                setupNotifications()
                checkAuthentication()
            }
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                if !isConnected && appState.hasLaunchedBefore {
                    showNetworkError = true
                }
            }
            .alert("No Internet Connection", isPresented: $showNetworkError) {
                Button("Retry") {
                    if networkMonitor.isConnected {
                        checkAuthentication()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("IRC requires an internet connection to connect to servers.")
            }
        }
    }
    
    private func checkAuthentication() {
        Task {
            if let user = try? DatabaseManager.shared.getCurrentUser() {
                await MainActor.run {
                    appState.currentUser = user
                    appState.hasLaunchedBefore = true
                    isAuthenticated = true
                    showSplash = false
                    showOnboarding = false
                }
            } else {
                await MainActor.run {
                    appState.hasLaunchedBefore = true
                    showSplash = false
                }
            }
        }
    }
    
    private func loadInitialData() {
        Task {
            do {
                try DatabaseManager.shared.cleanupOldMessages()
                
                let servers = try DatabaseManager.shared.fetchServers()
                if servers.isEmpty {
                    for server in Server.defaultNetworks {
                        try DatabaseManager.shared.saveServer(server)
                    }
                }
                
                await MainActor.run {
                    appState.servers = (try? DatabaseManager.shared.fetchServers()) ?? Server.defaultNetworks
                }
            } catch {
                print("Failed to load initial data: \(error)")
            }
        }
    }
    
    private func setupAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().standardAppearance = navBarAppearance
    }
    
    private func setupNotifications() {
        Task {
            await NotificationManager.shared.checkAuthorizationStatus()
            
            // Request authorization if enabled in settings but not yet granted
            if watchManager.settings.notificationsEnabled && !NotificationManager.shared.isAuthorized {
                _ = await NotificationManager.shared.requestAuthorization()
            }
        }
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.parso.irc.watch",
            using: nil
        ) { task in
            Task { @MainActor in
                await handleWatchBackgroundTask(task as! BGAppRefreshTask)
            }
        }
    }
    
    private func handleWatchBackgroundTask(_ task: BGAppRefreshTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Check watched channels for new messages
        await checkWatchedChannels()
        
        // Schedule next background task
        scheduleBackgroundTask()
        
        task.setTaskCompleted(success: true)
    }
    
    private func scheduleBackgroundTask() {
        guard WatchManager.shared.settings.notificationsEnabled else { return }
        
        let request = BGAppRefreshTaskRequest(identifier: "com.parso.irc.watch")
        let interval = TimeInterval(WatchManager.shared.settings.pollIntervalMinutes * 60)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    private func checkWatchedChannels() async {
        // This would check watched channels for new messages
        // In a real implementation, this would query the IRC connection
        // for the latest messages in watched channels
        
        guard let servers = try? DatabaseManager.shared.fetchServers() else { return }
        
        for server in servers {
            for channel in server.channels where channel.isWatched {
                // Check for new messages since last checked
                // If new messages and should notify, send notification
                
                // This is a simplified version - actual implementation
                // would need to track message timestamps from IRC
            }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore = false
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    @AppStorage("lastTabIndex") var lastTabIndex = 1
    @AppStorage("lastServerId") var lastServerId: String?
    @AppStorage("lastChannelName") var lastChannelName: String?
    @AppStorage("lastUsername") var lastUsername: String?
    @AppStorage("debugModeEnabled") var debugModeEnabled = true
    
    @Published var servers: [Server] = []
    @Published var selectedServerId: String?
    @Published var selectedChannel: Channel?
    @Published var showingServerSheet = false
    @Published var showingAddChannel = false
    @Published var currentViewingChannelId: String?
    @Published var selectedTab: Int = 1
    
    @Published var showFirstTimeConnect = false
    @Published var reconnectInfo: (serverId: String, channelName: String)?
    @Published var showReconnectingSheet = false
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    var currentNick: String {
        guard let serverId = selectedServerId else { return "" }
        return IRCClientManager.shared.currentNicknames[serverId] ?? ""
    }
    
    func isViewingChannel(_ channelId: String) -> Bool {
        return currentViewingChannelId == channelId
    }
    
    func navigateToChannel(serverId: String, channelName: String) {
        lastServerId = serverId
        lastChannelName = channelName
        selectedServerId = serverId
        
        if let server = servers.first(where: { $0.id == serverId }),
           let channel = server.channels.first(where: { $0.name == channelName }) {
            selectedChannel = channel
        }
        
        selectedTab = 1
    }
}