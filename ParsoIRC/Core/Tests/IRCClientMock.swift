import Foundation

#if os(Linux)
#if canImport(Network)
import Network
#endif

actor IRCClientMock {
    private var connected = false
    private var messages: [IRCMessage] = []
    private var nickname: String = ""
    private var channels: [String] = []
    private var shouldFail = false
    private var failError: Error?
    
    nonisolated(unsafe) var onWelcome: ((String) -> Void)?
    nonisolated(unsafe) var onMessage: ((IRCMessage) -> Void)?
    nonisolated(unsafe) var onJoin: ((String, String) -> Void)?
    nonisolated(unsafe) var onDisconnect: (() -> Void)?
    nonisolated(unsafe) var onError: ((Error) -> Void)?
    
    func setFailOnConnect(_ error: Error) {
        self.shouldFail = true
        self.failError = error
    }
    
    func clearFail() {
        self.shouldFail = false
        self.failError = nil
    }
    
    func connect(
        host: String,
        port: Int,
        tls: Bool,
        nickname: String,
        username: String,
        realname: String
    ) async throws {
        if shouldFail, let error = failError {
            throw error
        }
        
        self.connected = true
        self.nickname = nickname
        
        let welcome = IRCMessage(rawLine: "001 \(nickname)")
        self.onWelcome?(nickname)
        messages.append(welcome)
    }
    
    func disconnect() {
        connected = false
        channels.removeAll()
        self.onDisconnect?()
    }
    
    func sendMessage(_ text: String, to channel: String) async throws {
        guard connected else {
            throw IRCError.notConnected
        }
        
        let message = IRCMessage(rawLine: ":\(nickname) PRIVMSG \(channel) :\(text)")
        messages.append(message)
        
        let echo = IRCMessage(rawLine: ":\(nickname)!~\(nickname)@localhost PRIVMSG \(channel) :\(text)")
        self.onMessage?(echo)
    }
    
    func join(channel: String) async throws {
        guard connected else {
            throw IRCError.notConnected
        }
        
        channels.append(channel)
        
        let joinMsg = IRCMessage(rawLine: ":\(nickname)!~\(nickname)@localhost JOIN \(channel)")
        messages.append(joinMsg)
        
        self.onJoin?(channel, nickname)
    }
    
    func leave(channel: String, message: String? = nil) async throws {
        guard connected else {
            throw IRCError.notConnected
        }
        
        channels.removeAll { $0 == channel }
    }
    
    func getMessages() -> [IRCMessage] {
        return messages
    }
    
    func getJoinedChannels() -> [String] {
        return channels
    }
    
    func isConnected() -> Bool {
        return connected
    }
    
    func getNickname() -> String {
        return nickname
    }
    
    func reset() {
        connected = false
        messages.removeAll()
        nickname = ""
        channels.removeAll()
        shouldFail = false
        failError = nil
    }
}

#endif // os(Linux)