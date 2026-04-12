import XCTest
#if canImport(Network)
@testable import ParsoIRC

final class IRCIntegrationTests: XCTestCase {
    
    private var client: IRCClient?
    private var testServerURL: String?
    private var testUsername: String?
    private var testPassword: String?
    private var testChannel: String?
    
    override func setUp() async throws {
        loadTestCredentials()
    }
    
    override func tearDown() async throws {
        if let client = client {
            await client.disconnect()
        }
    }
    
    private func loadTestCredentials() {
        testServerURL = ProcessInfo.processInfo.environment["IRC_TEST_URL"]
        testUsername = ProcessInfo.processInfo.environment["IRC_TEST_USERNAME"]
        testPassword = ProcessInfo.processInfo.environment["IRC_TEST_PASSWORD"]
        testChannel = ProcessInfo.processInfo.environment["IRC_TEST_CHANNEL"]
    }
    
    private func parseURL(_ url: String) -> (host: String, port: Int, tls: Bool)? {
        guard url.hasPrefix("ircs://") else { return nil }
        
        let withoutScheme = String(url.dropFirst(6))
        let components = withoutScheme.split(separator: ":")
        guard components.count == 2,
              let port = Int(components[1]) else { return nil }
        
        return (String(components[0]), port, true)
    }
    
    func testConnectAndAuthenticate() async throws {
        guard let url = testServerURL,
              let parsed = parseURL(url),
              let username = testUsername,
              let password = testPassword else {
            throw XCTSkip("Test credentials not configured")
        }
        
        let client = IRCClient()
        self.client = client
        
        var authCompleted = false
        var authError: Error?
        
        await MainActor.run {
            client.onWelcome = { nick in
                authCompleted = true
            }
            client.onError = { error in
                authError = error
            }
        }
        
        try await client.connect(
            host: parsed.host,
            port: parsed.port,
            tls: parsed.tls,
            nickname: username,
            username: username,
            realname: "ParsoIRC Test"
        )
        
        try await client.authenticateSASL(username: username, password: password)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        XCTAssertTrue(authCompleted, "Authentication should complete")
        XCTAssertNil(authError, "Should have no errors: \(authError?.localizedDescription ?? "nil")")
        
        await client.disconnect()
    }
    
    func testJoinChannel() async throws {
        guard let url = testServerURL,
              let parsed = parseURL(url),
              let username = testUsername,
              let password = testPassword,
              let channel = testChannel else {
            throw XCTSkip("Test credentials not configured")
        }
        
        let client = IRCClient()
        self.client = client
        
        var joined = false
        
        await MainActor.run {
            client.onJoin = { chan, nick in
                if chan == channel {
                    joined = true
                }
            }
        }
        
        try await client.connect(
            host: parsed.host,
            port: parsed.port,
            tls: parsed.tls,
            nickname: username,
            username: username,
            realname: "ParsoIRC Test"
        )
        
        try await client.authenticateSASL(username: username, password: password)
        try await client.join(channel: channel)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        XCTAssertTrue(joined, "Should join channel")
        
        await client.disconnect()
    }
    
    func testSendAndReceiveMessage() async throws {
        guard let url = testServerURL,
              let parsed = parseURL(url),
              let username = testUsername,
              let password = testPassword,
              let channel = testChannel else {
            throw XCTSkip("Test credentials not configured")
        }
        
        let client = IRCClient()
        self.client = client
        
        let uniqueMessage = "test-\(UUID().uuidString.prefix(8))"
        var receivedMessage: String?
        
        await MainActor.run {
            client.onMessage = { message in
                if message.command == "PRIVMSG",
                   message.parameters.first == channel,
                   message.parameters.last ?? "" == uniqueMessage {
                    receivedMessage = message.parameters.last ?? ""
                }
            }
        }
        
        try await client.connect(
            host: parsed.host,
            port: parsed.port,
            tls: parsed.tls,
            nickname: username,
            username: username,
            realname: "ParsoIRC Test"
        )
        
        try await client.authenticateSASL(username: username, password: password)
        try await client.join(channel: channel)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        try await client.sendMessage(uniqueMessage, to: channel)
        
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        XCTAssertEqual(receivedMessage, uniqueMessage, "Should receive the sent message")
        
        await client.disconnect()
    }
    
    func testFullConversation() async throws {
        guard let url = testServerURL,
              let parsed = parseURL(url),
              let username = testUsername,
              let password = testPassword,
              let channel = testChannel else {
            throw XCTSkip("Test credentials not configured")
        }
        
        let client = IRCClient()
        self.client = client
        
        let uniqueMessage = "conversation-test-\(UUID().uuidString.prefix(8))"
        var receivedMessage: String?
        
        await MainActor.run {
            client.onWelcome = { _ in
                print("Connected and authenticated")
            }
            client.onJoin = { chan, nick in
                print("Joined channel: \(chan) as \(nick)")
            }
            client.onMessage = { message in
                if message.command == "PRIVMSG",
                   message.parameters.first == channel {
                    receivedMessage = message.parameters.last ?? ""
                    print("Received: \(message.parameters.last ?? "")")
                }
            }
        }
        
        try await client.connect(
            host: parsed.host,
            port: parsed.port,
            tls: parsed.tls,
            nickname: username,
            username: username,
            realname: "ParsoIRC Test"
        )
        
        try await client.authenticateSASL(username: username, password: password)
        try await client.join(channel: channel)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        try await client.sendMessage(uniqueMessage, to: channel)
        
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        XCTAssertEqual(receivedMessage, uniqueMessage, "Full conversation should work")
        
        await client.disconnect()
    }
}
#else
final class IRCIntegrationTests: XCTestCase {
    func testNoNetworkFramework() {
        throw XCTSkip("Network framework not available on Linux")
    }
}
#endif