import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isTyping = false
    @Published var channel: Channel
    @Published var channelMembers: [ChannelMember] = []
    
    let server: Server
    private let channelId: String
    private var previousSender: String?
    private var previousTimestamp: Date?
    
    struct MessageGroup {
        let date: Date
        let messages: [Message]
    }
    
    var groupedMessages: [MessageGroup] {
        var groups: [Date: [Message]] = [:]
        
        for message in messages {
            let dateKey = Calendar.current.startOfDay(for: message.timestamp)
            if groups[dateKey] == nil {
                groups[dateKey] = []
            }
            groups[dateKey]?.append(message)
        }
        
        return groups.map { MessageGroup(date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    init(server: Server, channel: Channel) {
        self.server = server
        self.channel = channel
        self.channelId = channel.id
    }
    
    func setupIRCCallbacks() {
        let serverId = server.id
        
        IRCClientManager.shared.onMessage(serverId: serverId) { [weak self] ircMessage in
            Task { @MainActor in
                self?.handleIRCMessage(ircMessage)
            }
        }
        
        IRCClientManager.shared.onJoin(serverId: serverId) { [weak self] channelName, nick in
            Task { @MainActor in
                if channelName == self?.channel.name {
                    self?.channelMembers.append(ChannelMember(nick: nick))
                    self?.channel.memberCount = self?.channelMembers.count ?? 0
                    
                    let systemMessage = Message(
                        channelId: self?.channelId ?? "",
                        sender: "",
                        content: "\(nick) has joined the channel",
                        type: .join
                    )
                    self?.messages.append(systemMessage)
                    self?.saveMessage(systemMessage)
                }
            }
        }
        
        IRCClientManager.shared.onPart(serverId: serverId) { [weak self] channelName, nick, message in
            Task { @MainActor in
                if channelName == self?.channel.name {
                    self?.channelMembers.removeAll { $0.nick == nick }
                    self?.channel.memberCount = self?.channelMembers.count ?? 0
                    
                    let reason = message ?? "Leaving"
                    let systemMessage = Message(
                        channelId: self?.channelId ?? "",
                        sender: "",
                        content: "\(nick) has left the channel (\(reason))",
                        type: .part
                    )
                    self?.messages.append(systemMessage)
                    self?.saveMessage(systemMessage)
                }
            }
        }
        
        IRCClientManager.shared.onQuit(serverId: serverId) { [weak self] nick, message in
            Task { @MainActor in
                self?.channelMembers.removeAll { $0.nick == nick }
                
                let reason = message ?? "Quit"
                let systemMessage = Message(
                    channelId: self?.channelId ?? "",
                    sender: "",
                    content: "\(nick) has quit (\(reason))",
                    type: .quit
                )
                self?.messages.append(systemMessage)
                self?.saveMessage(systemMessage)
            }
        }
        
        IRCClientManager.shared.onNickChange(serverId: serverId) { [weak self] oldNick, newNick in
            Task { @MainActor in
                if let index = self?.channelMembers.firstIndex(where: { $0.nick == oldNick }) {
                    self?.channelMembers[index].nick = newNick
                }
                
                let systemMessage = Message(
                    channelId: self?.channelId ?? "",
                    sender: "",
                    content: "\(oldNick) is now known as \(newNick)",
                    type: .nick
                )
                self?.messages.append(systemMessage)
                self?.saveMessage(systemMessage)
            }
        }
        
        IRCClientManager.shared.onTopicChange(serverId: serverId) { [weak self] channelName, topic, nick in
            Task { @MainActor in
                if channelName == self?.channel.name {
                    self?.channel.topic = topic
                    
                    let systemMessage = Message(
                        channelId: self?.channelId ?? "",
                        sender: "",
                        content: "\(nick) has set the topic: \(topic)",
                        type: .topic
                    )
                    self?.messages.append(systemMessage)
                    self?.saveMessage(systemMessage)
                }
            }
        }
        
        IRCClientManager.shared.onNamesList(serverId: serverId) { [weak self] channelName, nicks in
            Task { @MainActor in
                if channelName == self?.channel.name {
                    self?.channelMembers = nicks.map { nick in
                        let mode: ChannelMember.MemberMode = .none
                        if nick.hasPrefix("@") {
                            mode = .operator_
                        } else if nick.hasPrefix("+") {
                            mode = .voice
                        }
                        return ChannelMember(nick: String(nick.dropFirst()))
                    }
                    self?.channel.memberCount = nicks.count
                }
            }
        }
    }
    
    private func handleIRCMessage(_ ircMessage: IRCMessage) {
        guard ircMessage.parameters.count >= 2 else { return }
        
        let target = ircMessage.parameters[0]
        let content = ircMessage.parameters.last ?? ""
        
        guard target == channel.name || target == server.nickname else { return }
        
        let isAction = ircMessage.tags?["intent"] == "action"
        let messageType: Message.MessageType = isAction ? .action : .message
        let sender = ircMessage.source?.nick ?? "unknown"
        
        let currentNick = IRCClientManager.shared.currentNicknames[server.id] ?? ""
        let isFromMe = sender == currentNick
        
        let message = Message(
            channelId: channelId,
            sender: sender,
            senderHost: ircMessage.source?.host,
            content: content,
            timestamp: Date(),
            type: messageType,
            isFromCurrentUser: isFromMe,
            previousSameSenderMessage: previousSender == sender && previousTimestamp != nil && (Date().timeIntervalSince(previousTimestamp!) < 300) ? messages.last : nil
        )
        
        previousSender = sender
        previousTimestamp = message.timestamp
        
        messages.append(message)
        saveMessage(message)
        
        HapticManager.lightImpact()
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            do {
                try await IRCClientManager.shared.sendMessage(
                    inputText,
                    to: channel.name,
                    on: server.id
                )
                
                let currentNick = IRCClientManager.shared.currentNicknames[server.id] ?? ""
                let message = Message(
                    channelId: channelId,
                    sender: currentNick,
                    content: inputText,
                    timestamp: Date(),
                    type: .message,
                    isFromCurrentUser: true
                )
                
                messages.append(message)
                saveMessage(message)
                
                inputText = ""
                HapticManager.lightImpact()
            } catch {
                print("Failed to send message: \(error)")
                HapticManager.errorFeedback()
            }
        }
    }
    
    func loadMessages() {
        Task {
            do {
                let storedMessages = try DatabaseManager.shared.fetchMessages(forChannel: channelId)
                await MainActor.run {
                    var enrichedMessages: [Message] = []
                    
                    for message in storedMessages {
                        var enriched = message
                        if let last = enrichedMessages.last, last.sender == message.sender {
                            let timeDiff = message.timestamp.timeIntervalSince(last.timestamp)
                            if timeDiff < 300 {
                                enriched.previousSameSenderMessage = last
                            }
                        }
                        enrichedMessages.append(enriched)
                    }
                    
                    messages = enrichedMessages
                }
            } catch {
                print("Failed to load messages: \(error)")
            }
        }
    }
    
    private func saveMessage(_ message: Message) {
        Task {
            try? DatabaseManager.shared.saveMessage(message)
        }
    }
    
    func searchMessages(query: String) -> [Message] {
        (try? DatabaseManager.shared.searchMessages(query: query, inChannel: channelId)) ?? []
    }
}