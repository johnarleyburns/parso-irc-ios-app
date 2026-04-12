import Foundation

// Test result tracker
final class TestResults: @unchecked Sendable {
    var passed: Int = 0
    var failed: Int = 0
    
    func recordPass() { passed += 1 }
    func recordFail() { failed += 1 }
}

let results = TestResults()

print("=== Message Parsing Tests ===")

// IRCMessage parsing
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

// Test runner
func runTest(_ name: String, _ fn: () throws -> Void) {
    do {
        try fn()
        print("✓ \(name)")
        results.recordPass()
    } catch {
        print("✗ \(name): \(error)")
        results.recordFail()
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    if actual != expected {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected \(expected) but got \(actual)"])
    }
}

func assertTrue(_ value: Bool) throws {
    if !value {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected true"])
    }
}

// Tests
runTest("testParsePrivmsg") {
    let message = IRCMessage(rawLine: ":nick!user@host PRIVMSG #channel :Hello world")
    try assertEqual(message.command, "PRIVMSG")
    try assertEqual(message.source?.nick, "nick!user@host")
    try assertEqual(message.parameters.first, "#channel")
    try assertEqual(message.trailing, "Hello world")
}

runTest("testParseJoin") {
    let message = IRCMessage(rawLine: ":nick!~user@host JOIN #channel")
    try assertEqual(message.command, "JOIN")
    try assertEqual(message.source?.nick, "nick!~user@host")
    try assertEqual(message.parameters.first, "#channel")
}

runTest("testParsePart") {
    let message = IRCMessage(rawLine: ":nick!user@host PART #channel :Goodbye")
    try assertEqual(message.command, "PART")
    try assertEqual(message.parameters.first, "#channel")
    try assertEqual(message.trailing, "Goodbye")
}

runTest("testParseQuit") {
    let message = IRCMessage(rawLine: ":nick!user@host QUIT :Leaving")
    try assertEqual(message.command, "QUIT")
    try assertEqual(message.trailing, "Leaving")
}

runTest("testParsePing") {
    let message = IRCMessage(rawLine: "PING :server")
    try assertEqual(message.command, "PING")
    try assertEqual(message.trailing, "server")
}

runTest("testParseNick") {
    let message = IRCMessage(rawLine: ":oldnick NICK :newnick")
    try assertEqual(message.command, "NICK")
    try assertEqual(message.source?.nick, "oldnick")
    try assertEqual(message.trailing, "newnick")
}

runTest("testParseMode") {
    let message = IRCMessage(rawLine: ":nick MODE #channel +nt")
    try assertEqual(message.command, "MODE")
    try assertEqual(message.parameters, ["#channel", "+nt"])
}

runTest("testParseTopic") {
    let message = IRCMessage(rawLine: ":nick TOPIC #channel :New topic")
    try assertEqual(message.command, "TOPIC")
    try assertEqual(message.parameters.first, "#channel")
    try assertEqual(message.trailing, "New topic")
}

runTest("testParseNumeric") {
    let message = IRCMessage(rawLine: ":server 353 nick = #channel :user1 user2 user3")
    try assertEqual(message.command, "353")
    try assertEqual(message.parameters[1], "=")
    try assertEqual(message.parameters[2], "#channel")
    try assertEqual(message.trailing, "user1 user2 user3")
}

runTest("testParseMessageWithoutPrefix") {
    let message = IRCMessage(rawLine: "QUOTE :test message")
    try assertEqual(message.command, "QUOTE")
    try assertEqual(message.trailing, "test message")
    try assertTrue(message.source == nil)
}

runTest("testParseEmptyTrailing") {
    let message = IRCMessage(rawLine: ":nick PRIVMSG #channel")
    try assertEqual(message.command, "PRIVMSG")
    try assertEqual(message.trailing, "#channel")
}

// Summary
print("\n=== Results ===")
print("Passed: \(results.passed)")
print("Failed: \(results.failed)")
print("Total:  \(results.passed + results.failed)")

if results.failed > 0 {
    exit(1)
}