import Foundation
import SwiftUI

/// Tracks open DM (private message) threads across servers.
///
/// A DM thread is modelled as a `Channel` with `isDM = true` stored in
/// the database.  `ConversationsViewModel` loads all DM channels on init
/// and vends them sorted by most-recent message timestamp.
///
/// The channel name for a DM is the remote nick, e.g. "alice".
@MainActor
final class ConversationsViewModel: ObservableObject {

    @Published private(set) var conversations: [Channel] = []

    private let ircManager: IRCClientManager

    init(ircManager: IRCClientManager) {
        self.ircManager = ircManager
    }

    // MARK: - Load

    func loadConversations() {
        let servers = (try? DatabaseManager.shared.fetchServers()) ?? []
        var dms: [Channel] = []
        for server in servers {
            let channels = (try? DatabaseManager.shared.fetchChannels(forServer: server.id)) ?? []
            let dmChannels = channels.filter { $0.isDM }
            dms.append(contentsOf: dmChannels)
        }
        // Sort: most recent first using last message timestamp from DB
        conversations = dms.sorted { a, b in
            let tA = (try? DatabaseManager.shared.getLatestMessage(forChannel: a.id))?.timestamp ?? Date.distantPast
            let tB = (try? DatabaseManager.shared.getLatestMessage(forChannel: b.id))?.timestamp ?? Date.distantPast
            return tA > tB
        }
    }

    // MARK: - Open / create a DM thread

    /// Returns (or creates) a DM channel for `nick` on `serverId`.
    func openDM(with nick: String, serverId: String) -> Channel {
        // Look for existing DM channel
        let existing = conversations.first { $0.name == nick && $0.serverId == serverId && $0.isDM }
        if let ch = existing { return ch }

        // Create a new DM channel
        var ch = Channel(serverId: serverId, name: nick)
        ch.isDM = true
        try? DatabaseManager.shared.saveChannel(ch, serverId: serverId)
        loadConversations()
        return ch
    }

    // MARK: - Delete a DM thread

    func deleteConversation(_ channel: Channel) {
        // Remove from DB (cascade removes messages too via cleanupOldMessages)
        // For now just remove from display list; proper cascade is Phase 6
        conversations.removeAll { $0.id == channel.id }
    }
}
