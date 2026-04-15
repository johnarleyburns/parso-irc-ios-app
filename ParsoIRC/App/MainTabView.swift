import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    var body: some View {
        NavigationStack {
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
            .navigationDestination(isPresented: $appState.showChat) {
                if let serverId = appState.selectedServerId,
                   let server = appState.servers.first(where: { $0.id == serverId }),
                   let channel = appState.selectedChannel {
                    ChatView(server: server, channel: channel)
                }
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}
