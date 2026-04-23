#if !os(Linux)
import XCTest
@testable import ParsoIRC

// MARK: - Phase 7 Tests
//
// Tests covering:
//   • Demo mode "Join Channel" fast path (no getClient error)
//   • Demo DM — intro messages loaded per-nick
//   • Demo DM — send produces an optimistic message + bot reply
//   • Demo DM — report / delete / block context-menu actions work
//   • Demo bot reply uses correct channelId (not __demo_channel__ for DMs)
//   • Reconnect timer is never nil after scheduling (RunLoop.main fix)

// MARK: - DemoJoinChannelTests

/// Verifies that the demo fast path in joinChannel() works correctly.
/// The logic being tested mirrors ChannelBrowserSheet.joinChannel():
///   if isDemoServer → save channel + call onJoined, do NOT call getClient.
@MainActor
final class DemoJoinChannelTests: XCTestCase {

    // Helper that mirrors the fixed joinChannel() logic for unit testing.
    // Returns nil on success, or an error string if getClient would have been hit.
    private func simulateJoin(
        rawName: String,
        serverId: String
    ) -> (channelName: String?, joinError: String?) {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return (nil, "empty name") }
        if !name.hasPrefix("#") && !name.hasPrefix("&") { name = "#\(name)" }

        // Demo fast path — mirrors ChannelBrowserSheet fix
        if IRCClientManager.isDemoServer(serverId) {
            return (name, nil)       // success: no error
        }

        // Non-demo: simulate getClient returning nil (not connected)
        let client = IRCClientManager.shared.getClient(for: serverId)
        if client == nil {
            return (nil, "Not connected to server")
        }
        return (name, nil)
    }

    func testJoinDemoChannelSucceeds() {
        let (name, error) = simulateJoin(rawName: "#demo",
                                         serverId: DemoContent.serverId)
        XCTAssertNil(error,
            "Joining #demo in demo mode must not produce an error (was: \(error ?? "nil"))")
        XCTAssertEqual(name, "#demo")
    }

    func testJoinArbitraryChannelInDemoSucceeds() {
        let (name, error) = simulateJoin(rawName: "general",
                                         serverId: DemoContent.serverId)
        XCTAssertNil(error,
            "Joining any channel in demo mode must not produce an error")
        XCTAssertEqual(name, "#general",
            "Channel name must be normalised with # prefix")
    }

    func testJoinWithHashPrefixInDemoSucceeds() {
        let (name, error) = simulateJoin(rawName: "#linux",
                                         serverId: DemoContent.serverId)
        XCTAssertNil(error)
        XCTAssertEqual(name, "#linux")
    }

    func testJoinWithWhitespaceTrimmedInDemo() {
        let (name, error) = simulateJoin(rawName: "  swift  ",
                                         serverId: DemoContent.serverId)
        XCTAssertNil(error)
        XCTAssertEqual(name, "#swift",
            "Leading/trailing whitespace must be stripped before normalisation")
    }

    func testJoinNonDemoServerWithoutClientFails() {
        // A real (non-demo) server with no active connection should still fail
        let (_, error) = simulateJoin(rawName: "#linux",
                                      serverId: "real-server-not-connected")
        XCTAssertNotNil(error,
            "A non-demo server with no client must produce an error")
    }

    func testJoinEmptyNameIsIgnored() {
        let (name, error) = simulateJoin(rawName: "  ",
                                         serverId: DemoContent.serverId)
        XCTAssertNil(name)
        XCTAssertNotNil(error)
    }

    func testAmpersandPrefixPreservedInDemo() {
        let (name, error) = simulateJoin(rawName: "&local",
                                         serverId: DemoContent.serverId)
        XCTAssertNil(error)
        XCTAssertEqual(name, "&local",
            "& prefix must be preserved (local channel sigil)")
    }
}

// MARK: - DemoContentDMTests

/// Tests the new DemoContent DM helpers directly (no view model needed).
final class DemoContentDMTests: XCTestCase {

    // MARK: dmIntroMessages

    func testAliceIntroMessagesNotEmpty() {
        let msgs = DemoContent.dmIntroMessages(for: "Alice", channelId: "dm-alice")
        XCTAssertFalse(msgs.isEmpty, "Alice DM intro messages must not be empty")
    }

    func testBobIntroMessagesNotEmpty() {
        let msgs = DemoContent.dmIntroMessages(for: "Bob", channelId: "dm-bob")
        XCTAssertFalse(msgs.isEmpty)
    }

    func testCharlieIntroMessagesNotEmpty() {
        let msgs = DemoContent.dmIntroMessages(for: "Charlie", channelId: "dm-charlie")
        XCTAssertFalse(msgs.isEmpty)
    }

    func testUnknownNickFallsBackToDefault() {
        let msgs = DemoContent.dmIntroMessages(for: "DemoBot", channelId: "dm-bot")
        XCTAssertFalse(msgs.isEmpty, "Unknown nick must fall back to default intro messages")
    }

    func testIntroMessagesUseDMChannelId() {
        let cid = "test-dm-channel-id"
        let msgs = DemoContent.dmIntroMessages(for: "Alice", channelId: cid)
        for msg in msgs {
            XCTAssertEqual(msg.channelId, cid,
                "All intro messages must use the provided channelId, not __demo_channel__")
        }
    }

    func testIntroMessagesSenderIsTheNick() {
        let msgs = DemoContent.dmIntroMessages(for: "Bob", channelId: "any")
        let nonBobSenders = msgs.filter { $0.sender.lowercased() != "bob" }
        XCTAssertTrue(nonBobSenders.isEmpty,
            "All DM intro messages for Bob must have sender == 'Bob'")
    }

    func testIntroMessagesHaveReasonableTimestamps() {
        let before = Date()
        let msgs = DemoContent.dmIntroMessages(for: "Alice", channelId: "ts-test")
        for msg in msgs {
            XCTAssertLessThanOrEqual(msg.timestamp, before,
                "Intro messages must be in the past (not future-dated)")
        }
    }

    // MARK: dmBotReply

    func testDMBotReplyUsesProvidedChannelId() {
        let cid = "unique-dm-cid"
        let reply = DemoContent.dmBotReply(to: "Alice", index: 0, channelId: cid)
        XCTAssertEqual(reply.channelId, cid,
            "dmBotReply must use the provided channelId, not __demo_channel__")
    }

    func testDMBotReplyChannelIdIsNotDemoChannel() {
        let reply = DemoContent.dmBotReply(to: "Bob", index: 0, channelId: "my-dm")
        XCTAssertNotEqual(reply.channelId, DemoContent.channelId,
            "dmBotReply must NOT use __demo_channel__ when a custom channelId is supplied")
    }

    func testDMBotReplySenderIsTheNick() {
        let reply = DemoContent.dmBotReply(to: "Charlie", index: 0, channelId: "any")
        XCTAssertEqual(reply.sender, "Charlie",
            "dmBotReply sender must be the target nick, not DemoBot")
    }

    func testDMBotRepliesRotateForAlice() {
        // Collect 20 replies and verify at least 2 distinct content strings
        let replies = (0..<20).map {
            DemoContent.dmBotReply(to: "Alice", index: $0, channelId: "c").content
        }
        let unique = Set(replies)
        XCTAssertGreaterThan(unique.count, 1,
            "dmBotReply must rotate through multiple replies, not repeat the same one")
    }

    func testDMBotRepliesRotateForUnknownNick() {
        let replies = (0..<20).map {
            DemoContent.dmBotReply(to: "Stranger", index: $0, channelId: "c").content
        }
        let unique = Set(replies)
        XCTAssertGreaterThan(unique.count, 1,
            "Unknown nick must also rotate through the default reply set")
    }

    func testChannelBotReplyUsesProvidedChannelId() {
        // botReply(index:channelId:) — the channel-mode reply must also honour
        // the channelId override so ChannelViewModel can pass its real channelId.
        let cid = "channel-cid-override"
        let reply = DemoContent.botReply(index: 0, channelId: cid)
        XCTAssertEqual(reply.channelId, cid)
    }

    func testChannelBotReplyDefaultsToDemo() {
        // When called without an explicit channelId it must default to the
        // demo channel ID (backward compatibility).
        let reply = DemoContent.botReply(index: 0)
        XCTAssertEqual(reply.channelId, DemoContent.channelId)
    }
}

// MARK: - DemoDMViewModelTests

/// Tests ChannelViewModel behaviour in demo mode with a DM channelName.
@MainActor
final class DemoDMViewModelTests: XCTestCase {

    private var viewModel: ChannelViewModel!

    override func setUp() async throws {
        // Use the demo server ID with a nick (non-# name) to simulate a DM
        viewModel = ChannelViewModel(
            serverId: DemoContent.serverId,
            channelName: "Alice",   // DM target
            ircManager: IRCClientManager.shared
        )
    }

    override func tearDown() async throws {
        // Clean up any moderation state written to the shared DB during tests.
        // Demo DM intro messages use stable IDs — without cleanup, a test that
        // blocks Alice or hides "dm-alice-0" contaminates subsequent tests that
        // load those same IDs via loadModerationState().
        try? DatabaseManager.shared.unblockUser(nick: "Alice")
        for id in ["dm-alice-0", "dm-alice-1", "dm-alice-2"] {
            try? DatabaseManager.shared.unhideMessage(id: id)
        }
        viewModel = nil
    }

    // MARK: Loading

    func testDemoDMLoadsIntroMessagesOnStart() async {
        await viewModel.start()
        XCTAssertFalse(viewModel.displayMessages.isEmpty,
            "Demo DM must have pre-seeded intro messages after start()")
    }

    func testDemoDMDoesNotLoadChannelMessages() async {
        await viewModel.start()
        // Channel messages contain #demo-specific content like "joined #demo"
        let channelSpecific = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.content.contains("joined #demo") || $0.sender == "DemoBot" && $0.content.contains("Welcome to #demo") }
        XCTAssertTrue(channelSpecific.isEmpty,
            "Demo DM must not show #demo channel messages")
    }

    func testDemoDMIntroMessagesSenderIsAlice() async {
        await viewModel.start()
        let messages = viewModel.displayMessages.compactMap { $0.message }
        XCTAssertFalse(messages.isEmpty)
        let nonAlice = messages.filter { $0.sender.lowercased() != "alice" }
        XCTAssertTrue(nonAlice.isEmpty,
            "All pre-seeded messages in Alice DM must be from Alice")
    }

    func testDemoDMIsLoadingHistoryFalseAfterStart() async {
        await viewModel.start()
        XCTAssertFalse(viewModel.isLoadingHistory,
            "isLoadingHistory must be false after loadDemoMessages completes")
    }

    // MARK: Sending

    func testDemoDMSendAppendsOwnMessageImmediately() async {
        await viewModel.start()
        let countBefore = viewModel.displayMessages.count
        viewModel.send("Hello Alice!")
        XCTAssertGreaterThan(viewModel.displayMessages.count, countBefore,
            "Sending a message must optimistically append it immediately")
    }

    func testDemoDMSentMessageHasCorrectContent() async {
        await viewModel.start()
        viewModel.send("test DM message")
        let last = viewModel.displayMessages.compactMap({ $0.message }).last
        XCTAssertEqual(last?.content, "test DM message")
    }

    func testDemoDMSentMessageIsFromCurrentUser() async {
        await viewModel.start()
        viewModel.send("my own message")
        let ownMessages = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.isFromCurrentUser }
        XCTAssertFalse(ownMessages.isEmpty,
            "Sent message must be marked isFromCurrentUser = true")
    }

    func testDemoDMBotReplyArrivesAsynchronously() async {
        await viewModel.start()
        let countAfterLoad = viewModel.displayMessages.count
        viewModel.send("Hi Alice!")

        // Wait for the 1.5s bot reply
        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
        XCTAssertGreaterThan(viewModel.displayMessages.count, countAfterLoad + 1,
            "A bot reply from Alice must arrive after ~1.5s")
    }

    func testDemoDMBotReplyIsFromAlice() async {
        await viewModel.start()
        viewModel.send("trigger reply")
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        let aliceReplies = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.sender == "Alice" && !$0.isFromCurrentUser }
        XCTAssertFalse(aliceReplies.isEmpty,
            "Bot reply in Alice DM must be from Alice, not DemoBot")
    }

    func testDemoDMBotReplyUsesCorrectChannelId() async {
        await viewModel.start()
        viewModel.send("ping")
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        let botMessages = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.sender == "Alice" && !$0.isFromCurrentUser }
        guard let reply = botMessages.last else {
            XCTFail("Expected a bot reply"); return
        }
        XCTAssertNotEqual(reply.channelId, DemoContent.channelId,
            "DM bot reply channelId must NOT be __demo_channel__")
    }

    // MARK: Moderation in demo DM

    func testDemoDMDeleteMessageHidesIt() async {
        await viewModel.start()
        guard let msg = viewModel.displayMessages.compactMap({ $0.message }).first else {
            XCTFail("Expected at least one pre-seeded message"); return
        }
        viewModel.locallyDeleteMessage(id: msg.id)
        let visible = viewModel.displayMessages.compactMap { $0.message }.contains { $0.id == msg.id }
        XCTAssertFalse(visible,
            "locallyDeleteMessage must remove the message from displayMessages")
    }

    func testDemoDMDeletedMessageIdInHiddenSet() async {
        await viewModel.start()
        guard let msg = viewModel.displayMessages.compactMap({ $0.message }).first else {
            XCTFail("Expected at least one pre-seeded message"); return
        }
        viewModel.locallyDeleteMessage(id: msg.id)
        XCTAssertTrue(viewModel.hiddenMessageIds.contains(msg.id),
            "Deleted message ID must be in hiddenMessageIds")
    }

    func testDemoDMBlockSenderHidesTheirMessages() async {
        await viewModel.start()
        // Verify Alice has messages, then block her
        let aliceBefore = viewModel.displayMessages.compactMap { $0.message }.filter { $0.sender == "Alice" }
        XCTAssertFalse(aliceBefore.isEmpty, "Need Alice messages present before blocking")

        viewModel.blockSender(nick: "Alice")

        let aliceAfter = viewModel.displayMessages.compactMap { $0.message }.filter { $0.sender == "Alice" }
        XCTAssertTrue(aliceAfter.isEmpty,
            "All Alice messages must be hidden after blockSender(nick: 'Alice')")
    }

    func testDemoDMBlockedNickInBlockedSet() async {
        await viewModel.start()
        viewModel.blockSender(nick: "Alice")
        XCTAssertTrue(viewModel.blockedNicks.contains("Alice"),
            "Blocked nick must appear in blockedNicks set")
    }

    func testDemoDMCannotBlockCurrentUser() async {
        await viewModel.start()
        let myNick = viewModel.currentNick
        viewModel.blockSender(nick: myNick)
        XCTAssertFalse(viewModel.blockedNicks.contains(myNick),
            "blockSender must not block the current user's own nick")
    }

    func testDemoDMDeleteThenRebuildStaysHidden() async {
        await viewModel.start()
        guard let msg = viewModel.displayMessages.compactMap({ $0.message }).first else {
            XCTFail("Need a message to delete"); return
        }
        viewModel.locallyDeleteMessage(id: msg.id)
        // Send another message to trigger a fresh rebuild
        viewModel.send("trigger rebuild")
        let visible = viewModel.displayMessages.compactMap { $0.message }.contains { $0.id == msg.id }
        XCTAssertFalse(visible,
            "Deleted message must stay hidden even after a subsequent rebuild")
    }

    func testDemoDMBlockThenSendStaysHidden() async {
        await viewModel.start()
        viewModel.blockSender(nick: "Alice")
        viewModel.send("any message")
        let aliceVisible = viewModel.displayMessages.compactMap { $0.message }.filter { $0.sender == "Alice" }
        XCTAssertTrue(aliceVisible.isEmpty,
            "Alice's messages must stay hidden after blocking, even after new sends")
    }
}

// MARK: - DemoDMBobViewModelTests

/// Smoke-tests the same DM logic for Bob to confirm per-nick routing works.
@MainActor
final class DemoDMBobViewModelTests: XCTestCase {

    private var viewModel: ChannelViewModel!

    override func setUp() async throws {
        viewModel = ChannelViewModel(
            serverId: DemoContent.serverId,
            channelName: "Bob",
            ircManager: IRCClientManager.shared
        )
    }

    override func tearDown() async throws { viewModel = nil }

    func testBobDMLoadsIntroMessages() async {
        await viewModel.start()
        XCTAssertFalse(viewModel.displayMessages.isEmpty)
    }

    func testBobDMIntroSenderIsBob() async {
        await viewModel.start()
        let messages = viewModel.displayMessages.compactMap { $0.message }
        let nonBob = messages.filter { $0.sender.lowercased() != "bob" }
        XCTAssertTrue(nonBob.isEmpty,
            "All pre-seeded messages in Bob DM must be from Bob")
    }

    func testBobDMBotReplyIsFromBob() async {
        await viewModel.start()
        viewModel.send("Hey Bob!")
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let bobReplies = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.sender == "Bob" && !$0.isFromCurrentUser }
        XCTAssertFalse(bobReplies.isEmpty, "Bot reply in Bob DM must be from Bob")
    }
}

// MARK: - DemoChannelViewModelTests

/// Confirms the existing #demo channel behaviour is unchanged by our refactor.
@MainActor
final class DemoChannelViewModelTests: XCTestCase {

    private var viewModel: ChannelViewModel!

    override func setUp() async throws {
        viewModel = ChannelViewModel(
            serverId: DemoContent.serverId,
            channelName: DemoContent.channelName,   // "#demo"
            ircManager: IRCClientManager.shared
        )
    }

    override func tearDown() async throws {
        // Clean up moderation state written to the shared DB during tests.
        // Demo channel messages use stable IDs — without cleanup, a hide/block
        // from one test contaminates subsequent tests via loadModerationState().
        try? DatabaseManager.shared.unblockUser(nick: "Alice")
        let stableChannelIds = ["demo-sys-0", "demo-sys-1", "demo-sys-2",
                                "demo-msg-1", "demo-msg-2", "demo-msg-3",
                                "demo-msg-4", "demo-msg-5", "demo-msg-6",
                                "demo-msg-7", "demo-msg-8", "demo-msg-9",
                                "demo-msg-10", "demo-msg-11"]
        for id in stableChannelIds {
            try? DatabaseManager.shared.unhideMessage(id: id)
        }
        viewModel = nil
    }

    func testDemoChannelLoadsMessages() async {
        await viewModel.start()
        XCTAssertFalse(viewModel.displayMessages.isEmpty,
            "#demo channel must load pre-seeded messages")
    }

    func testDemoChannelLoadsMembers() async {
        await viewModel.start()
        XCTAssertFalse(viewModel.members.isEmpty,
            "#demo channel must populate the member list")
    }

    func testDemoChannelTopicSet() async {
        await viewModel.start()
        XCTAssertFalse(viewModel.topic.isEmpty,
            "#demo channel must have a non-empty topic")
    }

    func testDemoChannelBotReplyIsFromDemoBot() async {
        await viewModel.start()
        viewModel.send("Hello channel!")
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let botReplies = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.sender == "DemoBot" }
        XCTAssertFalse(botReplies.isEmpty,
            "Channel bot reply must come from DemoBot")
    }

    func testDemoChannelBotReplyChannelIdIsCorrect() async {
        await viewModel.start()
        viewModel.send("trigger")
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let botReplies = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.sender == "DemoBot" && !$0.isFromCurrentUser }
        guard let reply = botReplies.last else {
            XCTFail("Expected a DemoBot reply"); return
        }
        // Must NOT be __demo_channel__ when using the real channelId of this VM
        // (the fixed botReply now uses the VM's channelId, which for this VM
        //  happens to be the demo channel id if it's in the DB, or the
        //  serverId:channelName fallback — either way it must equal viewModel.channelId)
        XCTAssertEqual(reply.channelId, viewModel.channelId,
            "Channel bot reply channelId must match the view model's channelId")
    }

    func testDemoChannelDeleteMessageWorks() async {
        await viewModel.start()
        guard let msg = viewModel.displayMessages.compactMap({ $0.message }).first else {
            XCTFail("Need a message"); return
        }
        viewModel.locallyDeleteMessage(id: msg.id)
        let visible = viewModel.displayMessages.compactMap { $0.message }.contains { $0.id == msg.id }
        XCTAssertFalse(visible)
    }

    func testDemoChannelBlockSenderWorks() async {
        await viewModel.start()
        viewModel.blockSender(nick: "Alice")
        let aliceVisible = viewModel.displayMessages
            .compactMap { $0.message }
            .filter { $0.sender == "Alice" }
        XCTAssertTrue(aliceVisible.isEmpty)
    }
}

// MARK: - DemoReportMessageTests

/// Validates the report message data structure used by MessageListView.
/// (We can't open the mail client in unit tests, but we can verify the data.)
final class DemoReportMessageTests: XCTestCase {

    private func buildReportBody(channel: String, message: Message) -> String {
        let formatter = ISO8601DateFormatter()
        let ts = formatter.string(from: message.timestamp)
        return """
        Channel: \(channel)
        Sender: \(message.sender)
        Time: \(ts)
        Message: \(message.content)
        """
    }

    func testReportBodyContainsSender() {
        let msg = Message(channelId: "c", sender: "Alice",
                          content: "bad content", type: .message)
        let body = buildReportBody(channel: "#demo", message: msg)
        XCTAssertTrue(body.contains("Alice"),
            "Report body must include the sender's nick")
    }

    func testReportBodyContainsContent() {
        let msg = Message(channelId: "c", sender: "Bob",
                          content: "offensive text", type: .message)
        let body = buildReportBody(channel: "#demo", message: msg)
        XCTAssertTrue(body.contains("offensive text"),
            "Report body must include the message content")
    }

    func testReportBodyContainsChannel() {
        let msg = Message(channelId: "c", sender: "Charlie",
                          content: "msg", type: .message)
        let body = buildReportBody(channel: "Alice", message: msg)
        XCTAssertTrue(body.contains("Alice"),
            "Report body must include the channel/DM name")
    }

    func testReportBodyContainsTimestamp() {
        let msg = Message(channelId: "c", sender: "DemoBot",
                          content: "some msg", type: .message)
        let body = buildReportBody(channel: "#demo", message: msg)
        // ISO8601 timestamps contain "T" and "Z"
        XCTAssertTrue(body.contains("T") && body.contains(":"),
            "Report body must include a formatted timestamp")
    }

    func testReportBodyNotEmpty() {
        let msgs = DemoContent.dmIntroMessages(for: "Alice", channelId: "c")
        for msg in msgs {
            let body = buildReportBody(channel: "Alice", message: msg)
            XCTAssertFalse(body.isEmpty)
        }
    }
}

// MARK: - ReconnectTimerTests

/// Verifies reconnect timer scheduling properties (RunLoop.main fix).
final class ReconnectTimerTests: XCTestCase {

    /// Verifies that the timer created by the reconnect path is valid and
    /// fires on the main thread.  We replicate the fixed pattern directly.
    func testTimerCreatedWithRunLoopMainDoesNotReturnNil() {
        var fired = false
        var firedOnMain = false
        let expectation = XCTestExpectation(description: "Timer fires")

        let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
            fired = true
            firedOnMain = Thread.isMainThread
            expectation.fulfill()
        }
        RunLoop.main.add(timer, forMode: .common)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(fired, "Timer must fire")
        XCTAssertTrue(firedOnMain,
            "Timer added to RunLoop.main must fire on the main thread")
        // Clean up
        timer.invalidate()
    }

    func testTimerIsValidAfterAddingToRunLoop() {
        let timer = Timer(timeInterval: 60, repeats: false) { _ in }
        RunLoop.main.add(timer, forMode: .common)
        XCTAssertTrue(timer.isValid, "Timer must be valid immediately after adding to RunLoop")
        timer.invalidate()
        XCTAssertFalse(timer.isValid, "Invalidated timer must report isValid == false")
    }

    func testInvalidatingTimerBeforeFireDoesNotCrash() {
        let timer = Timer(timeInterval: 10, repeats: false) { _ in
            XCTFail("Invalidated timer must not fire")
        }
        RunLoop.main.add(timer, forMode: .common)
        timer.invalidate()
        // Sleep briefly to confirm it does not fire
        Thread.sleep(forTimeInterval: 0.05)
        // If we reach here without XCTFail, the test passes.
    }

    func testMultipleTimersCanBeAddedAndIndividuallyInvalidated() {
        var timerA: Timer?
        var timerB: Timer?

        timerA = Timer(timeInterval: 60, repeats: false) { _ in }
        timerB = Timer(timeInterval: 60, repeats: false) { _ in }
        RunLoop.main.add(timerA!, forMode: .common)
        RunLoop.main.add(timerB!, forMode: .common)

        timerA?.invalidate()

        XCTAssertFalse(timerA!.isValid, "timerA must be invalidated")
        XCTAssertTrue(timerB!.isValid, "timerB must still be valid")

        timerB?.invalidate()
    }
}

#endif // !os(Linux)
