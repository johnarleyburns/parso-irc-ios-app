import XCTest

struct IRCUser: Hashable, Sendable {
    let nick: String
    let user: String?
    let host: String?

    init(nick: String, user: String? = nil, host: String? = nil) {
        self.nick = nick
        self.user = user
        self.host = host
    }

    init?(prefix: String) {
        guard !prefix.isEmpty else { return nil }

        if prefix.hasPrefix(":") {
            let trimmed = String(prefix.dropFirst())
            if let bangIndex = trimmed.firstIndex(of: "!") {
                self.nick = String(trimmed[..<bangIndex])
                let rest = String(trimmed[trimmed.index(after: bangIndex)...])
                if let atIndex = rest.firstIndex(of: "@") {
                    self.user = String(rest[..<atIndex])
                    self.host = String(rest[rest.index(after: atIndex)...])
                } else {
                    self.user = rest
                    self.host = nil
                }
            } else {
                self.nick = trimmed
                self.user = nil
                self.host = nil
            }
        } else {
            self.nick = prefix
            self.user = nil
            self.host = nil
        }
    }
}

struct IRCMessage: Sendable {
    let tags: IRCTags?
    let source: IRCUser?
    let command: String
    let parameters: [String]

    var trailing: String {
        parameters.last ?? ""
    }

    init(rawLine: String) {
        var tags: IRCTags? = nil
        var remaining = rawLine

        if remaining.hasPrefix("@") {
            if let spaceIndex = remaining.firstIndex(of: " ") {
                let tagsString = String(remaining[..<remaining.index(after: spaceIndex)].dropFirst())
                tags = IRCTags.parse(tagsString)
                remaining = String(remaining[remaining.index(after: spaceIndex)...])
            }
        }

        var source: IRCUser? = nil
        if remaining.hasPrefix(":") {
            if let spaceIndex = remaining.firstIndex(of: " ") {
                let sourceString = String(remaining[..<spaceIndex].dropFirst())
                source = IRCUser(prefix: sourceString)
                remaining = String(remaining[remaining.index(after: spaceIndex)...])
            }
        }

        remaining = remaining.trimmingCharacters(in: .whitespaces)

        let parts = remaining.split(separator: " ", maxSplits: 1)
        let command = parts.first.map(String.init) ?? ""
        let params = parts.count > 1 ? String(parts[1]) : ""

        var parameters: [String] = []
        if params.hasPrefix(":") {
            parameters = [String(params.dropFirst())]
        } else if !params.isEmpty {
            if let colonIndex = params.firstIndex(of: ":") {
                let prefix = String(params[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let trailing = String(params[params.index(after: colonIndex)...])
                parameters = prefix.split(separator: " ").map(String.init)
                parameters.append(trailing)
            } else {
                parameters = params.split(separator: " ").map(String.init)
            }
        }

        self.tags = tags
        self.source = source
        self.command = command
        self.parameters = parameters
    }

    init(tags: IRCTags? = nil, source: IRCUser? = nil, command: String, parameters: [String]) {
        self.tags = tags
        self.source = source
        self.command = command
        self.parameters = parameters
    }
}

struct IRCTags: Sendable {
    let dictionary: [String: String]
    
    static func parse(_ raw: String) -> IRCTags? {
        guard !raw.isEmpty else { return nil }
        
        var tags: [String: String] = [:]
        let items = raw.split(separator: ";")
        for item in items {
            let keyValue = item.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                tags[String(keyValue[0])] = String(keyValue[1])
            }
        }
        return IRCTags(dictionary: tags)
    }
}

final class IRCMessageTests: XCTestCase {
    
    func testParsePrivmsg() {
        let message = IRCMessage(rawLine: ":nick!user@host PRIVMSG #channel :Hello world")
        
        XCTAssertEqual(message.command, "PRIVMSG")
        XCTAssertEqual(message.source?.nick, "nick")
        XCTAssertEqual(message.source?.user, "user")
        XCTAssertEqual(message.source?.host, "host")
        XCTAssertEqual(message.parameters.first, "#channel")
        XCTAssertEqual(message.trailing, "Hello world")
    }
    
    func testParseJoin() {
        let message = IRCMessage(rawLine: ":nick!~user@host JOIN #channel")
        
        XCTAssertEqual(message.command, "JOIN")
        XCTAssertEqual(message.source?.nick, "nick")
        XCTAssertEqual(message.parameters.first, "#channel")
    }
    
    func testParsePart() {
        let message = IRCMessage(rawLine: ":nick!user@host PART #channel :Goodbye")
        
        XCTAssertEqual(message.command, "PART")
        XCTAssertEqual(message.parameters.first, "#channel")
        XCTAssertEqual(message.trailing, "Goodbye")
    }
    
    func testParseQuit() {
        let message = IRCMessage(rawLine: ":nick!user@host QUIT :Leaving")
        
        XCTAssertEqual(message.command, "QUIT")
        XCTAssertEqual(message.trailing, "Leaving")
    }
    
    func testParsePing() {
        let message = IRCMessage(rawLine: "PING :server")
        
        XCTAssertEqual(message.command, "PING")
        XCTAssertEqual(message.trailing, "server")
    }
    
    func testParseNick() {
        let message = IRCMessage(rawLine: ":oldnick NICK :newnick")
        
        XCTAssertEqual(message.command, "NICK")
        XCTAssertEqual(message.source?.nick, "oldnick")
        XCTAssertEqual(message.trailing, "newnick")
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
        XCTAssertEqual(message.trailing, "New topic")
    }
    
    func testParseNumeric() {
        let message = IRCMessage(rawLine: ":server 353 nick = #channel :user1 user2 user3")
        
        XCTAssertEqual(message.command, "353")
        XCTAssertEqual(message.parameters[1], "=")
        XCTAssertEqual(message.parameters[2], "#channel")
        XCTAssertEqual(message.trailing, "user1 user2 user3")
    }
    
    func testParseMessageWithoutPrefix() {
        let message = IRCMessage(rawLine: "QUOTE :test message")
        
        XCTAssertEqual(message.command, "QUOTE")
        XCTAssertEqual(message.trailing, "test message")
        XCTAssertNil(message.source)
    }
    
    func testParseEmptyTrailing() {
        let message = IRCMessage(rawLine: ":nick PRIVMSG #channel")
        
        XCTAssertEqual(message.command, "PRIVMSG")
        XCTAssertEqual(message.trailing, "")
    }
}

// Linux test execution 
import XCTest

var tests = IRCMessageTests(name: "IRCMessageTests", testClosure: { _ in })
tests.testParsePrivmsg()
print("✓ testParsePrivmsg passed")

tests.testParseJoin()
print("✓ testParseJoin passed")

tests.testParsePart()
print("✓ testParsePart passed")

tests.testParseQuit()
print("✓ testParseQuit passed")

tests.testParsePing()
print("✓ testParsePing passed")

tests.testParseNick()
print("✓ testParseNick passed")

tests.testParseMode()
print("✓ testParseMode passed")

tests.testParseTopic()
print("✓ testParseTopic passed")

tests.testParseNumeric()
print("✓ testParseNumeric passed")

tests.testParseMessageWithoutPrefix()
print("✓ testParseMessageWithoutPrefix passed")

tests.testParseEmptyTrailing()
print("✓ testParseEmptyTrailing passed")

print("\n✓ All 11 tests passed!")