import Foundation

final class MockIRCServer {
    private let port: UInt16
    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "mock.irc.server")
    
    private var connectedClients: [Int32] = []
    private var clientNicks: [Int32: String] = [:]
    private var clientUsers: [Int32: String] = [:]
    private var clientRealnames: [Int32: String] = [:]
    private var joinedChannels: [Int32: Set<String>] = [:]
    
    private var receivedCommands: [String] = []
    
    init(port: UInt16 = 6667) {
        self.port = port
    }
    
    func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: "MockIRCServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr -> Int32 in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else {
            close(serverSocket)
            throw NSError(domain: "MockIRCServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"])
        }
        
        guard listen(serverSocket, 5) >= 0 else {
            close(serverSocket)
            throw NSError(domain: "MockIRCServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }
        
        isRunning = true
        queue.async { [weak self] in
            self?.acceptLoop()
        }
        
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    func stop() {
        isRunning = false
        for client in connectedClients {
            close(client)
        }
        connectedClients.removeAll()
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
    
    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr -> Int32 in
                    accept(serverSocket, sockPtr, &clientAddrLen)
                }
            }
            
            if client >= 0 {
                connectedClients.append(client)
                joinedChannels[client] = []
                
                queue.async { [weak self] in
                    self?.handleClient(client)
                }
            }
        }
    }
    
    private func handleClient(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        while isRunning {
            let bytesRead = recv(client, &buffer, buffer.count, 0)
            
            if bytesRead <= 0 {
                break
            }
            
            let data = Data(buffer[0..<bytesRead])
            if let command = String(data: data, encoding: .utf8) {
                let lines = command.components(separatedBy: "\r\n")
                for line in lines where !line.isEmpty {
                    receivedCommands.append(line)
                    processCommand(line, from: client)
                }
            }
        }
        
        close(client)
        connectedClients.removeAll { $0 == client }
        clientNicks.removeValue(forKey: client)
    }
    
    private func processCommand(_ command: String, from client: Int32) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first else { return }
        
        let params = parts.count > 1 ? parts[1] : ""
        
        switch cmd {
        case "NICK":
            let nick = params.hasPrefix(":") ? String(params.dropFirst()) : params
            clientNicks[client] = nick
            sendReply(to: client, message: ":\(serverName()) 001 \(nick) :Welcome to Mock IRC")
            
        case "USER":
            let userParts = params.split(separator: " ")
            if userParts.count >= 4 {
                clientUsers[client] = String(userParts[0])
                clientRealnames[client] = userParts.last ?? ""
            }
            
        case "JOIN":
            let channel = params.hasPrefix(":") ? String(params.dropFirst()) : params
            joinedChannels[client, default: []].insert(channel)
            let nick = clientNicks[client] ?? "*"
            broadcast(":!nick!@host JOIN :\(channel)")
            sendReply(to: client, message: ":\(serverName()) 353 \(nick) = #test :\(nick)")
            sendReply(to: client, message: ":\(serverName()) 366 \(nick) :End of /NAMES list")
            
        case "PART":
            let channel = params.hasPrefix(":") ? String(params.dropFirst()) : params
            joinedChannels[client, default: []].remove(channel)
            let nick = clientNicks[client] ?? "*"
            broadcast(":!nick!@host PART \(channel)")
            
        case "PRIVMSG":
            let content = params.hasPrefix(":") ? String(params.dropFirst()) : params
            let channel = content.split(separator: " ").first.map(String.init) ?? content
            let message = content.contains(" ") ? String(content.dropFirst(content.firstIndex(of: " ")! + 1)) : ""
            let nick = clientNicks[client] ?? "*"
            broadcast(":\(nick)!~\(nick)@localhost PRIVMSG \(channel) :\(message)")
            
        case "PING":
            let server = params.hasPrefix(":") ? String(params.dropFirst()) : "*"
            sendReply(to: client, message: "PONG :\(server)")
            
        case "QUIT":
            let nick = clientNicks[client] ?? "*"
            broadcast(":!nick!@host QUIT :")
            connectedClients.removeAll { $0 == client }
            
        default:
            break
        }
    }
    
    private func sendReply(to client: Int32, message: String) {
        var data = (message + "\r\n").data(using: .utf8) ?? Data()
        _ = data.withUnsafeBytes { ptr in
            send(client, ptr.baseAddress, data.count, 0)
        }
    }
    
    private func broadcast(_ message: String) {
        for client in connectedClients {
            sendReply(to: client, message: message)
        }
    }
    
    private func serverName() -> String {
        return "mock.irc.local"
    }
    
    func getReceivedCommands() -> [String] {
        return receivedCommands
    }
    
    func getClientNick(_ client: Int32) -> String? {
        return clientNicks[client]
    }
    
    func getJoinedChannels(_ client: Int32) -> Set<String>? {
        return joinedChannels[client]
    }
    
    func clearReceivedCommands() {
        receivedCommands.removeAll()
    }
    
    deinit {
        stop()
    }
}

final class MockIRCClient {
    private let host: String
    private let port: UInt16
    private var socket: Int32 = -1
    private var isConnected = false
    private let queue = DispatchQueue(label: "mock.irc.client")
    
    private var nickname: String = ""
    private var username: String = ""
    private var realname: String = ""
    
    private var receivedMessages: [String] = []
    private var welcomeReceived = false
    private var joinedChannels: [String] = []
    
    var onWelcome: ((String) -> Void)?
    var onMessage: ((String, String) -> Void)?
    var onJoin: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
    
    func connect() throws {
        socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw NSError(domain: "MockIRCClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr -> Int32 in
                connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard connectResult >= 0 else {
            close(socket)
            throw NSError(domain: "MockIRCClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to connect"])
        }
        
        isConnected = true
        queue.async { [weak self] in
            self?.receiveLoop()
        }
    }
    
    func disconnect() {
        if isConnected {
            sendCommand("QUIT")
            isConnected = false
        }
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }
    
    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        while isConnected {
            let bytesRead = recv(socket, &buffer, buffer.count, 0)
            
            if bytesRead <= 0 {
                break
            }
            
            let data = Data(buffer[0..<bytesRead])
            if let message = String(data: data, encoding: .utf8) {
                let lines = message.components(separatedBy: "\r\n")
                for line in lines where !line.isEmpty {
                    receivedMessages.append(line)
                    processMessage(line)
                }
            }
        }
    }
    
    private func processMessage(_ message: String) {
        let parts = message.split(separator: " ", maxSplits: 2).map(String.init)
        guard let command = parts.first else { return }
        
        switch command {
        case "001":
            welcomeReceived = true
            onWelcome?(nickname)
            
        case "PRIVMSG":
            if parts.count >= 3 {
                let target = parts[1]
                let content = parts[2].hasPrefix(":") ? String(parts[2].dropFirst()) : parts[2]
                onMessage?(target, content)
            }
            
        case "JOIN":
            if parts.count >= 2 {
                let channel = parts[1].hasPrefix(":") ? String(parts[1].dropFirst()) : parts[1]
                joinedChannels.append(channel)
                onJoin?(channel)
            }
            
        default:
            break
        }
    }
    
    func sendCommand(_ command: String) {
        guard isConnected else { return }
        var data = (command + "\r\n").data(using: .utf8) ?? Data()
        _ = data.withUnsafeBytes { ptr in
            send(socket, ptr.baseAddress, data.count, 0)
        }
    }
    
    func nick(_ nick: String) {
        nickname = nick
        sendCommand("NICK :\(nick)")
    }
    
    func user(_ username: String, realname: String) {
        self.username = username
        self.realname = realname
        sendCommand("USER \(username) 8 * :\(realname)")
    }
    
    func join(_ channel: String) {
        sendCommand("JOIN :\(channel)")
    }
    
    func part(_ channel: String) {
        sendCommand("PART :\(channel)")
    }
    
    func privmsg(_ target: String, message: String) {
        sendCommand("PRIVMSG \(target) :\(message)")
    }
    
    func isWelcome() -> Bool {
        return welcomeReceived
    }
    
    func getJoinedChannels() -> [String] {
        return joinedChannels
    }
    
    func getReceivedMessages() -> [String] {
        return receivedMessages
    }
    
    deinit {
        disconnect()
    }
}