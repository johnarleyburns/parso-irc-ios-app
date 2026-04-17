import SwiftUI

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            SimpleConnectView()
                .environmentObject(ircManager)
                .environmentObject(appState)
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