#if !os(Linux)
import XCTest
@testable import ParsoIRC

// MARK: - DisplayMessage Tests

final class DisplayMessageTests: XCTestCase {

    // MARK: Identifiers

    func testDateSeparatorHasStableId() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let sep = DisplayMessage.dateSeparator(date)
        XCTAssertEqual(sep.id, "sep-1000000.0")
    }

    func testMessageIdMatchesUnderlyingMessage() {
        let msg = Message(id: "abc123", channelId: "ch", sender: "alice", content: "hi")
        let dm = DisplayMessage.message(msg, grouped: false)
        XCTAssertEqual(dm.id, "abc123")
    }

    func testDateSeparatorIsNotSystemMessage() {
        let sep = DisplayMessage.dateSeparator(Date())
        XCTAssertFalse(sep.isSystemMessage)
    }

    func testDateSeparatorMessagePropertyIsNil() {
        let sep = DisplayMessage.dateSeparator(Date())
        XCTAssertNil(sep.message)
    }

    // MARK: isSystemMessage

    func testRegularMessageIsNotSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "hello", type: .message)
        XCTAssertFalse(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testActionMessageIsNotSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "waves", type: .action)
        XCTAssertFalse(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testNoticeIsNotSystem() {
        let msg = Message(channelId: "c", sender: "server", content: "notice", type: .notice)
        XCTAssertFalse(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testJoinIsSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "alice joined", type: .join)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testPartIsSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "alice left", type: .part)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testQuitIsSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "alice quit", type: .quit)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testNickChangeIsSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "alice → bob", type: .nick)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testModeIsSystem() {
        let msg = Message(channelId: "c", sender: "#linux", content: "+m", type: .mode)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testTopicIsSystem() {
        let msg = Message(channelId: "c", sender: "alice", content: "new topic", type: .topic)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    func testKickIsSystem() {
        let msg = Message(channelId: "c", sender: "op", content: "kicked bob", type: .kick)
        XCTAssertTrue(DisplayMessage.message(msg, grouped: false).isSystemMessage)
    }

    // MARK: Grouped flag round-trip

    func testGroupedFlagRoundTrip() {
        let msg = Message(channelId: "c", sender: "alice", content: "x")
        let grouped   = DisplayMessage.message(msg, grouped: true)
        let ungrouped = DisplayMessage.message(msg, grouped: false)

        if case .message(_, let g) = grouped   { XCTAssertTrue(g)  }
        if case .message(_, let g) = ungrouped { XCTAssertFalse(g) }
    }

    // MARK: message property

    func testMessagePropertyReturnsCorrectMessage() {
        let msg = Message(channelId: "c", sender: "alice", content: "hello")
        let dm  = DisplayMessage.message(msg, grouped: false)
        XCTAssertEqual(dm.message?.id, msg.id)
        XCTAssertEqual(dm.message?.content, "hello")
    }
}

// MARK: - ChannelViewModel Display-Rebuild Logic Tests
//
// These tests exercise the pure-logic helpers on ChannelViewModel without
// starting a live IRC connection.  We use the @MainActor annotation because
// ChannelViewModel is @MainActor-isolated.

@MainActor
final class ChannelViewModelLogicTests: XCTestCase {

    private var viewModel: ChannelViewModel!

    override func setUp() async throws {
        viewModel = ChannelViewModel(
            serverId: "test-server",
            channelName: "#test",
            ircManager: IRCClientManager.shared
        )
    }

    override func tearDown() async throws {
        viewModel = nil
    }

    // MARK: Initial state

    func testInitialStateIsEmpty() {
        XCTAssertTrue(viewModel.displayMessages.isEmpty)
        XCTAssertTrue(viewModel.members.isEmpty)
        XCTAssertEqual(viewModel.topic, "")
        XCTAssertFalse(viewModel.isLoadingHistory)
        XCTAssertEqual(viewModel.unreadCount, 0)
    }

    func testInitialNickIsEmpty() {
        // No server connected in test environment
        XCTAssertEqual(viewModel.currentNick, "")
    }

    // MARK: markRead

    func testMarkReadResetsUnreadCount() {
        // Access the internal unread counter via the public API
        // We can't increment it directly (it's private), but we can verify the
        // public markRead() doesn't crash and leaves unread at 0.
        viewModel.markRead()
        XCTAssertEqual(viewModel.unreadCount, 0)
    }

    // MARK: send (optimistic append)

    func testSendEmptyStringIsNoOp() {
        viewModel.send("")
        XCTAssertTrue(viewModel.displayMessages.isEmpty,
                      "Sending empty string should not add a message")
    }

    func testSendWhitespaceOnlyIsNoOp() {
        viewModel.send("   \t\n  ")
        XCTAssertTrue(viewModel.displayMessages.isEmpty,
                      "Sending whitespace-only string should not add a message")
    }

    func testSendNonEmptyAddsOptimisticMessage() {
        viewModel.send("Hello world")
        XCTAssertFalse(viewModel.displayMessages.isEmpty,
                       "Sending a message should optimistically append it")
        // The last display item should be the message
        let lastItem = viewModel.displayMessages.last
        XCTAssertNotNil(lastItem)
        XCTAssertEqual(lastItem?.message?.content, "Hello world")
        XCTAssertEqual(lastItem?.message?.type, .message)
    }

    func testSendActionStripsPrefix() {
        viewModel.send("/me waves")
        let lastMsg = viewModel.displayMessages.last?.message
        XCTAssertEqual(lastMsg?.type, .action)
        XCTAssertEqual(lastMsg?.content, "waves",
                       "/me prefix should be stripped from action content")
    }

    func testSendAddsDateSeparatorForFirstMessage() {
        viewModel.send("First message")
        // First item should be a date separator
        let firstItem = viewModel.displayMessages.first
        guard case .dateSeparator = firstItem else {
            XCTFail("Expected a date separator as the first display item")
            return
        }
    }

    func testSendTwoMessagesConsecutivelyGroupsSecond() {
        viewModel.send("First")
        viewModel.send("Second")

        // Should have: dateSeparator, message(grouped:false), message(grouped:true)
        XCTAssertEqual(viewModel.displayMessages.count, 3)

        if case .message(_, let grouped) = viewModel.displayMessages[2] {
            XCTAssertTrue(grouped, "Second consecutive message from same sender should be grouped")
        } else {
            XCTFail("Expected third item to be a message")
        }
    }

    func testSendIsOutgoingMessage() {
        viewModel.send("outgoing test")
        let lastMsg = viewModel.displayMessages.last?.message
        XCTAssertEqual(lastMsg?.isFromCurrentUser, true)
    }
}

// MARK: - DisplayMessage Date Separator Logic Tests

final class DisplayMessageDateSeparatorTests: XCTestCase {

    func testSeparatorIdIsDateBased() {
        let ref = Date(timeIntervalSinceReferenceDate: 500_000)
        let sep = DisplayMessage.dateSeparator(ref)
        XCTAssertTrue(sep.id.hasPrefix("sep-"))
        XCTAssertTrue(sep.id.contains("500000"))
    }

    func testTwoSeparatorsForDifferentDatesHaveDifferentIds() {
        let d1 = Date(timeIntervalSinceReferenceDate: 100_000)
        let d2 = Date(timeIntervalSinceReferenceDate: 200_000)
        let s1 = DisplayMessage.dateSeparator(d1)
        let s2 = DisplayMessage.dateSeparator(d2)
        XCTAssertNotEqual(s1.id, s2.id)
    }
}

// MARK: - NAMES parsing logic (extracted from ChannelViewModel)

final class NamesParsingTests: XCTestCase {

    /// Mirrors the parsing logic inside ChannelViewModel.registerCallbacks onNamesList.
    private func parseMember(_ rawNick: String) -> ChannelMember {
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

    func testOperatorPrefix() {
        let m = parseMember("@alice")
        XCTAssertEqual(m.nick, "alice")
        XCTAssertEqual(m.mode, .operator_)
    }

    func testVoicePrefix() {
        let m = parseMember("+bob")
        XCTAssertEqual(m.nick, "bob")
        XCTAssertEqual(m.mode, .voice)
    }

    func testHalfopPrefix() {
        let m = parseMember("%charlie")
        XCTAssertEqual(m.nick, "charlie")
        XCTAssertEqual(m.mode, .halfop)
    }

    func testAdminPrefix() {
        let m = parseMember("&dave")
        XCTAssertEqual(m.nick, "dave")
        XCTAssertEqual(m.mode, .admin)
    }

    func testFounderPrefix() {
        let m = parseMember("~eve")
        XCTAssertEqual(m.nick, "eve")
        XCTAssertEqual(m.mode, .founder)
    }

    func testNoPrefixIsNoneMode() {
        let m = parseMember("frank")
        XCTAssertEqual(m.nick, "frank")
        XCTAssertEqual(m.mode, .none)
    }

    func testEmptyStringNoPrefixIsNone() {
        let m = parseMember("")
        XCTAssertEqual(m.nick, "")
        XCTAssertEqual(m.mode, .none)
    }

    func testMultipleMembers() {
        let raw = ["@op", "+voice", "plain", "~founder"]
        let members = raw.map { parseMember($0) }
        XCTAssertEqual(members[0].mode, .operator_)
        XCTAssertEqual(members[1].mode, .voice)
        XCTAssertEqual(members[2].mode, .none)
        XCTAssertEqual(members[3].mode, .founder)
    }
}

// MARK: - Member sorting logic

final class MemberSortingTests: XCTestCase {

    /// Mirror of the sort key used in ChannelViewModel's NAMES handler.
    private func modeOrder(_ mode: ChannelMember.MemberMode) -> Int {
        let order: [ChannelMember.MemberMode] = [.founder, .admin, .operator_, .halfop, .voice, .none]
        return order.firstIndex(of: mode) ?? 5
    }

    func testFounderBeforeAdmin() {
        XCTAssertLessThan(modeOrder(.founder), modeOrder(.admin))
    }

    func testAdminBeforeOperator() {
        XCTAssertLessThan(modeOrder(.admin), modeOrder(.operator_))
    }

    func testOperatorBeforeHalfop() {
        XCTAssertLessThan(modeOrder(.operator_), modeOrder(.halfop))
    }

    func testHalfopBeforeVoice() {
        XCTAssertLessThan(modeOrder(.halfop), modeOrder(.voice))
    }

    func testVoiceBeforeNone() {
        XCTAssertLessThan(modeOrder(.voice), modeOrder(.none))
    }

    func testNoneIsLast() {
        XCTAssertEqual(modeOrder(.none), 5)
    }

    func testFullSort() {
        var members = [
            ChannelMember(nick: "zebra",  mode: .none),
            ChannelMember(nick: "alice",  mode: .operator_),
            ChannelMember(nick: "bob",    mode: .voice),
            ChannelMember(nick: "carol",  mode: .founder),
            ChannelMember(nick: "dave",   mode: .halfop),
        ]
        members.sort { lhs, rhs in
            let li = modeOrder(lhs.mode)
            let ri = modeOrder(rhs.mode)
            return li == ri ? lhs.nick.lowercased() < rhs.nick.lowercased() : li < ri
        }
        XCTAssertEqual(members[0].nick, "carol")   // founder
        XCTAssertEqual(members[1].nick, "alice")   // operator
        XCTAssertEqual(members[2].nick, "dave")    // halfop
        XCTAssertEqual(members[3].nick, "bob")     // voice
        XCTAssertEqual(members[4].nick, "zebra")   // none
    }
}

// MARK: - CTCP ACTION detection

final class CTCPActionDetectionTests: XCTestCase {

    private func isAction(_ body: String) -> Bool {
        body.hasPrefix("\u{0001}ACTION ") && body.hasSuffix("\u{0001}")
    }

    private func stripAction(_ body: String) -> String {
        String(body.dropFirst(8).dropLast())
    }

    func testActionBodyDetected() {
        XCTAssertTrue(isAction("\u{0001}ACTION waves\u{0001}"))
    }

    func testRegularBodyNotAction() {
        XCTAssertFalse(isAction("hello world"))
    }

    func testEmptyBodyNotAction() {
        XCTAssertFalse(isAction(""))
    }

    func testPartialCTCPNotAction() {
        XCTAssertFalse(isAction("\u{0001}ACTION waves"))
        XCTAssertFalse(isAction("ACTION waves\u{0001}"))
    }

    func testActionContentStripped() {
        let raw = "\u{0001}ACTION waves at everyone\u{0001}"
        XCTAssertEqual(stripAction(raw), "waves at everyone")
    }

    func testActionWithSpacesStripped() {
        let raw = "\u{0001}ACTION   dances   \u{0001}"
        XCTAssertEqual(stripAction(raw), "  dances   ")
    }
}

// MARK: - Mention detection

final class MentionDetectionTests: XCTestCase {

    private func isMention(content: String, currentNick: String) -> Bool {
        guard !currentNick.isEmpty else { return false }
        return content.localizedCaseInsensitiveContains(currentNick)
    }

    func testDirectMentionDetected() {
        XCTAssertTrue(isMention(content: "Hey alice, how are you?", currentNick: "alice"))
    }

    func testCaseInsensitiveMention() {
        XCTAssertTrue(isMention(content: "ALICE: check this out", currentNick: "alice"))
    }

    func testNoMentionWhenNickAbsent() {
        XCTAssertFalse(isMention(content: "Hey bob, how are you?", currentNick: "alice"))
    }

    func testEmptyNickNeverMentioned() {
        XCTAssertFalse(isMention(content: "anything", currentNick: ""))
    }

    func testEmptyContentNoMention() {
        XCTAssertFalse(isMention(content: "", currentNick: "alice"))
    }

    func testNickSubstringInContent() {
        // "alice" appears as substring of "malice" — this is intentional
        // (conservative: prefer false positive to missing a real mention)
        XCTAssertTrue(isMention(content: "don't be a malice actor", currentNick: "alice"))
    }
}

// MARK: - BubbleShape corner logic

final class BubbleShapeTests: XCTestCase {

    func testShapeWithAllCornersDoesNotCrash() {
        let shape = BubbleShape(corners: .allCorners)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 50)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
    }

    func testShapeWithNoRoundedCornersUsesMinRadius() {
        // UIRectCorner() = empty set (no rounded corners)
        // All corners should use minRadius (4pt), shape should still render
        let shape = BubbleShape(corners: UIRectCorner(), radius: 16, minRadius: 4)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
    }

    func testShapeWithTopRightOnlyDoesNotCrash() {
        let shape = BubbleShape(corners: [.topRight, .bottomLeft, .bottomRight])
        let rect = CGRect(x: 0, y: 0, width: 150, height: 44)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
    }
}

#endif // !os(Linux)
