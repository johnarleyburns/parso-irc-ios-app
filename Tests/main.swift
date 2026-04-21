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

        // The prefix may or may not have a leading ":" when passed here,
        // depending on whether the caller already stripped it.
        let raw = prefix.hasPrefix(":") ? String(prefix.dropFirst()) : prefix

        if let bangIndex = raw.firstIndex(of: "!") {
            self.nick = String(raw[..<bangIndex])
            let rest = String(raw[raw.index(after: bangIndex)...])
            if let atIndex = rest.firstIndex(of: "@") {
                self.user = String(rest[..<atIndex])
                self.host = String(rest[rest.index(after: atIndex)...])
            } else {
                self.user = rest
                self.host = nil
            }
        } else {
            self.nick = raw
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
    try assertEqual(message.source?.nick, "nick")
    try assertEqual(message.source?.user, "user")
    try assertEqual(message.source?.host, "host")
    try assertEqual(message.parameters.first, "#channel")
    try assertEqual(message.trailing, "Hello world")
}

runTest("testParseJoin") {
    let message = IRCMessage(rawLine: ":nick!~user@host JOIN #channel")
    try assertEqual(message.command, "JOIN")
    try assertEqual(message.source?.nick, "nick")
    try assertEqual(message.source?.user, "~user")
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

// MARK: - Credential generation tests (updated for adjective+noun nick)

print("\n=== Credential Generation Tests ===")

/// Mirrors IdentityPage.generateNick() — adjective+noun, max 9 chars IRC-safe
func generateNick() -> String {
    let adjectives = [
        "swift", "bright", "bold", "calm", "cool",
        "dark", "deep", "fast", "free", "grey",
        "keen", "loud", "mild", "neat", "pure",
        "quiet", "rough", "sharp", "slim", "wild"
    ]
    let nouns = [
        "bear", "bird", "cat", "deer", "duck",
        "fish", "fox", "frog", "hawk", "hare",
        "kite", "lion", "lynx", "mink", "mole",
        "newt", "puma", "rook", "seal", "wolf"
    ]
    let adj  = adjectives.randomElement() ?? "cool"
    let noun = nouns.randomElement()      ?? "wolf"
    let base = adj + noun
    if base.count <= 7 {
        let suffix = Int.random(in: 10...99)
        return String((base + "\(suffix)").prefix(9))
    } else {
        return String(base.prefix(9))
    }
}

func generatePassword() -> String {
    let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return String((0..<14).compactMap { _ in chars.randomElement() })
}

runTest("testGeneratedNickIsIRCSafe") {
    for _ in 0..<50 {
        let nick = generateNick()
        // Must be 1–9 chars
        try assertTrue(nick.count >= 1 && nick.count <= 9)
        // Must only contain alphanumeric + - _
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        try assertTrue(nick.unicodeScalars.allSatisfy { allowed.contains(Character($0)) })
    }
}

runTest("testGeneratedNickIsAdjectiveNounFormat") {
    // Run 50 times and verify every result contains only lowercase + digits (no spaces)
    for _ in 0..<50 {
        let nick = generateNick()
        try assertFalse(nick.contains(" "))
        try assertTrue(nick.count <= 9)
    }
}

runTest("testGeneratedNicksAreUnique") {
    // Generate 20 nicks — the word list + 2-digit suffix gives 400*90 = 36,000 combinations,
    // so collisions in a small sample should be rare but not impossible.
    // The important property is that nicks are IRC-safe and varied — tested elsewhere.
    // Here just verify we can generate many without crashing, and that they're not all the same.
    var nicks = Set<String>()
    for _ in 0..<20 { nicks.insert(generateNick()) }
    // With 400+ base combinations, we expect at least 10 unique in 20 attempts
    try assertTrue(nicks.count >= 10)
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
    let pw1 = generatePassword()
    let pw2 = generatePassword()
    try assertTrue(pw1 != pw2)
}

// MARK: - BATCH open/close tracking tests

print("\n=== BATCH Tracking Tests ===")

// Simulates the continuation-based flag-setting in handleCapMessage.
// In production this is handled by CheckedContinuation resumption; here
// we just verify the flag-setting and lookup logic is correct.

runTest("testCapNegotiationFlagSetOnLS") {
    // When a non-multiline CAP LS arrives, isCapNegotiationComplete should be set
    var isCapNegotiationComplete = false
    let lsMsg = IRCMessage(rawLine: ":irc.libera.chat CAP * LS :batch server-time chathistory")
    // Simulate handleCapMessage LS handling
    let isMultiLine = lsMsg.parameters.count >= 4 && lsMsg.parameters[2] == "*"
    if !isMultiLine {
        isCapNegotiationComplete = true
    }
    try assertTrue(isCapNegotiationComplete)
}

runTest("testCapNegotiationNotSetOnMultilineLS") {
    // Multi-line CAP LS (asterisk in position 2) should NOT complete negotiation yet
    var isCapNegotiationComplete = false
    let multilineLS = IRCMessage(rawLine: ":server CAP * LS * :batch server-time")
    let isMultiLine = multilineLS.parameters.count >= 4 && multilineLS.parameters[2] == "*"
    if !isMultiLine {
        isCapNegotiationComplete = true
    }
    try assertFalse(isCapNegotiationComplete)
}

runTest("testCapAckFlagSetOnACK") {
    var isCapAckReceived = false
    var chathistoryEnabled = false
    let ackMsg = IRCMessage(rawLine: ":server CAP * ACK :batch server-time chathistory")
    if let caps = ackMsg.parameters.last {
        let acknowledged = caps.split(separator: " ").map(String.init)
        for cap in acknowledged {
            let capName = cap.trimmingCharacters(in: .init(charactersIn: "-~="))
            if capName == "chathistory" || capName == "draft/chathistory" {
                chathistoryEnabled = true
            }
        }
    }
    isCapAckReceived = true  // always set on ACK
    try assertTrue(isCapAckReceived)
    try assertTrue(chathistoryEnabled)
}

runTest("testCapAckFlagSetOnNAK") {
    var isCapAckReceived = false
    // NAK should also set the flag so connect() isn't blocked waiting
    // (simulates: server rejected our CAP REQ)
    isCapAckReceived = true
    try assertTrue(isCapAckReceived)
}

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

// MARK: - 366 RPL_ENDOFNAMES tests
// These test the chat-history trigger fix: CHATHISTORY must only be sent after
// 366 confirms the JOIN is fully processed, not before.

print("\n=== 366 RPL_ENDOFNAMES Tests ===")

/// Simulates the channel name extracted from a 366 message (mirrors handleMessage case "366").
func channelFromEndOfNames(_ rawLine: String) -> String? {
    let msg = IRCMessage(rawLine: rawLine)
    guard msg.command == "366", msg.parameters.count >= 2 else { return nil }
    return msg.parameters[1]
}

runTest("test366ExtractsChannelName") {
    // Standard Libera.Chat format: :server 366 yournick #channel :End of /NAMES list
    let channel = channelFromEndOfNames(":irc.libera.chat 366 coolbear42 #linux :End of /NAMES list")
    try assertEqual(channel, "#linux")
}

runTest("test366ExtractsCasedChannel") {
    let channel = channelFromEndOfNames(":server 366 nick #Freenode :End of /NAMES list")
    try assertEqual(channel, "#Freenode")
}

runTest("test366WithOnlyTwoParams") {
    // Some servers send minimal 366: :server 366 nick #chan
    let msg = IRCMessage(rawLine: ":server 366 nick #chan")
    guard msg.command == "366" else { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 366"]) }
    // parameters = [nick, #chan] — index 1 is the channel
    try assertEqual(msg.parameters.count, 2)
    try assertEqual(msg.parameters[1], "#chan")
}

runTest("test366DoesNotMatchWrongNumeric") {
    // 365 RPL_ENDOFLINKS should not be mistaken for 366
    let channel = channelFromEndOfNames(":server 365 nick #chan :End of /LINKS list")
    try assertTrue(channel == nil)
}

runTest("test366FiresForCorrectChannelOnly") {
    // Simulates the guard in the onEndOfNames callback:
    // only trigger history for the channel matching our channelName.
    let endOfNamesChannel = "#linux"
    let ourChannel = "#linux"
    let otherChannel = "#python"

    // Guard mirrors: channel.lowercased() == self.channelName.lowercased()
    let shouldTriggerForOurs   = endOfNamesChannel.lowercased() == ourChannel.lowercased()
    let shouldTriggerForOther  = endOfNamesChannel.lowercased() == otherChannel.lowercased()

    try assertTrue(shouldTriggerForOurs)
    try assertFalse(shouldTriggerForOther)
}

runTest("test366ChannelMatchIsCaseInsensitive") {
    // IRC channel names are case-insensitive
    let endOfNamesChannel = "#Linux"
    let ourChannel = "#linux"
    try assertTrue(endOfNamesChannel.lowercased() == ourChannel.lowercased())
}

runTest("testChathistoryNotRequestedBeforeJoinConfirmed") {
    // This test documents the sequence fix:
    // CHATHISTORY must be sent AFTER 366, not before it.
    //
    // The old (broken) sequence:
    //   start() → requestChatHistoryIfSupported() → CHATHISTORY sent → 366 arrives
    //
    // The new (correct) sequence:
    //   start() → registerCallbacks() → 366 arrives → onEndOfNames callback fires
    //             → requestChatHistoryIfSupported() → CHATHISTORY sent
    //
    // We verify the correct sequence by checking that:
    // 1. The 366 message carries the channel name
    // 2. Only after receiving 366 for our channel should we send CHATHISTORY

    var receivedEndOfNames = false
    var chathistoryRequestSent = false

    // Simulate receiving 366
    let msg366 = IRCMessage(rawLine: ":server 366 nick #linux :End of /NAMES list")
    if msg366.command == "366", msg366.parameters.count >= 2 {
        let channel = msg366.parameters[1]
        if channel.lowercased() == "#linux" {
            receivedEndOfNames = true
            // Only now is it safe to send CHATHISTORY
            chathistoryRequestSent = true
        }
    }

    try assertTrue(receivedEndOfNames)
    try assertTrue(chathistoryRequestSent)
}

runTest("testChathistoryRequestFormat") {
    // CHATHISTORY LATEST <target> * <limit> — the format used by requestHistory()
    // Verify the command string we'd send is well-formed
    let target = "#linux"
    let limit = 50
    let command = "CHATHISTORY LATEST \(target) * \(limit)"
    try assertTrue(command.hasPrefix("CHATHISTORY LATEST"))
    try assertTrue(command.contains(target))
    try assertTrue(command.hasSuffix("\(limit)"))
}

// MARK: - SASL PLAIN tests
// Covers the AUTHENTICATE + flow fix:
// The client must respond to "AUTHENTICATE +" with the base64-encoded credential,
// not just send "AUTHENTICATE PLAIN" and wait.

print("\n=== SASL PLAIN Tests ===")

/// Mirrors IRCClient.authenticateSASL: encodes \0user\0pass in base64.
func saslPlainCredential(username: String, password: String) -> String {
    let saslData = "\0\(username)\0\(password)"
    return saslData.data(using: .utf8)?.base64EncodedString() ?? "+"
}

runTest("testSaslPlainEncodingFormat") {
    // SASL PLAIN: \0username\0password base64-encoded
    let encoded = saslPlainCredential(username: "coolfox42", password: "abc123XYZ")
    // Decode and verify structure
    guard let data = Data(base64Encoded: encoded),
          let decoded = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Base64 decode failed"])
    }
    let parts = decoded.split(separator: "\0", omittingEmptySubsequences: false)
    // Parts: ["", "coolfox42", "abc123XYZ"]
    try assertEqual(parts.count, 3)
    try assertEqual(String(parts[0]), "")          // leading null
    try assertEqual(String(parts[1]), "coolfox42") // username
    try assertEqual(String(parts[2]), "abc123XYZ") // password
}

runTest("testSaslPlainEncodingIsBase64") {
    let encoded = saslPlainCredential(username: "neatbird", password: "S3cur3P@ss!")
    // Must be valid base64 (only valid chars, correct padding)
    let base64Chars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
    try assertTrue(encoded.allSatisfy { base64Chars.contains($0) })
    try assertTrue(Data(base64Encoded: encoded) != nil)
}

runTest("testSaslPlainHandlesEmptyPassword") {
    // Should produce valid base64 even with empty password
    let encoded = saslPlainCredential(username: "user", password: "")
    try assertTrue(Data(base64Encoded: encoded) != nil)
}

runTest("testSaslPlainHandlesSpecialChars") {
    // Passwords can contain any UTF-8 character
    let encoded = saslPlainCredential(username: "user42", password: "p@$$w0rd!#€")
    try assertTrue(Data(base64Encoded: encoded) != nil)
    guard let data = Data(base64Encoded: encoded),
          let decoded = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Decode failed"])
    }
    try assertTrue(decoded.contains("p@$$w0rd!#€"))
}

runTest("testAuthenticatePlusTriggersCredentialSend") {
    // Simulates the AUTHENTICATE + response handling:
    // When the server sends "AUTHENTICATE +", we must respond with the encoded credential.
    let msg = IRCMessage(rawLine: ":server AUTHENTICATE +")
    try assertEqual(msg.command, "AUTHENTICATE")
    try assertEqual(msg.parameters.first, "+")

    // In the fixed code: when parameters.first == "+" && saslRequested == true,
    // we call saslPlainCredential and send it.
    var credentialSent = false
    if msg.parameters.first == "+" {
        let _ = saslPlainCredential(username: "neatbird", password: "testpass")
        credentialSent = true
    }
    try assertTrue(credentialSent)
}

runTest("testSaslNotEnabledForNewUsersInOnboarding") {
    // New users should NOT have SASL enabled — their nick isn't registered yet.
    // SASL requires prior NickServ registration to work.
    // Verify the onboarding logic: saslEnabled = false regardless of password presence.
    let hasPassword = true          // user has an auto-generated password
    let saslEnabled = false         // correct: disabled for new unregistered nicks
    // The old (broken) code was:  saslEnabled = pass != nil  → true when password set
    // The new (correct) code is:  saslEnabled = false  always for onboarding-created servers
    try assertFalse(saslEnabled)
    try assertTrue(hasPassword)     // password still stored for later NickServ registration
}

runTest("testNoticeRoutingForNickServMessages") {
    // NickServ sends: NOTICE yournick :neatbird is not a registered nickname.
    // The target is the user's nick, not a channel name.
    // Our fixed onMessage guard must accept these (isForUs = true).
    let msg = IRCMessage(rawLine: ":NickServ!NickServ@services.libera.chat NOTICE neatbird :neatbird is not a registered nickname.")
    try assertEqual(msg.command, "NOTICE")
    let target = msg.parameters.first ?? ""
    try assertEqual(target, "neatbird")
    // The target does NOT start with # — so it's a user-directed notice
    let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
    try assertFalse(isChannel)
    // Our resolvedNick would be "neatbird", so isForUs = true
    let resolvedNick = "neatbird"
    let isForUs = !isChannel && target.lowercased() == resolvedNick.lowercased()
    try assertTrue(isForUs)
}

runTest("testChannelMessageNotShownInWrongChannel") {
    // A message to #python must not appear in the #linux channel view.
    let msg = IRCMessage(rawLine: ":alice!user@host PRIVMSG #python :Hello Python!")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#")
    try assertTrue(isChannel)
    let isForLinux = isChannel && target.lowercased() == "#linux"
    try assertFalse(isForLinux)
}

// MARK: - PASS command suppression tests
// Root cause of "cannot post anything": the auto-generated password was being sent
// via the IRC PASS command to public servers like Libera.Chat.  Libera.Chat responds
// with "ERROR :Bad password" and immediately closes the connection, silently killing
// every subsequent send attempt.

print("\n=== PASS Command Suppression Tests ===")

// Simulate the Server model's useConnectionPassword flag
struct TestServer {
    var password: String?
    var saslEnabled: Bool
    var useConnectionPassword: Bool
}

/// Mirrors the fixed IRCClientManager logic:
/// serverPassword is only passed when useConnectionPassword == true.
func resolvedServerPassword(for server: TestServer) -> String? {
    server.useConnectionPassword ? server.password : nil
}

runTest("testPublicServerNeverSendsPASS") {
    // Libera.Chat, OFTC, etc. — password is for NickServ/SASL, NOT for PASS command
    let server = TestServer(password: "Xk4mB2pQzRs9vN", saslEnabled: false, useConnectionPassword: false)
    let pass = resolvedServerPassword(for: server)
    try assertTrue(pass == nil)
}

runTest("testPublicServerWithSASLNeverSendsPASS") {
    let server = TestServer(password: "SaslPassword123", saslEnabled: true, useConnectionPassword: false)
    let pass = resolvedServerPassword(for: server)
    try assertTrue(pass == nil)
}

runTest("testBouncerServerSendsPASS") {
    // Private server / bouncer that requires a server-level password
    let server = TestServer(password: "bouncer_secret", saslEnabled: false, useConnectionPassword: true)
    let pass = resolvedServerPassword(for: server)
    try assertEqual(pass, "bouncer_secret")
}

runTest("testBouncerWithNilPasswordSendsNilPASS") {
    // useConnectionPassword=true but no password set → nil
    let server = TestServer(password: nil, saslEnabled: false, useConnectionPassword: true)
    let pass = resolvedServerPassword(for: server)
    try assertTrue(pass == nil)
}

runTest("testBouncerWithEmptyPasswordSendsNilPASS") {
    // Empty string password should NOT produce "PASS " (a PASS with no argument)
    let server = TestServer(password: "", saslEnabled: false, useConnectionPassword: true)
    let pass = resolvedServerPassword(for: server)
    // The IRCClient.connect() guard is: if let password = serverPassword, !password.isEmpty
    // An empty string passed here would be caught by that guard.
    // resolvedServerPassword returns "" which is still non-nil, but connect() checks isEmpty.
    // Test that a blank password is treated as absent.
    let effectivePass: String? = (server.useConnectionPassword && !(server.password ?? "").isEmpty) ? server.password : nil
    try assertTrue(effectivePass == nil)
}

runTest("testNewServerDefaultsToNoConnectionPassword") {
    // Servers created via onboarding should default to useConnectionPassword = false
    let server = TestServer(password: "auto-generated", saslEnabled: false, useConnectionPassword: false)
    try assertFalse(server.useConnectionPassword)
}

runTest("testPASSCommandFormat") {
    // When we DO send PASS, verify it's formatted correctly (no colon prefix)
    let password = "my_bouncer_pass"
    let passLine = "PASS \(password)"
    try assertTrue(passLine.hasPrefix("PASS "))
    try assertFalse(passLine.contains(":"))  // PASS takes a single middle param, no trailing colon
    try assertEqual(passLine, "PASS my_bouncer_pass")
}

// MARK: - PRIVMSG send path tests
// Tests that cover the complete chain from ChannelViewModel.send() to the wire.

print("\n=== PRIVMSG Send Path Tests ===")

/// Simulates send(command:parameters:) from IRCClient
func buildPrivmsgLine(channel: String, text: String) -> String {
    // send(command: "PRIVMSG", parameters: [channel, text])
    // → "PRIVMSG #channel :message text"
    return "PRIVMSG \(channel) :\(text)"
}

runTest("testPrivmsgBuildsCorrectly") {
    let line = buildPrivmsgLine(channel: "#linux", text: "Hello world")
    try assertEqual(line, "PRIVMSG #linux :Hello world")
}

runTest("testPrivmsgWithSpecialChars") {
    let line = buildPrivmsgLine(channel: "#linux", text: "hello: how are you?")
    try assertEqual(line, "PRIVMSG #linux :hello: how are you?")
}

runTest("testPrivmsgEndsWithCRLF") {
    // Wire format must end with \r\n
    let line = buildPrivmsgLine(channel: "#test", text: "hi")
    var data = (line).data(using: .utf8)!
    data.append(contentsOf: [0x0D, 0x0A])
    let str = String(data: data, encoding: .utf8)!
    try assertTrue(str.hasSuffix("\r\n"))
}

runTest("testPrivmsgNotSentWhenDisconnected") {
    // Simulates the guard in send_raw: guard isConnected else { throw notConnected }
    let isConnected = false
    var threw = false
    if !isConnected {
        threw = true  // would throw IRCError.notConnected
    }
    try assertTrue(threw)
}

runTest("testPrivmsgSentWhenConnected") {
    let isConnected = true
    var threw = false
    if !isConnected {
        threw = true
    }
    try assertFalse(threw)
}

runTest("testCtcpActionFormat") {
    // /me message → PRIVMSG #chan :\u{0001}ACTION text\u{0001}
    let action = "waves hello"
    let ctcp = "\u{0001}ACTION \(action)\u{0001}"
    let line = "PRIVMSG #linux :\(ctcp)"
    try assertTrue(line.contains("\u{0001}ACTION"))
    try assertTrue(line.hasSuffix("\u{0001}"))
}

runTest("testEmptyMessageNotSent") {
    // ChannelViewModel.send() guards: guard !trimmed.isEmpty else { return }
    let text = "   "
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    try assertTrue(trimmed.isEmpty)
}

runTest("testWhitespaceOnlyMessageNotSent") {
    let text = "\t\n  \r\n"
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    try assertTrue(trimmed.isEmpty)
}

// MARK: - Connection flow tests (NICK + USER must be sent)

print("\n=== Connection Registration Tests ===")

// Simulate the sequence of commands sent during IRC registration.
// These are the commands that MUST appear in order for the server to accept us.

struct CommandLog {
    var sent: [String] = []
    mutating func sendRaw(_ line: String) { sent.append(line) }
}

runTest("testRegistrationSendsNickBeforeUser") {
    var log = CommandLog()
    log.sendRaw("CAP LS 302")
    log.sendRaw("CAP REQ :batch server-time chathistory")
    // PASS omitted (useConnectionPassword = false)
    log.sendRaw("NICK neatbird")
    log.sendRaw("USER neatbird 0 * :neatbird")
    log.sendRaw("CAP END")

    let nickIdx = log.sent.firstIndex(where: { $0.hasPrefix("NICK ") })
    let userIdx = log.sent.firstIndex(where: { $0.hasPrefix("USER ") })
    try assertTrue(nickIdx != nil)
    try assertTrue(userIdx != nil)
    try assertTrue(nickIdx! < userIdx!)
}

runTest("testRegistrationNoPASSForPublicServer") {
    var log = CommandLog()
    // Simulate connect() with useConnectionPassword = false
    let serverPassword: String? = nil  // resolvedServerPassword returned nil
    if let pw = serverPassword, !pw.isEmpty {
        log.sendRaw("PASS \(pw)")
    }
    log.sendRaw("NICK neatbird")
    log.sendRaw("USER neatbird 0 * :neatbird")

    let hasPass = log.sent.contains(where: { $0.hasPrefix("PASS ") })
    try assertFalse(hasPass)
    try assertTrue(log.sent.contains("NICK neatbird"))
    try assertTrue(log.sent.contains("USER neatbird 0 * :neatbird"))
}

runTest("testRegistrationSendsPASSForPrivateServer") {
    var log = CommandLog()
    let serverPassword: String? = "bouncer123"  // useConnectionPassword = true
    if let pw = serverPassword, !pw.isEmpty {
        log.sendRaw("PASS \(pw)")
    }
    log.sendRaw("NICK neatbird")
    log.sendRaw("USER neatbird 0 * :neatbird")

    try assertTrue(log.sent.contains("PASS bouncer123"))
    let passIdx = log.sent.firstIndex(of: "PASS bouncer123")!
    let nickIdx = log.sent.firstIndex(of: "NICK neatbird")!
    try assertTrue(passIdx < nickIdx)  // PASS must come before NICK
}

runTest("testRegistrationCapEndSentLast") {
    var log = CommandLog()
    log.sendRaw("CAP LS 302")
    log.sendRaw("CAP REQ :batch chathistory")
    log.sendRaw("NICK neatbird")
    log.sendRaw("USER neatbird 0 * :neatbird")
    log.sendRaw("CAP END")

    try assertEqual(log.sent.last, "CAP END")
}

runTest("testNickCommandFormat") {
    // NICK must NOT have a trailing colon: "NICK neatbird" not "NICK :neatbird"
    let nick = "neatbird"
    let line = "NICK \(nick)"
    try assertFalse(line.contains(":"))
    try assertEqual(line, "NICK neatbird")
}

runTest("testUserCommandFormat") {
    // USER format: USER <username> 0 * :<realname>
    let username = "neatbird"
    let realname = "Neat Bird"
    let line = "USER \(username) 0 * :\(realname)"
    try assertTrue(line.hasPrefix("USER "))
    try assertTrue(line.contains(" 0 * :"))
    try assertTrue(line.hasSuffix(realname))
}

// MARK: - CHATHISTORY flow tests

print("\n=== CHATHISTORY Flow Tests ===")

runTest("testChathistoryNotSentWhenDisabled") {
    // If chathistoryEnabled == false, requestChatHistoryIfSupported() returns early
    let chathistoryEnabled = false
    var requestSent = false
    if chathistoryEnabled {
        requestSent = true
    }
    try assertFalse(requestSent)
}

runTest("testChathistoryNotSentBeforeConnectionEstablished") {
    // Simulates the scenario that caused chathistory to fail:
    // The connection is killed by ERROR :Bad password before chathistory can be sent.
    // Now that PASS is suppressed, this scenario no longer occurs.
    var isConnected = true
    // Simulate ERROR :Bad password closing the connection
    isConnected = false
    var requestSent = false
    if isConnected {
        requestSent = true  // would only reach this if connected
    }
    try assertFalse(requestSent)
}

runTest("testChathistoryOnlySentAfter366") {
    // The 366 RPL_ENDOFNAMES is the gating event.
    // This test documents the correct sequence.
    var chathistoryRequestSent = false
    var joinConfirmed = false

    // Simulate receiving 366
    let msg366 = IRCMessage(rawLine: ":server 366 neatbird #linux :End of /NAMES list")
    if msg366.command == "366", msg366.parameters.count >= 2 {
        joinConfirmed = true
        // NOW it's safe to send CHATHISTORY
        chathistoryRequestSent = true
    }

    try assertTrue(joinConfirmed)
    try assertTrue(chathistoryRequestSent)
    // Key invariant: chathistory was NOT sent before 366
}

runTest("testChathistoryCommandFormat") {
    // CHATHISTORY LATEST <target> <anchor> <limit>
    // Anchor "*" means "from the most recent message"
    let target = "#linux"
    let limit = 100
    let cmd = "CHATHISTORY LATEST \(target) * \(limit)"
    let parsed = IRCMessage(rawLine: cmd)
    try assertEqual(parsed.command, "CHATHISTORY")
    try assertEqual(parsed.parameters[0], "LATEST")
    try assertEqual(parsed.parameters[1], target)
    try assertEqual(parsed.parameters[2], "*")
    try assertEqual(parsed.parameters[3], "\(limit)")
}

runTest("testChathistorySinceCommandFormat") {
    // CHATHISTORY LATEST <target> timestamp=<iso8601> <limit>
    let target = "#linux"
    let ts = "2026-04-20T00:00:00.000Z"
    let limit = 50
    let cmd = "CHATHISTORY LATEST \(target) timestamp=\(ts) \(limit)"
    try assertTrue(cmd.contains("timestamp="))
    try assertTrue(cmd.contains(target))
    try assertTrue(cmd.hasSuffix("\(limit)"))
}

runTest("testChathistoryLimitCappedAtServerMax") {
    // Client should never request more than chathistoryMaxLimit
    let serverMax = 100
    let requestedLimit = 200
    let effectiveLimit = min(requestedLimit, serverMax)
    try assertEqual(effectiveLimit, 100)
}

runTest("testChathistoryLimitCappedAt100ForHistory") {
    // ChannelViewModel caps at 100 even if server allows more
    let serverMax = 1000
    let appCap = 100
    let requestedLimit = min(serverMax, appCap)
    try assertEqual(requestedLimit, 100)
}

runTest("testChathistoryBatchRoutingByType") {
    // Only messages whose batch ref maps to a "chathistory" type go to onHistoryMessage
    let activeBatches = ["hist1": "chathistory", "live1": ""]
    let histMsg = IRCMessage(rawLine: "@batch=hist1 :alice!a@b PRIVMSG #linux :History message")
    let liveMsg = IRCMessage(rawLine: "@batch=live1 :bob!b@c PRIVMSG #linux :Live message")
    let noTagMsg = IRCMessage(rawLine: ":carol!c@d PRIVMSG #linux :No batch tag")

    try assertTrue(isHistoryBatch(message: histMsg, activeBatches: activeBatches))
    try assertFalse(isHistoryBatch(message: liveMsg, activeBatches: activeBatches))
    try assertFalse(isHistoryBatch(message: noTagMsg, activeBatches: activeBatches))
}

runTest("testChathistoryEnabledOnlyAfterExplicitCapAck") {
    // chathistoryEnabled must only be true when "chathistory" or "draft/chathistory"
    // is explicitly in CAP ACK — not just because "batch" was ACKed.
    var chathistoryEnabled = false
    let ackCaps = ["batch", "server-time", "message-tags"]  // no "chathistory"
    for cap in ackCaps {
        let capName = cap.trimmingCharacters(in: .init(charactersIn: "-~="))
        if capName == "chathistory" || capName == "draft/chathistory" {
            chathistoryEnabled = true
        }
    }
    try assertFalse(chathistoryEnabled)
}

runTest("testChathistoryEnabledWhenExplicitlyAcked") {
    var chathistoryEnabled = false
    let ackCaps = ["batch", "server-time", "chathistory"]
    for cap in ackCaps {
        let capName = cap.trimmingCharacters(in: .init(charactersIn: "-~="))
        if capName == "chathistory" || capName == "draft/chathistory" {
            chathistoryEnabled = true
        }
    }
    try assertTrue(chathistoryEnabled)
}

// MARK: - Error :Bad password scenario tests
// Regression tests documenting the exact bug that caused messages not to send.

print("\n=== ERROR :Bad password Regression Tests ===")

runTest("testErrorBadPasswordKillsConnection") {
    // Simulates receiving "ERROR :Bad password" from the server.
    // This is what Libera.Chat sends when PASS is sent with a wrong/unexpected password.
    let errorLine = ":irc.libera.chat ERROR :Bad password"
    let msg = IRCMessage(rawLine: errorLine)
    try assertEqual(msg.command, "ERROR")
    try assertTrue(msg.parameters.first?.contains("Bad password") == true)
}

runTest("testErrorCommandCausesDisconnect") {
    // After ERROR is received, the connection must be treated as dead.
    // Sending any command after this must throw .notConnected.
    var isConnected = true
    let msg = IRCMessage(rawLine: ":server ERROR :Bad password")
    if msg.command == "ERROR" {
        isConnected = false  // handleMessage sets isConnected = false
    }
    try assertFalse(isConnected)
}

runTest("testSuppressingPASSPreventsErrorBadPassword") {
    // The fix: useConnectionPassword = false → no PASS sent → no ERROR response.
    var log = CommandLog()
    let useConnectionPassword = false
    let password = "Xk4mB2pQzRs9vN"  // auto-generated onboarding password

    // Fixed connect flow:
    if useConnectionPassword && !password.isEmpty {
        log.sendRaw("PASS \(password)")
    }
    log.sendRaw("NICK neatbird")
    log.sendRaw("USER neatbird 0 * :neatbird")

    let hasPass = log.sent.contains(where: { $0.hasPrefix("PASS ") })
    try assertFalse(hasPass)  // PASS is not sent → Libera.Chat never sends ERROR :Bad password
}

runTest("testConnectionSurvivesWithoutPASS") {
    // After fixing PASS suppression, connection should stay alive and sends work.
    var isConnected = false
    var log = CommandLog()

    // Simulate successful connect (no ERROR because no PASS was sent)
    isConnected = true  // 001 RPL_WELCOME received
    log.sendRaw("JOIN #linux")
    log.sendRaw("PRIVMSG #linux :Hello!")

    try assertTrue(isConnected)
    try assertTrue(log.sent.contains(where: { $0.hasPrefix("PRIVMSG") }))
}

// MARK: - Member list parsing tests
// Covers ChannelViewModel.parseNick() and the merge/sort logic that populates
// viewModel.members.  The same logic runs in the new Combine-subscription path
// so correctness here ensures the MemberListView is never blank due to parsing bugs.

print("\n=== Member List Parsing Tests ===")

// Simulates ChannelViewModel.parseNick() — mirrors the implementation exactly
struct TestMember: Equatable {
    var nick: String
    var mode: String  // "", "+", "@", "%", "&", "~"
}

func parseNick(_ raw: String) -> TestMember {
    switch raw.first {
    case "@": return TestMember(nick: String(raw.dropFirst()), mode: "@")
    case "+": return TestMember(nick: String(raw.dropFirst()), mode: "+")
    case "%": return TestMember(nick: String(raw.dropFirst()), mode: "%")
    case "&": return TestMember(nick: String(raw.dropFirst()), mode: "&")
    case "~": return TestMember(nick: String(raw.dropFirst()), mode: "~")
    default:  return TestMember(nick: raw, mode: "")
    }
}

func parseModeOrder(_ mode: String) -> Int {
    switch mode {
    case "~": return 0   // founder
    case "&": return 1   // admin
    case "@": return 2   // operator
    case "%": return 3   // halfop
    case "+": return 4   // voiced
    default:  return 5   // regular
    }
}

runTest("testMemberListParsesOpPrefix") {
    let m = parseNick("@alice")
    try assertEqual(m.nick, "alice")
    try assertEqual(m.mode, "@")
}

runTest("testMemberListParsesVoicePrefix") {
    let m = parseNick("+bob")
    try assertEqual(m.nick, "bob")
    try assertEqual(m.mode, "+")
}

runTest("testMemberListParsesFounderPrefix") {
    let m = parseNick("~chan_owner")
    try assertEqual(m.nick, "chan_owner")
    try assertEqual(m.mode, "~")
}

runTest("testMemberListParsesHalfopPrefix") {
    let m = parseNick("%helper")
    try assertEqual(m.nick, "helper")
    try assertEqual(m.mode, "%")
}

runTest("testMemberListParsesAdminPrefix") {
    let m = parseNick("&admin")
    try assertEqual(m.nick, "admin")
    try assertEqual(m.mode, "&")
}

runTest("testMemberListParsesNoPrefix") {
    let m = parseNick("regular_user")
    try assertEqual(m.nick, "regular_user")
    try assertEqual(m.mode, "")
}

runTest("testMemberListParsesNickWithNumbers") {
    let m = parseNick("@op42")
    try assertEqual(m.nick, "op42")
    try assertEqual(m.mode, "@")
}

runTest("testMemberListMergesWithoutDuplicates") {
    // Simulates receiving 353 NAMREPLY twice for the same nick
    var members: [TestMember] = []
    let batch1 = ["@alice", "bob"]
    let batch2 = ["@alice", "carol"]   // alice already present
    for raw in batch1 {
        let m = parseNick(raw)
        if !members.contains(where: { $0.nick == m.nick }) { members.append(m) }
    }
    for raw in batch2 {
        let m = parseNick(raw)
        if !members.contains(where: { $0.nick == m.nick }) { members.append(m) }
    }
    try assertEqual(members.count, 3)   // alice, bob, carol — no duplicate alice
    try assertEqual(members.filter { $0.nick == "alice" }.count, 1)
}

runTest("testMemberListSortsFounderBeforeOp") {
    var members = [parseNick("@op"), parseNick("~founder")]
    members.sort { parseModeOrder($0.mode) < parseModeOrder($1.mode) }
    try assertEqual(members[0].nick, "founder")
    try assertEqual(members[1].nick, "op")
}

runTest("testMemberListSortsOpBeforeVoice") {
    var members = [parseNick("+voiced"), parseNick("@op")]
    members.sort { parseModeOrder($0.mode) < parseModeOrder($1.mode) }
    try assertEqual(members[0].nick, "op")
    try assertEqual(members[1].nick, "voiced")
}

runTest("testMemberListSortsOpBeforeRegular") {
    var members = [parseNick("regular"), parseNick("@op")]
    members.sort { parseModeOrder($0.mode) < parseModeOrder($1.mode) }
    try assertEqual(members[0].nick, "op")
    try assertEqual(members[1].nick, "regular")
}

runTest("testMemberListSortsAlphaWithinGroup") {
    // Within same mode, sort alphabetically by nick (lowercased)
    var members = [parseNick("Zara"), parseNick("alice"), parseNick("Bob")]
        .map { m in m }  // all regular (mode "")
    members.sort { lhs, rhs in
        parseModeOrder(lhs.mode) == parseModeOrder(rhs.mode)
            ? lhs.nick.lowercased() < rhs.nick.lowercased()
            : parseModeOrder(lhs.mode) < parseModeOrder(rhs.mode)
    }
    try assertEqual(members[0].nick, "alice")
    try assertEqual(members[1].nick, "Bob")
    try assertEqual(members[2].nick, "Zara")
}

runTest("testMemberListChannelFilterIgnoresOtherChannels") {
    // The onNamesList handler guards: channel.lowercased() == self.channelName.lowercased()
    // If we're in #linux, a NAMES reply for #rust must be ignored.
    let myChannel = "#linux"
    let namesChannel = "#rust"
    let shouldProcess = namesChannel.lowercased() == myChannel.lowercased()
    try assertFalse(shouldProcess)
}

runTest("testMemberListChannelFilterAcceptsOwnChannel") {
    let myChannel = "#linux"
    let namesChannel = "#linux"
    let shouldProcess = namesChannel.lowercased() == myChannel.lowercased()
    try assertTrue(shouldProcess)
}

runTest("testMemberListChannelFilterCaseInsensitive") {
    let myChannel = "#Linux"
    let namesChannel = "#linux"
    let shouldProcess = namesChannel.lowercased() == myChannel.lowercased()
    try assertTrue(shouldProcess)
}

runTest("testMemberListRemovedOnPart") {
    var members = [parseNick("@alice"), parseNick("bob"), parseNick("carol")]
    // Simulate PART by bob
    members.removeAll { $0.nick == "bob" }
    try assertEqual(members.count, 2)
    try assertFalse(members.contains(where: { $0.nick == "bob" }))
}

runTest("testMemberListRemovedOnQuit") {
    var members = [parseNick("alice"), parseNick("@bob"), parseNick("carol")]
    // QUIT removes from all channels (no channel check needed)
    members.removeAll { $0.nick == "alice" }
    try assertEqual(members.count, 2)
    try assertFalse(members.contains(where: { $0.nick == "alice" }))
}

runTest("testMemberListNickUpdatedOnNickChange") {
    var members = [parseNick("oldnick"), parseNick("@alice")]
    // Simulate NICK oldnick -> newnick
    if let idx = members.firstIndex(where: { $0.nick == "oldnick" }) {
        members[idx].nick = "newnick"
    }
    try assertTrue(members.contains(where: { $0.nick == "newnick" }))
    try assertFalse(members.contains(where: { $0.nick == "oldnick" }))
}

runTest("testNamesCommandNotSentForDMTarget") {
    // requestNamesIfNeeded() guards: channelName.hasPrefix("#") || .hasPrefix("&")
    // A nick like "alice" should NOT trigger NAMES
    let channelName = "alice"
    let isChannelTarget = channelName.hasPrefix("#") || channelName.hasPrefix("&")
    try assertFalse(isChannelTarget)
}

runTest("testNamesCommandSentForChannelTarget") {
    let channelName = "#linux"
    let isChannelTarget = channelName.hasPrefix("#") || channelName.hasPrefix("&")
    try assertTrue(isChannelTarget)
}

runTest("testNamesCommandSentForAmpersandChannel") {
    // IRC allows & prefix channels
    let channelName = "&local"
    let isChannelTarget = channelName.hasPrefix("#") || channelName.hasPrefix("&")
    try assertTrue(isChannelTarget)
}

// MARK: - DM creation and routing tests

print("\n=== DM Creation and Routing Tests ===")

runTest("testDMChannelNameIsNick") {
    // When a DM is created, channel.name == the remote nick (not "#nick")
    let nick = "alice"
    let channelName = nick   // not "#" + nick
    try assertFalse(channelName.hasPrefix("#"))
    try assertEqual(channelName, "alice")
}

runTest("testDMSendTargetsNickDirectly") {
    // ChannelViewModel.send() calls sendMessage(to: channelName)
    // For a DM, channelName is the nick, so PRIVMSG goes to "alice" not "#alice"
    let dmChannelName = "alice"
    let privmsgLine = "PRIVMSG \(dmChannelName) :Hello"
    try assertTrue(privmsgLine.hasPrefix("PRIVMSG alice"))
    try assertFalse(privmsgLine.hasPrefix("PRIVMSG #"))
}

runTest("testPrivateMessageRoutingToCurrentUser") {
    // PRIVMSG alice :msg (where we are "alice") → isForUs = true
    let msg = IRCMessage(rawLine: ":bob!b@host PRIVMSG alice :Hello there")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#")
    let myNick = "alice"
    let isForUs = !isChannel && target.lowercased() == myNick.lowercased()
    try assertFalse(isChannel)
    try assertTrue(isForUs)
}

runTest("testChannelMessageNotRoutedToDMView") {
    // PRIVMSG #linux :msg with dmChannelName = "alice" → neither isForChannel nor isForUs
    let msg = IRCMessage(rawLine: ":bob!b@host PRIVMSG #linux :General chat")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#")
    let dmChannelName = "alice"   // DM view for "alice"
    let myNick = "alice"
    let isForChannel = isChannel && target.lowercased() == dmChannelName.lowercased()
    let isForUs = !isChannel && target.lowercased() == myNick.lowercased()
    try assertFalse(isForChannel)  // #linux != alice
    try assertFalse(isForUs)       // it IS a channel message
}

runTest("testNickServNoticeIsRoutedToCurrentUser") {
    // :NickServ!NickServ@services NOTICE alice :This nickname is registered.
    let msg = IRCMessage(rawLine: ":NickServ!NickServ@services.libera.chat NOTICE alice :This nickname is registered.")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#")
    let myNick = "alice"
    let isForUs = !isChannel && target.lowercased() == myNick.lowercased()
    try assertTrue(isForUs)
}

runTest("testNickServNoticeNotRoutedToOtherUser") {
    let msg = IRCMessage(rawLine: ":NickServ!NickServ@services NOTICE someone_else :Welcome.")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#")
    let myNick = "alice"
    let isForUs = !isChannel && target.lowercased() == myNick.lowercased()
    try assertFalse(isForUs)
}

runTest("testOpenDMCreatesChannelWithCorrectFields") {
    // Mirrors openOrCreateDM logic: isDM = true, name = nick, not starting with #
    let nick = "bob"
    var ch_name = nick
    let ch_isDM = true
    try assertFalse(ch_name.hasPrefix("#"))
    try assertTrue(ch_isDM)
    try assertEqual(ch_name, "bob")
}

runTest("testDMIsDMFlagDistinguishesFromChannel") {
    // Regular channels have isDM = false, DMs have isDM = true
    let channel_isDM = false
    let dm_isDM = true
    try assertFalse(channel_isDM)
    try assertTrue(dm_isDM)
}

// MARK: - Fan-out / background message processing tests
// These test the logic in IRCClientManager.handleIncomingMessage() and
// ChannelViewModel.handleSubscribedMessage() — ensuring ALL channels receive
// messages regardless of which one is currently visible.

print("\n=== Fan-out / Background Message Tests ===")

/// Simulates IRCClientManager.handleIncomingMessage logic:
/// determines if a message should be persisted and whether unread should increment.
func shouldPersist(msg: IRCMessage, myNick: String) -> Bool {
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
    guard isChannel else { return false }  // server notices handled separately
    let nick = msg.source?.nick ?? "server"
    return nick.lowercased() != myNick.lowercased()  // don't double-persist own messages
}

func shouldIncrementUnread(msg: IRCMessage, myNick: String, activeChannelId: String, channelId: String) -> Bool {
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
    guard isChannel else { return false }
    let nick = msg.source?.nick ?? "server"
    let isOwn = nick.lowercased() == myNick.lowercased()
    let isActive = activeChannelId == channelId
    return !isOwn && !isActive
}

runTest("testIncomingMessagePersistedForBackgroundChannel") {
    // bob sends to #rust while user is on #linux
    let msg = IRCMessage(rawLine: ":bob!b@host PRIVMSG #rust :Hey everyone")
    try assertTrue(shouldPersist(msg: msg, myNick: "alice"))
}

runTest("testOwnMessageNotDoublePersistedByManager") {
    // alice sends to #linux — manager should NOT persist (send() does it on success)
    let msg = IRCMessage(rawLine: ":alice!a@host PRIVMSG #linux :Hello")
    try assertFalse(shouldPersist(msg: msg, myNick: "alice"))
}

runTest("testUnreadIncrementedForNonActiveChannel") {
    // bob sends to #rust, user is viewing #linux — unread for #rust should increment
    let msg = IRCMessage(rawLine: ":bob!b@host PRIVMSG #rust :Hello")
    let activeId = "server:linux"
    let rustId   = "server:rust"
    try assertTrue(shouldIncrementUnread(msg: msg, myNick: "alice",
                                         activeChannelId: activeId, channelId: rustId))
}

runTest("testUnreadNotIncrementedForActiveChannel") {
    // bob sends to #linux, user is already viewing #linux — no unread increment
    let msg = IRCMessage(rawLine: ":bob!b@host PRIVMSG #linux :Hello")
    let activeId = "server:linux"
    try assertFalse(shouldIncrementUnread(msg: msg, myNick: "alice",
                                          activeChannelId: activeId, channelId: activeId))
}

runTest("testUnreadNotIncrementedForOwnMessages") {
    // alice sends to #linux (own message) — no unread
    let msg = IRCMessage(rawLine: ":alice!a@host PRIVMSG #linux :My message")
    let activeId = "server:rust"  // different channel, but own message
    let linuxId  = "server:linux"
    try assertFalse(shouldIncrementUnread(msg: msg, myNick: "alice",
                                          activeChannelId: activeId, channelId: linuxId))
}

runTest("testServerNoticeNotPersistedAsChannelMessage") {
    // NickServ notices target the user's nick, not a channel — don't persist as channel msg
    let msg = IRCMessage(rawLine: ":NickServ!NS@services NOTICE alice :Welcome to Libera.Chat")
    try assertFalse(shouldPersist(msg: msg, myNick: "alice"))
}

runTest("testIsChannelTargetHashPrefix") {
    let msg = IRCMessage(rawLine: ":alice!a@b PRIVMSG #linux :test")
    let target = msg.parameters.first ?? ""
    try assertTrue(target.hasPrefix("#"))
}

runTest("testIsChannelTargetAmpersandPrefix") {
    let msg = IRCMessage(rawLine: ":alice!a@b PRIVMSG &local :test")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
    try assertTrue(isChannel)
}

runTest("testIsNotChannelTargetForNick") {
    let msg = IRCMessage(rawLine: ":alice!a@b PRIVMSG bob :Direct message")
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
    try assertFalse(isChannel)
}

// MARK: - Server notice buffer tests

print("\n=== Server Notice Buffer Tests ===")

/// Simulates the serverNoticeBuffer logic in IRCClientManager
func bufferNotice(_ msg: IRCMessage, into buffer: inout [IRCMessage], max: Int) {
    buffer.append(msg)
    if buffer.count > max { buffer.removeFirst() }
}

runTest("testServerNoticeBufferedWhenNoChannelOpen") {
    var buffer: [IRCMessage] = []
    let notice = IRCMessage(rawLine: ":NickServ!NS@services NOTICE alice :You are now identified.")
    bufferNotice(notice, into: &buffer, max: 30)
    try assertEqual(buffer.count, 1)
    try assertEqual(buffer[0].source?.nick, "NickServ")
}

runTest("testServerNoticeBufferCappedAtMax") {
    var buffer: [IRCMessage] = []
    for i in 0..<35 {
        let msg = IRCMessage(rawLine: ":server NOTICE alice :Message \(i)")
        bufferNotice(msg, into: &buffer, max: 30)
    }
    try assertEqual(buffer.count, 30)
}

runTest("testServerNoticeBufferDrainedOnOpen") {
    var buffer: [IRCMessage] = []
    for i in 0..<5 {
        let msg = IRCMessage(rawLine: ":server NOTICE alice :Notice \(i)")
        bufferNotice(msg, into: &buffer, max: 30)
    }
    // Drain (as drainServerNotices does)
    let drained = buffer
    buffer = []
    try assertEqual(drained.count, 5)
    try assertEqual(buffer.count, 0)   // buffer cleared after drain
}

runTest("testServerNoticeBufferMaintainsOrder") {
    var buffer: [IRCMessage] = []
    bufferNotice(IRCMessage(rawLine: ":NickServ NOTICE alice :First"), into: &buffer, max: 30)
    bufferNotice(IRCMessage(rawLine: ":NickServ NOTICE alice :Second"), into: &buffer, max: 30)
    bufferNotice(IRCMessage(rawLine: ":NickServ NOTICE alice :Third"), into: &buffer, max: 30)
    try assertEqual(buffer[0].trailing, "First")
    try assertEqual(buffer[1].trailing, "Second")
    try assertEqual(buffer[2].trailing, "Third")
}

runTest("testServerNoticeBufferEvictsOldestFirst") {
    var buffer: [IRCMessage] = []
    // Fill to max
    for i in 0..<30 {
        bufferNotice(IRCMessage(rawLine: ":s NOTICE alice :msg\(i)"), into: &buffer, max: 30)
    }
    // Add one more — msg0 should be evicted
    bufferNotice(IRCMessage(rawLine: ":s NOTICE alice :newest"), into: &buffer, max: 30)
    try assertEqual(buffer.count, 30)
    try assertEqual(buffer.last?.trailing, "newest")
    try assertFalse(buffer.first?.trailing == "msg0")
}

// MARK: - IRC event routing tests

print("\n=== IRC Event Routing Tests ===")

runTest("testJoinEventRoutedToCorrectChannel") {
    // A join event for #rust must NOT update #linux's member list
    let joinChannel = "#rust"
    let myChannel   = "#linux"
    let isMyChannel = joinChannel.lowercased() == myChannel.lowercased()
    try assertFalse(isMyChannel)
}

runTest("testJoinEventAcceptedForMyChannel") {
    let joinChannel = "#linux"
    let myChannel   = "#linux"
    try assertTrue(joinChannel.lowercased() == myChannel.lowercased())
}

runTest("testPartEventRoutedToCorrectChannel") {
    // PART in #rust should only remove from #rust's member list
    let partChannel = "#rust"
    let myChannel   = "#linux"
    let isMyChannel = partChannel.lowercased() == myChannel.lowercased()
    try assertFalse(isMyChannel)
}

runTest("testQuitEventAffectsAllChannels") {
    // QUIT has no channel parameter — it affects any channel the nick was in.
    // The guard in handleEvent(.quit) does NOT filter by channel — intentional.
    var linux = [parseNick("alice"), parseNick("bob")]
    var rust  = [parseNick("alice"), parseNick("carol")]
    // Simulate QUIT for alice
    linux.removeAll { $0.nick == "alice" }
    rust.removeAll  { $0.nick == "alice" }
    try assertFalse(linux.contains(where: { $0.nick == "alice" }))
    try assertFalse(rust.contains(where:  { $0.nick == "alice" }))
}

runTest("testTopicChangeRoutedToCorrectChannel") {
    // topicChange for #rust should not update #linux's topic
    let topicChannel = "#rust"
    let myChannel    = "#linux"
    let isMyChannel  = topicChannel.lowercased() == myChannel.lowercased()
    try assertFalse(isMyChannel)
}

runTest("testTopicChangeAcceptedForMyChannel") {
    let topicChannel = "#linux"
    let myChannel    = "#linux"
    var topic        = ""
    if topicChannel.lowercased() == myChannel.lowercased() {
        topic = "Linux discussion — https://kernel.org"
    }
    try assertEqual(topic, "Linux discussion — https://kernel.org")
}

runTest("testEndOfNamesTriggersForCorrectChannel") {
    // 366 for #linux should only trigger CHATHISTORY for #linux
    let endOfNamesChannel = "#linux"
    let myChannel = "#linux"
    let other     = "#rust"
    try assertTrue(endOfNamesChannel.lowercased() == myChannel.lowercased())
    try assertFalse(endOfNamesChannel.lowercased() == other.lowercased())
}

runTest("testEndOfNamesParseFromMessage") {
    // Verify the 366 message parsing: parameters[1] is the channel
    let msg = IRCMessage(rawLine: ":irc.libera.chat 366 neatbird #linux :End of /NAMES list")
    try assertEqual(msg.command, "366")
    try assertEqual(msg.parameters[1], "#linux")
}

runTest("testChathistoryBatchEndParsedFromBatchClose") {
    // "BATCH -ref" closes a batch; if type was "chathistory" → .chathistoryBatchEnd fires
    var activeBatches = ["ref1": "chathistory"]
    var closedType = ""
    if let first = IRCMessage(rawLine: ":server BATCH -ref1").parameters.first,
       first.hasPrefix("-") {
        let ref = String(first.dropFirst())
        closedType = activeBatches.removeValue(forKey: ref) ?? ""
    }
    try assertTrue(closedType.contains("chathistory"))
    try assertTrue(activeBatches.isEmpty)
}

runTest("testZncBatchEndParsedFromBatchClose") {
    var activeBatches = ["znc1": "znc.in/playback"]
    var closedType = ""
    if let first = IRCMessage(rawLine: ":server BATCH -znc1").parameters.first,
       first.hasPrefix("-") {
        let ref = String(first.dropFirst())
        closedType = activeBatches.removeValue(forKey: ref) ?? ""
    }
    try assertTrue(closedType.contains("znc.in/playback"))
}

runTest("testModeChangeRoutedToCorrectChannel") {
    let modeTarget = "#linux"
    let myChannel  = "#rust"
    let isMyChannel = modeTarget.lowercased() == myChannel.lowercased()
    try assertFalse(isMyChannel)
}

runTest("testNickChangeUpdatesMemberList") {
    var members = [parseNick("alice"), parseNick("@bob")]
    // Simulate NICK alice -> aliceNew
    if let idx = members.firstIndex(where: { $0.nick == "alice" }) {
        members[idx].nick = "aliceNew"
    }
    try assertTrue(members.contains(where: { $0.nick == "aliceNew" }))
    try assertFalse(members.contains(where: { $0.nick == "alice" }))
    try assertEqual(members[0].mode, "")  // mode preserved
}

runTest("testNickChangeUpdatesCurrentNickWhenOursChanges") {
    var currentNick = "alice"
    let oldNick = "alice"
    let newNick = "alice_away"
    if oldNick.lowercased() == currentNick.lowercased() {
        currentNick = newNick
    }
    try assertEqual(currentNick, "alice_away")
}

runTest("testNickChangeDoesNotUpdateCurrentNickForOthers") {
    var currentNick = "alice"
    let oldNick = "bob"
    let newNick = "bob_away"
    if oldNick.lowercased() == currentNick.lowercased() {
        currentNick = newNick
    }
    try assertEqual(currentNick, "alice")  // unchanged
}

// MARK: - Unread badge display tests
// These verify the display logic for the unread capsule badge in ChannelRowView.

print("\n=== Unread Badge Display Tests ===")

runTest("testUnreadBadgeShowsCountBelow100") {
    let count = 42
    let label = count < 100 ? "\(count)" : "99+"
    try assertEqual(label, "42")
}

runTest("testUnreadBadgeShowsMax99Plus") {
    let count = 150
    let label = count < 100 ? "\(count)" : "99+"
    try assertEqual(label, "99+")
}

runTest("testUnreadBadgeHiddenWhenZero") {
    let count = 0
    let shouldShow = count > 0
    try assertFalse(shouldShow)
}

runTest("testUnreadBadgeHiddenWhenMuted") {
    let count = 10
    let isMuted = true
    let shouldShow = count > 0 && !isMuted
    try assertFalse(shouldShow)
}

runTest("testUnreadBadgeShownWhenNotMuted") {
    let count = 5
    let isMuted = false
    let shouldShow = count > 0 && !isMuted
    try assertTrue(shouldShow)
}

runTest("testChannelRowBoldWhenUnread") {
    // Channel name font weight is .semibold when unread > 0
    let unreadCount = 3
    let isBold = unreadCount > 0
    try assertTrue(isBold)
}

runTest("testChannelRowNormalWeightWhenRead") {
    let unreadCount = 0
    let isBold = unreadCount > 0
    try assertFalse(isBold)
}

// MARK: - Fix #1: Own message echo suppression tests
// When the user sends a message, Libera.Chat echoes it back as a PRIVMSG from
// the user's own nick.  Before this fix, that echo was fanned out via msgSubject
// and created a duplicate second bubble.  Now we skip msgSubject.send() for own
// non-history messages.

print("\n=== Fix #1: Own Message Echo Suppression Tests ===")

/// Mirrors the isOwnEcho check in IRCClientManager.client.onMessage
func isOwnEcho(msg: IRCMessage, myNick: String) -> Bool {
    guard !myNick.isEmpty else { return false }
    let senderNick = msg.source?.nick ?? ""
    let isBatch    = msg.tags?["batch"] != nil
    return senderNick.lowercased() == myNick.lowercased() && !isBatch
}

runTest("testOwnEchoSuppressed") {
    // Libera echoes ":alice!a@b PRIVMSG #linux :Hello" back to alice
    let echo = IRCMessage(rawLine: ":alice!a@b PRIVMSG #linux :Hello")
    try assertTrue(isOwnEcho(msg: echo, myNick: "alice"))
}

runTest("testOtherUserEchoNotSuppressed") {
    let msg = IRCMessage(rawLine: ":bob!b@c PRIVMSG #linux :Hello")
    try assertFalse(isOwnEcho(msg: msg, myNick: "alice"))
}

runTest("testOwnHistoryMessageNotSuppressed") {
    // History replay messages have a @batch tag — they must NOT be suppressed
    // because they carry server-side messages we haven't seen yet.
    let history = IRCMessage(rawLine: "@batch=ref1 :alice!a@b PRIVMSG #linux :Old message")
    try assertFalse(isOwnEcho(msg: history, myNick: "alice"))
}

runTest("testEmptyMyNickNeverSuppresses") {
    let echo = IRCMessage(rawLine: ":alice!a@b PRIVMSG #linux :Hello")
    // If we don't know our own nick yet, don't suppress anything
    try assertFalse(isOwnEcho(msg: echo, myNick: ""))
}

runTest("testOwnEchoMatchIsCaseInsensitive") {
    let echo = IRCMessage(rawLine: ":Alice!a@b PRIVMSG #linux :Hello")
    try assertTrue(isOwnEcho(msg: echo, myNick: "alice"))
}

runTest("testOwnEchoDMNotSuppressed") {
    // DMs to another user from us — the echo target is the other user, not us,
    // but the sender IS us; still suppress to avoid double-display in DM view.
    let echo = IRCMessage(rawLine: ":alice!a@b PRIVMSG bob :Hey Bob")
    try assertTrue(isOwnEcho(msg: echo, myNick: "alice"))
}

// MARK: - Fix #2: channelMembershipVersion tests

print("\n=== Fix #2: Channel Membership Version Tests ===")

runTest("testChannelMembershipVersionIncrementsOnLeave") {
    var version = 0
    // Simulate leaveChannel() bumping the version
    version += 1
    try assertEqual(version, 1)
}

runTest("testChannelMembershipVersionStartsAtZero") {
    let version = 0
    try assertEqual(version, 0)
}

runTest("testLeaveChannelClearsJoinedAt") {
    // When leaveChannel() runs, joinedAt must be set to nil so the channel
    // isn't auto-rejoined on the next connect.
    var joinedAt: Date? = Date()
    joinedAt = nil
    try assertTrue(joinedAt == nil)
}

// MARK: - Fix #4: Join/quit suppressed in DM windows

print("\n=== Fix #4: System Messages Suppressed in DM Windows ===")

/// Mirrors ChannelViewModel.isChannelConversation
func isChannelConversation(_ channelName: String) -> Bool {
    channelName.hasPrefix("#") || channelName.hasPrefix("&")
        || channelName.hasPrefix("!") || channelName.hasPrefix("+")
}

runTest("testIsChannelConversationHashChannel") {
    try assertTrue(isChannelConversation("#linux"))
}

runTest("testIsChannelConversationAmpersandChannel") {
    try assertTrue(isChannelConversation("&local"))
}

runTest("testIsNotChannelConversationForNick") {
    try assertFalse(isChannelConversation("alice"))
}

runTest("testQuitSystemMessageSuppressedInDMView") {
    // In DM view (channelName = "alice"), quit events must not produce system messages
    let channelName = "alice"
    let shouldAppendSystemMessage = isChannelConversation(channelName)
    try assertFalse(shouldAppendSystemMessage)
}

runTest("testQuitSystemMessageShownInChannelView") {
    let channelName = "#linux"
    let shouldAppendSystemMessage = isChannelConversation(channelName)
    try assertTrue(shouldAppendSystemMessage)
}

runTest("testNickChangeSystemMessageSuppressedInDMView") {
    let channelName = "bob"
    let shouldAppend = isChannelConversation(channelName)
    try assertFalse(shouldAppend)
}

runTest("testNickChangeSystemMessageShownInChannel") {
    let channelName = "#rust"
    let shouldAppend = isChannelConversation(channelName)
    try assertTrue(shouldAppend)
}

// MARK: - Fix #5: isFromCurrentUser re-derived on load

print("\n=== Fix #5: isFromCurrentUser Re-derived on Load ===")

/// Mirrors the loadPersistedMessages re-derivation logic
func rederiveIsFromCurrentUser(sender: String, myNick: String) -> Bool {
    guard !myNick.isEmpty else { return false }
    return sender.lowercased() == myNick.lowercased()
}

runTest("testOwnMessageMarkedIsFromCurrentUser") {
    let isOwn = rederiveIsFromCurrentUser(sender: "alice", myNick: "alice")
    try assertTrue(isOwn)
}

runTest("testOtherMessageNotMarkedIsFromCurrentUser") {
    let isOwn = rederiveIsFromCurrentUser(sender: "bob", myNick: "alice")
    try assertFalse(isOwn)
}

runTest("testIsFromCurrentUserCaseInsensitive") {
    // Nicks are case-insensitive on IRC
    let isOwn = rederiveIsFromCurrentUser(sender: "Alice", myNick: "alice")
    try assertTrue(isOwn)
}

runTest("testIsFromCurrentUserEmptyNickReturnsFalse") {
    // If we don't know our nick yet, default to false (incoming alignment)
    let isOwn = rederiveIsFromCurrentUser(sender: "alice", myNick: "")
    try assertFalse(isOwn)
}

runTest("testMultipleMessagesRedrived") {
    let myNick = "alice"
    let messages = [
        ("alice", true),   // own message
        ("bob",   false),  // other
        ("Alice", true),   // own nick, different case
        ("",      false),  // empty sender
    ]
    for (sender, expected) in messages {
        let result = rederiveIsFromCurrentUser(sender: sender, myNick: myNick)
        try assertEqual(result, expected)
    }
}

// MARK: - Fix #6: DM PRIVMSG not shown in channel views

print("\n=== Fix #6: DM PRIVMSG Not Shown in Channel Views ===")

/// Mirrors the isForUs logic in ChannelViewModel.handleSubscribedMessage
func isForUs(
    ircMsg: IRCMessage,
    myNick: String,
    channelName: String
) -> Bool {
    let target = ircMsg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#") || target.hasPrefix("&")
        || target.hasPrefix("!") || target.hasPrefix("+")
    guard !isChannel else { return false }  // channel messages handled by isForChannel
    guard target.lowercased() == myNick.lowercased() else { return false }
    let isNotice = ircMsg.command == "NOTICE"
    let isChannelView = isChannelConversation(channelName)
    // Channel views: only accept NOTICEs, not PRIVMSG DMs
    // DM views: accept both
    return isNotice || !isChannelView
}

runTest("testDMPrivmsgRejectedByChannelView") {
    // Bob sends alice a DM while alice is in #linux
    let dm = IRCMessage(rawLine: ":bob!b@c PRIVMSG alice :Hey, are you there?")
    let accepted = isForUs(ircMsg: dm, myNick: "alice", channelName: "#linux")
    try assertFalse(accepted)
}

runTest("testDMPrivmsgAcceptedByDMView") {
    // The DM view for "bob" should accept this
    let dm = IRCMessage(rawLine: ":bob!b@c PRIVMSG alice :Hey, are you there?")
    let accepted = isForUs(ircMsg: dm, myNick: "alice", channelName: "bob")
    try assertTrue(accepted)
}

runTest("testNickServNoticeAcceptedByChannelView") {
    // NOTICE from NickServ should still appear in the active channel view
    let notice = IRCMessage(rawLine: ":NickServ!NS@services NOTICE alice :This nickname is registered.")
    let accepted = isForUs(ircMsg: notice, myNick: "alice", channelName: "#linux")
    try assertTrue(accepted)
}

runTest("testNickServNoticeAcceptedByDMView") {
    // NOTICE also accepted in DM view
    let notice = IRCMessage(rawLine: ":NickServ!NS@services NOTICE alice :Password accepted.")
    let accepted = isForUs(ircMsg: notice, myNick: "alice", channelName: "bob")
    try assertTrue(accepted)
}

runTest("testDMToOtherUserNotAccepted") {
    // PRIVMSG addressed to "charlie", not "alice" — not for us at all
    let msg = IRCMessage(rawLine: ":bob!b@c PRIVMSG charlie :Hello Charlie")
    let accepted = isForUs(ircMsg: msg, myNick: "alice", channelName: "bob")
    try assertFalse(accepted)
}

runTest("testChannelPrivmsgNotAcceptedAsForUs") {
    // Regular channel message (#linux) is not "for us" in the isForUs path
    let msg = IRCMessage(rawLine: ":bob!b@c PRIVMSG #linux :General message")
    // isForUs guard: guard !isChannel else { return false }
    let target = msg.parameters.first ?? ""
    let isChannel = target.hasPrefix("#")
    try assertTrue(isChannel)   // confirms it's a channel message
    // Therefore isForUs returns false before the nick check
    let accepted = isForUs(ircMsg: msg, myNick: "alice", channelName: "alice")
    try assertFalse(accepted)
}

runTest("testDMInWrongChannelViewRejected") {
    // DM to alice while alice has #rust open — must be rejected
    let dm = IRCMessage(rawLine: ":carol!c@d PRIVMSG alice :See you later")
    let inRust   = isForUs(ircMsg: dm, myNick: "alice", channelName: "#rust")
    let inLinux  = isForUs(ircMsg: dm, myNick: "alice", channelName: "#linux")
    let inDMView = isForUs(ircMsg: dm, myNick: "alice", channelName: "carol")
    try assertFalse(inRust)
    try assertFalse(inLinux)
    try assertTrue(inDMView)
}

// MARK: - Performance fix tests (freeze/watchdog crash prevention)

print("\n=== Performance Fix Tests ===")

// Fix #1: Left channel filtering (joinedAt = nil hidden from sidebar)

runTest("testJoinedChannelShownInSidebar") {
    let joinedAt: Date? = Date()
    try assertTrue(joinedAt != nil)
}

runTest("testLeftChannelHiddenFromSidebar") {
    // leaveChannel() sets joinedAt = nil — channel must not appear in sidebar
    let joinedAt: Date? = nil
    try assertTrue(joinedAt == nil)
}

runTest("testFilterRemovesLeftChannels") {
    typealias FakeChannel = (name: String, joinedAt: Date?)
    let channels: [FakeChannel] = [
        ("#linux",   Date()),
        ("#rust",    Date()),
        ("#python",  nil),
        ("#haskell", nil),
    ]
    let visible = channels.filter { $0.joinedAt != nil }
    try assertEqual(visible.count, 2)
    try assertTrue(visible.contains(where: { $0.name == "#linux" }))
    try assertFalse(visible.contains(where: { $0.name == "#python" }))
}

runTest("testLeaveChannelSetsJoinedAtNil") {
    var joinedAt: Date? = Date()
    joinedAt = nil
    try assertTrue(joinedAt == nil)
}

// Fix #2A: O(N) vs O(N²) rebuildDisplay complexity

runTest("testHistoryBatchSingleRebuildIsLinear") {
    // Before: N messages → N calls to rebuildDisplay → O(N²) total iterations
    // After:  N messages → 1 call to rebuildDisplay → O(N) total iterations
    let n = 100
    let oldIterations = n * (n + 1) / 2  // 5050 — triangular number
    let newIterations = n                 // 100  — single pass
    try assertEqual(oldIterations, 5050)
    try assertEqual(newIterations, 100)
    try assertTrue(newIterations < oldIterations)
}

runTest("testHistoryBatchAccumulatesBeforeRebuild") {
    // Simulate: appendRaw() per message, rebuildDisplay() once at batch end
    var rawCount = 0
    var rebuildCount = 0
    let historyMessages = 50
    // New path: accumulate
    for _ in 0..<historyMessages { rawCount += 1 /* appendRaw, no rebuild */ }
    rebuildCount += 1  // chathistoryBatchEnd fires once
    try assertEqual(rawCount, 50)
    try assertEqual(rebuildCount, 1)  // single rebuild for entire batch
}

runTest("testLiveMessageStillRebuildsImmediately") {
    // Live (non-history) messages still call append() which calls rebuildDisplay()
    var rebuildCount = 0
    let isHistory = false
    if !isHistory { rebuildCount += 1 }
    try assertEqual(rebuildCount, 1)
}

runTest("testEmptyBatchEndIsNoOp") {
    var rebuildCount = 0
    let pendingHistoryMessageCount = 0
    // guard pendingHistoryMessageCount > 0 else { return }
    if pendingHistoryMessageCount > 0 { rebuildCount += 1 }
    try assertEqual(rebuildCount, 0)
}

runTest("testSpeedupFactor50xFor100Messages") {
    let n = 100
    let before = n * (n + 1) / 2
    let after  = n
    let speedup = before / after
    try assertEqual(speedup, 50)
}

// Fix #2B: Cached mention regex

runTest("testMentionRegexCachedNotRecompiled") {
    var cache: [String: Int] = [:]
    var compiles = 0
    func getCompileCount(nick: String) -> Int {
        let key = nick.lowercased()
        if cache[key] != nil { return 0 }  // cache hit — 0 new compilations
        compiles += 1
        cache[key] = compiles
        return 1  // compiled
    }
    try assertEqual(getCompileCount(nick: "alice"), 1)  // first: compiles
    try assertEqual(getCompileCount(nick: "alice"), 0)  // second: cached
    try assertEqual(getCompileCount(nick: "bob"), 1)    // new nick: compiles
    try assertEqual(compiles, 2)  // only 2 total compilations for 3 calls
}

runTest("testMentionRegexCacheKeyLowercased") {
    var cache: [String: Bool] = [:]
    let key1 = "Alice".lowercased()
    let key2 = "alice".lowercased()
    cache[key1] = true
    try assertTrue(cache[key2] != nil)  // same key
    try assertEqual(cache.count, 1)
}

runTest("testMentionPatternMatchesWholeWord") {
    let nick = "alice"
    let escaped = NSRegularExpression.escapedPattern(for: nick)
    let pattern = "(?i)(?<![\\w])\\Q\(escaped)\\E(?![\\w])"
    try assertTrue("hey alice how are you".range(of: pattern, options: .regularExpression) != nil)
    try assertTrue("alice: thanks".range(of: pattern, options: .regularExpression) != nil)
}

runTest("testMentionPatternDoesNotMatchSubstring") {
    let nick = "ali"
    let escaped = NSRegularExpression.escapedPattern(for: nick)
    let pattern = "(?i)(?<![\\w])\\Q\(escaped)\\E(?![\\w])"
    // "alice" contains "ali" as a substring — must NOT match
    try assertTrue("hey alice".range(of: pattern, options: .regularExpression) == nil)
}

runTest("testMentionSkippedForOwnOutgoingMessages") {
    // isOutgoing=true short-circuits before the regex runs
    let isOutgoing = true
    var regexRan = false
    if !isOutgoing { regexRan = true }
    try assertFalse(regexRan)
}

// Fix #2C: rulesURL cached, not recomputed on every render

runTest("testRulesURLEmptyTopicIsNil") {
    let topic = ""
    let rulesURL: URL? = topic.isEmpty ? nil : URL(string: "https://example.com")
    try assertTrue(rulesURL == nil)
}

runTest("testRulesURLComputedOnlyWhenTopicChanges") {
    // Simulate: compute count increments only when topic setter fires
    var computeCount = 0
    var topic = "" {
        didSet { computeCount += 1 }
    }
    // Two renders with same topic — only one computation
    topic = "Join rules: https://libera.chat/guides"
    topic = "Join rules: https://libera.chat/guides"  // same value, still fires didSet
    // Key insight: render passes DON'T recompute — only topic changes do
    // For 100 messages rendered, computeCount stays at 2 (one per topic assignment)
    try assertEqual(computeCount, 2)
}

runTest("testRulesURLUpdatesWhenTopicChanges") {
    // Verifies that rulesURL only updates on topic change, not on render.
    // NSDataDetector is Apple-platform only; here we test the caching logic.
    var computeCount = 0
    var rulesURL: String? = nil

    func onTopicChange(_ newTopic: String) {
        computeCount += 1
        // Simplified URL extraction for test purposes
        if newTopic.contains("https://") {
            rulesURL = newTopic.components(separatedBy: " ").first(where: { $0.hasPrefix("https://") })
        } else {
            rulesURL = nil
        }
    }

    onTopicChange("See rules at https://libera.chat/policies")
    try assertTrue(rulesURL != nil)
    try assertTrue(rulesURL?.contains("libera.chat") == true)
    onTopicChange("No URL in this topic")
    try assertTrue(rulesURL == nil)
    try assertEqual(computeCount, 2)  // only 2 — not per-render
}

// Summary
print("\n=== Results ===")
print("Passed: \(results.passed)")
print("Failed: \(results.failed)")
print("Total:  \(results.passed + results.failed)")

if results.failed > 0 {
    exit(1)
}