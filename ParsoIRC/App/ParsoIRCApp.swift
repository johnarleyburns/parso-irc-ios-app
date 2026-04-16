import SwiftUI
import Combine
import BackgroundTasks
import UserNotifications
import Network

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState.shared
    @State private var networkMonitor = NetworkMonitor()
    @State private var showNetworkError = false
    
    @State private var showSplash = true
    @State private var showServerSelection = false
    @State private var connectedServer: Server?
    @State private var connectedChannel: Channel?
    
    init() {
        setupAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashScreenView(isPresented: $showSplash)
                        .onDisappear {
                            withAnimation {
                                showServerSelection = true
                            }
                        }
                } else if showServerSelection {
                    ServerSelectionView()
                        .environmentObject(ircManager)
                        .environmentObject(appState)
                        .onChange(of: ircManager.activeConnectionServerId) { _, newServerId in
                            if let serverId = newServerId,
                               let server = appState.servers.first(where: { $0.id == serverId }) {
                                connectedServer = server
                                let channelName = server.lastActiveChannel ?? server.channels.first?.name ?? "#linux"
                                connectedChannel = server.channels.first(where: { $0.name == channelName }) ?? Channel(name: channelName)
                            }
                        }
                        .fullScreenCover(item: $connectedServer) { server in
                            if let channel = connectedChannel {
                                NavigationStack {
                                    TerminalView(server: server, channel: channel)
                                        .environmentObject(ircManager)
                                        .environmentObject(appState)
                                }
                            }
                        }
                }
            }
            .onAppear {
                networkMonitor.startMonitoring()
            }
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                if !isConnected && appState.hasLaunchedBefore {
                    showNetworkError = true
                }
            }
            .alert("No Internet Connection", isPresented: $showNetworkError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("IRC requires an internet connection.")
            }
        }
    }
    
    private func setupAppearance() {
        UINavigationBar.appearance().barStyle = .black
        UITextView.appearance().backgroundColor = .clear
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore = false
    
    @Published var servers: [Server] = []
    @Published var selectedServerId: String?
    @Published var selectedChannel: Channel?
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var showChat = false
    
    var currentNick: String {
        guard let serverId = selectedServerId else { return "" }
        return IRCClientManager.shared.currentNicknames[serverId] ?? ""
    }
}