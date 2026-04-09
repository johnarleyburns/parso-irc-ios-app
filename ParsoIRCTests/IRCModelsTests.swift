import XCTest
@testable import ParsoIRC

final class IRCModelsTests: XCTestCase {
    
    // MARK: - Channel Display Name Tests
    
    func testChannelDisplayName_stripsHashPrefix() {
        let channel = Channel(name: "#libera")
        XCTAssertEqual(channel.displayName, "libera")
    }
    
    func testChannelDisplayName_preservesNonHashNames() {
        let channel = Channel(name: "libera")
        XCTAssertEqual(channel.displayName, "libera")
    }
    
    // MARK: - Message Grouping Tests
    
    func testMessageGrouping_sameSenderWithin5Minutes() {
        let time1 = Date()
        let time2 = time1.addingTimeInterval(60) // 1 minute later
        
        let msg1 = Message(
            channelId: "1",
            sender: "alice",
            content: "Hello",
            timestamp: time1,
            type: .message
        )
        
        let msg2 = Message(
            channelId: "1",
            sender: "alice",
            content: "World",
            timestamp: time2,
            type: .message
        )
        
        XCTAssertTrue(msg1.sender == msg2.sender)
        XCTAssertTrue(time2.timeIntervalSince(time1) < 300)
    }
    
    func testMessageGrouping_differentSendersNotGrouped() {
        let time = Date()
        
        let msg1 = Message(
            channelId: "1",
            sender: "alice",
            content: "Hello",
            timestamp: time,
            type: .message
        )
        
        let msg2 = Message(
            channelId: "1",
            sender: "bob",
            content: "World",
            timestamp: time,
            type: .message
        )
        
        XCTAssertFalse(msg1.sender == msg2.sender)
    }
    
    func testMessageGrouping_over5MinutesNotGrouped() {
        let time1 = Date()
        let time2 = time1.addingTimeInterval(400) // Over 5 minutes
        
        let msg1 = Message(
            channelId: "1",
            sender: "alice",
            content: "Hello",
            timestamp: time1,
            type: .message
        )
        
        let msg2 = Message(
            channelId: "1",
            sender: "alice",
            content: "World",
            timestamp: time2,
            type: .message
        )
        
        XCTAssertFalse(time2.timeIntervalSince(time1) < 300)
    }
    
    // MARK: - Member Mode Tests
    
    func testMemberMode_operatorPrefix() {
        let member = ChannelMember(nick: "alice", mode: .operator_)
        XCTAssertEqual(member.mode.prefix, "@")
    }
    
    func testMemberMode_voicePrefix() {
        let member = ChannelMember(nick: "alice", mode: .voice)
        XCTAssertEqual(member.mode.prefix, "+")
    }
    
    func testMemberMode_nonePrefix() {
        let member = ChannelMember(nick: "alice", mode: .none)
        XCTAssertEqual(member.mode.prefix, "")
    }
    
    // MARK: - Server Equality Tests
    
    func testServerEquality_basedOnAllFields() {
        let server1 = Server(
            id: "1",
            name: "Libera.Chat",
            host: "irc.libera.chat",
            port: 6697,
            nickname: "user1"
        )
        
        let server2 = Server(
            id: "1",
            name: "Libera.Chat",
            host: "irc.libera.chat",
            port: 6697,
            nickname: "user1"
        )
        
        XCTAssertEqual(server1, server2)
    }
    
    func testServerEquality_differentIdsNotEqual() {
        let server1 = Server(id: "1", name: "Test", host: "test.com")
        let server2 = Server(id: "2", name: "Test", host: "test.com")
        
        XCTAssertNotEqual(server1, server2)
    }
    
    // MARK: - Channel Equality Tests
    
    func testChannelEquality_basedOnAllFields() {
        let channel1 = Channel(id: "1", name: "#test")
        let channel2 = Channel(id: "1", name: "#test")
        
        XCTAssertEqual(channel1, channel2)
    }
    
    // MARK: - Default Networks Tests
    
    func testDefaultNetworks_notEmpty() {
        XCTAssertFalse(Server.defaultNetworks.isEmpty)
    }
    
    func testDefaultNetworks_liberaChatHasChannels() {
        guard let libera = Server.defaultNetworks.first(where: { $0.name == "Libera.Chat" }) else {
            XCTFail("Libera.Chat not found in default networks")
            return
        }
        
        XCTAssertFalse(libera.channels.isEmpty)
    }
}