import SwiftUI
import Combine
import BackgroundTasks
import UserNotifications

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState()
    @StateObject private var watchManager = WatchManager.shared
    
    init() {
        setupAppearance()
        registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ircManager)
                .environmentObject(appState)
                .environmentObject(watchManager)
                .onAppear {
                    loadInitialData()
                    setupNotifications()
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
    
    private func loadInitialData() {
        Task {
            do {
                try DatabaseManager.shared.cleanupOldData()
                
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
    @Published var servers: [Server] = []
    @Published var selectedServerId: String?
    @Published var selectedChannel: Channel?
    @Published var showingServerSheet = false
    @Published var showingAddChannel = false
    @Published var currentViewingChannelId: String?
    
    var currentNick: String {
        guard let serverId = selectedServerId else { return "" }
        return IRCClientManager.shared.currentNicknames[serverId] ?? ""
    }
    
    func isViewingChannel(_ channelId: String) -> Bool {
        return currentViewingChannelId == channelId
    }
}