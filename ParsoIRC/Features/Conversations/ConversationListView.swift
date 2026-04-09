import SwiftUI
import Combine

struct ConversationListView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedConversation: (server: Server, channel: Channel)?
    
    var filteredConversations: [(server: Server, channel: Channel)] {
        var result: [(server: Server, channel: Channel)] = []
        
        for server in appState.servers {
            for channel in server.channels {
                if searchText.isEmpty || channel.name.localizedCaseInsensitiveContains(searchText) {
                    result.append((server: server, channel: channel))
                }
            }
        }
        
        return result.sorted { $0.channel.name < $1.channel.name }
    }
    
    var groupedConversations: [(serverName: String, conversations: [(server: Server, channel: Channel)])] {
        var grouped: [String: [(server: Server, channel: Channel)]] = [:]
        
        for conversation in filteredConversations {
            let serverName = conversation.server.name
            if grouped[serverName] == nil {
                grouped[serverName] = []
            }
            grouped[serverName]?.append(conversation)
        }
        
        return grouped.map { (serverName: $0.key, conversations: $0.value) }
            .sorted { $0.serverName < $1.serverName }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if appState.servers.isEmpty {
                    ContentUnavailableView(
                        "No Servers",
                        systemImage: "server.rack",
                        description: Text("Add a server to start chatting")
                    )
                } else {
                    ForEach(groupedConversations, id: \.serverName) { group in
                        Section(group.serverName) {
                            ForEach(group.conversations, id: \.channel.id) { conversation in
                                ConversationCell(
                                    channel: conversation.channel,
                                    connectionState: ircManager.connectionStates[conversation.server.id] ?? .disconnected
                                )
                                .accessibilityIdentifier("channel-\(conversation.channel.id)")
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedConversation = conversation
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Conversations")
            .searchable(text: $searchText, prompt: "Search channels")
            .navigationDestination(item: $selectedConversation) { conversation in
                ChatView(server: conversation.server, channel: conversation.channel)
            }
            .refreshable {
                // Refresh conversations
            }
        }
    }
}

struct ConversationCell: View {
    let channel: Channel
    let connectionState: IRCClientManager.ConnectionState
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.theme.sentBubble.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "number")
                    .font(.system(size: 18))
                    .foregroundColor(Color.theme.sentBubble)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name)
                        .font(.headline)
                    
                    if channel.isWatched {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundColor(Color.theme.sentBubble)
                    }
                    
                    Spacer()
                    
                    Text("12:30 PM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let topic = channel.topic, !topic.isEmpty {
                    Text(topic)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No topic")
                        .font(.subheadline)
                        .foregroundColor(.tertiary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                // Toggle watch - would need callback
            } label: {
                Label(
                    channel.isWatched ? "Stop Watching" : "Watch Channel",
                    systemImage: channel.isWatched ? "eye.slash" : "eye"
                )
            }
            
            Button {
                // Channel settings
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
}