import SwiftUI

@main
struct ParsoIRCApp: App {
    @StateObject private var ircManager = IRCClientManager.shared
    @StateObject private var appState = AppState.shared
    @ObservedObject private var debugLog = DebugLogManager.shared
    
    var body: some View {
        Text("Test")
    }
}

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
}