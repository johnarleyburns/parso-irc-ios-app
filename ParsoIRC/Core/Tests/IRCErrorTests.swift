#if !os(Linux)
import XCTest

final class IRCErrorTests: XCTestCase {
    
    func testNotConnectedError() {
        let error = IRCError.notConnected
        
        XCTAssertEqual(error.localizedDescription, "Not connected to server")
    }
    
    func testMaxReconnectAttemptsReached() {
        let error = IRCError.maxReconnectAttemptsReached
        
        XCTAssertEqual(error.localizedDescription, "Maximum reconnection attempts reached")
    }
    
    func testAuthenticationFailed() {
        let error = IRCError.authenticationFailed
        
        XCTAssertEqual(error.localizedDescription, "Authentication failed")
    }
    
    func testConnectionFailed() {
        let error = IRCError.connectionFailed("DNS failure")
        
        XCTAssertEqual(error.localizedDescription, "Connection failed: DNS failure")
    }
    
    func testInvalidResponse() {
        let error = IRCError.invalidResponse("invalid format")
        
        XCTAssertEqual(error.localizedDescription, "Invalid response: invalid format")
    }
    
    func testSendFailed() {
        let error = IRCError.sendFailed("connection closed")
        
        XCTAssertEqual(error.localizedDescription, "Failed to send: connection closed")
    }
    
    func testTimeout() {
        let error = IRCError.timeout
        
        XCTAssertEqual(error.localizedDescription, "Connection timeout")
    }
    
    func testEncodingFailed() {
        let error = IRCError.encodingFailed
        
        XCTAssertEqual(error.localizedDescription, "Failed to encode message")
    }
    
    func testErrorConformsToLocalizedError() {
        let error: Error = IRCError.notConnected
        
        XCTAssertNotNil(error.localizedDescription)
    }
}

#endif // !os(Linux)