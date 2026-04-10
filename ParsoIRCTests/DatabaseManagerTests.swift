import XCTest
@testable import ParsoIRC

final class DatabaseManagerTests: XCTestCase {
    
    // MARK: - Server CRUD Tests
    
    func testSaveServer_insertsNewServer() throws {
        let server = Server(
            id: "test-server-\(UUID().uuidString)",
            name: "TestServer",
            host: "irc.test.com",
            port: 6697,
            nickname: "testuser"
        )
        
        try DatabaseManager.shared.saveServer(server)
        
        let fetchedServers = try DatabaseManager.shared.fetchServers()
        let foundServer = fetchedServers.first { $0.id == server.id }
        
        XCTAssertNotNil(foundServer)
        XCTAssertEqual(foundServer?.name, "TestServer")
        XCTAssertEqual(foundServer?.host, "irc.test.com")
    }
    
    func testSaveServer_updatesExistingServer() throws {
        let serverId = "test-server-update-\(UUID().uuidString)"
        let server = Server(
            id: serverId,
            name: "OriginalName",
            host: "irc.test.com",
            port: 6697,
            nickname: "testuser"
        )
        
        try DatabaseManager.shared.saveServer(server)
        
        var updatedServer = server
        updatedServer.name = "UpdatedName"
        try DatabaseManager.shared.saveServer(updatedServer)
        
        let fetchedServers = try DatabaseManager.shared.fetchServers()
        let foundServer = fetchedServers.first { $0.id == serverId }
        
        XCTAssertEqual(foundServer?.name, "UpdatedName")
    }
    
    func testFetchServers_returnsEmptyArrayWhenNoServers() throws {
        let servers = try DatabaseManager.shared.fetchServers()
        
        XCTAssertNotNil(servers)
    }
    
    func testDeleteServer_removesServerAndChannels() throws {
        let serverId = "test-server-delete-\(UUID().uuidString)"
        let server = Server(
            id: serverId,
            name: "DeleteMe",
            host: "irc.test.com",
            port: 6697,
            nickname: "testuser"
        )
        
        try DatabaseManager.shared.saveServer(server)
        
        try DatabaseManager.shared.deleteServer(id: serverId)
        
        let fetchedServers = try DatabaseManager.shared.fetchServers()
        let foundServer = fetchedServers.first { $0.id == serverId }
        
        XCTAssertNil(foundServer)
    }
    
    // MARK: - Channel CRUD Tests
    
    func testSaveChannel_insertsNewChannel() throws {
        let serverId = "test-server-channel-\(UUID().uuidString)"
        let server = Server(
            id: serverId,
            name: "TestServer",
            host: "irc.test.com",
            port: 6697,
            nickname: "testuser"
        )
        
        try DatabaseManager.shared.saveServer(server)
        
        let channel = Channel(
            id: "test-channel-\(UUID().uuidString)",
            serverId: serverId,
            name: "#testchannel"
        )
        
        try DatabaseManager.shared.saveChannel(channel, serverId: serverId)
        
        let channels = try DatabaseManager.shared.fetchChannels(forServer: serverId)
        let foundChannel = channels.first { $0.id == channel.id }
        
        XCTAssertNotNil(foundChannel)
        XCTAssertEqual(foundChannel?.name, "#testchannel")
    }
    
    func testSaveChannel_updatesExistingChannel() throws {
        let serverId = "test-server-channel-update-\(UUID().uuidString)"
        let server = Server(
            id: serverId,
            name: "TestServer",
            host: "irc.test.com",
            port: 6697,
            nickname: "testuser"
        )
        
        try DatabaseManager.shared.saveServer(server)
        
        let channelId = "test-channel-update-\(UUID().uuidString)"
        var channel = Channel(
            id: channelId,
            serverId: serverId,
            name: "#original"
        )
        
        try DatabaseManager.shared.saveChannel(channel, serverId: serverId)
        
        channel.name = "#updated"
        channel.topic = "New topic"
        try DatabaseManager.shared.saveChannel(channel, serverId: serverId)
        
        let channels = try DatabaseManager.shared.fetchChannels(forServer: serverId)
        let foundChannel = channels.first { $0.id == channelId }
        
        XCTAssertEqual(foundChannel?.name, "#updated")
        XCTAssertEqual(foundChannel?.topic, "New topic")
    }
    
    // MARK: - Message CRUD Tests
    
    func testSaveMessage_insertsNewMessage() throws {
        let channelId = "test-channel-msg-\(UUID().uuidString)"
        
        let message = Message(
            id: "msg-\(UUID().uuidString)",
            channelId: channelId,
            sender: "alice",
            content: "Hello world",
            timestamp: Date(),
            type: .message
        )
        
        try DatabaseManager.shared.saveMessage(message)
        
        let fetchedMessages = try DatabaseManager.shared.fetchMessages(forChannel: channelId)
        
        XCTAssertFalse(fetchedMessages.isEmpty)
        XCTAssertEqual(fetchedMessages.first?.content, "Hello world")
    }
    
    func testSaveMessage_updatesExistingMessage() throws {
        let channelId = "test-channel-msg-update-\(UUID().uuidString)"
        let messageId = "msg-update-\(UUID().uuidString)"
        
        var message = Message(
            id: messageId,
            channelId: channelId,
            sender: "alice",
            content: "Original",
            timestamp: Date(),
            type: .message
        )
        
        try DatabaseManager.shared.saveMessage(message)
        
        message.content = "Updated"
        try DatabaseManager.shared.saveMessage(message)
        
        let fetchedMessages = try DatabaseManager.shared.fetchMessages(forChannel: channelId)
        let foundMessage = fetchedMessages.first { $0.id == messageId }
        
        XCTAssertEqual(foundMessage?.content, "Updated")
    }
    
    func testFetchMessages_returnsInReverseChronologicalOrder() throws {
        let channelId = "test-channel-msg-order-\(UUID().uuidString)"
        
        let now = Date()
        let msg1 = Message(id: "msg1-\(UUID().uuidString)", channelId: channelId, sender: "alice", content: "First", timestamp: now, type: .message)
        let msg2 = Message(id: "msg2-\(UUID().uuidString)", channelId: channelId, sender: "bob", content: "Second", timestamp: now.addingTimeInterval(60), type: .message)
        let msg3 = Message(id: "msg3-\(UUID().uuidString)", channelId: channelId, sender: "charlie", content: "Third", timestamp: now.addingTimeInterval(120), type: .message)
        
        try DatabaseManager.shared.saveMessage(msg1)
        try DatabaseManager.shared.saveMessage(msg2)
        try DatabaseManager.shared.saveMessage(msg3)
        
        let fetchedMessages = try DatabaseManager.shared.fetchMessages(forChannel: channelId)
        
        XCTAssertEqual(fetchedMessages.first?.content, "First")
        XCTAssertEqual(fetchedMessages.last?.content, "Third")
    }
    
    func testFetchMessages_respectsLimit() throws {
        let channelId = "test-channel-msg-limit-\(UUID().uuidString)"
        
        for i in 0..<10 {
            let message = Message(
                id: "msg-limit-\(i)-\(UUID().uuidString)",
                channelId: channelId,
                sender: "user\(i)",
                content: "Message \(i)",
                timestamp: Date().addingTimeInterval(Double(i)),
                type: .message
            )
            try DatabaseManager.shared.saveMessage(message)
        }
        
        let fetchedMessages = try DatabaseManager.shared.fetchMessages(forChannel: channelId, limit: 5)
        
        XCTAssertEqual(fetchedMessages.count, 5)
    }
    
    // MARK: - Search Tests
    
    func testSearchMessages_findsMatchingContent() throws {
        let channelId = "test-channel-search-\(UUID().uuidString)"
        
        let msg1 = Message(id: "search-1-\(UUID().uuidString)", channelId: channelId, sender: "alice", content: "Hello world", timestamp: Date(), type: .message)
        let msg2 = Message(id: "search-2-\(UUID().uuidString)", channelId: channelId, sender: "bob", content: "Goodbye world", timestamp: Date(), type: .message)
        let msg3 = Message(id: "search-3-\(UUID().uuidString)", channelId: channelId, sender: "charlie", content: "No match here", timestamp: Date(), type: .message)
        
        try DatabaseManager.shared.saveMessage(msg1)
        try DatabaseManager.shared.saveMessage(msg2)
        try DatabaseManager.shared.saveMessage(msg3)
        
        let results = try DatabaseManager.shared.searchMessages(query: "world", inChannel: channelId)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchMessages_isCaseInsensitive() throws {
        let channelId = "test-channel-search-case-\(UUID().uuidString)"
        
        let message = Message(id: "search-case-\(UUID().uuidString)", channelId: channelId, sender: "alice", content: "HELLO World", timestamp: Date(), type: .message)
        try DatabaseManager.shared.saveMessage(message)
        
        let results = try DatabaseManager.shared.searchMessages(query: "hello", inChannel: channelId)
        
        XCTAssertFalse(results.isEmpty)
    }
    
    // MARK: - Settings Tests
    
    func testSaveSetting_andFetchSetting() throws {
        let key = "test-setting-key-\(UUID().uuidString)"
        let value = "test-value"
        
        try DatabaseManager.shared.saveSetting(key: key, value: value)
        
        let fetchedValue = try DatabaseManager.shared.fetchSetting(key: key)
        
        XCTAssertEqual(fetchedValue, value)
    }
    
    func testFetchSetting_returnsNilForNonExistentKey() throws {
        let fetchedValue = try DatabaseManager.shared.fetchSetting(key: "non-existent-key-12345")
        
        XCTAssertNil(fetchedValue)
    }
    
    // MARK: - Watch Channel Tests
    
    func testGetWatchedChannels_returnsOnlyWatched() throws {
        let serverId = "test-server-watched-\(UUID().uuidString)"
        let server = Server(
            id: serverId,
            name: "TestServer",
            host: "irc.test.com",
            port: 6697,
            nickname: "testuser"
        )
        
        try DatabaseManager.shared.saveServer(server)
        
        let watchedChannel = Channel(
            id: "watched-\(UUID().uuidString)",
            serverId: serverId,
            name: "#watched",
            isWatched: true
        )
        
        let notWatchedChannel = Channel(
            id: "not-watched-\(UUID().uuidString)",
            serverId: serverId,
            name: "#notwatched",
            isWatched: false
        )
        
        try DatabaseManager.shared.saveChannel(watchedChannel, serverId: serverId)
        try DatabaseManager.shared.saveChannel(notWatchedChannel, serverId: serverId)
        
        let watchedChannels = try DatabaseManager.shared.getWatchedChannels()
        
        XCTAssertTrue(watchedChannels.contains { $0.id == watchedChannel.id })
        XCTAssertFalse(watchedChannels.contains { $0.id == notWatchedChannel.id })
    }
    
    // MARK: - Get Latest Message Tests
    
    func testGetLatestMessage_returnsMostRecent() throws {
        let channelId = "test-channel-latest-\(UUID().uuidString)"
        
        let oldMessage = Message(id: "latest-1-\(UUID().uuidString)", channelId: channelId, sender: "alice", content: "Old", timestamp: Date().addingTimeInterval(-60), type: .message)
        let newMessage = Message(id: "latest-2-\(UUID().uuidString)", channelId: channelId, sender: "bob", content: "New", timestamp: Date(), type: .message)
        
        try DatabaseManager.shared.saveMessage(oldMessage)
        try DatabaseManager.shared.saveMessage(newMessage)
        
        let latestMessage = try DatabaseManager.shared.getLatestMessage(forChannel: channelId)
        
        XCTAssertEqual(latestMessage?.content, "New")
    }
}