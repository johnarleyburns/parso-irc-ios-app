#if canImport(Combine)
import Combine
#endif
#if canImport(Foundation)
import Foundation
import Combine
#endif

#if canImport(Darwin)
import Darwin
#endif

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(Error)
    
    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.reconnecting, .reconnecting): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}

@MainActor
final class IRCClientManager: ObservableObject {
    static let shared = IRCClientManager()
    
    var connections: [String: IRCClient] = [:]
    @Published var connectionStates: [String: ConnectionState] = [:]
    @Published var currentNicknames: [String: String] = [:]

    // MARK: - Unread counts (keyed by channel ID)
    @Published private(set) var unreadCounts: [String: Int] = [:]

    func incrementUnread(channelId: String) {
        unreadCounts[channelId, default: 0] += 1
    }
    func clearUnread(channelId: String) {
        unreadCounts[channelId] = 0
    }

    // MARK: - Channel list cache (app-lifetime, in-memory)
    struct CachedListEntry: Equatable {
        let name: String
        let members: Int
        let topic: String
    }
    struct CachedChannelList {
        var entries: [CachedListEntry]
        let fetchedAt: Date
    }
    @Published private(set) var channelListCache: [String: CachedChannelList] = [:]
    private var listStagingBuffer: [String: [CachedListEntry]] = [:]

    func clearChannelListCache(for serverId: String) {
        channelListCache.removeValue(forKey: serverId)
    }

    /// Appended by ChannelBrowserSheet when it owns the list callbacks during a full LIST.
    func appendToListStagingBuffer(serverId: String, entry: CachedListEntry) {
        listStagingBuffer[serverId, default: []].append(entry)
    }

    /// Commits staging buffer to the cache (called on RPL_LISTEND).
    func commitListStagingBuffer(serverId: String) {
        let entries = listStagingBuffer.removeValue(forKey: serverId) ?? []
        channelListCache[serverId] = CachedChannelList(entries: entries, fetchedAt: Date())
    }

    // MARK: - Explicit disconnect tracking
    var explicitlyDisconnectedServerIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "explicitDisconnects") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "explicitDisconnects") }
    }

    // MARK: - Last-foregrounded connected servers
    func saveConnectedServerIds() {
        let ids = connections.keys.filter { connectionStates[$0] == .connected }
        UserDefaults.standard.set(Array(ids), forKey: "lastConnectedServerIds")
    }
    var lastConnectedServerIds: [String] {
        UserDefaults.standard.stringArray(forKey: "lastConnectedServerIds") ?? []
    }

    func getClient(for serverId: String) -> IRCClient? {
        return connections[serverId]
    }
    
    private var reconnectTimers: [String: Timer] = [:]
    private var reconnectAttempts: [String: Int] = [:]
    private var maxReconnectAttempts = 5

    /// Fires the server ID every time a connection is (re)established.
    /// ChannelViewModel subscribes so it can re-register callbacks and re-fetch history.
    let reconnectSubject = PassthroughSubject<String, Never>()
    
    private init() {}

    // MARK: - Connection State
    
    func connectionState(for serverId: String) -> ConnectionState {
        connectionStates[serverId] ?? .disconnected
    }
    
    func isConnected(serverId: String) -> Bool {
        return connectionStates[serverId] == .connected
    }
    
    // MARK: - Connection Management
    
    func connect(to server: Server) async throws {
        // Remove from explicit-disconnect set — user is re-connecting
        var explicit = explicitlyDisconnectedServerIds
        explicit.remove(server.id)
        explicitlyDisconnectedServerIds = explicit

        connectionStates[server.id] = .connecting
        
        let client = IRCClient()
        
        client.onWelcome = { [weak self] nick in
            Task { @MainActor in
                self?.currentNicknames[server.id] = nick
                self?.connectionStates[server.id] = .connected
                self?.reconnectAttempts[server.id] = 0  // reset on successful connect
                // Notify subscribers (e.g. ChannelViewModel) that connection is live
                self?.reconnectSubject.send(server.id)
                // Request CHATHISTORY for all joined channels
                if let self, let client = self.connections[server.id] {
                    await self.requestHistoryAfterReconnect(serverId: server.id, client: client)
                }
            }
        }

        // Wire LIST callbacks to populate cache
        client.onListEntry = { [weak self] name, count, topic in
            Task { @MainActor in
                guard let self else { return }
                let entry = CachedListEntry(name: name, members: count, topic: topic)
                self.listStagingBuffer[server.id, default: []].append(entry)
            }
        }
        client.onListEnd = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let entries = self.listStagingBuffer.removeValue(forKey: server.id) ?? []
                self.channelListCache[server.id] = CachedChannelList(entries: entries, fetchedAt: Date())
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
            let nickname = server.nickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : server.nickname
            
            try await client.connect(
                host: server.host,
                port: server.port,
                tls: server.ssl,
                nickname: nickname,
                username: server.realname.isEmpty ? "parso" : server.realname,
                realname: server.realname.isEmpty ? "Parso IRC" : server.realname,
                serverPassword: server.password,
                useSASL: server.saslEnabled,
                saslPassword: server.password
            )
            
            connections[server.id] = client
            
            // Only join channels the user explicitly joined (joinedAt != nil)
            for channel in server.channels where channel.joinedAt != nil {
                try await client.join(channel: channel.name)
            }
            
        } catch {
            connectionStates[server.id] = .failed(IRCError.connectionFailed(error.localizedDescription))
            throw error
        }
    }
    
    func connectWithHistory(to server: Server, onConnected: ((String, String) -> Void)? = nil) async throws {
        connectionStates[server.id] = .connecting
        
        let client = IRCClient()
        
        client.onWelcome = { [weak self] nick in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentNicknames[server.id] = nick
                self.connectionStates[server.id] = .connected
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
            let nickname = server.nickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : server.nickname
            
            try await client.connect(
                host: server.host,
                port: server.port,
                tls: server.ssl,
                nickname: nickname,
                username: server.realname.isEmpty ? "parso" : server.realname,
                realname: server.realname.isEmpty ? "Parso IRC" : server.realname,
                serverPassword: server.password,
                useSASL: server.saslEnabled,
                saslPassword: server.password
            )
            
            connections[server.id] = client
            
            for channel in server.channels {
                try await client.join(channel: channel.name)
            }
            
            try await Task.sleep(nanoseconds: 500_000_000)
            
            if await client.hasChathistorySupport() {
                let targetChannel = server.lastActiveChannel ?? server.channels.first?.name ?? ""
                if !targetChannel.isEmpty {
                    let limit = await client.getChathistoryLimit()
                    try await client.requestHistory(target: targetChannel, limit: limit)
                }
            }
            
            if let callback = onConnected {
                let targetChannel = server.lastActiveChannel ?? server.channels.first?.name ?? ""
                callback(server.id, targetChannel)
            }
            
        } catch {
            connectionStates[server.id] = .failed(IRCError.connectionFailed(error.localizedDescription))
            throw error
        }
    }
    
    func disconnect(from serverId: String) {
        reconnectTimers[serverId]?.invalidate()
        reconnectTimers[serverId] = nil

        // Track as explicitly disconnected so auto-connect won't reconnect it
        var explicit = explicitlyDisconnectedServerIds
        explicit.insert(serverId)
        explicitlyDisconnectedServerIds = explicit
        
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
        let attempts = reconnectAttempts[serverId, default: 0]
        
        guard attempts < maxReconnectAttempts else {
            connectionStates[serverId] = .failed(IRCError.maxReconnectAttemptsReached)
            reconnectAttempts[serverId] = 0
            return
        }
        
        connectionStates[serverId] = .reconnecting
        reconnectAttempts[serverId] = attempts + 1

        // Attempt 0 is instant (0s), then 1s, 2s, 4s, 8s
        let delay: Double = attempts == 0 ? 0 : pow(2.0, Double(attempts - 1))
        
        reconnectTimers[serverId]?.invalidate()

        if delay == 0 {
            // Reconnect immediately in a new Task — no Timer overhead
            Task { @MainActor [weak self] in
                if let server = try? DatabaseManager.shared.fetchServers().first(where: { $0.id == serverId }) {
                    try? await self?.connect(to: server)
                }
            }
        } else {
            reconnectTimers[serverId] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    if let server = try? DatabaseManager.shared.fetchServers().first(where: { $0.id == serverId }) {
                        try? await self?.connect(to: server)
                    }
                }
            }
        }
    }
    
    // MARK: - Keepalive ping

    /// Sends a PING to every connected server. Called from the background
    /// refresh task and WatchManager to keep sockets alive.
    func pingAllServers() async {
        for (_, client) in connections {
            try? await client.send_raw("PING :parso-keepalive")
        }
    }

    // MARK: - Post-reconnect history fetch

    /// Requests CHATHISTORY for every explicitly-joined channel on `serverId`
    /// after a (re)connection. Called from onWelcome so it covers both fresh
    /// connects and auto-reconnects seamlessly.
    private func requestHistoryAfterReconnect(serverId: String, client: IRCClient) async {
        guard await client.hasChathistorySupport() else { return }
        let channels = (try? DatabaseManager.shared.fetchChannels(forServer: serverId)) ?? []
        let limit = min(await client.getChathistoryLimit(), 100)
        for channel in channels where channel.joinedAt != nil && !channel.isDM {
            try? await client.requestHistory(target: channel.name, limit: limit)
            // Small gap between requests to avoid flooding the server
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s
        }
    }

    // MARK: - Background refresh (BGAppRefreshTask handler)

    /// Apple-recommended background refresh:
    /// 1. Reconnect any dropped servers
    /// 2. PING to keep the socket alive
    /// 3. Fetch new messages for watched channels via CHATHISTORY timestamp anchor
    /// 4. Fire a local mention notification if the user's nick appeared while away
    func performBackgroundRefresh() async {
        let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
        let explicit = explicitlyDisconnectedServerIds

        for server in servers where !explicit.contains(server.id) {
            // Step 1: Reconnect if the socket died while backgrounded
            let state = connectionStates[server.id]
            if state == .disconnected {
                try? await connect(to: server)
                // Wait up to 10 s for the connection
                for _ in 0..<100 {
                    if connectionStates[server.id] == .connected { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            guard connectionStates[server.id] == .connected,
                  let client = connections[server.id] else { continue }

            // Step 2: Keep the socket alive
            try? await client.send_raw("PING :parso-background")

            // Step 3 & 4: Fetch new messages, check for mentions
            guard await client.hasChathistorySupport() else { continue }
            let watchedChannels = (try? DatabaseManager.shared.getWatchedChannels())?
                .filter { $0.serverId == server.id } ?? []
            let limit = min(await client.getChathistoryLimit(), 50)
            let myNick = currentNicknames[server.id] ?? server.nickname

            for channel in watchedChannels {
                let since = channel.lastCheckedAt ?? Date(timeIntervalSinceNow: -3600)
                try? await client.requestHistorySince(since, target: channel.name, limit: limit)
                // Give the server time to deliver the batch before we query the DB
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s

                let recent = (try? DatabaseManager.shared.fetchMessagesSince(since, channelId: channel.id)) ?? []
                let mentions = recent.filter {
                    !myNick.isEmpty && $0.content.localizedCaseInsensitiveContains(myNick)
                }
                if !mentions.isEmpty, let first = mentions.first {
                    await NotificationManager.shared.sendMentionNotification(
                        channel: channel, message: first, count: mentions.count
                    )
                }

                try? DatabaseManager.shared.updateChannelLastChecked(channelId: channel.id, date: Date())
                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 s gap between channels
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
        let parts = trimmed.split(separator: " ", maxSplits: 1)
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
                // Fire watch notification if the target channel is watched
                await self.maybeNotify(serverId: serverId, ircMessage: message)
            }
        }
    }

    // MARK: - Watch notifications

    private func maybeNotify(serverId: String, ircMessage: IRCMessage) async {
        guard ircMessage.command == "PRIVMSG" else { return }
        let target = ircMessage.parameters.first ?? ""
        guard target.hasPrefix("#") || target.hasPrefix("&") else { return }

        // Look up channel in DB
        guard let channel = (try? DatabaseManager.shared.fetchChannels(forServer: serverId))
                .flatMap({ $0 })?.first(where: { $0.name.lowercased() == target.lowercased() }),
              channel.isWatched else { return }

        let nick = ircMessage.source?.nick ?? "someone"
        let body = ircMessage.parameters.count > 1 ? ircMessage.parameters[1] : ""
        let msg = Message(channelId: channel.id, sender: nick, content: body)
        await NotificationManager.shared.sendWatchNotification(channel: channel, message: msg)
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