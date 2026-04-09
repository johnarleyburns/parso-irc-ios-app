import SwiftUI
import Combine

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState()
    
    init() {
        setupAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ircManager)
                .environmentObject(appState)
                .onAppear {
                    loadInitialData()
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
}

@MainActor
class AppState: ObservableObject {
    @Published var servers: [Server] = []
    @Published var selectedServerId: String?
    @Published var selectedChannel: Channel?
    @Published var showingServerSheet = false
    @Published var showingAddChannel = false
    
    var currentNick: String {
        guard let serverId = selectedServerId else { return "" }
        return IRCClientManager.shared.currentNicknames[serverId] ?? ""
    }
}