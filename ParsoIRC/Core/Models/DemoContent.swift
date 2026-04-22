import Foundation

// MARK: - Demo Server Constants

/// All static content for the "Parso Demo Server" experience.
///
/// The demo server looks and feels identical to a real IRC server — no UI labels
/// distinguish it from a live connection.  The only hint is the welcome system
/// message that appears at the top of the #demo channel on first open.
enum DemoContent {

    // MARK: - IDs (stable across launches)

    static let serverId    = "__demo_server__"
    static let channelId   = "__demo_channel__"
    static let channelName = "#demo"
    static let serverName  = "Parso Demo Server"
    static let serverHost  = "demo.parso.internal"

    // MARK: - Credentials

    static let nick     = "demo"
    static let username = "demo"
    static let password = "demo1234"

    // MARK: - Server model

    static var server: Server {
        Server(
            id: serverId,
            name: serverName,
            host: serverHost,
            port: 6697,
            ssl: true,
            nickname: nick,
            realname: nick,
            password: password,
            saslEnabled: false,
            saslMechanism: "PLAIN",
            autoConnect: true,
            createdAt: Date(),
            lastConnected: nil,
            isConnected: false,
            channels: [],
            lastActiveChannel: channelName,
            useConnectionPassword: false
        )
    }

    // MARK: - Channel model

    static var channel: Channel {
        Channel(
            id: channelId,
            serverId: serverId,
            name: channelName,
            topic: "Welcome to Parso IRC — open source IRC chat for iOS",
            isMuted: false,
            notifications: .mentions,
            lastReadMessageId: nil,
            joinedAt: Date(),
            memberCount: 5,
            members: members,
            isWatched: false,
            lastNotifiedAt: nil,
            lastCheckedAt: nil,
            notifyOnAnyMessage: false,
            isDM: false,
            unreadCount: 0
        )
    }

    // MARK: - Pre-populated members

    static let members: [ChannelMember] = [
        ChannelMember(nick: "Alice",   username: "alice",   hostname: "parso.guru",   mode: .operator_),
        ChannelMember(nick: "Bob",     username: "bob",     hostname: "parso.guru",   mode: .none),
        ChannelMember(nick: "Charlie", username: "charlie", hostname: "parso.guru",   mode: .none),
        ChannelMember(nick: "DemoBot", username: "demobot", hostname: "bot.parso.internal", mode: .voice),
        ChannelMember(nick: nick,      username: username,  hostname: "user.parso.internal", mode: .none),
    ]

    // MARK: - Pre-populated messages

    /// Returns a fresh set of demo messages anchored to `now`, spread over
    /// the preceding ~35 minutes so date grouping and timestamps look natural.
    static func messages(channelId cid: String = channelId) -> [Message] {
        let now = Date()
        func t(_ minutesAgo: Double) -> Date {
            now.addingTimeInterval(-minutesAgo * 60)
        }

        return [
            // System welcome — the ONE line that mentions this is a demo
            Message(id: "demo-sys-0", channelId: cid, sender: "system",
                    content: "Welcome! This is a live demo of Parso IRC. Try long-pressing any message or send your own reply.",
                    timestamp: t(35), type: .system),

            // Alice joins
            Message(id: "demo-sys-1", channelId: cid, sender: "Alice",
                    content: "Alice joined #demo",
                    timestamp: t(34), type: .join),

            // Chat begins
            Message(id: "demo-msg-1", channelId: cid, sender: "Alice",
                    content: "Hey everyone, good to see you all!",
                    timestamp: t(33)),
            Message(id: "demo-msg-2", channelId: cid, sender: "Bob",
                    content: "What's everyone working on today?",
                    timestamp: t(32)),
            Message(id: "demo-msg-3", channelId: cid, sender: "Charlie",
                    content: "waves at everyone",
                    timestamp: t(31), type: .action),
            Message(id: "demo-msg-4", channelId: cid, sender: "Alice",
                    content: "I've been setting up a new IRC bouncer — ZNC is great for staying connected",
                    timestamp: t(28)),
            Message(id: "demo-msg-5", channelId: cid, sender: "Bob",
                    content: "Nice! I've been lurking on Libera.Chat a lot lately",
                    timestamp: t(27)),
            Message(id: "demo-msg-6", channelId: cid, sender: "Charlie",
                    content: "Anyone tried irssi vs weechat? Can't decide which to use",
                    timestamp: t(24)),
            Message(id: "demo-msg-7", channelId: cid, sender: "Alice",
                    content: "Weechat all the way — the scripting is unmatched",
                    timestamp: t(23)),

            // DemoBot joins
            Message(id: "demo-sys-2", channelId: cid, sender: "DemoBot",
                    content: "DemoBot joined #demo",
                    timestamp: t(20), type: .join),

            // Bot notice
            Message(id: "demo-msg-8", channelId: cid, sender: "DemoBot",
                    content: "Welcome to #demo — feel free to send a message!",
                    timestamp: t(20), type: .notice),

            // More chat
            Message(id: "demo-msg-9", channelId: cid, sender: "Charlie",
                    content: "Has anyone tried the Parso IRC app? Pretty slick on iPhone",
                    timestamp: t(15)),
            Message(id: "demo-msg-10", channelId: cid, sender: "Alice",
                    content: "Yeah it has great TLS support and chat history replay",
                    timestamp: t(14)),

            // Mention of the demo user — triggers yellow highlight
            Message(id: "demo-msg-11", channelId: cid, sender: "Bob",
                    content: "demo: welcome! Glad you joined us",
                    timestamp: t(5)),
        ]
    }

    // MARK: - DemoBot rotating replies

    static let botReplies: [String] = [
        "Glad you're here! IRC has been around since 1988 and it's still going strong.",
        "Did you know Parso IRC supports TLS, SASL, and ZNC bouncers out of the box?",
        "You can join thousands of channels on networks like Libera.Chat and OFTC.",
        "Try the long-press on any message to see message options.",
        "When you're ready, tap 'Add Server' to connect to a real IRC network!",
    ]

    static func botReply(index: Int) -> Message {
        let text = botReplies[index % botReplies.count]
        return Message(
            id: UUID().uuidString,
            channelId: channelId,
            sender: "DemoBot",
            content: text,
            timestamp: Date(),
            type: .message
        )
    }
}
