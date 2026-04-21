import Foundation
import SwiftUI
import Combine

/// The view model for a single channel (or DM thread).
///
/// Subscribes to `IRCClientManager.messagePublisher` and `.eventPublisher` via
/// Combine instead of writing directly to `IRCClient.onXxx` slots.  This means
/// messages for every joined channel are processed by the manager at all times,
/// and multiple `ChannelViewModel` instances can coexist without overwriting
/// each other's callbacks.
///
/// All mutation happens on the `@MainActor` — SwiftUI can safely bind to
/// every `@Published` property without extra hops.
@MainActor
final class ChannelViewModel: ObservableObject {

    // MARK: - Public state

    /// Fully processed messages ready for `MessageListView`.
    @Published private(set) var displayMessages: [DisplayMessage] = []

    /// Current channel topic.
    @Published private(set) var topic: String = ""

    /// The first URL found in the channel topic, if any (used for "Rules" button).
    /// Updated only when topic changes — not recomputed on every render.
    @Published private(set) var rulesURL: URL? = nil

    let serverId: String
    let channelName: String   // e.g. "#linux"

    // MARK: - Private

    private let ircManager: IRCClientManager
    private var rawMessages: [Message] = []
    private var seenMessageIds: Set<String> = []
    private let _cachedChannelId: String
    /// Combine cancellables — holds message/event subscriptions.
    private var cancellables = Set<AnyCancellable>()
    /// Counts history messages arriving in a single batch (for the separator line).
    private var pendingHistoryMessageCount: Int = 0

    // MARK: - Init

    init(serverId: String, channelName: String, ircManager: IRCClientManager) {
        self.serverId = serverId
        self.channelName = channelName
        self.ircManager = ircManager
        self.currentNick = ircManager.currentNicknames[serverId] ?? ""
        self._cachedChannelId = (try? DatabaseManager.shared.fetchChannels(forServer: serverId)
            .first { $0.name == channelName }?.id)
            ?? "\(serverId):\(channelName)"
    }

    // MARK: - Lifecycle (called from ChatView .task)

    func start() async {
        currentNick = ircManager.currentNicknames[serverId] ?? ""
        await loadPersistedMessages()
        registerSubscriptions()
        await requestNamesIfNeeded()
        // CHATHISTORY is triggered by the .endOfNames event when 366 arrives —
        // that is the only safe time to send CHATHISTORY after a JOIN.
    }

    /// Tear down Combine subscriptions.  The manager's permanent IRCClient
    /// callbacks are NOT touched — they continue running for all channels.
    func stop() {
        cancellables.removeAll()
    }

    // MARK: - Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedNick = ircManager.currentNicknames[serverId] ?? currentNick
        let outgoing = Message(
            channelId: channelId,
            sender: resolvedNick.isEmpty ? currentNick : resolvedNick,
            content: trimmed.hasPrefix("/me ") ? String(trimmed.dropFirst(4)) : trimmed,
            type: trimmed.hasPrefix("/me ") ? .action : .message,
            isFromCurrentUser: true
        )
        // Optimistic append — not persisted until send succeeds
        append(outgoing, persist: false)
        HapticManager.lightImpact()
        Task {
            do {
                try await ircManager.sendMessage(trimmed, to: channelName, on: serverId)
                if !failedMessageIds.contains(outgoing.id) {
                    try? DatabaseManager.shared.saveMessage(outgoing)
                }
            } catch {
                failedMessageIds.insert(outgoing.id)
                rebuildDisplay()
            }
        }
    }

    func retrySend(message: Message) {
        failedMessageIds.remove(message.id)
        Task {
            do {
                try await ircManager.sendMessage(message.content, to: channelName, on: serverId)
                try? DatabaseManager.shared.saveMessage(message)
            } catch {
                failedMessageIds.insert(message.id)
                rebuildDisplay()
            }
        }
    }

    // MARK: - Mark read

    func markRead() {
        unreadCount = 0
        ircManager.clearUnread(channelId: channelId)
        try? DatabaseManager.shared.updateChannelLastChecked(
            channelId: channelId, date: Date())
    }

    // MARK: - Private helpers

    // MARK: - Conversation type helpers

    /// True when this ViewModel represents a standard IRC channel (#, &, !, +).
    /// False for DM conversations (channelName is a nick).
    private var isChannelConversation: Bool {
        channelName.hasPrefix("#") || channelName.hasPrefix("&")
            || channelName.hasPrefix("!") || channelName.hasPrefix("+")
    }

    var channelId: String { _cachedChannelId }

    // MARK: - Topic URL extraction

    /// Scans the current topic for the first URL and caches it in `rulesURL`.
    /// Called only when `topic` changes via its `didSet` observer — never on render.
    private func updateRulesURL() {
        guard !topic.isEmpty else { rulesURL = nil; return }
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue) else { rulesURL = nil; return }
        let range = NSRange(topic.startIndex..., in: topic)
        guard let match = detector.firstMatch(in: topic, options: [], range: range),
              let swiftRange = Range(match.range, in: topic) else { rulesURL = nil; return }
        rulesURL = URL(string: String(topic[swiftRange]))
    }

    // MARK: Persisted history

    private func loadPersistedMessages() async {
        isLoadingHistory = true
        let cid = channelId
        // currentNick is set in start() before this is called.
        // We use it to re-derive isFromCurrentUser, which is NOT stored in the DB schema.
        // Without this, all loaded messages appear left-aligned (isFromCurrentUser = false).
        let myNick = currentNick.isEmpty
            ? (ircManager.currentNicknames[serverId] ?? "")
            : currentNick
        let persisted = (try? DatabaseManager.shared.fetchMessages(
            forChannel: cid, limit: 200)) ?? []
        for var msg in persisted {
            if !myNick.isEmpty {
                msg.isFromCurrentUser = msg.sender.lowercased() == myNick.lowercased()
            }
            appendRaw(msg)
        }
        rebuildDisplay()
        isLoadingHistory = false
    }

    // MARK: - Combine subscriptions
    //
    // Subscribe to the per-server Combine subjects published by IRCClientManager.
    // These subjects are permanent (created in connect()) so subscriptions survive
    // channel switches — messages for THIS channel keep arriving even when the
    // user is viewing a different channel.

    private func registerSubscriptions() {
        cancellables.removeAll()

        // ── Incoming messages (PRIVMSG / NOTICE / history) ──────────────────
        ircManager.messagePublisher(for: serverId)
            .receive(on: RunLoop.main)
            .sink { [weak self] msg in self?.handleSubscribedMessage(msg) }
            .store(in: &cancellables)

        // ── IRC events (join/part/quit/names/topic/etc.) ─────────────────────
        ircManager.eventPublisher(for: serverId)
            .receive(on: RunLoop.main)
            .sink { [weak self] event in self?.handleEvent(event) }
            .store(in: &cancellables)

        // ── Reconnect — re-subscribe and re-request names ────────────────────
        ircManager.reconnectSubject
            .filter { [weak self] sid in sid == self?.serverId }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { await self?.handleReconnect() } }
            .store(in: &cancellables)

        // ── Drain any server notices buffered before we opened ───────────────
        let notices = ircManager.drainServerNotices(for: serverId)
        for notice in notices { handleSubscribedMessage(notice) }
    }

    // MARK: - Message handler

    private func handleSubscribedMessage(_ ircMsg: IRCMessage) {
        let target = ircMsg.parameters.first ?? ""
        let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
            || target.hasPrefix("!") || target.hasPrefix("+")

        let resolvedNick = currentNick.isEmpty
            ? (ircManager.currentNicknames[serverId] ?? "") : currentNick

        // Channel message: only show if it's for this specific channel.
        let isForChannel = isChannel && target.lowercased() == channelName.lowercased()

        // Non-channel message routing:
        //   • NOTICE (NickServ, MemoServ, server notices) → show in any active channel view
        //   • PRIVMSG to our nick (actual DM) → show ONLY in DM views (not in channels)
        // This prevents "alice DMs you" from appearing inside #linux.
        let isNotice = ircMsg.command == "NOTICE"
        let isForUs = !isChannel
            && (resolvedNick.isEmpty || target.lowercased() == resolvedNick.lowercased())
            && (isNotice || !isChannelConversation)
            //    ↑ channel views accept server NOTICEs but reject PRIVMSG DMs

        guard isForChannel || isForUs else { return }

        let nick = ircMsg.source?.nick ?? "server"
        let body = ircMsg.parameters.count > 1 ? ircMsg.parameters[1] : ""
        let isAction = body.hasPrefix("\u{0001}ACTION ") && body.hasSuffix("\u{0001}")
        let content  = isAction ? String(body.dropFirst(8).dropLast()) : body
        let isHistory = ircMsg.tags?["batch"] != nil  // batch tag → history replay

        let msg = Message(
            channelId: channelId,
            sender: nick,
            senderHost: ircMsg.source?.host,
            content: content,
            type: isAction ? .action : (ircMsg.command == "NOTICE" ? .notice : .message),
            isFromCurrentUser: nick.lowercased() == resolvedNick.lowercased()
        )

        if isHistory {
            // History batch: accumulate without rebuilding on every message.
            // rebuildDisplay() will be called once when the batch closes
            // (chathistoryBatchEnd / zncBatchEnd), reducing O(N²) to O(N).
            appendRaw(msg)
            pendingHistoryMessageCount += 1
        } else {
            append(msg, persist: false)
            if nick.lowercased() != resolvedNick.lowercased() {
                unreadCount += 1
                if AppState.shared.selectedChannelId != channelId {
                    ircManager.incrementUnread(channelId: channelId)
                }
            }
        }
    }

    // MARK: - Event handler

    private func handleEvent(_ event: IRCEvent) {
        switch event {

        // ── Member list (NAMES batches) ──────────────────────────────────────
        case .namesList(let channel, let nicks):
            guard channel.lowercased() == channelName.lowercased() else { return }
            let parsed = nicks.map { parseNick($0) }
            for member in parsed {
                if !members.contains(where: { $0.nick == member.nick }) {
                    members.append(member)
                }
            }
            sortMembers()

        case .endOfNames(let channel):
            guard channel.lowercased() == channelName.lowercased() else { return }
            Task { await requestChatHistoryIfSupported() }

        // ── Membership changes ───────────────────────────────────────────────
        case .join(let channel, let nick):
            guard channel.lowercased() == channelName.lowercased() else { return }
            if !members.contains(where: { $0.nick == nick }) {
                members.append(ChannelMember(nick: nick))
            }
            let msg = Message(channelId: channelId, sender: nick,
                              content: "\(nick) joined \(channel)", type: .join)
            append(msg, persist: false)

        case .part(let channel, let nick, let reason):
            guard channel.lowercased() == channelName.lowercased() else { return }
            members.removeAll { $0.nick == nick }
            let detail = reason.map { " (\($0))" } ?? ""
            let msg = Message(channelId: channelId, sender: nick,
                              content: "\(nick) left\(detail)", type: .part)
            append(msg, persist: false)

        case .quit(let nick, let reason):
            members.removeAll { $0.nick == nick }
            // Don't show quit notices in DM windows — they belong only in channel views.
            guard isChannelConversation else { return }
            let detail = reason.map { " (\($0))" } ?? ""
            let msg = Message(channelId: channelId, sender: nick,
                              content: "\(nick) quit\(detail)", type: .quit)
            append(msg, persist: false)

        case .kick(let channel, let kicked, let by, let reason):
            guard channel.lowercased() == channelName.lowercased() else { return }
            members.removeAll { $0.nick == kicked }
            let detail = reason.map { " (\($0))" } ?? ""
            let msg = Message(channelId: channelId, sender: by,
                              content: "\(kicked) was kicked by \(by)\(detail)", type: .kick)
            append(msg, persist: false)

        // ── Nick change ──────────────────────────────────────────────────────
        case .nickChange(let oldNick, let newNick):
            if oldNick.lowercased() == currentNick.lowercased() { currentNick = newNick }
            if let idx = members.firstIndex(where: { $0.nick == oldNick }) {
                members[idx].nick = newNick
            }
            // Don't show nick-change notices in DM windows — channels only.
            guard isChannelConversation else { return }
            let msg = Message(channelId: channelId, sender: oldNick,
                              content: "\(oldNick) is now known as \(newNick)", type: .nick)
            append(msg, persist: false)

        // ── Topic ────────────────────────────────────────────────────────────
        case .topicChange(let channel, let newTopic, let byNick):
            guard channel.lowercased() == channelName.lowercased() else { return }
            topic = newTopic
            updateRulesURL()
            let content = newTopic.isEmpty
                ? "\(byNick) cleared the topic"
                : "\(byNick) set the topic: \(newTopic)"
            let msg = Message(channelId: channelId, sender: byNick,
                              content: content, type: .topic)
            append(msg, persist: false)

        case .initialTopic(let channel, let newTopic):
            guard channel.lowercased() == channelName.lowercased() else { return }
            topic = newTopic
            updateRulesURL()

        // ── Mode ─────────────────────────────────────────────────────────────
        case .mode(let target, let modeString, let params):
            guard target.lowercased() == channelName.lowercased() else { return }
            let paramStr = params.isEmpty ? "" : " \(params.joined(separator: " "))"
            let msg = Message(channelId: channelId, sender: target,
                              content: "Mode \(modeString)\(paramStr)", type: .mode)
            append(msg, persist: false)

        // ── History batch end ────────────────────────────────────────────────
        case .chathistoryBatchEnd:
            guard pendingHistoryMessageCount > 0 else { return }
            let count = pendingHistoryMessageCount
            pendingHistoryMessageCount = 0
            let sep = Message(
                channelId: channelId, sender: "system",
                content: "── \(count) message\(count == 1 ? "" : "s") loaded from history ──",
                type: .system, isFromCurrentUser: false)
            // appendRaw then a single rebuildDisplay — not append() which would call rebuildDisplay twice
            appendRaw(sep)
            rebuildDisplay()

        case .zncBatchEnd:
            guard pendingHistoryMessageCount > 0 else { return }
            let count = pendingHistoryMessageCount
            pendingHistoryMessageCount = 0
            let sep = Message(
                channelId: channelId, sender: "system",
                content: "── ZNC replayed \(count) message\(count == 1 ? "" : "s") ──",
                type: .system, isFromCurrentUser: false)
            appendRaw(sep)
            rebuildDisplay()

        // ── Pass-through numerics ────────────────────────────────────────────
        case .unhandled:
            break  // terminal view handles these via eventPublisher itself
        }
    }

    // MARK: - NAMES request

    private func requestNamesIfNeeded() async {
        // DM targets are nicks, not channels — NAMES is meaningless for them
        guard channelName.hasPrefix("#") || channelName.hasPrefix("&") else { return }
        guard let client = ircManager.getClient(for: serverId), members.isEmpty else { return }
        try? await client.names(channelName)
    }

    private func handleReconnect() async {
        members.removeAll()          // fresh state after reconnect
        registerSubscriptions()      // re-subscribe (new subjects after reconnect)
        await requestNamesIfNeeded()
    }

    private func requestChatHistoryIfSupported() async {
        guard let client = ircManager.getClient(for: serverId) else { return }
        let supported = await client.hasChathistorySupport()
        guard supported else { return }

        let lastFetchKey = "chathistory_lastfetch_\(channelId)"
        let lastFetchDate = UserDefaults.standard.object(forKey: lastFetchKey) as? Date

        let needsFetch: Bool
        if rawMessages.isEmpty {
            needsFetch = true
        } else if let lastFetch = lastFetchDate {
            let lastForeground = AppState.shared.lastForegroundedAt
            needsFetch = lastForeground == nil || lastForeground! > lastFetch
        } else {
            needsFetch = true
        }
        guard needsFetch else { return }

        let limit = min(await client.getChathistoryLimit(), 100)
        if let since = lastFetchDate, !rawMessages.isEmpty {
            try? await client.requestHistorySince(since, target: channelName, limit: limit)
        } else {
            try? await client.requestHistory(target: channelName, limit: limit)
        }
        UserDefaults.standard.set(Date(), forKey: lastFetchKey)
    }

    // MARK: - Member parsing helpers

    private func parseNick(_ rawNick: String) -> ChannelMember {
        let mode: ChannelMember.MemberMode
        let nick: String
        switch rawNick.first {
        case "@": mode = .operator_; nick = String(rawNick.dropFirst())
        case "+": mode = .voice;     nick = String(rawNick.dropFirst())
        case "%": mode = .halfop;    nick = String(rawNick.dropFirst())
        case "&": mode = .admin;     nick = String(rawNick.dropFirst())
        case "~": mode = .founder;   nick = String(rawNick.dropFirst())
        default:  mode = .none;      nick = rawNick
        }
        return ChannelMember(nick: nick, mode: mode)
    }

    private func sortMembers() {
        let order: [ChannelMember.MemberMode] =
            [.founder, .admin, .operator_, .halfop, .voice, .none]
        members.sort { lhs, rhs in
            let li = order.firstIndex(of: lhs.mode) ?? 5
            let ri = order.firstIndex(of: rhs.mode) ?? 5
            return li == ri ? lhs.nick.lowercased() < rhs.nick.lowercased() : li < ri
        }
    }

    // MARK: - Message appending

    private func append(_ message: Message, persist: Bool) {
        guard !seenMessageIds.contains(message.id) else { return }
        appendRaw(message)
        if persist { try? DatabaseManager.shared.saveMessage(message) }
        rebuildDisplay()
    }

    private func appendRaw(_ message: Message) {
        seenMessageIds.insert(message.id)
        rawMessages.append(message)
        if rawMessages.count > 1000 {
            let removed = rawMessages.removeFirst()
            seenMessageIds.remove(removed.id)
        }
    }

    // MARK: - Display message construction

    private func rebuildDisplay() {
        var result: [DisplayMessage] = []
        var lastDate: Date? = nil
        var lastSender: String? = nil
        var lastTimestamp: Date? = nil

        for msg in rawMessages {
            if lastDate == nil || !msg.timestamp.isSameDay(as: lastDate!) {
                result.append(.dateSeparator(msg.timestamp))
                lastDate = msg.timestamp
                lastSender = nil
                lastTimestamp = nil
            }

            let canGroup = msg.type == .message || msg.type == .action
            let sameRun = canGroup
                && lastSender == msg.sender
                && lastTimestamp.map { msg.timestamp.timeIntervalSince($0) < 300 } == true

            // Apply failed-send overlay for outgoing messages
            if failedMessageIds.contains(msg.id) {
                result.append(.message(msg, grouped: sameRun))
            } else {
                result.append(.message(msg, grouped: sameRun))
            }

            if canGroup {
                lastSender = msg.sender
                lastTimestamp = msg.timestamp
            } else {
                lastSender = nil
                lastTimestamp = nil
            }
        }

        displayMessages = result
    }
}

// MARK: - DisplayMessage

enum DisplayMessage: Identifiable {
    case dateSeparator(Date)
    case message(Message, grouped: Bool)

    var id: String {
        switch self {
        case .dateSeparator(let date):
            return "sep-\(date.timeIntervalSinceReferenceDate)"
        case .message(let msg, _):
            return msg.id
        }
    }

    var isSystemMessage: Bool {
        guard case .message(let msg, _) = self else { return false }
        switch msg.type {
        case .join, .part, .quit, .nick, .mode, .topic, .kick, .ban, .invite, .system:
            return true
        default:
            return false
        }
    }

    var message: Message? {
        guard case .message(let msg, _) = self else { return nil }
        return msg
    }
}
