import Foundation

struct Server: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var ssl: Bool
    var nickname: String
    var realname: String
    var password: String?
    var saslEnabled: Bool
    var saslMechanism: String
    var autoConnect: Bool
    var createdAt: Date
    var lastConnected: Date?
    var isConnected: Bool
    var channels: [Channel]
    var lastActiveChannel: String?

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
        lastActiveChannel: String? = nil
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
    }

    static let defaultNetworks: [Server] = [
        Server(
            name: "Libera.Chat",
            host: "irc.libera.chat",
            port: 6697,
            ssl: true,
            nickname: "",
            realname: "",
            saslEnabled: false,
            channels: [
                Channel(name: "#linux"),
                Channel(name: "#kde"),
                Channel(name: "#libera"),
                Channel(name: "#archlinux"),
                Channel(name: "#python"),
                Channel(name: "#debian"),
                Channel(name: "#rust"),
                Channel(name: "#emacs"),
                Channel(name: "#bash"),
                Channel(name: "#ubuntu"),
                Channel(name: "#gentoo"),
                Channel(name: "#golang"),
                Channel(name: "#javascript"),
                Channel(name: "#vim"),
                Channel(name: "#fedora"),
                Channel(name: "#opensuse"),
                Channel(name: "#nginx"),
                Channel(name: "#systemd"),
                Channel(name: "#kernel"),
                Channel(name: "#security"),
                Channel(name: "#lxc")
            ],
            lastActiveChannel: "#linux"
        ),
        Server(
            name: "OFTC",
            host: "irc.oftc.net",
            port: 6697,
            ssl: true,
            nickname: "",
            realname: "",
            channels: [
                Channel(name: "#debian"),
                Channel(name: "#linux")
            ]
        ),
        Server(
            name: "hackint",
            host: "irc.hackint.org",
            port: 6697,
            ssl: true,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "IRCnet",
            host: "ircnet.ircchat.de",
            port: 6667,
            ssl: false,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "Undernet",
            host: "irc.undernet.org",
            port: 6667,
            ssl: false,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "Rizon",
            host: "irc.rizon.net",
            port: 6697,
            ssl: true,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "QuakeNet",
            host: "irc.quakenet.org",
            port: 6667,
            ssl: false,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "DALnet",
            host: "irc.dal.net",
            port: 6667,
            ssl: false,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "EFnet",
            host: "irc.efnet.org",
            port: 6667,
            ssl: false,
            nickname: "",
            realname: ""
        ),
        Server(
            name: "Snoonet",
            host: "irc.snoonet.org",
            port: 6697,
            ssl: true,
            nickname: "",
            realname: ""
        )
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
        notifyOnAnyMessage: Bool = false
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