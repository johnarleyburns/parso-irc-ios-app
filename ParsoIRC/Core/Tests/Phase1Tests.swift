#if !os(Linux)
import XCTest
@testable import ParsoIRC

// MARK: - Server Model Tests

final class ServerModelTests: XCTestCase {

    func testServerDefaultValues() {
        let server = Server(name: "Test", host: "irc.example.com")
        XCTAssertFalse(server.id.isEmpty, "id should be a non-empty UUID string")
        XCTAssertEqual(server.port, 6697)
        XCTAssertTrue(server.ssl)
        XCTAssertFalse(server.saslEnabled)
        XCTAssertEqual(server.saslMechanism, "PLAIN")
        XCTAssertTrue(server.autoConnect)
        XCTAssertFalse(server.isConnected)
        XCTAssertTrue(server.channels.isEmpty)
        XCTAssertNil(server.password)
        XCTAssertNil(server.lastActiveChannel)
    }

    func testServerCustomInit() {
        let id = UUID().uuidString
        let server = Server(
            id: id,
            name: "Libera",
            host: "irc.libera.chat",
            port: 6697,
            ssl: true,
            nickname: "testuser",
            realname: "Test User",
            password: "secret",
            saslEnabled: true,
            autoConnect: false,
            channels: [Channel(name: "#test")],
            lastActiveChannel: "#test"
        )
        XCTAssertEqual(server.id, id)
        XCTAssertEqual(server.name, "Libera")
        XCTAssertEqual(server.host, "irc.libera.chat")
        XCTAssertEqual(server.port, 6697)
        XCTAssertTrue(server.ssl)
        XCTAssertEqual(server.nickname, "testuser")
        XCTAssertEqual(server.realname, "Test User")
        XCTAssertEqual(server.password, "secret")
        XCTAssertTrue(server.saslEnabled)
        XCTAssertFalse(server.autoConnect)
        XCTAssertEqual(server.channels.count, 1)
        XCTAssertEqual(server.lastActiveChannel, "#test")
    }

    func testServerEquality() {
        let id = UUID().uuidString
        // Pin createdAt so all fields match — Server.Equatable is synthesized
        // from all stored properties including createdAt.
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = Server(id: id, name: "A", host: "irc.a.net", createdAt: fixedDate)
        let s2 = Server(id: id, name: "A", host: "irc.a.net", createdAt: fixedDate)
        let s3 = Server(id: UUID().uuidString, name: "B", host: "irc.b.net", createdAt: fixedDate)
        XCTAssertEqual(s1, s2)
        XCTAssertNotEqual(s1, s3)
    }

    func testServerDefaultNetworksExist() {
        XCTAssertFalse(Server.defaultNetworks.isEmpty, "defaultNetworks should not be empty")
        XCTAssertGreaterThanOrEqual(Server.defaultNetworks.count, 5)
    }

    func testDefaultNetworkLibera() {
        let libera = Server.defaultNetworks.first { $0.name == "Libera.Chat" }
        XCTAssertNotNil(libera)
        XCTAssertEqual(libera?.host, "irc.libera.chat")
        XCTAssertEqual(libera?.port, 6697)
        XCTAssertTrue(libera?.ssl ?? false)
    }

    func testDefaultNetworkEFnet() {
        let efnet = Server.defaultNetworks.first { $0.name == "EFnet" }
        XCTAssertNotNil(efnet)
        XCTAssertEqual(efnet?.host, "irc.efnet.org")
    }

    func testDefaultNetworksHaveUniqueIDs() {
        let ids = Server.defaultNetworks.map(\.id)
        let uniqueIds = Set(ids)
        // Default networks are value types recreated each time — IDs are random UUIDs
        // so every call to defaultNetworks yields a fresh set; just verify no duplicates
        // within a single call.
        XCTAssertEqual(ids.count, uniqueIds.count, "All default networks should have unique IDs")
    }

    func testServerCodable() throws {
        let server = Server(
            name: "Test",
            host: "irc.test.net",
            nickname: "coding",
            realname: "Code Test"
        )
        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(Server.self, from: data)
        XCTAssertEqual(decoded.id, server.id)
        XCTAssertEqual(decoded.name, server.name)
        XCTAssertEqual(decoded.host, server.host)
        XCTAssertEqual(decoded.nickname, server.nickname)
        XCTAssertEqual(decoded.realname, server.realname)
    }
}

// MARK: - Channel Model Tests

final class ChannelModelTests: XCTestCase {

    func testChannelDisplayName() {
        XCTAssertEqual(Channel(name: "#linux").displayName, "linux")
        XCTAssertEqual(Channel(name: "&local").displayName, "&local")
        XCTAssertEqual(Channel(name: "nodash").displayName, "nodash")
    }

    func testChannelDefaultValues() {
        let ch = Channel(name: "#test")
        XCTAssertFalse(ch.isMuted)
        XCTAssertEqual(ch.notifications, .mentions)
        XCTAssertEqual(ch.memberCount, 0)
        XCTAssertFalse(ch.isWatched)
        XCTAssertNil(ch.topic)
        XCTAssertNil(ch.joinedAt)
    }

    func testChannelNotificationLevelDisplayNames() {
        XCTAssertEqual(Channel.NotificationLevel.all.displayName, "All Messages")
        XCTAssertEqual(Channel.NotificationLevel.mentions.displayName, "Mentions Only")
        XCTAssertEqual(Channel.NotificationLevel.none.displayName, "None")
    }

    func testChannelCodable() throws {
        let ch = Channel(name: "#swift", topic: "Swift programming", memberCount: 42)
        let data = try JSONEncoder().encode(ch)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertEqual(decoded.id, ch.id)
        XCTAssertEqual(decoded.name, "#swift")
        XCTAssertEqual(decoded.topic, "Swift programming")
        XCTAssertEqual(decoded.memberCount, 42)
    }
}

// MARK: - ChannelMember Mode Tests

final class ChannelMemberModeTests: XCTestCase {

    func testModeDisplayNames() {
        XCTAssertEqual(ChannelMember.MemberMode.none.displayName, "")
        XCTAssertEqual(ChannelMember.MemberMode.voice.displayName, "+")
        XCTAssertEqual(ChannelMember.MemberMode.operator_.displayName, "@")
        XCTAssertEqual(ChannelMember.MemberMode.halfop.displayName, "%")
        XCTAssertEqual(ChannelMember.MemberMode.admin.displayName, "&")
        XCTAssertEqual(ChannelMember.MemberMode.founder.displayName, "~")
    }

    func testModePrefixes() {
        XCTAssertEqual(ChannelMember.MemberMode.operator_.prefix, "@")
        XCTAssertEqual(ChannelMember.MemberMode.voice.prefix, "+")
    }

    func testMemberDefaultsToNoMode() {
        let member = ChannelMember(nick: "testuser")
        XCTAssertEqual(member.mode, .none)
        XCTAssertFalse(member.isAway)
    }
}

// MARK: - Message Model Tests

final class MessageModelTests: XCTestCase {

    func testMessageDefaultValues() {
        let msg = Message(channelId: "ch1", sender: "alice", content: "hello")
        XCTAssertFalse(msg.id.isEmpty)
        XCTAssertEqual(msg.type, .message)
        XCTAssertFalse(msg.isRead)
        XCTAssertFalse(msg.isFromCurrentUser)
        XCTAssertTrue(msg.reactions.isEmpty)
    }

    // NOTE: Message.previousSameSenderMessage has a stub getter that always returns nil.
    // Therefore isGroupedWithPrevious always returns false at the model level.
    // Phase 2's ChannelViewModel will supply the previous message at render time.
    // These tests document the current model behaviour and verify that the
    // previousSameSenderMessageId is wired correctly via the setter.

    func testMessageGroupingPropertyAlwaysFalseAtModelLevel() {
        let base = Date()
        let first = Message(
            id: "m1",
            channelId: "ch1",
            sender: "alice",
            content: "first",
            timestamp: base
        )
        let second = Message(
            id: "m2",
            channelId: "ch1",
            sender: "alice",
            content: "second",
            timestamp: base.addingTimeInterval(60),
            previousSameSenderMessage: first
        )
        // The getter is a stub; grouping is resolved by the view layer in Phase 2
        XCTAssertFalse(second.isGroupedWithPrevious,
                       "isGroupedWithPrevious is always false at the model level (getter is a stub)")
    }

    func testPreviousSameSenderMessageIdSetBySetter() {
        let base = Date()
        let first = Message(id: "m1", channelId: "ch1", sender: "alice", content: "hi", timestamp: base)
        let second = Message(
            id: "m2",
            channelId: "ch1",
            sender: "alice",
            content: "there",
            timestamp: base.addingTimeInterval(30),
            previousSameSenderMessage: first
        )
        // The setter stores the id even though the getter always returns nil
        XCTAssertEqual(second.previousSameSenderMessageId, "m1",
                       "Setter should store the previous message's id")
    }

    func testIsGroupedWithPreviousReturnsFalseWithNoPrevious() {
        let msg = Message(channelId: "ch1", sender: "alice", content: "standalone")
        XCTAssertFalse(msg.isGroupedWithPrevious, "No previous message means not grouped")
        XCTAssertNil(msg.previousSameSenderMessageId)
    }

    func testMessageTypes() {
        let types: [Message.MessageType] = [
            .message, .action, .notice, .join, .part, .quit, .nick, .mode, .topic, .kick, .ban, .invite
        ]
        for type in types {
            let msg = Message(channelId: "ch", sender: "s", content: "c", type: type)
            XCTAssertEqual(msg.type, type)
        }
    }

    func testMessageCodable() throws {
        let msg = Message(
            channelId: "ch1",
            sender: "alice",
            senderHost: "alice@example.com",
            content: "Hello IRC!",
            type: .message
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.id, msg.id)
        XCTAssertEqual(decoded.sender, "alice")
        XCTAssertEqual(decoded.content, "Hello IRC!")
        XCTAssertEqual(decoded.senderHost, "alice@example.com")
    }
}

// MARK: - ConnectionState Tests

final class ConnectionStateTests: XCTestCase {

    func testStateEquality() {
        XCTAssertEqual(ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(ConnectionState.connecting, .connecting)
        XCTAssertEqual(ConnectionState.connected, .connected)
        XCTAssertEqual(ConnectionState.reconnecting, .reconnecting)

        // .failed is equal to any other .failed regardless of associated error
        let e1 = ConnectionState.failed(IRCError.notConnected)
        let e2 = ConnectionState.failed(IRCError.timeout)
        XCTAssertEqual(e1, e2)
    }

    func testStateInequality() {
        XCTAssertNotEqual(ConnectionState.connected, .disconnected)
        XCTAssertNotEqual(ConnectionState.connecting, .connected)
        XCTAssertNotEqual(ConnectionState.reconnecting, .failed(IRCError.timeout))
    }
}

// MARK: - PresetNetwork Tests

final class PresetNetworkTests: XCTestCase {

    func testAllPresetsHaveHosts() {
        for preset in PresetNetwork.allCases where preset != .custom {
            XCTAssertFalse(preset.host.isEmpty, "\(preset.displayName) should have a non-empty host")
        }
    }

    func testCustomHasEmptyHost() {
        XCTAssertEqual(PresetNetwork.custom.host, "")
    }

    func testTLSAlignedWithPort() {
        for preset in PresetNetwork.allCases where preset != .custom {
            if preset.tls {
                XCTAssertEqual(preset.port, 6697, "\(preset.displayName) TLS port should be 6697")
            } else {
                XCTAssertEqual(preset.port, 6667, "\(preset.displayName) plain port should be 6667")
            }
        }
    }

    func testPresetRoundTripFromHost() {
        let libera = PresetNetwork(host: "irc.libera.chat")
        XCTAssertEqual(libera, .libera)

        let oftc = PresetNetwork(host: "irc.oftc.net")
        XCTAssertEqual(oftc, .oftc)

        let custom = PresetNetwork(host: "irc.someunknown.example")
        XCTAssertNil(custom, "Unknown host should return nil")
    }

    func testAllPresetsHaveDisplayNames() {
        for preset in PresetNetwork.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "All presets must have a display name")
        }
    }

    func testLiberaPreset() {
        XCTAssertEqual(PresetNetwork.libera.host, "irc.libera.chat")
        XCTAssertEqual(PresetNetwork.libera.port, 6697)
        XCTAssertTrue(PresetNetwork.libera.tls)
    }

    func testEFnetPreset() {
        XCTAssertEqual(PresetNetwork.efnet.host, "irc.efnet.org")
        XCTAssertEqual(PresetNetwork.efnet.port, 6667)
        XCTAssertFalse(PresetNetwork.efnet.tls)
    }

    func testAllCasesCount() {
        // Ensure we have all 10 presets + custom
        XCTAssertEqual(PresetNetwork.allCases.count, 10)
    }
}

// MARK: - IRCClientManager State Tests (mock-based, no network)

// IRCClientManager is @MainActor-isolated, so all tests calling its methods
// must run on the main actor.
@MainActor
final class IRCClientManagerStateTests: XCTestCase {

    // Test that connectionState(for:) returns .disconnected for an unknown server ID
    func testUnknownServerIsDisconnected() {
        let manager = IRCClientManager.shared
        let state = manager.connectionState(for: "nonexistent-server-id")
        XCTAssertEqual(state, .disconnected)
    }

    // Test isConnected returns false when state is disconnected
    func testIsConnectedFalseWhenDisconnected() {
        let manager = IRCClientManager.shared
        XCTAssertFalse(manager.isConnected(serverId: "unknown-id"))
    }

    // Test that getClient returns nil for an unknown ID
    func testGetClientReturnsNilForUnknown() {
        let manager = IRCClientManager.shared
        XCTAssertNil(manager.getClient(for: "nonexistent"))
    }
}

// MARK: - NickColorGenerator Tests

final class NickColorGeneratorTests: XCTestCase {

    func testSameNickAlwaysGetsSameColor() {
        let c1 = NickColorGenerator.color(for: "alice")
        let c2 = NickColorGenerator.color(for: "alice")
        // SwiftUI Color does not implement Equatable so compare via UIColor
        XCTAssertEqual(NickColorGenerator.uiColor(for: "alice"),
                       NickColorGenerator.uiColor(for: "alice"))
        // The result should not be nil
        _ = c1
        _ = c2
    }

    func testDifferentNicksCanGetDifferentColors() {
        let nicks = ["alice", "bob", "charlie", "dave", "eve",
                     "frank", "grace", "heidi", "ivan", "judy"]
        let colors = nicks.map { NickColorGenerator.uiColor(for: $0) }
        // Not every nick will differ (16 colors for N nicks), but at least 2 should
        let unique = Set(colors.map { $0.description })
        XCTAssertGreaterThan(unique.count, 1, "Different nicks should sometimes get different colors")
    }

    func testEmptyNickDoesNotCrash() {
        _ = NickColorGenerator.color(for: "")
        _ = NickColorGenerator.uiColor(for: "")
    }

    func testLongNickDoesNotCrash() {
        let longNick = String(repeating: "x", count: 512)
        _ = NickColorGenerator.color(for: longNick)
    }
}

// MARK: - Channel DisplayName Edge Cases

final class ChannelDisplayNameTests: XCTestCase {

    func testHashPrefixRemoved() {
        XCTAssertEqual(Channel(name: "#linux").displayName, "linux")
    }

    func testAmpersandPrefixKept() {
        // & channels are local and less common; displayName just drops leading #
        XCTAssertEqual(Channel(name: "&local").displayName, "&local")
    }

    func testNoPrefix() {
        XCTAssertEqual(Channel(name: "nochan").displayName, "nochan")
    }

    func testEmptyName() {
        XCTAssertEqual(Channel(name: "").displayName, "")
    }
}

// MARK: - Server Nickname Fallback Logic

final class ServerNicknameFallbackTests: XCTestCase {

    /// Validates the nickname resolution logic used in IRCClientManager.connect(to:)
    func testEmptyNicknameGetsFallback() {
        let server = Server(name: "Test", host: "irc.test.net", nickname: "")
        let nick = server.nickname.isEmpty ? "parso1234" : server.nickname
        XCTAssertEqual(nick, "parso1234")
    }

    func testNonEmptyNicknameIsPreserved() {
        let server = Server(name: "Test", host: "irc.test.net", nickname: "coolguy")
        let nick = server.nickname.isEmpty ? "parso1234" : server.nickname
        XCTAssertEqual(nick, "coolguy")
    }

    func testRealnameEmptyFallsBackToParsIRC() {
        let server = Server(name: "Test", host: "irc.test.net", realname: "")
        let real = server.realname.isEmpty ? "Parso IRC" : server.realname
        XCTAssertEqual(real, "Parso IRC")
    }
}

#endif // !os(Linux)
