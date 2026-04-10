import XCTest
@testable import ParsoIRC

final class IRCClientManagerTests: XCTestCase {
    
    private var manager: IRCClientManager!
    
    override func setUp() {
        super.setUp()
        manager = IRCClientManager.shared
    }
    
    override func tearDown() {
        manager.disconnectAll()
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState_noConnections() {
        XCTAssertTrue(manager.connections.isEmpty)
    }
    
    func testInitialState_noConnectionStates() {
        XCTAssertTrue(manager.connectionStates.isEmpty)
    }
    
    func testInitialState_noNicknames() {
        XCTAssertTrue(manager.currentNicknames.isEmpty)
    }
    
    // MARK: - Connection State Management Tests
    
    func testConnectionState_setConnecting() {
        let serverId = "test-connection-state-\(UUID().uuidString)"
        
        manager.connectionStates[serverId] = .connecting
        
        XCTAssertEqual(manager.connectionStates[serverId], .connecting)
    }
    
    func testConnectionState_setConnected() {
        let serverId = "test-connection-state-connected-\(UUID().uuidString)"
        
        manager.connectionStates[serverId] = .connected
        
        XCTAssertEqual(manager.connectionStates[serverId], .connected)
    }
    
    func testConnectionState_setDisconnected() {
        let serverId = "test-connection-state-disconnected-\(UUID().uuidString)"
        
        manager.connectionStates[serverId] = .disconnected
        
        XCTAssertEqual(manager.connectionStates[serverId], .disconnected)
    }
    
    func testConnectionState_setReconnecting() {
        let serverId = "test-connection-state-reconnecting-\(UUID().uuidString)"
        
        manager.connectionStates[serverId] = .reconnecting
        
        XCTAssertEqual(manager.connectionStates[serverId], .reconnecting)
    }
    
    func testConnectionState_setFailed() {
        let serverId = "test-connection-state-failed-\(UUID().uuidString)"
        let testError = NSError(domain: "test", code: 123, userInfo: nil)
        
        manager.connectionStates[serverId] = .failed(testError)
        
        if case .failed(let error) = manager.connectionStates[serverId] {
            XCTAssertEqual((error as NSError).code, 123)
        } else {
            XCTFail("Expected .failed state")
        }
    }
    
    // MARK: - Nickname Management Tests
    
    func testNickname_setForServer() {
        let serverId = "test-nickname-\(UUID().uuidString)"
        
        manager.currentNicknames[serverId] = "TestNick"
        
        XCTAssertEqual(manager.currentNicknames[serverId], "TestNick")
    }
    
    func testNickname_updateForServer() {
        let serverId = "test-nickname-update-\(UUID().uuidString)"
        
        manager.currentNicknames[serverId] = "OldNick"
        manager.currentNicknames[serverId] = "NewNick"
        
        XCTAssertEqual(manager.currentNicknames[serverId], "NewNick")
    }
    
    func testNickname_removeForServer() {
        let serverId = "test-nickname-remove-\(UUID().uuidString)"
        
        manager.currentNicknames[serverId] = "TestNick"
        manager.currentNicknames[serverId] = nil
        
        XCTAssertNil(manager.currentNicknames[serverId])
    }
    
    // MARK: - Disconnect Tests
    
    func testDisconnect_updatesConnectionState() async {
        let serverId = "test-disconnect-\(UUID().uuidString)"
        
        manager.connectionStates[serverId] = .connected
        manager.disconnect(from: serverId)
        
        // Give time for async disconnect to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(manager.connectionStates[serverId], .disconnected)
    }
    
    func testDisconnectAll_disconnectsMultipleServers() async {
        let serverId1 = "test-disconnect-all-1-\(UUID().uuidString)"
        let serverId2 = "test-disconnect-all-2-\(UUID().uuidString)"
        
        manager.connectionStates[serverId1] = .connected
        manager.connectionStates[serverId2] = .connected
        
        manager.disconnectAll()
        
        // Give time for async disconnect to complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(manager.connectionStates[serverId1], .disconnected)
        XCTAssertEqual(manager.connectionStates[serverId2], .disconnected)
    }
    
    // MARK: - Error Cases Tests
    
    func testIRCError_notConnectedDescription() {
        let error = IRCError.notConnected
        
        XCTAssertEqual(error.errorDescription, "Not connected to server")
    }
    
    func testIRCError_maxReconnectAttemptsReachedDescription() {
        let error = IRCError.maxReconnectAttemptsReached
        
        XCTAssertEqual(error.errorDescription, "Maximum reconnection attempts reached")
    }
    
    func testIRCError_authenticationFailedDescription() {
        let error = IRCError.authenticationFailed
        
        XCTAssertEqual(error.errorDescription, "Authentication failed")
    }
    
    // MARK: - Connection State Enum Tests
    
    func testConnectionState_equatable() {
        let state1: IRCClientManager.ConnectionState = .disconnected
        let state2: IRCClientManager.ConnectionState = .disconnected
        
        XCTAssertEqual(state1, state2)
    }
    
    func testConnectionState_differentCasesNotEqual() {
        let state1: IRCClientManager.ConnectionState = .disconnected
        let state2: IRCClientManager.ConnectionState = .connecting
        
        XCTAssertNotEqual(state1, state2)
    }
    
    func testConnectionState_failedWithSameError() {
        let error = NSError(domain: "test", code: 123, userInfo: nil)
        let state1: IRCClientManager.ConnectionState = .failed(error)
        let state2: IRCClientManager.ConnectionState = .failed(error)
        
        XCTAssertEqual(state1, state2)
    }
}