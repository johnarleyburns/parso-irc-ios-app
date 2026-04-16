#if !os(Linux)
import XCTest
@testable import ParsoIRC

final class IRCMessageTests: XCTestCase {
    
    func testParsePrivmsg() {
        let message = IRCMessage(rawLine: ":nick!user@host PRIVMSG #channel :Hello world")
        
        XCTAssertEqual(message.command, "PRIVMSG")
        XCTAssertEqual(message.source?.nick, "nick")
        XCTAssertEqual(message.source?.user, "user")
        XCTAssertEqual(message.source?.host, "host")
        XCTAssertEqual(message.parameters.first, "#channel")
        XCTAssertEqual(message.parameters.last ?? "", "Hello world")
    }
    
    func testParseJoin() {
        let message = IRCMessage(rawLine: ":nick!~user@host JOIN #channel")
        
        XCTAssertEqual(message.command, "JOIN")
        XCTAssertEqual(message.source?.nick, "nick")
        XCTAssertEqual(message.source?.user, "~user")
        XCTAssertEqual(message.source?.host, "host")
        XCTAssertEqual(message.parameters.first, "#channel")
    }
    
    func testParsePart() {
        let message = IRCMessage(rawLine: ":nick!user@host PART #channel :Goodbye")
        
        XCTAssertEqual(message.command, "PART")
        XCTAssertEqual(message.parameters.first, "#channel")
        XCTAssertEqual(message.parameters.last ?? "", "Goodbye")
    }
    
    func testParseQuit() {
        let message = IRCMessage(rawLine: ":nick!user@host QUIT :Leaving")
        
        XCTAssertEqual(message.command, "QUIT")
        XCTAssertEqual(message.parameters.last ?? "", "Leaving")
    }
    
    func testParsePing() {
        let message = IRCMessage(rawLine: "PING :server")
        
        XCTAssertEqual(message.command, "PING")
        XCTAssertEqual(message.parameters.last ?? "", "server")
    }
    
    func testParseNick() {
        let message = IRCMessage(rawLine: ":oldnick NICK :newnick")
        
        XCTAssertEqual(message.command, "NICK")
        XCTAssertEqual(message.source?.nick, "oldnick")
        XCTAssertEqual(message.parameters.last ?? "", "newnick")
    }
    
    func testParseMode() {
        let message = IRCMessage(rawLine: ":nick MODE #channel +nt")
        
        XCTAssertEqual(message.command, "MODE")
        XCTAssertEqual(message.parameters, ["#channel", "+nt"])
    }
    
    func testParseTopic() {
        let message = IRCMessage(rawLine: ":nick TOPIC #channel :New topic")
        
        XCTAssertEqual(message.command, "TOPIC")
        XCTAssertEqual(message.parameters.first, "#channel")
        XCTAssertEqual(message.parameters.last ?? "", "New topic")
    }
    
    func testParseNumeric() {
        let message = IRCMessage(rawLine: ":server 353 nick = #channel :user1 user2 user3")
        
        XCTAssertEqual(message.command, "353")
        XCTAssertEqual(message.parameters[1], "=")
        XCTAssertEqual(message.parameters[2], "#channel")
        XCTAssertEqual(message.parameters.last ?? "", "user1 user2 user3")
    }
    
    func testParseMessageWithoutPrefix() {
        let message = IRCMessage(rawLine: "QUOTE :test message")
        
        XCTAssertEqual(message.command, "QUOTE")
        XCTAssertEqual(message.parameters.last ?? "", "test message")
        XCTAssertNil(message.source)
    }
    
    func testParseEmptyTrailing() {
        let message = IRCMessage(rawLine: ":nick PRIVMSG #channel")
        
        XCTAssertEqual(message.command, "PRIVMSG")
        XCTAssertEqual(message.parameters.first, "#channel")
    }
}

final class IRCClientTests: XCTestCase {
    
    private var mock: IRCClientMock!
    private var welcomeReceived: String?
    private var joinReceived: String?
    private var nickChangeReceived: (String, String)?
    private var disconnectReceived: Bool = false
    
    override func setUp() async throws {
        mock = IRCClientMock()
        
        await MainActor.run {
            mock.onWelcome = { [weak self] nick in
                self?.welcomeReceived = nick
            }
            mock.onJoin = { [weak self] channel, nick in
                self?.joinReceived = channel
            }
            mock.onNickChange = { [weak self] oldNick, newNick in
                self?.nickChangeReceived = (oldNick, newNick)
            }
            mock.onDisconnect = { [weak self] in
                self?.disconnectReceived = true
            }
        }
    }
    
    override func tearDown() async throws {
        await mock.reset()
        welcomeReceived = nil
        joinReceived = nil
        nickChangeReceived = nil
        disconnectReceived = false
    }
    
    func testConnect() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test User"
        )
        
        let isConnected = await mock.isConnected()
        XCTAssertTrue(isConnected, "Should be connected")
        
        let nick = await mock.getNickname()
        XCTAssertEqual(nick, "testuser", "Nickname should be set")
        
        XCTAssertNotNil(welcomeReceived, "Welcome callback should fire")
        XCTAssertEqual(welcomeReceived, "testuser")
    }
    
    func testNickCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "oldnick",
            username: "oldnick",
            realname: "Test"
        )
        
        try await mock.nick("newnick")
        
        let messages = await mock.getSentMessages()
        XCTAssertEqual(messages.count, 1, "Should have 1 message (NICK)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("NICK") }, "Should contain NICK command")
    }
    
    func testJoinChannel() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.join(channel: "#linux")
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.hasPrefix("JOIN") }, "Should contain JOIN command")
        
        let channels = await mock.getJoinedChannels()
        XCTAssertTrue(channels.contains("#linux"), "Should be in #linux channel")
        
        XCTAssertNotNil(joinReceived, "Join callback should fire")
    }
    
    func testPartChannel() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.join(channel: "#linux")
        try await mock.leave(channel: "#linux")
        
        let channels = await mock.getJoinedChannels()
        XCTAssertFalse(channels.contains("#linux"), "Should have left channel")
    }
    
    func testListCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.list()
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.hasPrefix("LIST") }, "Should contain LIST command")
    }
    
    func testNamesCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.names("#linux")
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.hasPrefix("NAMES") }, "Should contain NAMES command")
    }
    
    func testPrivmsgCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.sendMessage("Hello", to: "#test")
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.hasPrefix("PRIVMSG") }, "Should contain PRIVMSG command")
    }
    
    func testMeCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.me("waves", to: "#test")
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.contains("ACTION") }, "Should contain ACTION in PRIVMSG")
    }
    
    func testWhoisCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.whois("someuser")
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.hasPrefix("WHOIS") }, "Should contain WHOIS command")
    }
    
    func testAwayCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.away("Be right back")
        
        let away = await mock.getAwayMessage()
        XCTAssertEqual(away, "Be right back", "Away message should be set")
    }
    
    func testAwayClear() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.away("BRB")
        try await mock.away(nil)
        
        let away = await mock.getAwayMessage()
        XCTAssertNil(away, "Away message should be cleared")
    }
    
    func testQuitCommand() async throws {
        try await mock.connect(
            host: "irc.example.com",
            port: 6697,
            tls: true,
            nickname: "testuser",
            username: "testuser",
            realname: "Test"
        )
        
        try await mock.quit("Goodbye")
        
        let messages = await mock.getSentMessages()
        XCTAssertTrue(messages.contains { $0.hasPrefix("QUIT") }, "Should contain QUIT command")
        XCTAssertTrue(disconnectReceived, "Disconnect callback should fire")
    }
}

#endif // !os(Linux)