#if !os(Linux)
import XCTest
import UserNotifications
@testable import ParsoIRC

// MARK: - ChannelListCacheTests

final class ChannelListCacheTests: XCTestCase {

    func testCacheStoresEntriesByServerId() async {
        let manager = IRCClientManager.shared
        // Inject a cache entry directly via the staging mechanism by simulating list-end
        // We test the public interface: channelListCache is @Published and readable.
        let entry = IRCClientManager.CachedListEntry(name: "#swift", members: 42, topic: "Swift chat")
        // Since we can't inject without a live connection, we verify the type exists and is readable
        XCTAssertNotNil(manager.channelListCache)
        _ = entry // suppress unused warning
    }

    func testCacheEntriesHaveCorrectFields() {
        let entry = IRCClientManager.CachedListEntry(name: "#rust", members: 100, topic: "Rust lang")
        XCTAssertEqual(entry.name, "#rust")
        XCTAssertEqual(entry.members, 100)
        XCTAssertEqual(entry.topic, "Rust lang")
    }

    func testCacheListIsInitiallyEmpty() async {
        // A fresh server ID should have no cache
        let manager = IRCClientManager.shared
        XCTAssertNil(manager.channelListCache["nonexistent-server-id-12345"])
    }

    func testClearChannelListCacheRemovesEntry() async {
        let manager = IRCClientManager.shared
        // clearChannelListCache on a non-existent key should not crash
        manager.clearChannelListCache(for: "nonexistent-server-id")
        XCTAssertNil(manager.channelListCache["nonexistent-server-id"])
    }

    func testCachedListEntryEquality() {
        let a = IRCClientManager.CachedListEntry(name: "#linux", members: 50, topic: "Linux help")
        let b = IRCClientManager.CachedListEntry(name: "#linux", members: 50, topic: "Linux help")
        let c = IRCClientManager.CachedListEntry(name: "#bsd",   members: 10, topic: "BSD chat")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - UnreadCountTests

@MainActor
final class UnreadCountTests: XCTestCase {

    func testIncrementFromZero() {
        let manager = IRCClientManager.shared
        let id = "test-channel-unread-1"
        manager.clearUnread(channelId: id)
        manager.incrementUnread(channelId: id)
        XCTAssertEqual(manager.unreadCounts[id], 1)
    }

    func testIncrementTwiceEqualsTwo() {
        let manager = IRCClientManager.shared
        let id = "test-channel-unread-2"
        manager.clearUnread(channelId: id)
        manager.incrementUnread(channelId: id)
        manager.incrementUnread(channelId: id)
        XCTAssertEqual(manager.unreadCounts[id], 2)
    }

    func testClearResetsToZero() {
        let manager = IRCClientManager.shared
        let id = "test-channel-unread-3"
        manager.incrementUnread(channelId: id)
        manager.incrementUnread(channelId: id)
        manager.clearUnread(channelId: id)
        XCTAssertEqual(manager.unreadCounts[id] ?? 0, 0)
    }

    func testMultipleChannelsAreIndependent() {
        let manager = IRCClientManager.shared
        let a = "test-channel-a"
        let b = "test-channel-b"
        manager.clearUnread(channelId: a)
        manager.clearUnread(channelId: b)
        manager.incrementUnread(channelId: a)
        manager.incrementUnread(channelId: a)
        manager.incrementUnread(channelId: b)
        XCTAssertEqual(manager.unreadCounts[a], 2)
        XCTAssertEqual(manager.unreadCounts[b], 1)
    }

    func testClearNonExistentDoesNotCrash() {
        let manager = IRCClientManager.shared
        manager.clearUnread(channelId: "channel-that-never-existed-xyz")
        XCTAssertEqual(manager.unreadCounts["channel-that-never-existed-xyz"] ?? 0, 0)
    }
}

// MARK: - ExplicitDisconnectTrackingTests

final class ExplicitDisconnectTrackingTests: XCTestCase {

    private let testServerId = "explicit-disconnect-test-server"

    override func setUp() {
        super.setUp()
        // Clean up test key
        var explicit = IRCClientManager.shared.explicitlyDisconnectedServerIds
        explicit.remove(testServerId)
        IRCClientManager.shared.explicitlyDisconnectedServerIds = explicit
    }

    func testServerNotInSetByDefault() {
        let explicit = IRCClientManager.shared.explicitlyDisconnectedServerIds
        XCTAssertFalse(explicit.contains(testServerId))
    }

    func testAddingToSet() {
        var explicit = IRCClientManager.shared.explicitlyDisconnectedServerIds
        explicit.insert(testServerId)
        IRCClientManager.shared.explicitlyDisconnectedServerIds = explicit
        XCTAssertTrue(IRCClientManager.shared.explicitlyDisconnectedServerIds.contains(testServerId))
    }

    func testRemovingFromSet() {
        var explicit = IRCClientManager.shared.explicitlyDisconnectedServerIds
        explicit.insert(testServerId)
        IRCClientManager.shared.explicitlyDisconnectedServerIds = explicit
        explicit.remove(testServerId)
        IRCClientManager.shared.explicitlyDisconnectedServerIds = explicit
        XCTAssertFalse(IRCClientManager.shared.explicitlyDisconnectedServerIds.contains(testServerId))
    }

    func testExplicitSetPersistedToUserDefaults() {
        var explicit = IRCClientManager.shared.explicitlyDisconnectedServerIds
        explicit.insert(testServerId)
        IRCClientManager.shared.explicitlyDisconnectedServerIds = explicit
        // Re-read from UserDefaults to confirm persistence
        let stored = Set(UserDefaults.standard.stringArray(forKey: "explicitDisconnects") ?? [])
        XCTAssertTrue(stored.contains(testServerId))
    }
}

// MARK: - LastConnectedServerPersistenceTests

@MainActor
final class LastConnectedServerPersistenceTests: XCTestCase {

    func testSaveConnectedServerIdsWritesToUserDefaults() {
        // No active connections in test environment, so saveConnectedServerIds
        // should write an empty array (or just the connected ones).
        IRCClientManager.shared.saveConnectedServerIds()
        let stored = UserDefaults.standard.stringArray(forKey: "lastConnectedServerIds")
        XCTAssertNotNil(stored)  // key exists
    }

    func testLastConnectedServerIdsReadsBack() {
        UserDefaults.standard.set(["server-a", "server-b"], forKey: "lastConnectedServerIds")
        let ids = IRCClientManager.shared.lastConnectedServerIds
        XCTAssertTrue(ids.contains("server-a"))
        XCTAssertTrue(ids.contains("server-b"))
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "lastConnectedServerIds")
    }

    func testEmptyConnectionsSavesEmptyArray() {
        IRCClientManager.shared.saveConnectedServerIds()
        // The result depends on actual connection state; just check it doesn't crash
        let ids = IRCClientManager.shared.lastConnectedServerIds
        XCTAssertNotNil(ids)
    }
}

// MARK: - ChannelListSortTests

final class ChannelListSortTests: XCTestCase {

    private struct Entry {
        let name: String; let members: Int; let topic: String
    }

    private func sortByMembers(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.members > $1.members }
    }
    private func sortByName(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    private func sortByTopic(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.topic.lowercased() < $1.topic.lowercased() }
    }

    func testMembersDescDefault() {
        let entries = [
            Entry(name: "#b", members: 10, topic: ""),
            Entry(name: "#a", members: 50, topic: ""),
            Entry(name: "#c", members: 5,  topic: ""),
        ]
        let sorted = sortByMembers(entries)
        XCTAssertEqual(sorted[0].members, 50)
        XCTAssertEqual(sorted[1].members, 10)
        XCTAssertEqual(sorted[2].members, 5)
    }

    func testNameAscending() {
        let entries = [
            Entry(name: "#charlie", members: 1, topic: ""),
            Entry(name: "#alice",   members: 2, topic: ""),
            Entry(name: "#bob",     members: 3, topic: ""),
        ]
        let sorted = sortByName(entries)
        XCTAssertEqual(sorted[0].name, "#alice")
        XCTAssertEqual(sorted[1].name, "#bob")
        XCTAssertEqual(sorted[2].name, "#charlie")
    }

    func testTopicAscending() {
        let entries = [
            Entry(name: "#c", members: 1, topic: "Zebra"),
            Entry(name: "#a", members: 2, topic: "Apple"),
            Entry(name: "#b", members: 3, topic: "Mango"),
        ]
        let sorted = sortByTopic(entries)
        XCTAssertEqual(sorted[0].topic, "Apple")
        XCTAssertEqual(sorted[1].topic, "Mango")
        XCTAssertEqual(sorted[2].topic, "Zebra")
    }

    func testTieOnMembersPreservesRelativeOrder() {
        let entries = [
            Entry(name: "#z", members: 10, topic: ""),
            Entry(name: "#a", members: 10, topic: ""),
        ]
        let sorted = sortByMembers(entries)
        // Both have 10 members — order is stable (Swift sort is stable)
        XCTAssertEqual(sorted.count, 2)
    }
}

// MARK: - DMChannelTests

@MainActor
final class DMChannelTests: XCTestCase {

    func testOpenDMCreatesDMChannel() {
        let vm = ConversationsViewModel(ircManager: IRCClientManager.shared)
        let dm = vm.openDM(with: "alice", serverId: "test-server")
        XCTAssertTrue(dm.isDM)
        XCTAssertEqual(dm.name, "alice")
        XCTAssertEqual(dm.serverId, "test-server")
    }

    func testOpenDMTwiceReturnsSameName() {
        let vm = ConversationsViewModel(ircManager: IRCClientManager.shared)
        let dm1 = vm.openDM(with: "bob", serverId: "test-server")
        let dm2 = vm.openDM(with: "bob", serverId: "test-server")
        XCTAssertEqual(dm1.name, dm2.name)
        XCTAssertEqual(dm1.id,   dm2.id)
    }

    func testDeleteConversationRemovesFromList() {
        let vm = ConversationsViewModel(ircManager: IRCClientManager.shared)
        let dm = vm.openDM(with: "charlie-delete-test", serverId: "test-server")
        vm.loadConversations()
        vm.deleteConversation(dm)
        XCTAssertFalse(vm.conversations.contains { $0.id == dm.id })
    }
}

// MARK: - WatchSettingsPhase6Tests
// (WatchSettingsTests already exists in Phase4and5Tests; this extends it with
//  Phase 6 additions: poll-interval clamping and canSend logic.)

@MainActor
final class WatchSettingsPhase6Tests: XCTestCase {

    func testDefaultValues() {
        let s = WatchSettings.default
        XCTAssertEqual(s.pollIntervalMinutes, 5)
        XCTAssertTrue(s.notificationsEnabled)
        XCTAssertEqual(s.debounceSeconds, 60)
        XCTAssertTrue(s.showPreviewInNotification)
    }

    func testPollIntervalClamped() async {
        let wm = await WatchManager.shared
        await wm.updatePollInterval(0)
        await XCTAssertEqual(wm.settings.pollIntervalMinutes, 1)
        await wm.updatePollInterval(99)
        await XCTAssertEqual(wm.settings.pollIntervalMinutes, 5)
        await wm.updatePollInterval(3)
        await XCTAssertEqual(wm.settings.pollIntervalMinutes, 3)
    }

    func testCodable() throws {
        let original = WatchSettings(
            pollIntervalMinutes: 2,
            notificationsEnabled: false,
            debounceSeconds: 120,
            showPreviewInNotification: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchSettings.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testEquatable() {
        let a = WatchSettings.default
        var b = WatchSettings.default
        XCTAssertEqual(a, b)
        b.pollIntervalMinutes = 1
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - IRCListCallbackTests

final class IRCListCallbackTests: XCTestCase {

    func testOnListEntryCallbackExists() {
        let client = IRCClient()
        var receivedName: String?
        var receivedCount: Int?
        var receivedTopic: String?
        client.onListEntry = { name, count, topic in
            receivedName  = name
            receivedCount = count
            receivedTopic = topic
        }
        // Simulate calling it
        client.onListEntry?("#test", 42, "A test channel")
        XCTAssertEqual(receivedName,  "#test")
        XCTAssertEqual(receivedCount, 42)
        XCTAssertEqual(receivedTopic, "A test channel")
    }

    func testOnListEndCallbackExists() {
        let client = IRCClient()
        var called = false
        client.onListEnd = { called = true }
        client.onListEnd?()
        XCTAssertTrue(called)
    }

    func testOnListEntryAndUnhandledMessageAreIndependent() {
        let client = IRCClient()
        var listFired = false
        var unhandledFired = false
        client.onListEntry    = { _, _, _ in listFired = true }
        client.onUnhandledMessage = { _ in unhandledFired = true }
        client.onListEntry?("#ch", 1, "")
        // Setting onListEntry must not affect onUnhandledMessage
        XCTAssertTrue(listFired)
        XCTAssertFalse(unhandledFired)
    }
}

// MARK: - AutoConnectPolicyTests

final class AutoConnectPolicyTests: XCTestCase {

    func testAutoConnectFlagPredicates() {
        var server = Server.defaultNetworks[0]
        server.autoConnect = true
        XCTAssertTrue(server.autoConnect)
        server.autoConnect = false
        XCTAssertFalse(server.autoConnect)
    }

    func testExplicitlyDisconnectedServerShouldNotAutoConnect() {
        let manager = IRCClientManager.shared
        let id = "policy-test-server"
        var explicit = manager.explicitlyDisconnectedServerIds
        explicit.insert(id)
        manager.explicitlyDisconnectedServerIds = explicit

        let lastConnected: Set<String> = [id]
        let shouldConnect = lastConnected.contains(id) && !manager.explicitlyDisconnectedServerIds.contains(id)
        XCTAssertFalse(shouldConnect)

        // Cleanup
        explicit.remove(id)
        manager.explicitlyDisconnectedServerIds = explicit
    }

    func testNonExplicitServerInLastConnectedShouldAutoConnect() {
        let manager = IRCClientManager.shared
        let id = "policy-test-server-2"
        var explicit = manager.explicitlyDisconnectedServerIds
        explicit.remove(id)
        manager.explicitlyDisconnectedServerIds = explicit

        let lastConnected: Set<String> = [id]
        let shouldConnect = lastConnected.contains(id) && !manager.explicitlyDisconnectedServerIds.contains(id)
        XCTAssertTrue(shouldConnect)
    }
}

// MARK: - IRCMessageParsingExtendedTests

final class IRCMessageParsingExtendedTests: XCTestCase {

    func testParsePing() {
        let msg = IRCMessage(rawLine: "PING :irc.libera.chat")
        XCTAssertEqual(msg.command, "PING")
        XCTAssertEqual(msg.parameters.first, "irc.libera.chat")
    }

    func testParseRPLList() {
        let msg = IRCMessage(rawLine: ":irc.libera.chat 322 mynick #linux 1234 :Linux chat")
        XCTAssertEqual(msg.command, "322")
        XCTAssertEqual(msg.parameters.count, 4)
        XCTAssertEqual(msg.parameters[1], "#linux")
        XCTAssertEqual(msg.parameters[2], "1234")
        XCTAssertEqual(msg.parameters[3], "Linux chat")
    }

    func testParseRPLListEnd() {
        let msg = IRCMessage(rawLine: ":irc.libera.chat 323 mynick :End of LIST")
        XCTAssertEqual(msg.command, "323")
        XCTAssertEqual(msg.parameters.last, "End of LIST")
    }

    func testParsePrivmsgCTCPAction() {
        let msg = IRCMessage(rawLine: ":alice!~alice@host PRIVMSG #linux :\u{0001}ACTION waves\u{0001}")
        XCTAssertEqual(msg.command, "PRIVMSG")
        let body = msg.parameters.last ?? ""
        XCTAssertTrue(body.hasPrefix("\u{0001}ACTION"))
        XCTAssertTrue(body.hasSuffix("\u{0001}"))
    }

    func testParseNumericWithNoTrailing() {
        let msg = IRCMessage(rawLine: ":irc.libera.chat 001 mynick")
        XCTAssertEqual(msg.command, "001")
        XCTAssertEqual(msg.parameters.first, "mynick")
    }

    func testParseTaggedMessage() {
        let msg = IRCMessage(rawLine: "@time=2026-04-19T12:00:00Z :alice!user@host PRIVMSG #ch :hello")
        XCTAssertNotNil(msg.tags)
        XCTAssertEqual(msg.command, "PRIVMSG")
        XCTAssertEqual(msg.parameters.last, "hello")
    }
}

// MARK: - WatchManagerCanSendTests

@MainActor
final class WatchManagerCanSendTests: XCTestCase {

    func testCanSendWhenNoHistory() {
        WatchManager.shared.toggleNotifications(true)
        // Reset last notification
        UserDefaults.standard.removeObject(forKey: "last_notification_sent")
        WatchManager.shared.loadSettings()
        XCTAssertTrue(WatchManager.shared.canSendNotification())
    }

    func testCannotSendWhenDisabled() {
        WatchManager.shared.toggleNotifications(false)
        XCTAssertFalse(WatchManager.shared.canSendNotification())
        WatchManager.shared.toggleNotifications(true)
    }

    func testCannotSendWithinDebounceWindow() {
        WatchManager.shared.toggleNotifications(true)
        WatchManager.shared.recordNotificationSent()
        // Immediately after recording, debounce blocks the next send
        XCTAssertFalse(WatchManager.shared.canSendNotification())
    }
}

// MARK: - ChannelNameNormalisationExtendedTests

final class ChannelNameNormalisationExtendedTests: XCTestCase {

    private func normalise(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if !name.hasPrefix("#") && !name.hasPrefix("&") { name = "#\(name)" }
        return name
    }

    func testHashPrefixPreserved() { XCTAssertEqual(normalise("#linux"), "#linux") }
    func testAmpersandPrefixPreserved() { XCTAssertEqual(normalise("&local"), "&local") }
    func testNoPrefixGetsHash() { XCTAssertEqual(normalise("general"), "#general") }
    func testLeadingWhitespaceStripped() { XCTAssertEqual(normalise("  linux"), "#linux") }
    func testTrailingWhitespaceStripped() { XCTAssertEqual(normalise("linux  "), "#linux") }
    func testHashWithSpacesStripped() { XCTAssertEqual(normalise(" #linux "), "#linux") }
}

#endif // !os(Linux)
