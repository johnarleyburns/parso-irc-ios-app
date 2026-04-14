import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ServerListView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                .tag(0)
                .accessibilityIdentifier("serversTab")
            
            ConversationListView()
                .tabItem {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(1)
                .accessibilityIdentifier("conversationsTab")
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
                .accessibilityIdentifier("settingsTab")
        }
        .tint(Color.theme.sentBubble)
        .sheet(isPresented: $appState.showReconnectingSheet) {
            if let info = appState.reconnectInfo {
                ReconnectingSheet(serverId: info.serverId, channelName: info.channelName)
                    .onDisappear {
                        appState.reconnectInfo = nil
                    }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
        .environmentObject(WatchManager.shared)
}