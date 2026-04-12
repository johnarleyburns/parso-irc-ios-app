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
        XCTAssertEqual(message.parameters.last ?? "", "")
    }
}