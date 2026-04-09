import SwiftUI
import Combine

struct ChatView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ChatViewModel
    
    @State private var showMemberList = false
    @State private var showCommandPalette = false
    @FocusState private var isInputFocused: Bool
    
    init(server: Server, channel: Channel) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(server: server, channel: channel))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Channel Header
            channelHeader
            
            // Message List
            messageList
            
            // Input Bar
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(viewModel.channel.name)
                        .font(.headline)
                    Text("\(viewModel.channel.memberCount) members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showMemberList = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                    
                    Button {
                        // Show channel info
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showMemberList) {
            MemberListView(channel: viewModel.channel, server: viewModel.server)
        }
        .onAppear {
            viewModel.setupIRCCallbacks()
            viewModel.loadMessages()
        }
    }
    
    private var channelHeader: some View {
        VStack(spacing: 0) {
            if let topic = viewModel.channel.topic, !topic.isEmpty {
                HStack {
                    Text("Topic: \(topic)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    
                    Spacer()
                }
                .background(Color(uiColor: .secondarySystemBackground))
            }
        }
    }
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.groupedMessages, id: \.date) { group in
                        DateSeparatorView(date: group.date)
                            .id("date-\(group.date)")
                        
                        ForEach(group.messages) { message in
                            MessageBubbleView(
                                message: message,
                                currentNick: appState.currentNick
                            )
                            .id(message.id)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            InputBarView(
                text: $viewModel.inputText,
                onSend: {
                    viewModel.sendMessage()
                    isInputFocused = true
                },
                onCommand: {
                    showCommandPalette = true
                }
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview {
    NavigationStack {
        ChatView(
            server: Server.defaultNetworks[0],
            channel: Channel(name: "#libera")
        )
        .environmentObject(IRCClientManager.shared)
        .environmentObject(AppState())
    }
}