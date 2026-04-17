import SwiftUI

@main
struct ParsoIRCApp: App {
    var body: some View {
        Text("Test")
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    init() {}
}