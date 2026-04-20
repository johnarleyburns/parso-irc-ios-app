#if !os(Linux)
import XCTest
import SwiftUI
import UIKit
@testable import ParsoIRC

// MARK: - MemberRowView.modeColor Tests
//
// We verify the mapping via UIColor descriptions rather than SwiftUI Color
// equality, because Color(UIColor) equality is not reliable in test hosts.

final class MemberModeColorTests: XCTestCase {

    // Helper: convert SwiftUI Color → UIColor description for comparison
    private func uiDesc(_ mode: ChannelMember.MemberMode) -> String {
        UIColor(MemberRowView.modeColor(mode)).description
    }

    func testAllModesReturnNonNilColor() {
        let modes: [ChannelMember.MemberMode] = [.founder, .admin, .operator_, .halfop, .voice, .none]
        for mode in modes {
            // Just calling the function must not crash
            _ = MemberRowView.modeColor(mode)
        }
    }

    func testFounderAndAdminHaveDifferentColors() {
        // founder = systemYellow, admin = systemOrange — different
        XCTAssertNotEqual(uiDesc(.founder), uiDesc(.admin))
    }

    func testAllSixModesProduceSixDistinctColors() {
        let modes: [ChannelMember.MemberMode] = [.founder, .admin, .operator_, .halfop, .voice, .none]
        let descriptions = modes.map { uiDesc($0) }
        let unique = Set(descriptions)
        XCTAssertEqual(unique.count, 6,
                       "Every mode should produce a distinct color; got: \(descriptions)")
    }

    func testNoneColorDiffersFromAllPrivilegedModes() {
        let privileged: [ChannelMember.MemberMode] = [.founder, .admin, .operator_, .halfop, .voice]
        let noneDesc = uiDesc(.none)
        for mode in privileged {
            XCTAssertNotEqual(uiDesc(mode), noneDesc,
                              "\(mode) should differ from .none color")
        }
    }
}

// MARK: - MemberListView grouping logic

final class MemberListGroupingTests: XCTestCase {

    /// Mirrors the grouping predicates in MemberListView.
    private func group(_ members: [ChannelMember])
        -> (founders: [ChannelMember],
            operators: [ChannelMember],
            halfops: [ChannelMember],
            voiced: [ChannelMember],
            regulars: [ChannelMember])
    {
        (
            members.filter { $0.mode == .founder || $0.mode == .admin },
            members.filter { $0.mode == .operator_ },
            members.filter { $0.mode == .halfop },
            members.filter { $0.mode == .voice },
            members.filter { $0.mode == .none }
        )
    }

    func testEmptyListProducesEmptyGroups() {
        let g = group([])
        XCTAssertTrue(g.founders.isEmpty)
        XCTAssertTrue(g.operators.isEmpty)
        XCTAssertTrue(g.halfops.isEmpty)
        XCTAssertTrue(g.voiced.isEmpty)
        XCTAssertTrue(g.regulars.isEmpty)
    }

    func testSingleFounderGoesIntoFoundersGroup() {
        let m = ChannelMember(nick: "alice", mode: .founder)
        let g = group([m])
        XCTAssertEqual(g.founders.count, 1)
        XCTAssertEqual(g.founders[0].nick, "alice")
        XCTAssertTrue(g.operators.isEmpty)
    }

    func testAdminAlsoAppearsInFoundersGroup() {
        let m = ChannelMember(nick: "bob", mode: .admin)
        let g = group([m])
        XCTAssertEqual(g.founders.count, 1)
        XCTAssertEqual(g.founders[0].nick, "bob")
    }

    func testMixedMembersGroupCorrectly() {
        let members: [ChannelMember] = [
            ChannelMember(nick: "f",  mode: .founder),
            ChannelMember(nick: "a",  mode: .admin),
            ChannelMember(nick: "op", mode: .operator_),
            ChannelMember(nick: "h",  mode: .halfop),
            ChannelMember(nick: "v",  mode: .voice),
            ChannelMember(nick: "r1", mode: .none),
            ChannelMember(nick: "r2", mode: .none),
        ]
        let g = group(members)
        XCTAssertEqual(g.founders.count,  2)  // founder + admin
        XCTAssertEqual(g.operators.count, 1)
        XCTAssertEqual(g.halfops.count,   1)
        XCTAssertEqual(g.voiced.count,    1)
        XCTAssertEqual(g.regulars.count,  2)
    }

    func testTotalCountMatchesInput() {
        let members: [ChannelMember] = (0..<20).map {
            ChannelMember(nick: "u\($0)", mode: .none)
        }
        let g = group(members)
        XCTAssertEqual(g.regulars.count, 20)
        XCTAssertEqual(g.founders.count + g.operators.count + g.halfops.count
                        + g.voiced.count + g.regulars.count, 20)
    }
}

// MARK: - MemberListView member count title logic

final class MemberCountTitleTests: XCTestCase {

    /// Mirrors memberCountTitle computed property in MemberListView.
    private func title(channelName: String, count: Int) -> String {
        switch count {
        case 0:  return channelName
        case 1:  return "\(channelName) — 1 member"
        default: return "\(channelName) — \(count) members"
        }
    }

    func testZeroMembersShowsChannelNameOnly() {
        XCTAssertEqual(title(channelName: "#linux", count: 0), "#linux")
    }

    func testOneMemberSingular() {
        XCTAssertEqual(title(channelName: "#linux", count: 1), "#linux — 1 member")
    }

    func testTwoMembersPlural() {
        XCTAssertEqual(title(channelName: "#linux", count: 2), "#linux — 2 members")
    }

    func testLargeCountPlural() {
        XCTAssertEqual(title(channelName: "#ubuntu", count: 1234), "#ubuntu — 1234 members")
    }
}

// MARK: - UserProfileSheet WHOIS numeric parsing

final class WhoisParsingTests: XCTestCase {

    /// Simulate what UserProfileSheet.handleWhoisNumeric does for each numeric.
    /// We model the state as a simple struct and apply the same switch logic.

    private struct WhoisState {
        var realName: String? = nil
        var userHost: String? = nil
        var serverInfo: String? = nil
        var idleSecs: Int? = nil
        var channels: [String] = []
        var account: String? = nil
        var isOperator: Bool = false
        var isSecure: Bool = false
        var whoisDone: Bool = false
    }

    private func apply(_ msg: IRCMessage, to state: inout WhoisState, for nick: String) {
        switch msg.command {
        case "311":
            guard msg.parameters.count >= 4,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.userHost = "\(msg.parameters[2])@\(msg.parameters[3])"
            state.realName = msg.parameters.last
        case "312":
            guard msg.parameters.count >= 3,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.serverInfo = "\(msg.parameters[2]) — \(msg.parameters.last ?? "")"
        case "313":
            guard msg.parameters.count >= 2,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.isOperator = true
        case "317":
            guard msg.parameters.count >= 3,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.idleSecs = Int(msg.parameters[2])
        case "319":
            guard msg.parameters.count >= 3,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.channels = (msg.parameters.last ?? "").split(separator: " ").map(String.init)
        case "330":
            guard msg.parameters.count >= 3,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.account = msg.parameters[2]
        case "671":
            guard msg.parameters.count >= 2,
                  msg.parameters[1].lowercased() == nick.lowercased() else { return }
            state.isSecure = true
        case "318":
            state.whoisDone = true
        default:
            break
        }
    }

    func test311SetsUserHostAndRealName() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 311 me alice user host.example.com * :Alice Liddell")
        apply(msg, to: &s, for: "alice")
        XCTAssertEqual(s.userHost, "user@host.example.com")
        XCTAssertEqual(s.realName, "Alice Liddell")
    }

    func test311IgnoresWrongNick() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 311 me bob user host * :Bob")
        apply(msg, to: &s, for: "alice")
        XCTAssertNil(s.userHost)
        XCTAssertNil(s.realName)
    }

    func test311CaseInsensitiveNick() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 311 me ALICE user host * :Alice")
        apply(msg, to: &s, for: "alice")
        XCTAssertNotNil(s.userHost)
    }

    func test312SetsServerInfo() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 312 me alice irc.libera.chat :Libera.Chat")
        apply(msg, to: &s, for: "alice")
        XCTAssertEqual(s.serverInfo, "irc.libera.chat — Libera.Chat")
    }

    func test313SetsOperatorFlag() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 313 me alice :is an IRC operator")
        apply(msg, to: &s, for: "alice")
        XCTAssertTrue(s.isOperator)
    }

    func test317SetsIdleSecs() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 317 me alice 120 1234567890 :seconds idle")
        apply(msg, to: &s, for: "alice")
        XCTAssertEqual(s.idleSecs, 120)
    }

    func test319SetsChannels() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 319 me alice :#linux #rust #debian")
        apply(msg, to: &s, for: "alice")
        XCTAssertEqual(s.channels, ["#linux", "#rust", "#debian"])
    }

    func test330SetsAccount() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 330 me alice alice_account :is logged in as")
        apply(msg, to: &s, for: "alice")
        XCTAssertEqual(s.account, "alice_account")
    }

    func test671SetsSecureFlag() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 671 me alice :is using a secure connection")
        apply(msg, to: &s, for: "alice")
        XCTAssertTrue(s.isSecure)
    }

    func test318SetsWhoisDone() {
        var s = WhoisState()
        let msg = IRCMessage(rawLine: ":server 318 me alice :End of /WHOIS list")
        apply(msg, to: &s, for: "alice")
        XCTAssertTrue(s.whoisDone)
    }

    func testFullWhoisSequence() {
        var s = WhoisState()
        let lines = [
            ":server 311 me alice ~alice host.net * :Alice A",
            ":server 312 me alice irc.example.net :Example Net",
            ":server 319 me alice :#general #random",
            ":server 330 me alice myaccount :is logged in as",
            ":server 671 me alice :is using a secure connection",
            ":server 317 me alice 30 1000000 :seconds idle",
            ":server 318 me alice :End of WHOIS",
        ]
        for line in lines {
            apply(IRCMessage(rawLine: line), to: &s, for: "alice")
        }
        XCTAssertEqual(s.userHost, "~alice@host.net")
        XCTAssertEqual(s.realName, "Alice A")
        XCTAssertNotNil(s.serverInfo)
        XCTAssertEqual(s.channels, ["#general", "#random"])
        XCTAssertEqual(s.account, "myaccount")
        XCTAssertTrue(s.isSecure)
        XCTAssertEqual(s.idleSecs, 30)
        XCTAssertTrue(s.whoisDone)
    }
}

// MARK: - formatIdle helper

final class FormatIdleTests: XCTestCase {

    /// Mirrors UserProfileSheet.formatIdle.
    private func formatIdle(_ seconds: Int) -> String {
        if seconds < 60   { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return "\(h)h \(m)m"
    }

    func testZeroSeconds() {
        XCTAssertEqual(formatIdle(0), "0s")
    }

    func testUnderOneMinute() {
        XCTAssertEqual(formatIdle(45), "45s")
    }

    func testExactlyOneMinute() {
        XCTAssertEqual(formatIdle(60), "1m 0s")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(formatIdle(90), "1m 30s")
    }

    func testExactlyOneHour() {
        XCTAssertEqual(formatIdle(3600), "1h 0m")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(formatIdle(5400), "1h 30m")
    }

    func testLargeDuration() {
        XCTAssertEqual(formatIdle(7261), "2h 1m")
    }
}

// MARK: - ChannelMember mode display properties

final class ChannelMemberDisplayTests: XCTestCase {

    func testModeDisplayNamesMatchPrefix() {
        // These are the exact strings shown in the badge
        XCTAssertEqual(ChannelMember.MemberMode.founder.displayName,  "~")
        XCTAssertEqual(ChannelMember.MemberMode.admin.displayName,    "&")
        XCTAssertEqual(ChannelMember.MemberMode.operator_.displayName, "@")
        XCTAssertEqual(ChannelMember.MemberMode.halfop.displayName,   "%")
        XCTAssertEqual(ChannelMember.MemberMode.voice.displayName,    "+")
        XCTAssertEqual(ChannelMember.MemberMode.none.displayName,     "")
    }

    func testMemberDefaultsToNotAway() {
        let m = ChannelMember(nick: "test")
        XCTAssertFalse(m.isAway)
    }

    func testMemberWithAwayFlag() {
        let m = ChannelMember(nick: "gone", mode: .none, isAway: true)
        XCTAssertTrue(m.isAway)
    }

    func testMemberIdIsStable() {
        let m = ChannelMember(id: "fixed-id", nick: "alice")
        XCTAssertEqual(m.id, "fixed-id")
    }
}

// MARK: - Member search filter logic

final class MemberSearchFilterTests: XCTestCase {

    private let members: [ChannelMember] = [
        ChannelMember(nick: "alice"),
        ChannelMember(nick: "bob"),
        ChannelMember(nick: "charlie"),
        ChannelMember(nick: "alicia"),
    ]

    private func filter(_ text: String) -> [ChannelMember] {
        guard !text.isEmpty else { return members }
        return members.filter { $0.nick.localizedCaseInsensitiveContains(text) }
    }

    func testEmptySearchReturnsAll() {
        XCTAssertEqual(filter("").count, members.count)
    }

    func testExactMatchReturnsOne() {
        let results = filter("bob")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].nick, "bob")
    }

    func testPrefixMatchReturnMultiple() {
        let results = filter("ali")
        XCTAssertEqual(results.count, 2)
    }

    func testCaseInsensitiveMatch() {
        let results = filter("BOB")
        XCTAssertEqual(results.count, 1)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(filter("zzz").isEmpty)
    }

    func testSingleCharMatchAll() {
        // "a" matches "alice" and "alicia" (2 matches)
        let results = filter("a")
        XCTAssertEqual(results.count, 2)
    }
}

#endif // !os(Linux)
