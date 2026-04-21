import Foundation

/// Discriminated union of every non-message IRC event that `IRCClientManager`
/// fans out to `ChannelViewModel` subscribers via a per-server
/// `PassthroughSubject<IRCEvent, Never>`.
///
/// Having a single subject for all event types (rather than one per event)
/// keeps the subscriber API simple: each `ChannelViewModel` subscribes once
/// and routes internally via a `switch`.
enum IRCEvent: Sendable {
    // MARK: - Membership events
    /// A user joined a channel.
    case join(channel: String, nick: String)
    /// A user left a channel voluntarily.
    case part(channel: String, nick: String, reason: String?)
    /// A user disconnected from the server.
    case quit(nick: String, reason: String?)
    /// A user was kicked from a channel.
    case kick(channel: String, kicked: String, by: String, reason: String?)

    // MARK: - Identity events
    /// A user changed their nick.
    case nickChange(oldNick: String, newNick: String)

    // MARK: - Channel state events
    /// The topic for a channel changed.
    case topicChange(channel: String, topic: String, byNick: String)
    /// A numeric 332 RPL_TOPIC arrived on join (initial topic).
    case initialTopic(channel: String, topic: String)
    /// A mode change was applied to a channel or user.
    case mode(target: String, modeString: String, params: [String])

    // MARK: - Names / member list events
    /// A 353 RPL_NAMREPLY batch of nicks for a channel.
    case namesList(channel: String, nicks: [String])
    /// A 366 RPL_ENDOFNAMES — the NAMES list for a channel is complete.
    /// This is also the correct trigger point for CHATHISTORY requests.
    case endOfNames(channel: String)

    // MARK: - History replay events
    /// A standard IRCv3 CHATHISTORY BATCH envelope just closed.
    case chathistoryBatchEnd
    /// A ZNC znc.in/playback BATCH envelope just closed.
    case zncBatchEnd

    // MARK: - Pass-through
    /// Any unrecognised numeric or command — forwarded to the debug terminal.
    case unhandled(IRCMessage)
}
