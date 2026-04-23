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
        let count = unreadCounts[channelId] ?? 0
        try? DatabaseManager.shared.updateChannelUnreadCount(channelId: channelId, count: count)
    }
    func clearUnread(channelId: String) {
        unreadCounts[channelId] = 0
        try? DatabaseManager.shared.updateChannelUnreadCount(channelId: channelId, count: 0)
    }

    func restorePersistedUnreadCounts() {
        guard let servers = try? DatabaseManager.shared.fetchServers() else { return }
        for server in servers {
            if let channels = try? DatabaseManager.shared.fetchChannels(forServer: server.id) {
                for ch in channels where ch.unreadCount > 0 {
                    unreadCounts[ch.id] = ch.unreadCount
                }
            }
        }
    }

    // MARK: - Combine fan-out subjects (per server)
    //
    // These are permanent — registered once in connect(to:) and never overwritten.
    // ChannelViewModel subscribes via messagePublisher/eventPublisher instead of
    // writing directly to IRCClient.onXxx slots (which are single-slot and would
    // be overwritten on every channel switch, dropping messages for other channels).

    private var messageSubjects: [String: PassthroughSubject<IRCMessage, Never>] = [:]
    private var eventSubjects:   [String: PassthroughSubject<IRCEvent,   Never>] = [:]

    /// Server-level notices (NickServ, MemoServ, etc.) buffered while no channel
    /// view is open.  Drained into the first ChannelViewModel that registers.
    private var serverNoticeBuffer: [String: [IRCMessage]] = [:]
    private let serverNoticeBufferMax = 30

    /// Published so `ServerSidebarView` can observe when a channel is joined or left
    /// and reload the channel list without requiring a full reconnect event.
    @Published private(set) var channelMembershipVersion: Int = 0

    /// Published so ServerSidebarView can observe when new DM channels are created.
    @Published private(set) var dmChannelIds: Set<String> = []

    /// Leaves a channel: sends PART, clears `joinedAt` in the DB, clears unread,
    /// and bumps `channelMembershipVersion` so the sidebar reloads.
    func leaveChannel(_ channelName: String, serverId: String) {
        Task {
            guard let client = connections[serverId] else { return }
            try? await client.leave(channel: channelName)
            // Clear joinedAt so the channel isn't auto-rejoined on next connect
            if let ch = (try? DatabaseManager.shared.fetchChannels(forServer: serverId))?
                .first(where: { $0.name.lowercased() == channelName.lowercased() }) {
                var updated = ch
                updated.joinedAt = nil
                try? DatabaseManager.shared.saveChannel(updated, serverId: serverId)
                clearUnread(channelId: ch.id)
                // Invalidate cache so a re-join picks up the fresh DB record
                channelCache.removeValue(forKey: "\(serverId):\(channelName.lowercased())")
            }
            await MainActor.run {
                self.channelMembershipVersion += 1
            }
        }
    }

    func messagePublisher(for serverId: String) -> AnyPublisher<IRCMessage, Never> {
        (messageSubjects[serverId] ?? PassthroughSubject()).eraseToAnyPublisher()
    }
    func eventPublisher(for serverId: String) -> AnyPublisher<IRCEvent, Never> {
        (eventSubjects[serverId] ?? PassthroughSubject()).eraseToAnyPublisher()
    }
    /// Atomically drains buffered server notices for `serverId`.
    func drainServerNotices(for serverId: String) -> [IRCMessage] {
        let buf = serverNoticeBuffer[serverId] ?? []
        serverNoticeBuffer[serverId] = []
        return buf
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

    func appendToListStagingBuffer(serverId: String, entry: CachedListEntry) {
        listStagingBuffer[serverId, default: []].append(entry)
    }

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
        guard !IRCClientManager.isDemoServer(serverId) else { return nil }
        return connections[serverId]
    }
    
    private var reconnectTimers: [String: Timer] = [:]
    private var reconnectAttempts: [String: Int] = [:]
    private var maxReconnectAttempts = 5

    /// In-memory cache: "serverId:channelname.lowercased()" → Channel
    /// Populated at connect time and kept updated on join/part.
    /// Eliminates the per-message fetchChannels(forServer:) DB query that was
    /// causing O(N) DB reads at the message receive rate — a primary contributor
    /// to the 12-hour watchdog crash.
    private var channelCache: [String: Channel] = [:]

    /// Timestamp of the last maybeNotify Task spawned per channel ID.
    /// Used to rate-limit notification Tasks to at most 1/second per channel,
    /// preventing unbounded Task accumulation on busy channels.
    private var lastNotifyDate: [String: Date] = [:]

    /// Fires the server ID every time a connection is (re)established.
    /// ChannelViewModel subscribes so it can re-subscribe to the new subjects.
    let reconnectSubject = PassthroughSubject<String, Never>()
    
    private init() {}

    // MARK: - Connection State
    
    func connectionState(for serverId: String) -> ConnectionState {
        connectionStates[serverId] ?? .disconnected
    }
    
    func isConnected(serverId: String) -> Bool {
        return connectionStates[serverId] == .connected
    }

    // MARK: - Demo server helpers

    /// Returns true when `serverId` is the local demo server that never makes
    /// a real TCP connection.
    static func isDemoServer(_ serverId: String) -> Bool {
        serverId == DemoContent.serverId
    }

    // MARK: - Open / create a DM thread

    /// Returns (or creates) a DM channel for `nick` on `serverId`.
    /// Saves to the DB and fires `dmChannelIds` so the sidebar reloads.
    @discardableResult
    func openOrCreateDM(with nick: String, serverId: String) -> Channel {
        let dbChannels = (try? DatabaseManager.shared.fetchChannels(forServer: serverId)) ?? []
        if let existing = dbChannels.first(where: { $0.name == nick && $0.isDM }) {
            dmChannelIds.insert(existing.id)
            return existing
        }
        var ch = Channel(serverId: serverId, name: nick)
        ch.isDM = true
        try? DatabaseManager.shared.saveChannel(ch, serverId: serverId)
        dmChannelIds.insert(ch.id)
        return ch
    }
    
    // MARK: - Connection Management
    
    func connect(to server: Server) async throws {
        // ── Demo server: no real TCP connection needed ──────────────────────
        if IRCClientManager.isDemoServer(server.id) {
            var explicit = explicitlyDisconnectedServerIds
            explicit.remove(server.id)
            explicitlyDisconnectedServerIds = explicit

            connectionStates[server.id] = .connected
            currentNicknames[server.id] = DemoContent.nick
            // Create stub subjects so publishers don't crash (nobody sends on them)
            messageSubjects[server.id] = PassthroughSubject()
            eventSubjects[server.id]   = PassthroughSubject()
            reconnectSubject.send(server.id)
            return
        }

        var explicit = explicitlyDisconnectedServerIds
        explicit.remove(server.id)
        explicitlyDisconnectedServerIds = explicit

        connectionStates[server.id] = .connecting
        
        // Create fresh subjects for this connection
        let msgSubject   = PassthroughSubject<IRCMessage, Never>()
        let evtSubject   = PassthroughSubject<IRCEvent,   Never>()
        messageSubjects[server.id]  = msgSubject
        eventSubjects[server.id]    = evtSubject
        serverNoticeBuffer[server.id] = []
        
        let client = IRCClient()
        
        // ── Permanent welcome / lifecycle callbacks ──────────────────────────
        client.onWelcome = { [weak self] nick in
            Task { @MainActor in
                self?.currentNicknames[server.id] = nick
                self?.connectionStates[server.id] = .connected
                self?.reconnectAttempts[server.id] = 0
                self?.reconnectSubject.send(server.id)
            }
        }

        client.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect(serverId: server.id)
            }
        }
        
        client.onError = { [weak self] error in
            Task { @MainActor in
                self?.connectionStates[server.id] = .failed(
                    IRCError.connectionFailed(error.localizedDescription))
            }
        }

        // ── LIST callbacks (channel browser) ────────────────────────────────
        client.onListEntry = { [weak self] name, count, topic in
            Task { @MainActor in
                guard let self else { return }
                self.listStagingBuffer[server.id, default: []].append(
                    CachedListEntry(name: name, members: count, topic: topic))
            }
        }
        client.onListEnd = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let entries = self.listStagingBuffer.removeValue(forKey: server.id) ?? []
                self.channelListCache[server.id] = CachedChannelList(entries: entries, fetchedAt: Date())
            }
        }

        // ── Permanent fan-out callbacks ──────────────────────────────────────
        //
        // These are registered ONCE per connection.  They never get overwritten
        // because nothing else (ChannelViewModel, etc.) writes to these slots.
        // ChannelViewModel subscribes to the Combine subjects instead.

        client.onMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self else { return }
                self.handleIncomingMessage(msg, serverId: server.id)

                // Don't re-broadcast the server's echo of our own outgoing messages.
                // ChannelViewModel.send() already appends them optimistically, so
                // broadcasting the echo causes a duplicate second bubble.
                // History replay messages (tagged with @batch=…) must still fan out.
                let myNick = self.currentNicknames[server.id] ?? ""
                let senderNick = msg.source?.nick ?? ""
                let isOwnEcho = !myNick.isEmpty
                    && senderNick.lowercased() == myNick.lowercased()
                    && msg.tags?["batch"] == nil

                if !isOwnEcho {
                    msgSubject.send(msg)
                }
            }
        }

        client.onHistoryMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self else { return }
                self.handleIncomingMessage(msg, serverId: server.id)
                msgSubject.send(msg)
            }
        }

        client.onJoin = { [weak self] channel, nick in
            Task { @MainActor in
                evtSubject.send(.join(channel: channel, nick: nick))
            }
        }
        client.onPart = { [weak self] channel, nick, reason in
            Task { @MainActor in
                evtSubject.send(.part(channel: channel, nick: nick, reason: reason))
            }
        }
        client.onQuit = { [weak self] nick, reason in
            Task { @MainActor in
                evtSubject.send(.quit(nick: nick, reason: reason))
            }
        }
        client.onNickChange = { [weak self] old, new in
            Task { @MainActor in
                self?.currentNicknames[server.id] = {
                    // If this is our own nick change, update the manager's tracking
                    if self?.currentNicknames[server.id] == old { return new }
                    return self?.currentNicknames[server.id] ?? new
                }()
                evtSubject.send(.nickChange(oldNick: old, newNick: new))
            }
        }
        client.onTopicChange = { [weak self] channel, topic, by in
            Task { @MainActor in
                evtSubject.send(.topicChange(channel: channel, topic: topic, byNick: by))
            }
        }
        client.onNamesList = { [weak self] channel, nicks in
            Task { @MainActor in
                evtSubject.send(.namesList(channel: channel, nicks: nicks))
            }
        }
        client.onEndOfNames = { [weak self] channel in
            Task { @MainActor in
                evtSubject.send(.endOfNames(channel: channel))
            }
        }
        client.onKick = { [weak self] channel, kicked, by, reason in
            Task { @MainActor in
                evtSubject.send(.kick(channel: channel, kicked: kicked, by: by, reason: reason))
            }
        }
        client.onMode = { [weak self] target, mode, params in
            Task { @MainActor in
                evtSubject.send(.mode(target: target, modeString: mode, params: params))
            }
        }
        client.onChathistoryBatchEnd = { [weak self] in
            Task { @MainActor in
                evtSubject.send(.chathistoryBatchEnd)
            }
        }
        client.onZncBatchEnd = { [weak self] in
            Task { @MainActor in
                evtSubject.send(.zncBatchEnd)
            }
        }
        client.onUnhandledMessage = { [weak self] msg in
            Task { @MainActor in
                // 332 RPL_TOPIC — parse and surface as a typed event
                if msg.command == "332", msg.parameters.count >= 3 {
                    evtSubject.send(.initialTopic(channel: msg.parameters[1], topic: msg.parameters[2]))
                }
                evtSubject.send(.unhandled(msg))
            }
        }

        // ── Perform the TCP connection ────────────────────────────────────────
        do {
            let nickname = server.nickname.isEmpty
                ? "parso\(Int.random(in: 1000...9999))"
                : server.nickname
            
            try await client.connect(
                host: server.host,
                port: server.port,
                tls: server.ssl,
                nickname: nickname,
                username: server.realname.isEmpty ? "parso" : server.realname,
                realname: server.realname.isEmpty ? "Parso IRC" : server.realname,
                serverPassword: server.useConnectionPassword ? server.password : nil,
                useSASL: server.saslEnabled,
                saslPassword: server.password
            )
            
            connections[server.id] = client

            // Seed the channel ID cache from persisted channels.
            // This replaces per-message fetchChannels(forServer:) DB reads with
            // an O(1) dictionary lookup for the lifetime of the connection.
            if let channels = try? DatabaseManager.shared.fetchChannels(forServer: server.id) {
                for ch in channels {
                    channelCache["\(server.id):\(ch.name.lowercased())"] = ch
                }
            }

            for channel in server.channels where channel.joinedAt != nil {
                try await client.join(channel: channel.name)
            }
            
        } catch {
            connectionStates[server.id] = .failed(IRCError.connectionFailed(error.localizedDescription))
            throw error
        }
    }
    
    func connectWithHistory(to server: Server, onConnected: ((String, String) -> Void)? = nil) async throws {
        // Delegate to the canonical connect() so fan-out subjects are always created
        try await connect(to: server)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        if let client = connections[server.id], await client.hasChathistorySupport() {
            let targetChannel = server.lastActiveChannel ?? server.channels.first?.name ?? ""
            if !targetChannel.isEmpty {
                let limit = await client.getChathistoryLimit()
                try? await client.requestHistory(target: targetChannel, limit: limit)
            }
        }
        
        if let callback = onConnected {
            let targetChannel = server.lastActiveChannel ?? server.channels.first?.name ?? ""
            callback(server.id, targetChannel)
        }
    }
    
    func disconnect(from serverId: String) {
        // Demo server: just flip state, no real socket
        if IRCClientManager.isDemoServer(serverId) {
            connectionStates[serverId] = .disconnected
            messageSubjects.removeValue(forKey: serverId)
            eventSubjects.removeValue(forKey: serverId)
            return
        }

        reconnectTimers[serverId]?.invalidate()
        reconnectTimers[serverId] = nil

        var explicit = explicitlyDisconnectedServerIds
        explicit.insert(serverId)
        explicitlyDisconnectedServerIds = explicit

        // Tear down subjects so subscribers complete cleanly
        messageSubjects.removeValue(forKey: serverId)
        eventSubjects.removeValue(forKey: serverId)
        serverNoticeBuffer.removeValue(forKey: serverId)

        // Evict channel cache and list buffers for this server
        channelCache = channelCache.filter { !$0.key.hasPrefix(serverId + ":") }
        listStagingBuffer.removeValue(forKey: serverId)
        channelListCache.removeValue(forKey: serverId)

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

    func reconnectAllIfNeeded() {
        let explicit = explicitlyDisconnectedServerIds
        let lastConnected = lastConnectedServerIds
        Task { @MainActor in
            guard let servers = try? DatabaseManager.shared.fetchServers() else { return }
            for server in servers {
                guard !explicit.contains(server.id) else { continue }
                let state = connectionStates[server.id]
                let shouldReconnect = server.autoConnect || lastConnected.contains(server.id)
                if (state == .disconnected || state == nil) && shouldReconnect {
                    try? await self.connect(to: server)
                }
            }
        }
    }
    
    private func handleDisconnect(serverId: String) {
        // Demo server never actually disconnects
        guard !IRCClientManager.isDemoServer(serverId) else { return }
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

        let delay: Double = attempts == 0 ? 0 : pow(2.0, Double(attempts - 1))
        
        reconnectTimers[serverId]?.invalidate()

        if delay == 0 {
            Task { @MainActor [weak self] in
                if let server = try? DatabaseManager.shared.fetchServers().first(where: { $0.id == serverId }) {
                    try? await self?.connect(to: server)
                }
            }
        } else {
            // Explicitly add to RunLoop.main so the timer fires reliably even
            // when scheduleReconnect is called from a non-main-thread context
            // (e.g. a background Task).  Timer.scheduledTimer schedules on the
            // *current* RunLoop, which may not be the main RunLoop — if that
            // thread exits the timer silently never fires, leaving the server
            // permanently disconnected until the next app foreground.
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    if let server = try? DatabaseManager.shared.fetchServers()
                        .first(where: { $0.id == serverId }) {
                        try? await self?.connect(to: server)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            reconnectTimers[serverId] = timer
        }
    }

    // MARK: - Incoming message handling (fan-out + persistence)
    //
    // Called for every PRIVMSG / NOTICE / history message on every server.
    // Persists to DB so messages are available even when no ChatView is open.

    private func handleIncomingMessage(_ msg: IRCMessage, serverId: String) {
        let target = msg.parameters.first ?? ""
        let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
            || target.hasPrefix("!") || target.hasPrefix("+")
        let body = msg.parameters.count > 1 ? msg.parameters[1] : ""
        let nick = msg.source?.nick ?? "server"
        let myNick = currentNicknames[serverId] ?? ""

        guard isChannel else {
            // Server-targeted notice (NickServ, MemoServ, server NOTICE).
            // Buffer it so the next channel that opens will display it.
            var buf = serverNoticeBuffer[serverId] ?? []
            buf.append(msg)
            if buf.count > serverNoticeBufferMax { buf.removeFirst() }
            serverNoticeBuffer[serverId] = buf
            return
        }

        // Look up channel by name using the in-memory cache (O(1)).
        // Falls back to a DB read only if the cache misses (e.g. a channel
        // joined after connect), and then updates the cache for next time.
        let cacheKey = "\(serverId):\(target.lowercased())"
        var channel: Channel
        if let cached = channelCache[cacheKey] {
            channel = cached
        } else if let fetched = (try? DatabaseManager.shared.fetchChannels(forServer: serverId))?
                    .first(where: { $0.name.lowercased() == target.lowercased() }) {
            channelCache[cacheKey] = fetched
            channel = fetched
        } else {
            return
        }

        let isAction = body.hasPrefix("\u{0001}ACTION ") && body.hasSuffix("\u{0001}")
        let content  = isAction ? String(body.dropFirst(8).dropLast()) : body
        let isOwnMsg = nick.lowercased() == myNick.lowercased()

        // Persist messages from others — moved off @MainActor via a detached Task
        // (Fix E) so the heavy SQLite write never blocks the SwiftUI render loop.
        // Own messages are persisted by send() on success.
        if !isOwnMsg {
            let message = Message(
                channelId: channel.id,
                sender: nick,
                senderHost: msg.source?.host,
                content: content,
                type: isAction ? .action : (msg.command == "NOTICE" ? .notice : .message),
                isFromCurrentUser: false
            )
            Task.detached(priority: .utility) {
                try? DatabaseManager.shared.saveMessage(message)
            }

            // Increment unread for channels not currently active (main-actor work — fine)
            if AppState.shared.selectedChannelId != channel.id {
                incrementUnread(channelId: channel.id)
            }
        }

        // Fire watch notification if applicable — rate-limited to at most
        // 1 Task per channel per second to prevent unbounded Task accumulation
        // on high-traffic channels (a compounding factor in the 12-hour crash).
        let channelId = channel.id
        let now = Date()
        if now.timeIntervalSince(lastNotifyDate[channelId] ?? .distantPast) >= 1.0 {
            lastNotifyDate[channelId] = now
            Task { await maybeNotify(serverId: serverId, ircMessage: msg, cachedChannel: channel) }
        }
    }

    // MARK: - Keepalive ping

    func pingAllServers() async {
        for (_, client) in connections {
            try? await client.send_raw("PING :parso-keepalive")
        }
    }

    // MARK: - Background refresh (BGAppRefreshTask handler)

    func performBackgroundRefresh() async {
        // Prune old messages once per background refresh so the DB doesn't grow
        // unboundedly (cleanupOldMessages deletes rows older than 7 days).
        try? DatabaseManager.shared.cleanupOldMessages()

        let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
        let explicit = explicitlyDisconnectedServerIds

        for server in servers where !explicit.contains(server.id) {
            // Never attempt a real network connection for the demo server
            if IRCClientManager.isDemoServer(server.id) { continue }
            let state = connectionStates[server.id]
            if state == .disconnected {
                try? await connect(to: server)
                for _ in 0..<100 {
                    if connectionStates[server.id] == .connected { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            guard connectionStates[server.id] == .connected,
                  let client = connections[server.id] else { continue }

            try? await client.send_raw("PING :parso-background")

            guard await client.hasChathistorySupport() else { continue }
            let watchedChannels = (try? DatabaseManager.shared.getWatchedChannels())?
                .filter { $0.serverId == server.id } ?? []
            let limit = min(await client.getChathistoryLimit(), 50)
            let myNick = currentNicknames[server.id] ?? server.nickname

            for channel in watchedChannels {
                let since = channel.lastCheckedAt ?? Date(timeIntervalSinceNow: -3600)
                try? await client.requestHistorySince(since, target: channel.name, limit: limit)
                try? await Task.sleep(nanoseconds: 500_000_000)

                let recent = (try? DatabaseManager.shared.fetchMessagesSince(since, channelId: channel.id)) ?? []
                let mentions = recent.filter {
                    !myNick.isEmpty && $0.content.localizedCaseInsensitiveContains(myNick)
                }
                if !mentions.isEmpty, let first = mentions.first {
                    await NotificationManager.shared.sendMentionNotification(
                        channel: channel, message: first, count: mentions.count)
                }

                try? DatabaseManager.shared.updateChannelLastChecked(channelId: channel.id, date: Date())
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    // MARK: - Message Sending
    
    func sendMessage(_ content: String, to channel: String, on serverId: String) async throws {
        // Demo server: ChannelViewModel handles bot replies internally
        if IRCClientManager.isDemoServer(serverId) { return }

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
        if IRCClientManager.isDemoServer(serverId) { return }
        guard let client = connections[serverId] else {
            throw IRCError.notConnected
        }
        try await client.sendMessage(content, to: nick)
    }
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: String, channel: String, serverId: String) async throws {
        if IRCClientManager.isDemoServer(serverId) { return }
        guard let client = connections[serverId] else {
            throw IRCError.notConnected
        }
        
        let parts = command.dropFirst().split(separator: " ", maxSplits: 1)
        let cmd = String(parts.first ?? "").lowercased()
        let args = parts.count > 1 ? String(parts[1]) : ""
        
        switch cmd {
        case "nick":
            let newNick = args.isEmpty
                ? command.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                : args
            try await client.send(command: "NICK", parameters: [newNick])
            
        case "join":
            let channels = args.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            for chan in channels {
                try await client.join(channel: chan)
            }
            
        case "part", "leave":
            let chan = args.isEmpty
                ? channel
                : args.split(separator: " ").first.map(String.init) ?? channel
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
            try await client.send(command: "MODE",
                                  parameters: args.split(separator: " ").map(String.init))
            
        case "kick":
            let kparts = args.split(separator: " ")
            if let nick = kparts.first {
                let reason = kparts.dropFirst().joined(separator: " ")
                try await client.send(command: "KICK",
                                      parameters: [channel, String(nick), reason])
            }
            
        case "invite":
            let iparts = args.split(separator: " ")
            if let nick = iparts.first {
                try await client.send(command: "INVITE",
                                      parameters: [String(nick), channel])
            }
            
        case "whois":
            try await client.send(command: "WHOIS", parameters: [args])
            
        case "msg":
            let mparts = args.split(separator: " ", maxSplits: 1)
            if let target = mparts.first, let message = mparts.last {
                try await client.sendMessage(String(message), to: String(target))
            }
            
        case "list":
            try await client.send(command: "LIST", parameters: args.isEmpty ? [] : [args])
            
        case "names":
            try await client.send(command: "NAMES", parameters: [channel])
            
        case "who":
            try await client.send(command: "WHO",
                                  parameters: [args.isEmpty ? channel : args])
            
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

    // MARK: - Watch notifications

    private func maybeNotify(serverId: String, ircMessage: IRCMessage, cachedChannel: Channel? = nil) async {
        guard ircMessage.command == "PRIVMSG" else { return }
        let target = ircMessage.parameters.first ?? ""
        guard target.hasPrefix("#") || target.hasPrefix("&") else { return }

        // Use the pre-fetched channel from handleIncomingMessage to avoid a
        // second full fetchChannels(forServer:) DB scan on every message.
        let channel: Channel
        if let cached = cachedChannel {
            channel = cached
        } else if let fetched = (try? DatabaseManager.shared.fetchChannels(forServer: serverId))
                    .flatMap({ $0 })?.first(where: { $0.name.lowercased() == target.lowercased() }) {
            channel = fetched
        } else {
            return
        }
        guard channel.isWatched else { return }

        let nick = ircMessage.source?.nick ?? "someone"
        let body = ircMessage.parameters.count > 1 ? ircMessage.parameters[1] : ""
        let msg = Message(channelId: channel.id, sender: nick, content: body)
        await NotificationManager.shared.sendWatchNotification(channel: channel, message: msg)
    }

    // MARK: - Legacy event listener wrappers
    //
    // These exist so callers that used the old manager-level onXxx(serverId:handler:)
    // API still compile.  New code should use messagePublisher/eventPublisher instead.

    func onMessage(serverId: String, handler: @escaping (IRCMessage) -> Void) {
        // No-op: messages are now published via messagePublisher(for:)
        _ = messagePublisher(for: serverId)
    }

    func onJoin(serverId: String, handler: @escaping (String, String) -> Void) {}
    func onPart(serverId: String, handler: @escaping (String, String, String?) -> Void) {}
    func onQuit(serverId: String, handler: @escaping (String, String?) -> Void) {}
    func onNickChange(serverId: String, handler: @escaping (String, String) -> Void) {}
    func onTopicChange(serverId: String, handler: @escaping (String, String, String) -> Void) {}
    func onNamesList(serverId: String, handler: @escaping (String, [String]) -> Void) {}
}
