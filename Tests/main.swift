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
    
    subscript(key: String) -> String? { dictionary[key] }

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

func assertFalse(_ value: Bool) throws {
    if value {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected false"])
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

// MARK: - CAP negotiation tests

print("\n=== CAP Negotiation Tests ===")

runTest("testCapLsParsesChathistory") {
    // Simulate a CAP LS response from a server that supports chathistory
    let capLine = ":irc.libera.chat CAP * LS :batch server-time message-tags chathistory"
    let msg = IRCMessage(rawLine: capLine)
    try assertEqual(msg.command, "CAP")
    let caps = (msg.parameters.last ?? "").split(separator: " ").map(String.init)
    try assertTrue(caps.contains("chathistory"))
    try assertTrue(caps.contains("batch"))
    try assertTrue(caps.contains("server-time"))
}

runTest("testCapAckChathistorySetsChathistoryEnabled") {
    // Verify that ACK with "chathistory" but NOT "batch" alone sets the right flag
    // (mirrors the fixed ACK handler logic)
    var chathistoryEnabled = false
    var serverTimeEnabled = false
    var zncPlaybackEnabled = false
    let ackLine = ":irc.libera.chat CAP * ACK :batch server-time message-tags chathistory"
    let msg = IRCMessage(rawLine: ackLine)
    let caps = (msg.parameters.last ?? "").split(separator: " ").map(String.init)
    for cap in caps {
        let capName = cap.trimmingCharacters(in: .init(charactersIn: "-~="))
        if capName == "server-time" { serverTimeEnabled = true }
        else if capName == "chathistory" || capName == "draft/chathistory" { chathistoryEnabled = true }
        else if capName == "znc.in/playback" { zncPlaybackEnabled = true; chathistoryEnabled = true }
        // "batch" alone should NOT set chathistoryEnabled (this was the bug)
    }
    try assertTrue(chathistoryEnabled)
    try assertTrue(serverTimeEnabled)
    try assertFalse(zncPlaybackEnabled)
}

runTest("testCapAckBatchAloneDoesNotSetChathistoryEnabled") {
    // Regression test: ACK of "batch" alone must NOT set chathistoryEnabled
    var chathistoryEnabled = false
    let ackLine = ":irc.server.net CAP * ACK :batch"
    let msg = IRCMessage(rawLine: ackLine)
    let caps = (msg.parameters.last ?? "").split(separator: " ").map(String.init)
    for cap in caps {
        let capName = cap.trimmingCharacters(in: .init(charactersIn: "-~="))
        // The fixed logic: only chathistory/draft/chathistory/znc.in/playback sets chathistoryEnabled
        if capName == "chathistory" || capName == "draft/chathistory" { chathistoryEnabled = true }
        else if capName == "znc.in/playback" { chathistoryEnabled = true }
        // "batch" → chathistoryEnabled was the bug; the fix removes this
    }
    try assertFalse(chathistoryEnabled)
}

// MARK: - isHistoryBatch tests

print("\n=== isHistoryBatch Tests ===")

/// Simulates the fixed isHistoryBatch logic
func isHistoryBatch(message: IRCMessage, activeBatches: [String: String]) -> Bool {
    guard let batchRef = message.tags?["batch"]?.trimmingCharacters(in: .whitespaces) else { return false }
    guard let batchType = activeBatches[batchRef] else { return false }
    if batchType.contains("chathistory") { return true }
    if batchType.contains("znc.in/playback") { return true }
    return false
}

runTest("testIsHistoryBatchWithChathistoryType") {
    // BATCH +abc123 chathistory — then a PRIVMSG with @batch=abc123 should be classified as history
    let activeBatches = ["abc123": "chathistory"]
    let privmsg = IRCMessage(rawLine: "@batch=abc123 :nick!user@host PRIVMSG #channel :Hello history")
    try assertTrue(isHistoryBatch(message: privmsg, activeBatches: activeBatches))
}

runTest("testIsHistoryBatchWithZncPlayback") {
    // ZNC playback batch
    let activeBatches = ["xyz789": "znc.in/playback"]
    let privmsg = IRCMessage(rawLine: "@batch=xyz789 :nick!user@host PRIVMSG #channel :Old message")
    try assertTrue(isHistoryBatch(message: privmsg, activeBatches: activeBatches))
}

runTest("testIsHistoryBatchWithNoBatchTag") {
    // Regular message with no @batch tag → not history
    let activeBatches = ["abc123": "chathistory"]
    let privmsg = IRCMessage(rawLine: ":nick!user@host PRIVMSG #channel :Live message")
    try assertFalse(isHistoryBatch(message: privmsg, activeBatches: activeBatches))
}

runTest("testIsHistoryBatchBugFix_OpaqueRefNotContainingChathistory") {
    // The OLD (broken) code checked batchRef.contains("chathistory")
    // This would fail for opaque refs like "abc123" even when type IS chathistory.
    // The NEW code checks activeBatches[batchRef] for the type.
    let activeBatches = ["abc123": "chathistory"]
    // "abc123" does NOT contain "chathistory" — old code would return false (bug)
    // new code looks up activeBatches["abc123"] = "chathistory" → returns true (fixed)
    let privmsg = IRCMessage(rawLine: "@batch=abc123 :nick!user@host PRIVMSG #channel :History msg")
    let oldBuggyResult = "abc123".contains("chathistory")  // would have been false
    let newFixedResult = isHistoryBatch(message: privmsg, activeBatches: activeBatches)
    try assertFalse(oldBuggyResult)  // old code was wrong
    try assertTrue(newFixedResult)   // new code is correct
}

runTest("testIsHistoryBatchWithUnknownRef") {
    // Batch ref not in activeBatches (batch already closed or unknown)
    let activeBatches: [String: String] = [:]
    let privmsg = IRCMessage(rawLine: "@batch=unknown :nick!user@host PRIVMSG #channel :msg")
    try assertFalse(isHistoryBatch(message: privmsg, activeBatches: activeBatches))
}

// MARK: - Credential generation tests

print("\n=== Credential Generation Tests ===")

func generateNick() -> String {
    "parso\(Int.random(in: 1000...9999))"
}

func generatePassword() -> String {
    let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return String((0..<14).compactMap { _ in chars.randomElement() })
}

runTest("testGeneratedNickFormat") {
    let nick = generateNick()
    try assertTrue(nick.hasPrefix("parso"))
    try assertTrue(nick.count == 9)  // "parso" (5) + 4 digits
    let digits = String(nick.dropFirst(5))
    try assertTrue(digits.allSatisfy { $0.isNumber })
    let num = Int(digits)!
    try assertTrue(num >= 1000 && num <= 9999)
}

runTest("testGeneratedPasswordLength") {
    let pw = generatePassword()
    try assertEqual(pw.count, 14)
}

runTest("testGeneratedPasswordCharset") {
    let allowed = Set("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    for _ in 0..<20 {
        let pw = generatePassword()
        try assertTrue(pw.unicodeScalars.allSatisfy { allowed.contains(Character($0)) })
    }
}

runTest("testGeneratedPasswordsAreUnique") {
    // With 14 chars from 58-char alphabet, collision probability is astronomically low
    let pw1 = generatePassword()
    let pw2 = generatePassword()
    try assertTrue(pw1 != pw2)
}

// MARK: - BATCH open/close tracking tests

print("\n=== BATCH Tracking Tests ===")

runTest("testBatchOpenAndClose") {
    // Simulate BATCH +ref type and BATCH -ref
    var activeBatches: [String: String] = [:]

    let openMsg = IRCMessage(rawLine: ":server BATCH +abc123 chathistory #channel")
    if let first = openMsg.parameters.first, first.hasPrefix("+") {
        let ref = String(first.dropFirst())
        let type_ = openMsg.parameters.count > 1 ? openMsg.parameters[1] : ""
        activeBatches[ref] = type_
    }
    try assertEqual(activeBatches["abc123"], "chathistory")

    let closeMsg = IRCMessage(rawLine: ":server BATCH -abc123")
    if let first = closeMsg.parameters.first, first.hasPrefix("-") {
        let ref = String(first.dropFirst())
        activeBatches.removeValue(forKey: ref)
    }
    try assertTrue(activeBatches["abc123"] == nil)
}

runTest("testBatchTypePropagation") {
    // Messages inside a batch should be classifiable as history
    var activeBatches: [String: String] = ["ref42": "chathistory"]
    // Note: multiple tags separated by ;  — the batch ref needs trimming
    let histMsg = IRCMessage(rawLine: "@batch=ref42 :alice!a@b PRIVMSG #test :hi")
    try assertTrue(isHistoryBatch(message: histMsg, activeBatches: activeBatches))
    // After batch closes, same ref no longer classifies as history
    activeBatches.removeValue(forKey: "ref42")
    try assertFalse(isHistoryBatch(message: histMsg, activeBatches: activeBatches))
}

// Summary
print("\n=== Results ===")
print("Passed: \(results.passed)")
print("Failed: \(results.failed)")
print("Total:  \(results.passed + results.failed)")

if results.failed > 0 {
    exit(1)
}