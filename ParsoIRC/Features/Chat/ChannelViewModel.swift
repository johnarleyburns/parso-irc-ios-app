import Foundation
import SwiftUI

/// The view model for a single channel (or DM thread).
///
/// Owned by `ChatView` as a `@StateObject`.  Registers IRC event callbacks
/// on the shared `IRCClientManager` / `IRCClient` for exactly the channel it
/// represents, loads persisted history from `DatabaseManager` on init, and
/// exposes a ready-to-render `displayMessages` array that already has
/// grouping, date-separator markers, and mention highlighting applied.
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

    /// Live member list (populated from NAMES reply and updated on JOIN/PART/QUIT/NICK).
    @Published private(set) var members: [ChannelMember] = []

    /// True while the initial history load is in progress.
    @Published private(set) var isLoadingHistory: Bool = false

    /// The nickname this client is currently using on the server.
    @Published private(set) var currentNick: String = ""

    /// Unread count since the last time this channel was selected.
    @Published private(set) var unreadCount: Int = 0

    // MARK: - Identity

    let serverId: String
    let channelName: String   // e.g. "#linux"

    // MARK: - Private

    private let ircManager: IRCClientManager
    private var rawMessages: [Message] = []   // source of truth, append-only
    private var seenMessageIds: Set<String> = []  // dedup
    // Cached channel ID to avoid repeated DB queries on every message append
    private let _cachedChannelId: String

    // MARK: - Init / deinit

    init(serverId: String, channelName: String, ircManager: IRCClientManager) {
        self.serverId = serverId
        self.channelName = channelName
        self.ircManager = ircManager
        self.currentNick = ircManager.currentNicknames[serverId] ?? ""
        // Cache the channel ID once at init (DB lookup is expensive per-message)
        self._cachedChannelId = (try? DatabaseManager.shared.fetchChannels(forServer: serverId)
            .first { $0.name == channelName }?.id)
            ?? "\(serverId):\(channelName)"
    }

    // MARK: - Lifecycle (called from ChatView .task)

    func start() async {
        currentNick = ircManager.currentNicknames[serverId] ?? ""
        await loadPersistedMessages()
        registerCallbacks()
        await requestNamesIfNeeded()
        await requestChatHistoryIfSupported()
    }

    func stop() {
        // Unregister by replacing with nil-equivalent closures.
        // The client actor holds weak refs so this is safe across task cancellation.
        guard let client = ircManager.getClient(for: serverId) else { return }
        client.onMessage = nil
        client.onJoin = nil
        client.onPart = nil
        client.onQuit = nil
        client.onNickChange = nil
        client.onTopicChange = nil
        client.onNamesList = nil
        client.onKick = nil
        client.onMode = nil
        client.onUnhandledMessage = nil
        client.onHistoryMessage = nil
    }

    // MARK: - Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            try? await ircManager.sendMessage(trimmed, to: channelName, on: serverId)
        }
        // Optimistically append an outgoing message so the user sees it immediately.
        let outgoing = Message(
            channelId: channelId,
            sender: currentNick,
            content: trimmed.hasPrefix("/me ") ? String(trimmed.dropFirst(4)) : trimmed,
            type: trimmed.hasPrefix("/me ") ? .action : .message,
            isFromCurrentUser: true
        )
        append(outgoing, persist: true)
        HapticManager.lightImpact()
    }

    // MARK: - Mark read

    func markRead() {
        unreadCount = 0
        ircManager.clearUnread(channelId: channelId)
    }

    // MARK: - Private helpers

    private var channelId: String { _cachedChannelId }

    // MARK: Persisted history

    private func loadPersistedMessages() async {
        isLoadingHistory = true
        let cid = channelId
        let persisted = (try? DatabaseManager.shared.fetchMessages(forChannel: cid, limit: 200)) ?? []
        for msg in persisted {
            appendRaw(msg)
        }
        rebuildDisplay()
        isLoadingHistory = false
    }

    // MARK: IRC callbacks

    private func registerCallbacks() {
        guard let client = ircManager.getClient(for: serverId) else { return }

        // PRIVMSG / NOTICE
        client.onMessage = { [weak self] ircMsg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only handle messages addressed to our channel (or DMs to us)
                let target = ircMsg.parameters.first ?? ""
                guard target.lowercased() == self.channelName.lowercased()
                    || target.lowercased() == self.currentNick.lowercased() else { return }

                let nick = ircMsg.source?.nick ?? "server"
                let body = ircMsg.parameters.count > 1 ? ircMsg.parameters[1] : ""

                // CTCP ACTION
                let isAction = body.hasPrefix("\u{0001}ACTION ") && body.hasSuffix("\u{0001}")
                let content = isAction
                    ? String(body.dropFirst(8).dropLast())
                    : body

                let msg = Message(
                    channelId: self.channelId,
                    sender: nick,
                    senderHost: ircMsg.source?.host,
                    content: content,
                    type: isAction ? .action : (ircMsg.command == "NOTICE" ? .notice : .message),
                    isFromCurrentUser: nick == self.currentNick
                )
                self.append(msg, persist: true)
                if nick != self.currentNick {
                    self.unreadCount += 1
                    // Only bump manager-level unread if this channel isn't currently viewed
                    if AppState.shared.selectedChannelId != self.channelId {
                        self.ircManager.incrementUnread(channelId: self.channelId)
                    }
                }
            }
        }

        // JOIN
        client.onJoin = { [weak self] channel, nick in
            Task { @MainActor [weak self] in
                guard let self, channel.lowercased() == self.channelName.lowercased() else { return }
                // Add to member list if not already present
                if !self.members.contains(where: { $0.nick == nick }) {
                    self.members.append(ChannelMember(nick: nick))
                }
                let msg = Message(channelId: self.channelId, sender: nick,
                                  content: "\(nick) joined \(channel)", type: .join)
                self.append(msg, persist: false)
            }
        }

        // PART
        client.onPart = { [weak self] channel, nick, reason in
            Task { @MainActor [weak self] in
                guard let self, channel.lowercased() == self.channelName.lowercased() else { return }
                self.members.removeAll { $0.nick == nick }
                let detail = reason.map { " (\($0))" } ?? ""
                let msg = Message(channelId: self.channelId, sender: nick,
                                  content: "\(nick) left\(detail)", type: .part)
                self.append(msg, persist: false)
            }
        }

        // QUIT
        client.onQuit = { [weak self] nick, reason in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.members.removeAll { $0.nick == nick }
                let detail = reason.map { " (\($0))" } ?? ""
                let msg = Message(channelId: self.channelId, sender: nick,
                                  content: "\(nick) quit\(detail)", type: .quit)
                self.append(msg, persist: false)
            }
        }

        // NICK
        client.onNickChange = { [weak self] oldNick, newNick in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if oldNick == self.currentNick { self.currentNick = newNick }
                if let idx = self.members.firstIndex(where: { $0.nick == oldNick }) {
                    self.members[idx].nick = newNick
                }
                let msg = Message(channelId: self.channelId, sender: oldNick,
                                  content: "\(oldNick) is now known as \(newNick)", type: .nick)
                self.append(msg, persist: false)
            }
        }

        // TOPIC
        client.onTopicChange = { [weak self] channel, newTopic, byNick in
            Task { @MainActor [weak self] in
                guard let self, channel.lowercased() == self.channelName.lowercased() else { return }
                self.topic = newTopic
                let content = newTopic.isEmpty
                    ? "\(byNick) cleared the topic"
                    : "\(byNick) set the topic: \(newTopic)"
                let msg = Message(channelId: self.channelId, sender: byNick,
                                  content: content, type: .topic)
                self.append(msg, persist: false)
            }
        }

        // NAMES reply (353)
        client.onNamesList = { [weak self] channel, nicks in
            Task { @MainActor [weak self] in
                guard let self, channel.lowercased() == self.channelName.lowercased() else { return }
                let parsed = nicks.map { rawNick -> ChannelMember in
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
                // Merge: add new, don't duplicate
                for member in parsed {
                    if !self.members.contains(where: { $0.nick == member.nick }) {
                        self.members.append(member)
                    }
                }
                self.members.sort { lhs, rhs in
                    let order: [ChannelMember.MemberMode] = [.founder, .admin, .operator_, .halfop, .voice, .none]
                    let li = order.firstIndex(of: lhs.mode) ?? 5
                    let ri = order.firstIndex(of: rhs.mode) ?? 5
                    return li == ri ? lhs.nick.lowercased() < rhs.nick.lowercased() : li < ri
                }
            }
        }

        // KICK
        client.onKick = { [weak self] channel, kicked, by, reason in
            Task { @MainActor [weak self] in
                guard let self, channel.lowercased() == self.channelName.lowercased() else { return }
                self.members.removeAll { $0.nick == kicked }
                let detail = reason.map { " (\($0))" } ?? ""
                let msg = Message(channelId: self.channelId, sender: by,
                                  content: "\(kicked) was kicked by \(by)\(detail)", type: .kick)
                self.append(msg, persist: false)
            }
        }

        // MODE
        client.onMode = { [weak self] target, modeString, params in
            Task { @MainActor [weak self] in
                guard let self, target.lowercased() == self.channelName.lowercased() else { return }
                let paramStr = params.isEmpty ? "" : " \(params.joined(separator: " "))"
                let msg = Message(channelId: self.channelId, sender: target,
                                  content: "Mode \(modeString)\(paramStr)", type: .mode)
                self.append(msg, persist: false)
            }
        }

        // Server numerics that carry a topic on join (332)
        client.onUnhandledMessage = { [weak self] ircMsg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch ircMsg.command {
                case "332":
                    // RPL_TOPIC: params = [yournick, channel, topic]
                    guard ircMsg.parameters.count >= 3 else { return }
                    let channel = ircMsg.parameters[1]
                    guard channel.lowercased() == self.channelName.lowercased() else { return }
                    self.topic = ircMsg.parameters[2]
                default:
                    break
                }
            }
        }

        // History messages from CHATHISTORY — append without unread increment
        client.onHistoryMessage = { [weak self] ircMsg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let target = ircMsg.parameters.first ?? ""
                guard target.lowercased() == self.channelName.lowercased()
                    || target.lowercased() == self.currentNick.lowercased() else { return }

                let nick = ircMsg.source?.nick ?? "server"
                let body = ircMsg.parameters.count > 1 ? ircMsg.parameters[1] : ""
                let isAction = body.hasPrefix("\u{0001}ACTION ") && body.hasSuffix("\u{0001}")
                let content = isAction ? String(body.dropFirst(8).dropLast()) : body

                let msg = Message(
                    channelId: self.channelId,
                    sender: nick,
                    senderHost: ircMsg.source?.host,
                    content: content,
                    type: isAction ? .action : (ircMsg.command == "NOTICE" ? .notice : .message),
                    isFromCurrentUser: nick == self.currentNick
                )
                // append without persisting (history is already on server) and no unread bump
                self.append(msg, persist: true)
            }
        }
    }

    // MARK: NAMES request

    private func requestNamesIfNeeded() async {
        guard let client = ircManager.getClient(for: serverId), members.isEmpty else { return }
        try? await client.names(channelName)
    }

    private func requestChatHistoryIfSupported() async {
        guard let client = ircManager.getClient(for: serverId) else { return }
        let supported = await client.hasChathistorySupport()
        guard supported else { return }
        let limit = min(await client.getChathistoryLimit(), 50)
        try? await client.requestHistory(target: channelName, limit: limit)
    }

    // MARK: Message appending

    private func append(_ message: Message, persist: Bool) {
        guard !seenMessageIds.contains(message.id) else { return }
        appendRaw(message)
        if persist { try? DatabaseManager.shared.saveMessage(message) }
        rebuildDisplay()
    }

    private func appendRaw(_ message: Message) {
        seenMessageIds.insert(message.id)
        rawMessages.append(message)
        // Keep a reasonable in-memory cap
        if rawMessages.count > 1000 {
            let removed = rawMessages.removeFirst()
            seenMessageIds.remove(removed.id)
        }
    }

    // MARK: Display message construction

    /// Rebuilds `displayMessages` from `rawMessages`.
    /// Inserts date separators and computes grouping (same sender within 5 min).
    private func rebuildDisplay() {
        var result: [DisplayMessage] = []
        var lastDate: Date? = nil
        var lastSender: String? = nil
        var lastTimestamp: Date? = nil

        for msg in rawMessages {
            // Date separator
            if lastDate == nil || !msg.timestamp.isSameDay(as: lastDate!) {
                result.append(.dateSeparator(msg.timestamp))
                lastDate = msg.timestamp
                lastSender = nil
                lastTimestamp = nil
            }

            // Grouping: same sender, same type (message/action), within 5 minutes
            let canGroup = msg.type == .message || msg.type == .action
            let sameRun = canGroup
                && lastSender == msg.sender
                && lastTimestamp.map { msg.timestamp.timeIntervalSince($0) < 300 } == true

            result.append(.message(msg, grouped: sameRun))

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

/// A discriminated union used by MessageListView to render either a date
/// separator pill or a chat message bubble/system row.
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

    /// True if this is a system-style row (join/part/quit/nick/mode/topic/kick).
    var isSystemMessage: Bool {
        guard case .message(let msg, _) = self else { return false }
        switch msg.type {
        case .join, .part, .quit, .nick, .mode, .topic, .kick, .ban, .invite: return true
        default: return false
        }
    }

    /// The underlying `Message` if this is a `.message` case.
    var message: Message? {
        guard case .message(let msg, _) = self else { return nil }
        return msg
    }
}
