import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            ConversationListView()
                .tabItem {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .tint(Color.theme.sentBubble)
    }
}

#Preview {
    MainTabView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}
