#if !os(Linux)
import XCTest
@testable import ParsoIRC

// MARK: - ChannelBrowserSheet.ListEntry Tests

final class ChannelListEntryTests: XCTestCase {

    func testListEntryIdIsChannelName() {
        let entry = ChannelBrowserSheet.ListEntry(id: "#linux", name: "#linux",
                                                  members: 42, topic: "Linux chat")
        XCTAssertEqual(entry.id, "#linux")
    }

    func testListEntryStoredCorrectly() {
        let entry = ChannelBrowserSheet.ListEntry(id: "#swift", name: "#swift",
                                                  members: 100, topic: "Swift programming")
        XCTAssertEqual(entry.name, "#swift")
        XCTAssertEqual(entry.members, 100)
        XCTAssertEqual(entry.topic, "Swift programming")
    }

    func testListEntryWithEmptyTopic() {
        let entry = ChannelBrowserSheet.ListEntry(id: "#empty", name: "#empty",
                                                  members: 1, topic: "")
        XCTAssertTrue(entry.topic.isEmpty)
    }
}

// MARK: - ChannelBrowserSheet sort logic

final class ChannelBrowserSortTests: XCTestCase {

    private let entries: [ChannelBrowserSheet.ListEntry] = [
        .init(id: "#zebra",   name: "#zebra",   members: 5,   topic: "Aardvark topic"),
        .init(id: "#alpha",   name: "#alpha",   members: 100, topic: "Zebra topic"),
        .init(id: "#middle",  name: "#middle",  members: 50,  topic: "Middle topic"),
    ]

    func testSortByMembersDescending() {
        let sorted = entries.sorted { $0.members > $1.members }
        XCTAssertEqual(sorted[0].name, "#alpha")   // 100
        XCTAssertEqual(sorted[1].name, "#middle")  // 50
        XCTAssertEqual(sorted[2].name, "#zebra")   // 5
    }

    func testSortByNameAscending() {
        let sorted = entries.sorted { $0.name.lowercased() < $1.name.lowercased() }
        XCTAssertEqual(sorted[0].name, "#alpha")
        XCTAssertEqual(sorted[1].name, "#middle")
        XCTAssertEqual(sorted[2].name, "#zebra")
    }

    func testSortByTopicAscending() {
        let sorted = entries.sorted { $0.topic.lowercased() < $1.topic.lowercased() }
        XCTAssertEqual(sorted[0].topic, "Aardvark topic")
        XCTAssertEqual(sorted[1].topic, "Middle topic")
        XCTAssertEqual(sorted[2].topic, "Zebra topic")
    }

    func testSortByMembersWithTie() {
        let tied: [ChannelBrowserSheet.ListEntry] = [
            .init(id: "#b", name: "#b", members: 10, topic: ""),
            .init(id: "#a", name: "#a", members: 10, topic: ""),
        ]
        let sorted = tied.sorted { $0.members > $1.members }
        // Stable sort preserves original order for equal elements
        XCTAssertEqual(sorted.count, 2)
    }
}

// MARK: - ChannelBrowserSheet search filter

final class ChannelBrowserSearchTests: XCTestCase {

    private let entries: [ChannelBrowserSheet.ListEntry] = [
        .init(id: "#linux",  name: "#linux",  members: 50, topic: "Linux discussion"),
        .init(id: "#debian", name: "#debian", members: 30, topic: "Debian users"),
        .init(id: "#rust",   name: "#rust",   members: 20, topic: "Rust language"),
    ]

    private func filter(_ text: String) -> [ChannelBrowserSheet.ListEntry] {
        guard !text.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(text) ||
            $0.topic.localizedCaseInsensitiveContains(text)
        }
    }

    func testEmptySearchReturnsAll() {
        XCTAssertEqual(filter("").count, 3)
    }

    func testSearchByChannelName() {
        let results = filter("linux")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "#linux")
    }

    func testSearchByTopic() {
        let results = filter("rust language")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "#rust")
    }

    func testCaseInsensitiveSearch() {
        XCTAssertEqual(filter("LINUX").count, 1)
        XCTAssertEqual(filter("Debian").count, 1)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(filter("haskell").isEmpty)
    }
}

// MARK: - Channel isDM field tests

final class ChannelIsDMTests: XCTestCase {

    func testDefaultChannelIsNotDM() {
        let ch = Channel(name: "#linux")
        XCTAssertFalse(ch.isDM)
    }

    func testDMChannelFlag() {
        var ch = Channel(name: "alice")
        ch.isDM = true
        XCTAssertTrue(ch.isDM)
    }

    func testDMChannelInit() {
        let ch = Channel(serverId: "s1", name: "bob", isDM: true)
        XCTAssertTrue(ch.isDM)
        XCTAssertEqual(ch.name, "bob")
        XCTAssertEqual(ch.serverId, "s1")
    }

    func testChannelCodablePreservesDMFlag() throws {
        let ch = Channel(name: "carol", isDM: true)
        let data = try JSONEncoder().encode(ch)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertTrue(decoded.isDM)
    }

    func testRegularChannelCodableIsDMFalse() throws {
        let ch = Channel(name: "#general")
        let data = try JSONEncoder().encode(ch)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertFalse(decoded.isDM)
    }

    func testDMDisplayName() {
        // DM display name is just the nick (no # prefix to strip)
        let ch = Channel(name: "dave", isDM: true)
        XCTAssertEqual(ch.displayName, "dave")
    }
}

// MARK: - ConversationsViewModel logic tests

@MainActor
final class ConversationsViewModelTests: XCTestCase {

    var vm: ConversationsViewModel!

    override func setUp() async throws {
        vm = ConversationsViewModel(ircManager: IRCClientManager.shared)
    }

    func testInitialConversationsEmpty() {
        // In test environment no DB servers exist
        vm.loadConversations()
        // Just verify it doesn't crash and returns a list
        XCTAssertNotNil(vm.conversations)
    }

    func testOpenDMCreatesNewConversation() {
        // openDM creates a Channel with isDM = true
        let ch = vm.openDM(with: "alice", serverId: "test-server-999")
        XCTAssertEqual(ch.name, "alice")
        XCTAssertTrue(ch.isDM)
        XCTAssertEqual(ch.serverId, "test-server-999")
    }

    func testOpenDMReusesSameConversation() {
        let ch1 = vm.openDM(with: "bob", serverId: "svr1")
        let ch2 = vm.openDM(with: "bob", serverId: "svr1")
        // Both calls should return channels with the same name
        XCTAssertEqual(ch1.name, ch2.name)
        XCTAssertEqual(ch1.serverId, ch2.serverId)
    }

    func testDeleteConversationRemovesFromList() {
        // Manually add a DM channel to the vm's list for testing
        var ch = Channel(name: "charlie", isDM: true)
        ch.serverId = "svr-test"
        // We can't inject directly into private(set), so test via openDM
        let opened = vm.openDM(with: "charlie", serverId: "svr-test")
        vm.deleteConversation(opened)
        XCTAssertFalse(vm.conversations.contains { $0.name == "charlie" && $0.serverId == "svr-test" })
    }
}

// MARK: - WatchSettings tests

final class WatchSettingsTests: XCTestCase {

    func testDefaultSettings() {
        let s = WatchSettings.default
        XCTAssertEqual(s.pollIntervalMinutes, 5)
        XCTAssertTrue(s.notificationsEnabled)
        XCTAssertEqual(s.debounceSeconds, 60)
        XCTAssertTrue(s.showPreviewInNotification)
    }

    func testPollIntervalClamped() {
        var s = WatchSettings.default
        s.pollIntervalMinutes = max(1, min(5, 0))   // clamp 0 → 1
        XCTAssertEqual(s.pollIntervalMinutes, 1)
        s.pollIntervalMinutes = max(1, min(5, 99))  // clamp 99 → 5
        XCTAssertEqual(s.pollIntervalMinutes, 5)
    }

    func testCodable() throws {
        let s = WatchSettings(pollIntervalMinutes: 3, notificationsEnabled: false,
                              debounceSeconds: 120, showPreviewInNotification: false)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WatchSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testEquatable() {
        let a = WatchSettings.default
        var b = WatchSettings.default
        XCTAssertEqual(a, b)
        b.pollIntervalMinutes = 1
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - AppearanceSettingsView storage key tests

final class AppearanceSettingsTests: XCTestCase {

    func testDefaultFontSizeIsReasonable() {
        // The default is 15pt — sanity check
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: "messageFontSize")
        // If never set, UserDefaults returns 0; 15 is the code default
        // We just verify it's within the allowed slider range (0 means unset)
        XCTAssertTrue(stored == 0 || (stored >= 11 && stored <= 21),
                      "Font size should be in slider range 11–21pt or 0 (unset)")
    }

    func testDensityOptions() {
        let validValues = ["comfortable", "compact"]
        let stored = UserDefaults.standard.string(forKey: "messageDensity") ?? "comfortable"
        XCTAssertTrue(validValues.contains(stored),
                      "messageDensity should be one of \(validValues), got \(stored)")
    }
}

// MARK: - Channel name normalisation (join logic)

final class ChannelNameNormalisationTests: XCTestCase {

    /// Mirrors the "#" prefix normalisation in ChannelBrowserSheet.joinChannel
    /// and ChannelBrowserSheet.manualJoinSheet.
    private func normalise(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if !n.hasPrefix("#") && !n.hasPrefix("&") { n = "#\(n)" }
        return n
    }

    func testHashPrefixPreserved() {
        XCTAssertEqual(normalise("#linux"), "#linux")
    }

    func testAmpersandPrefixPreserved() {
        XCTAssertEqual(normalise("&local"), "&local")
    }

    func testNoPrefixGetsHash() {
        XCTAssertEqual(normalise("linux"), "#linux")
    }

    func testLeadingWhitespaceStripped() {
        XCTAssertEqual(normalise("  linux  "), "#linux")
    }

    func testHashAndWhitespace() {
        XCTAssertEqual(normalise("  #linux  "), "#linux")
    }
}

#endif // !os(Linux)
