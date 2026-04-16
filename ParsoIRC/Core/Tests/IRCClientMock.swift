import Foundation

#if os(Linux)
#if canImport(Network)
import Network
#endif

actor IRCClientMock {
    private var connected = false
    private var nickname: String = ""
    private var username: String = ""
    private var realname: String = ""
    private var channels: [String] = []
    private var awayMessage: String?
    
    private var sentMessages: [String] = []
    private var receivedMessages: [IRCMessage] = []
    
    private var shouldFail = false
    private var failError: Error?
    
    nonisolated(unsafe) var onWelcome: ((String) -> Void)?
    nonisolated(unsafe) var onMessage: ((IRCMessage) -> Void)?
    nonisolated(unsafe) var onJoin: ((String, String) -> Void)?
    nonisolated(unsafe) var onPart: ((String, String, String?) -> Void)?
    nonisolated(unsafe) var onNickChange: ((String, String) -> Void)?
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
    
    func getSentMessages() -> [String] {
        return sentMessages
    }
    
    func getReceivedMessages() -> [IRCMessage] {
        return receivedMessages
    }
    
    func connect(
        host: String,
        port: Int,
        tls: Bool,
        nickname: String,
        username: String,
        realname: String,
        serverPassword: String? = nil,
        useSASL: Bool = false,
        saslPassword: String? = nil
    ) async throws {
        if shouldFail, let error = failError {
            throw error
        }
        
        self.connected = true
        self.nickname = nickname
        self.username = username
        self.realname = realname
        
        let welcome = IRCMessage(rawLine: ":server 001 \(nickname) :Welcome to the Internet Relay Network")
        onWelcome?(nickname)
        receivedMessages.append(welcome)
    }
    
    func disconnect() {
        connected = false
        channels.removeAll()
        awayMessage = nil
        onDisconnect?()
    }
    
    func send_raw(_ message: String) async throws {
        guard connected else {
            throw IRCError.notConnected
        }
        
        sentMessages.append(message)
        
        let parsed = IRCMessage(rawLine: message)
        await handleCommand(parsed)
    }
    
    private func handleCommand(_ message: IRCMessage) async {
        let command = message.command
        
        switch command {
        case "NICK":
            if let newNick = message.parameters.first {
                let oldNick = nickname
                nickname = newNick
                let nickMsg = IRCMessage(rawLine: ":\(oldNick) NICK :\(newNick)")
                receivedMessages.append(nickMsg)
                onNickChange?(oldNick, newNick)
            }
            
        case "USER":
            let userMsg = IRCMessage(rawLine: ":server 001 \(nickname) :Welcome")
            receivedMessages.append(userMsg)
            onWelcome?(nickname)
            
        case "JOIN":
            if let channel = message.parameters.first {
                channels.append(channel)
                let joinMsg = IRCMessage(rawLine: ":\(nickname)!~\(username)@localhost JOIN \(channel)")
                receivedMessages.append(joinMsg)
                onJoin?(channel, nickname)
            }
            
        case "PART":
            if let channel = message.parameters.first {
                channels.removeAll { $0 == channel }
                let partMsg = IRCMessage(rawLine: ":\(nickname)!~\(username)@localhost PART \(channel)")
                receivedMessages.append(partMsg)
                onPart?(channel, nickname, nil)
            }
            
        case "PRIVMSG":
            if let target = message.parameters.first {
                let rest = message.parameters.dropFirst().joined(separator: " ")
                let privMsg = IRCMessage(rawLine: ":\(nickname)!~\(username)@localhost PRIVMSG \(target) :\(rest)")
                receivedMessages.append(privMsg)
                onMessage?(privMsg)
            }
            
        case "LIST":
            let listStart = IRCMessage(rawLine: ":server 321 Channel :Users  Name")
            receivedMessages.append(listStart)
            let listEnd = IRCMessage(rawLine: ":server 323 :End of LIST")
            receivedMessages.append(listEnd)
            
        case "NAMES":
            if let channel = message.parameters.first {
                let namesReply = IRCMessage(rawLine: ":server 353 \(nickname) = \(channel) :@nick1 +nick2 nick3")
                receivedMessages.append(namesReply)
                let endNames = IRCMessage(rawLine: ":server 366 \(nickname) \(channel) :End of NAMES list")
                receivedMessages.append(endNames)
            }
            
        case "WHOIS":
            if let target = message.parameters.first {
                let whoisUser = IRCMessage(rawLine: ":server 311 \(nickname) \(target) ~user localhost * :Real Name")
                receivedMessages.append(whoisUser)
                let whoisServer = IRCMessage(rawLine: ":server 312 \(nickname) \(target) server.local :Server Info")
                receivedMessages.append(whoisServer)
                let whoisEnd = IRCMessage(rawLine: ":server 318 \(nickname) \(target) :End of WHOIS")
                receivedMessages.append(whoisEnd)
            }
            
        case "AWAY":
            if let message = message.parameters.first {
                awayMessage = message
                let awayReply = IRCMessage(rawLine: ":server 306 \(nickname) :You are now away")
                receivedMessages.append(awayReply)
            } else {
                awayMessage = nil
                let backReply = IRCMessage(rawLine: ":server 305 \(nickname) :You are no longer away")
                receivedMessages.append(backReply)
            }
            
        case "QUIT":
            disconnect()
            
        default:
            break
        }
    }
    
    func sendMessage(_ text: String, to channel: String) async throws {
        try await send_raw("PRIVMSG \(channel) :\(text)")
    }
    
    func join(channel: String) async throws {
        try await send_raw("JOIN \(channel)")
    }
    
    func leave(channel: String, message: String? = nil) async throws {
        if let message = message {
            try await send_raw("PART \(channel) :\(message)")
        } else {
            try await send_raw("PART \(channel)")
        }
    }
    
    func nick(_ newNickname: String) async throws {
        try await send_raw("NICK :\(newNickname)")
    }
    
    func list() async throws {
        try await send_raw("LIST")
    }
    
    func names(_ channel: String) async throws {
        try await send_raw("NAMES \(channel)")
    }
    
    func whois(_ username: String) async throws {
        try await send_raw("WHOIS \(username)")
    }
    
    func away(_ message: String?) async throws {
        if let message = message {
            try await send_raw("AWAY :\(message)")
        } else {
            try await send_raw("AWAY")
        }
    }
    
    func me(_ message: String, to channel: String) async throws {
        try await send_raw("PRIVMSG \(channel) :\u0001ACTION \(message)\u0001")
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
    
    func getAwayMessage() -> String? {
        return awayMessage
    }
    
    func reset() {
        connected = false
        nickname = ""
        username = ""
        realname = ""
        channels.removeAll()
        awayMessage = nil
        sentMessages.removeAll()
        receivedMessages.removeAll()
        shouldFail = false
        failError = nil
    }
}

#endif