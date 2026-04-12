// Linux-only mock tests (not compiled on Darwin/iOS)
#if !canImport(Darwin)

import Foundation

print("=== Mock IRC Server Tests ===\n")

var passed = 0
var failed = 0

func test(_ name: String, _ fn: () throws -> Void) {
    do {
        try fn()
        print("✓ \(name)")
        passed += 1
    } catch {
        print("✗ \(name): \(error)")
        failed += 1
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
    if actual != expected {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected \(expected) but got \(actual): \(message)"])
    }
}

func assertTrue(_ value: Bool, _ message: String = "") throws {
    if !value {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected true: \(message)"])
    }
}

// Test 1: MockIRCServer starts and stops
test("MockIRCServer starts and stops") {
    let server = MockIRCServer(port: 6667)
    try server.start()
    try assertTrue(server.getReceivedCommands().isEmpty, "Should have no commands yet")
    server.stop()
}

// Test 2: MockIRCServer accepts connections
test("MockIRCServer accepts connections") {
    let server = MockIRCServer(port: 6668)
    try server.start()
    
    let client = MockIRCClient(host: "127.0.0.1", port: 6668)
    try client.connect()
    client.nick("testuser")
    client.user("testuser", realname: "Test User")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    let commands = server.getReceivedCommands()
    try assertTrue(commands.count >= 2, "Should have received NICK and USER")
    try assertTrue(commands.contains { $0.contains("NICK") }, "Should contain NICK")
    try assertTrue(commands.contains { $0.contains("USER") }, "Should contain USER")
    
    client.disconnect()
    server.stop()
}

// Test 3: MockIRCClient receives welcome
test("MockIRCClient receives welcome") {
    let server = MockIRCServer(port: 6669)
    try server.start()
    
    var welcomeReceived = false
    let client = MockIRCClient(host: "127.0.0.1", port: 6669)
    try client.connect()
    client.nick("testuser")
    client.user("testuser", realname: "Test User")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    let response = client.getReceivedMessages()
    let welcome = response.first { $0.contains("001") }
    try assertTrue(welcome != nil, "Should receive welcome 001")
    
    client.disconnect()
    server.stop()
}

// Test 4: JOIN command works
test("Client can JOIN channel") {
    let server = MockIRCServer(port: 6670)
    try server.start()
    
    let client = MockIRCClient(host: "127.0.0.1", port: 6670)
    try client.connect()
    client.nick("testuser")
    client.user("testuser", realname: "Test User")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    client.join("#test")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    let response = client.getReceivedMessages()
    let joinResponse = response.first { $0.contains("JOIN #test") || $0.contains("353") }
    try assertTrue(joinResponse != nil, "Should receive JOIN response")
    
    client.disconnect()
    server.stop()
}

// Test 5: PRIVMSG works
test("Client can send PRIVMSG") {
    let server = MockIRCServer(port: 6671)
    try server.start()
    
    let client = MockIRCClient(host: "127.0.0.1", port: 6671)
    try client.connect()
    client.nick("testuser")
    client.user("testuser", realname: "Test User")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    client.join("#test")
    Thread.sleep(forTimeInterval: 0.2)
    
    client.privmsg("#test", message: "Hello world")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    let response = client.getReceivedMessages()
    let privmsg = response.first { $0.contains("PRIVMSG") && $0.contains("Hello world") }
    try assertTrue(privmsg != nil, "Should receive PRIVMSG echo")
    
    client.disconnect()
    server.stop()
}

// Test 6: PING/PONG works
test("PING/PONG works") {
    let server = MockIRCServer(port: 6672)
    try server.start()
    
    let client = MockIRCClient(host: "127.0.0.1", port: 6672)
    try client.connect()
    client.nick("testuser")
    client.user("testuser", realname: "Test User")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    client.sendCommand("PING :test")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    let response = client.getReceivedMessages()
    let pong = response.first { $0.contains("PONG") }
    try assertTrue(pong != nil, "Should receive PONG")
    
    client.disconnect()
    server.stop()
}

// Test 7: Full conversation flow
test("Full conversation flow (connect -> nick -> user -> join -> privmsg -> quit)") {
    let server = MockIRCServer(port: 6673)
    try server.start()
    
    let client = MockIRCClient(host: "127.0.0.1", port: 6673)
    try client.connect()
    client.nick("testuser")
    client.user("testuser", realname: "Test User")
    
    Thread.sleep(forTimeInterval: 0.2)
    
    client.join("#test")
    Thread.sleep(forTimeInterval: 0.2)
    
    client.privmsg("#test", message: "Test message")
    Thread.sleep(forTimeInterval: 0.2)
    
    client.sendCommand("QUIT")
    Thread.sleep(forTimeInterval: 0.2)
    
    let serverCommands = server.getReceivedCommands()
    try assertTrue(serverCommands.contains { $0.contains("NICK") }, "Server should receive NICK")
    try assertTrue(serverCommands.contains { $0.contains("USER") }, "Server should receive USER")
    try assertTrue(serverCommands.contains { $0.contains("JOIN") }, "Server should receive JOIN")
    try assertTrue(serverCommands.contains { $0.contains("PRIVMSG") }, "Server should receive PRIVMSG")
    try assertTrue(serverCommands.contains { $0.contains("QUIT") }, "Server should receive QUIT")
    
    client.disconnect()
    server.stop()
}

// Print summary
print("\n=== Results ===")
print("Passed: \(passed)")
print("Failed: \(failed)")
print("Total:  \(passed + failed)")

if failed > 0 {
    exit(1)
}

#endif // !canImport(Darwin)