import Foundation

struct Server: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var ssl: Bool
    var nickname: String
    var realname: String
    /// The user's credential — used for SASL PLAIN or NickServ registration.
    /// Never sent as an IRC-level PASS command unless `useConnectionPassword` is true.
    var password: String?
    var saslEnabled: Bool
    var saslMechanism: String
    var autoConnect: Bool
    var createdAt: Date
    var lastConnected: Date?
    var isConnected: Bool
    var channels: [Channel]
    var lastActiveChannel: String?
    /// When true, the `password` field is sent as an IRC PASS command during registration.
    /// Use only for private servers / bouncers that require a server-level password.
    /// Leave false for public networks (Libera.Chat, OFTC, etc.) — sending PASS to those
    /// causes `ERROR :Bad password` and an immediate connection termination.
    var useConnectionPassword: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        port: Int = 6697,
        ssl: Bool = true,
        nickname: String = "",
        realname: String = "",
        password: String? = nil,
        saslEnabled: Bool = false,
        saslMechanism: String = "PLAIN",
        autoConnect: Bool = true,
        createdAt: Date = Date(),
        lastConnected: Date? = nil,
        isConnected: Bool = false,
        channels: [Channel] = [],
        lastActiveChannel: String? = nil,
        useConnectionPassword: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.ssl = ssl
        self.nickname = nickname
        self.realname = realname
        self.password = password
        self.saslEnabled = saslEnabled
        self.saslMechanism = saslMechanism
        self.autoConnect = autoConnect
        self.createdAt = createdAt
        self.lastConnected = lastConnected
        self.isConnected = isConnected
        self.channels = channels
        self.lastActiveChannel = lastActiveChannel
        self.useConnectionPassword = useConnectionPassword
    }

    static let defaultNetworks: [Server] = [
        // ── Tier 1: Large, active, well-known ──────────────────────────────
        Server(name: "Libera.Chat",   host: "irc.libera.chat",       port: 6697, ssl: true,  nickname: "", realname: "", saslEnabled: false, channels: []),
        Server(name: "OFTC",          host: "irc.oftc.net",          port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "Rizon",         host: "irc.rizon.net",         port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "IRCnet",        host: "open.ircnet.net",       port: 6667, ssl: false, nickname: "", realname: "", channels: []),
        Server(name: "EFnet",         host: "irc.efnet.org",         port: 6667, ssl: false, nickname: "", realname: "", channels: []),
        Server(name: "QuakeNet",      host: "irc.quakenet.org",      port: 6667, ssl: false, nickname: "", realname: "", channels: []),
        Server(name: "Undernet",      host: "irc.undernet.org",      port: 6667, ssl: false, nickname: "", realname: "", channels: []),
        Server(name: "DALnet",        host: "irc.dal.net",           port: 6667, ssl: false, nickname: "", realname: "", channels: []),
        Server(name: "hackint",       host: "irc.hackint.org",       port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "Snoonet",       host: "irc.snoonet.org",       port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        // ── Tier 2: Niche / community / retro ──────────────────────────────
        Server(name: "2600net",       host: "irc.2600.net",          port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "tilde.chat",    host: "irc.tilde.chat",        port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "Freenode",      host: "irc.freenode.net",      port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "GeekShed",      host: "irc.geekshed.net",      port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "GameSurge",     host: "irc.gamesurge.net",     port: 6667, ssl: false, nickname: "", realname: "", channels: []),
        Server(name: "IRCHighway",    host: "irc.irchighway.net",    port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "ChatJunkies",   host: "irc.chatjunkies.org",   port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "AllNetwork",    host: "irc.allnetwork.org",    port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "P2P-NET",       host: "irc.p2p-irc.net",      port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "SorceryNet",    host: "irc.sorcery.net",       port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        // ── Tier 3: Dev / hacker / special interest ─────────────────────────
        Server(name: "IRCAM",         host: "irc.ircam.fr",          port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "Digitalized",   host: "irc.digitalized.tv",    port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "PIRC",          host: "pirc.at",               port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "AnonOps",       host: "irc.anonops.com",       port: 6697, ssl: true,  nickname: "", realname: "", channels: []),
        Server(name: "Austnet",       host: "irc.austnet.org",       port: 6667, ssl: false, nickname: "", realname: "", channels: []),
    ]
}

struct Channel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var serverId: String
    var name: String
    var topic: String?
    var isMuted: Bool
    var notifications: NotificationLevel
    var lastReadMessageId: String?
    var joinedAt: Date?
    var memberCount: Int
    var members: [ChannelMember]

    // Watch functionality
    var isWatched: Bool
    var lastNotifiedAt: Date?
    var lastCheckedAt: Date?
    var notifyOnAnyMessage: Bool

    // Phase 4: direct message thread flag
    var isDM: Bool

    /// Persisted unread message count (survives app restart).
    var unreadCount: Int

    enum NotificationLevel: String, Codable, CaseIterable {
        case all = "all"
        case mentions = "mentions"
        case none = "none"

        var displayName: String {
            switch self {
            case .all: return "All Messages"
            case .mentions: return "Mentions Only"
            case .none: return "None"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        serverId: String = "",
        name: String,
        topic: String? = nil,
        isMuted: Bool = false,
        notifications: NotificationLevel = .mentions,
        lastReadMessageId: String? = nil,
        joinedAt: Date? = nil,
        memberCount: Int = 0,
        members: [ChannelMember] = [],
        isWatched: Bool = false,
        lastNotifiedAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        notifyOnAnyMessage: Bool = false,
        isDM: Bool = false,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.topic = topic
        self.isMuted = isMuted
        self.notifications = notifications
        self.lastReadMessageId = lastReadMessageId
        self.joinedAt = joinedAt
        self.memberCount = memberCount
        self.members = members
        self.isWatched = isWatched
        self.lastNotifiedAt = lastNotifiedAt
        self.lastCheckedAt = lastCheckedAt
        self.notifyOnAnyMessage = notifyOnAnyMessage
        self.isDM = isDM
        self.unreadCount = unreadCount
    }

    var displayName: String {
        name.hasPrefix("#") ? String(name.dropFirst()) : name
    }
}

struct ChannelMember: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var nick: String
    var username: String?
    var hostname: String?
    var mode: MemberMode
    var isAway: Bool

    enum MemberMode: String, Codable, Hashable {
        case none = ""
        case voice = "+"
        case operator_ = "@"
        case halfop = "%"
        case admin = "&"
        case founder = "~"

        var prefix: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .none: return ""
            case .voice: return "+"
            case .operator_: return "@"
            case .halfop: return "%"
            case .admin: return "&"
            case .founder: return "~"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        nick: String,
        username: String? = nil,
        hostname: String? = nil,
        mode: MemberMode = .none,
        isAway: Bool = false
    ) {
        self.id = id
        self.nick = nick
        self.username = username
        self.hostname = hostname
        self.mode = mode
        self.isAway = isAway
    }
}

struct Message: Identifiable, Codable, Equatable {
    let id: String
    var channelId: String
    var sender: String
    var senderHost: String?
    var content: String
    var timestamp: Date
    var type: MessageType
    var isRead: Bool
    var reactions: [MessageReaction]
    var isFromCurrentUser: Bool
    
    var previousSameSenderMessageId: String?
    
    var previousSameSenderMessage: Message? {
        get { nil }
        set { previousSameSenderMessageId = newValue?.id }
    }

    enum MessageType: String, Codable {
        case message
        case action
        case notice
        case join
        case part
        case quit
        case nick
        case mode
        case topic
        case kick
        case ban
        case invite
        case system
    }

    init(
        id: String = UUID().uuidString,
        channelId: String,
        sender: String,
        senderHost: String? = nil,
        content: String,
        timestamp: Date = Date(),
        type: MessageType = .message,
        isRead: Bool = false,
        reactions: [MessageReaction] = [],
        isFromCurrentUser: Bool = false,
        previousSameSenderMessage: Message? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.sender = sender
        self.senderHost = senderHost
        self.content = content
        self.timestamp = timestamp
        self.type = type
        self.isRead = isRead
        self.reactions = reactions
        self.isFromCurrentUser = isFromCurrentUser
        self.previousSameSenderMessage = previousSameSenderMessage
    }

    var isGroupedWithPrevious: Bool {
        guard let previous = previousSameSenderMessage else { return false }
        let timeDiff = timestamp.timeIntervalSince(previous.timestamp)
        return timeDiff < 300 && sender == previous.sender
    }

    var isGroupedWithNext: Bool = false

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }
}

struct MessageReaction: Identifiable, Codable, Equatable {
    let id: String
    var emoji: String
    var users: [String]
    
    init(id: String = UUID().uuidString, emoji: String, users: [String] = []) {
        self.id = id
        self.emoji = emoji
        self.users = users
    }
}

struct User: Identifiable, Codable, Equatable {
    let id: String
    var username: String
    var passwordHash: String
    var nickname: String?
    var avatarSeed: String?
    var status: String?
    var createdAt: Date
    var lastLogin: Date?
    
    init(
        id: String = UUID().uuidString,
        username: String,
        passwordHash: String,
        nickname: String? = nil,
        avatarSeed: String? = nil,
        status: String? = nil,
        createdAt: Date = Date(),
        lastLogin: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
        self.nickname = nickname
        self.avatarSeed = avatarSeed
        self.status = status
        self.createdAt = createdAt
        self.lastLogin = lastLogin
    }
}