import Foundation
import Combine

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(Error)
}

@MainActor
final class IRCClientManager: ObservableObject {
    static let shared = IRCClientManager()
    
    private var connections: [String: IRCClient] = [:]
    private var connectionStates: [String: ConnectionState] = [:]
    @Published var currentNicknames: [String: String] = [:]
    
    var connectionStatesPublisher: [String: ConnectionState] {
        connectionStates
    }
    
    private var reconnectTimers: [String: Timer] = [:]
    private var maxReconnectAttempts = 5
    
    private init() {}

    // MARK: - Connection State
    
    func connectionState(for serverId: String) -> ConnectionState {
        switch connectionStates[serverId] ?? .disconnected {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .reconnecting:
            return .reconnecting
        case .failed:
            return .failed(IRCError.maxReconnectAttemptsReached)
        }
    }
    
    // MARK: - Connection Management
    
    func connect(to server: Server) async throws {
        connectionStates[server.id] = .connecting
        
        let client = IRCClient()
        
        client.onWelcome = { [weak self] nick in
            Task { @MainActor in
                self?.currentNicknames[server.id] = nick
                self?.connectionStates[server.id] = .connected
            }
        }
        
        client.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect(serverId: server.id)
            }
        }
        
        client.onError = { [weak self] error in
            Task { @MainActor in
                self?.connectionStates[server.id] = .failed(IRCError.connectionFailed(error.localizedDescription))
            }
        }
        
        do {
            try await client.connect(
                host: server.host,
                port: server.port,
                tls: server.ssl,
                nickname: server.nickname.isEmpty ? "ParsoUser\(Int.random(in: 1000...9999))" : server.nickname,
                username: server.realname.isEmpty ? "parso" : server.realname,
                realname: server.realname.isEmpty ? "Parso IRC" : server.realname
            )
            
            if server.saslEnabled, let password = server.password {
                try await client.authenticateSASL(username: server.nickname, password: password)
            }
            
            connections[server.id] = client
            
            for channel in server.channels {
                try await client.join(channel: channel.name)
            }
            
        } catch {
            connectionStates[server.id] = .failed(IRCError.connectionFailed(error.localizedDescription))
            throw error
        }
    }
    
    func disconnect(from serverId: String) {
        reconnectTimers[serverId]?.invalidate()
        reconnectTimers[serverId] = nil
        
        Task {
            try? await connections[serverId]?.quit(message: "Parso IRC signing off")
            await MainActor.run {
                connections[serverId] = nil
                connectionStates[serverId] = .disconnected
            }
        }
    }
    
    func disconnectAll() {
        for serverId in connections.keys {
            disconnect(from: serverId)
        }
    }
    
    private func handleDisconnect(serverId: String) {
        connectionStates[serverId] = .disconnected
        
        scheduleReconnect(serverId: serverId)
    }
    
    private func scheduleReconnect(serverId: String) {
        let attempts = reconnectTimers.filter { $0.key == serverId }.count
        
        guard attempts < maxReconnectAttempts else {
            connectionStates[serverId] = .failed(IRCError.maxReconnectAttemptsReached)
            return
        }
        
        connectionStates[serverId] = .reconnecting
        
        let delay = pow(2.0, Double(attempts))
        
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if let server = try? DatabaseManager.shared.fetchServers().first(where: { $0.id == serverId }) {
                    try? await self?.connect(to: server)
                }
            }
        }
    }
    
    // MARK: - Message Sending
    
    func sendMessage(_ content: String, to channel: String, on serverId: String) async throws {
        guard let client = connections[serverId] else {
            throw IRCError.notConnected
        }
        
        if content.hasPrefix("/") {
            try await handleCommand(content, channel: channel, serverId: serverId)
        } else {
            try await client.sendMessage(content, to: channel)
        }
    }
    
    func sendPrivateMessage(_ content: String, to nick: String, on serverId: String) async throws {
        guard let client = connections[serverId] else {
            throw IRCError.notConnected
        }
        
        try await client.sendMessage(content, to: nick)
    }
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: String, channel: String, serverId: String) async throws {
        guard let client = connections[serverId] else {
            throw IRCError.notConnected
        }
        
        let parts = command.dropFirst().split(separator: " ", maxSplits: 1)
        let cmd = String(parts.first ?? "").lowercased()
        let args = parts.count > 1 ? String(parts[1]) : ""
        
        switch cmd {
        case "nick":
            let newNick = args.isEmpty ? command.split(separator: " ").dropFirst().first.map(String.init) ?? "" : args
            try await client.send(command: "NICK", parameters: [newNick])
            
        case "join":
            let channels = args.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for chan in channels {
                try await client.join(channel: chan)
            }
            
        case "part", "leave":
            let chan = args.isEmpty ? channel : args.split(separator: " ").first.map(String.init) ?? channel
            try await client.leave(channel: chan)
            
        case "quit":
            try await client.quit(message: args)
            connections[serverId] = nil
            
        case "me":
            let action = "\u{0001}ACTION \(args)\u{0001}"
            try await client.sendMessage(action, to: channel)
            
        case "topic":
            if args.isEmpty {
                try await client.send(command: "TOPIC", parameters: [channel])
            } else {
                try await client.send(command: "TOPIC", parameters: [channel, args])
            }
            
        case "mode":
            try await client.send(command: "MODE", parameters: args.split(separator: " ").map(String.init))
            
        case "kick":
            let parts = args.split(separator: " ")
            if let nick = parts.first {
                let reason = parts.dropFirst().joined(separator: " ")
                try await client.send(command: "KICK", parameters: [channel, String(nick), reason])
            }
            
        case "invite":
            let parts = args.split(separator: " ")
            if let nick = parts.first {
                try await client.send(command: "INVITE", parameters: [String(nick), channel])
            }
            
        case "whois":
            try await client.send(command: "WHOIS", parameters: [args])
            
        case "msg":
            let parts = args.split(separator: " ", maxSplits: 1)
            if let target = parts.first, let message = parts.last {
                try await client.sendMessage(String(message), to: String(target))
            }
            
        case "list":
            try await client.send(command: "LIST", parameters: args.isEmpty ? [] : [args])
            
        case "names":
            try await client.send(command: "NAMES", parameters: [channel])
            
        case "who":
            try await client.send(command: "WHO", parameters: [args.isEmpty ? channel : args])
            
        default:
            try await sendRawCommand(command, client: client)
        }
    }
    
    private func sendRawCommand(_ command: String, client: IRCClient) async throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = trimmed.split(separator: " ", maxSplits: 1)
        let cmd = String(parts.first ?? "")
        let params = parts.count > 1 ? String(parts[1]) : ""
        let paramsArray = params.isEmpty ? [] : params.split(separator: " ").map(String.init)
        try await client.send(command: cmd, parameters: paramsArray)
    }
    
    // MARK: - Event Listeners
    
    func onMessage(serverId: String, handler: @escaping (IRCMessage) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onMessage = { message in
            Task { @MainActor in
                handler(message)
            }
        }
    }
    
    func onJoin(serverId: String, handler: @escaping (String, String) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onJoin = { channel, nick in
            Task { @MainActor in
                handler(channel, nick)
            }
        }
    }
    
    func onPart(serverId: String, handler: @escaping (String, String, String?) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onPart = { channel, nick, message in
            Task { @MainActor in
                handler(channel, nick, message)
            }
        }
    }
    
    func onQuit(serverId: String, handler: @escaping (String, String?) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onQuit = { nick, message in
            Task { @MainActor in
                handler(nick, message)
            }
        }
    }
    
    func onNickChange(serverId: String, handler: @escaping (String, String) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onNickChange = { oldNick, newNick in
            Task { @MainActor in
                handler(oldNick, newNick)
            }
        }
    }
    
    func onTopicChange(serverId: String, handler: @escaping (String, String, String) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onTopicChange = { channel, topic, nick in
            Task { @MainActor in
                handler(channel, topic, nick)
            }
        }
    }
    
    func onNamesList(serverId: String, handler: @escaping (String, [String]) -> Void) {
        guard let client = connections[serverId] else { return }
        
        client.onNamesList = { channel, nicks in
            Task { @MainActor in
                handler(channel, nicks)
            }
        }
    }
}