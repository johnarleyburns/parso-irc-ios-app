import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ServerListView()
                .tabItem {
                    Label("Servers", systemImage: "server.rack")
                }
                .tag(0)
            
            ConversationListView()
                .tabItem {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(1)
        }
        .tint(Color.theme.sentBubble)
    }
}

#Preview {
    ContentView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}