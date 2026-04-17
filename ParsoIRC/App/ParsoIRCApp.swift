import SwiftUI

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var debugLog = DebugLogManager.shared
    
    var body: some Scene {
        WindowGroup {
            SimpleConnectView()
                .environmentObject(ircManager)
                .environmentObject(appState)
                .environmentObject(debugLog)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    init() {}
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    init() {}
}