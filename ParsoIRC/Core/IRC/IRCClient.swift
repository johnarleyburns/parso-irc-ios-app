import Foundation
#if canImport(Network)
import Network
#endif

actor IRCClient {
    private var connection: NWConnection?
    private var listener: NWListener?
    private var isConnected = false
    private var currentNick: String = ""
    private var serverInfo: (host: String, port: UInt16)?
    
    private let debugLog = DebugLogManager.shared
    
    var chathistoryEnabled: Bool = false
    var chathistoryMaxLimit: Int = 100
    var serverTimeEnabled: Bool = false
    
    private let queue = DispatchQueue(label: "irc.client", qos: .userInitiated)
    
    // Event handlers (IRCKit-compatible API)
    nonisolated(unsafe) var onWelcome: ((String) -> Void)?
    nonisolated(unsafe) var onDisconnect: (() -> Void)?
    nonisolated(unsafe) var onError: ((Error) -> Void)?
    nonisolated(unsafe) var onMessage: ((IRCMessage) -> Void)?
    nonisolated(unsafe) var onJoin: ((String, String) -> Void)?
    nonisolated(unsafe) var onPart: ((String, String, String?) -> Void)?
    nonisolated(unsafe) var onQuit: ((String, String?) -> Void)?
    nonisolated(unsafe) var onNickChange: ((String, String) -> Void)?
    nonisolated(unsafe) var onTopicChange: ((String, String, String) -> Void)?
    nonisolated(unsafe) var onNamesList: ((String, [String]) -> Void)?
    nonisolated(unsafe) var onHistoryMessage: ((IRCMessage) -> Void)?
    
    private var readStream: InputStream?
    private var writeStream: OutputStream?
    private var useTLS = false
    
    private var pendingCapabilities: Set<String> = []
    private var acknowledgedCapabilities: Set<String> = []
    private var isCapNegotiationComplete = false
    private var saslRequested = false
    // MARK: - Connection

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
        guard !isConnected else { return }

        debugLog.log("connect() called for \(host):\(port), tls: \(tls)", type: .info)
        serverInfo = (host, UInt16(port))
        useTLS = tls

        let hostNW = NWEndpoint.Host(host)
        let portNW = NWEndpoint.Port(integerLiteral: UInt16(port))

        debugLog.log("Creating NWConnection to \(host):\(port)...", type: .info)
        let parameters: NWParameters
        if tls {
            parameters = NWParameters(tls: .init())
        } else {
            parameters = .tcp
        }

        let connection = NWConnection(host: hostNW, port: portNW, using: parameters)
        self.connection = connection
        debugLog.log("Setting stateUpdateHandler...", type: .info)

        connection.stateUpdateHandler = { [weak self] state in
            debugLog.log("State changed: \(String(describing: state))", type: .info)
            Task {
                await self?.handleStateChange(state)
            }
        }

        debugLog.log("Starting connection...", type: .info)
        connection.start(queue: queue)
        debugLog.log("connection.start() called", type: .info)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    debugLog.log("Waiting for connection (timeout 30s)...", type: .info)
                    try await self.waitForConnection(timeout: 30)
                    debugLog.log("Connection ready!", type: .info)
                    self.isConnected = true
                    self.currentNick = nickname

                    try await self.send_raw("CAP LS 302")

                    continuation.resume()
                } catch {
                    debugLog.log("Connection failed: \(error.localizedDescription)", type: .error)
                    continuation.resume(throwing: error)
                }
            }
        }

        startReceiving()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    try await self.waitForCapNegotiation(timeout: 10)
                    
                    var capsToRequest = ["batch", "server-time", "message-tags", "draft/chathistory"]
                    if useSASL {
                        capsToRequest.append("sasl")
                    }
                    try await self.send_raw("CAP REQ :\(capsToRequest.joined(separator: " "))")
                    
                    try await Task.sleep(nanoseconds: 500_000_000)
                    
                    self.isCapNegotiationComplete = true
                    
                    if useSASL && self.acknowledgedCapabilities.contains("sasl") {
                        try await self.send_raw("CAP REQ :sasl")
                        try await self.send_raw("AUTHENTICATE +")
                        self.saslRequested = true
                    }
                    
                    try await self.send_raw("NICK :\(nickname)")
                    try await self.send_raw("USER \(username) 8 * :\(realname)")
                    
                    if let password = serverPassword, !password.isEmpty {
                        try await self.send_raw("PASS \(password)")
                    }
                    
                    try await self.send_raw("CAP END")
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func waitForCapNegotiation(timeout: Int) async throws {
        let startTime = Date()
        while !isCapNegotiationComplete {
            try await Task.sleep(nanoseconds: 100_000_000)
            if Date().timeIntervalSince(startTime) > Double(timeout) {
                isCapNegotiationComplete = true
                return
            }
        }
    }

    func disconnect() {
        guard isConnected else { return }

        Task {
            try? await send_raw("QUIT :Parso IRC")
            connection?.cancel()
            connection = nil
            isConnected = false
        }
    }

    private func waitForConnection(timeout: Int) async throws {
        let startTime = Date()
        while !isConnected {
            let elapsed = Date().timeIntervalSince(startTime)
            if Int(elapsed) % 5 == 0 && elapsed > 0.1 {
                debugLog.log("Still waiting... \(Int(elapsed))s elapsed", type: .info)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            if Date().timeIntervalSince(startTime) > Double(timeout) {
                debugLog.log("Connection timeout after \(timeout)s", type: .error)
                throw IRCError.timeout
            }
        }
    }

    private func handleStateChange(_ state: NWConnection.State) {
        debugLog.log("handleStateChange: \(String(describing: state))", type: .info)
        switch state {
        case .ready:
            debugLog.log("Connection ready!", type: .info)
            isConnected = true
        case .failed(let error):
            debugLog.log("Connection failed: \(error.localizedDescription)", type: .error)
            Task { @MainActor in
                self.onError?(error)
            }
            Task {
                disconnect()
            }
        case .cancelled:
            isConnected = false
            Task { @MainActor in
                self.onDisconnect?()
            }
        default:
            break
        }
    }

    // MARK: - Sending

    func send_raw(_ message: String) async throws {
        guard let connection = connection, isConnected else {
            debugLog.log("send_raw failed: not connected", type: .error)
            throw IRCError.notConnected
        }
        
        var data = message.data(using: .utf8) ?? Data()
        data.append(contentsOf: [0x0D, 0x0A])
        
        debugLog.log("SEND: \(message)", type: .sent)
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error = error {
                        debugLog.log("send_raw error: \(error.localizedDescription)", type: .error)
                        Task { @MainActor in
                            self.onError?(error)
                        }
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
            debugLog.log("send_raw success", type: .info)
        } catch {
            debugLog.log("send_raw threw: \(error.localizedDescription)", type: .error)
            throw error
        }
    }

    func send(command: String, parameters: [String]) async throws {
        var fullCommand = command

        let leadingParams = parameters.dropLast()
        if !leadingParams.isEmpty {
            fullCommand += " " + leadingParams.joined(separator: " ")
        }

        if let last = parameters.last, !last.isEmpty {
            fullCommand += " :\(last)"
        }

        try await send_raw(fullCommand)
    }

    func sendMessage(_ text: String, to channel: String) async throws {
        try await send(command: "PRIVMSG", parameters: [channel, text])
    }

    func join(channel: String) async throws {
        try await send(command: "JOIN", parameters: [channel])
    }

    func join(channel: String, key: String) async throws {
        try await send(command: "JOIN", parameters: [channel, key])
    }

    func leave(channel: String, message: String? = nil) async throws {
        if let message = message {
            try await send(command: "PART", parameters: [channel, message])
        } else {
            try await send(command: "PART", parameters: [channel])
        }
    }

    func quit(message: String = "Parso IRC") async throws {
        try await send(command: "QUIT", parameters: [message])
    }
    
    func nick(_ newNickname: String) async throws {
        try await send(command: "NICK", parameters: [newNickname])
    }
    
    func list() async throws {
        try await send(command: "LIST", parameters: [])
    }
    
    func names(_ channel: String) async throws {
        try await send(command: "NAMES", parameters: [channel])
    }
    
    func whois(_ username: String) async throws {
        try await send(command: "WHOIS", parameters: [username])
    }
    
    func away(_ message: String?) async throws {
        if let message = message {
            try await send(command: "AWAY", parameters: [message])
        } else {
            try await send(command: "AWAY", parameters: [])
        }
    }
    
    func me(_ message: String, to channel: String) async throws {
        let action = "\u{0001}ACTION \(message)\u{0001}"
        try await send(command: "PRIVMSG", parameters: [channel, action])
    }
    
    func isConnectedToServer() -> Bool {
        return isConnected
    }
    
    func getChathistoryLimit() -> Int {
        return chathistoryMaxLimit
    }
    
    func hasChathistorySupport() -> Bool {
        return chathistoryEnabled
    }

    func authenticateSASL(username: String, password: String) async throws {
        try await send_raw("CAP LS 302")
        try await send_raw("CAP REQ :sasl")
        try await send_raw("AUTHENTICATE +")

        let saslData = "\0\(username)\0\(password)"
        let encoded = saslData.data(using: .utf8)?.base64EncodedString() ?? ""
        try await send_raw("AUTHENTICATE \(encoded)")
        try await send_raw("CAP END")
    }

    // MARK: - Receiving

    private func startReceiving() {
        debugLog.log("startReceiving() called", type: .info)
        guard let connection = connection else {
            debugLog.log("startReceiving: connection is nil", type: .error)
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task {
                if let error = error {
                    debugLog.log("receive error: \(error.localizedDescription)", type: .error)
                }
                
                if let data = data, !data.isEmpty {
                    await self?.handleReceivedData(data)
                }

                if isComplete {
                    debugLog.log("Connection completed (isComplete=true)", type: .error)
                    await self?.disconnect()
                } else if error != nil {
                    debugLog.log("receive loop ending due to error", type: .error)
                    await self?.disconnect()
                } else {
                    await self?.startReceiving()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) async {
        guard let string = String(data: data, encoding: .utf8) else { return }

        debugLog.log("RECV raw: \(string.prefix(200))", type: .received)

        let lines = string.components(separatedBy: "\r\n")
        for line in lines where !line.isEmpty {
            let message = IRCMessage(rawLine: line)
            await handleMessage(message)
        }
    }

    private func handleMessage(_ message: IRCMessage) async {
        let command = message.command
        
        debugLog.log("RECV cmd: \(command) \(message.parameters.joined(separator: " "))", type: .received)

        switch command {
        case "PING":
            let param = message.parameters.first.map { ":\($0)" } ?? ":"
            try? await send_raw("PONG \(param)")

        case "CAP":
            await handleCapMessage(message)
            
        case "005", "RPL_ISUPPORT":
            handleISupportMessage(message)
            
        case "903", "RPL_SASLSUCCESS":
            if saslRequested {
                try? await send_raw("CAP END")
                saslRequested = false
            }
            
        case "904", "RPL_SASLFAILURE":
            if saslRequested {
                try? await send_raw("CAP END")
                saslRequested = false
            }

        case "001", "RPL_WELCOME":
            let nick = message.parameters.first ?? ""
            await MainActor.run {
                self.onWelcome?(nick)
            }

        case "JOIN":
            let channel = message.parameters.first ?? ""
            let nick = message.source?.nick ?? ""
            await MainActor.run {
                self.onJoin?(channel, nick)
            }

        case "PART":
            let channel = message.parameters.first ?? ""
            let nick = message.source?.nick ?? ""
            let partMessage: String? = message.parameters.count > 1 ? message.parameters[1] : nil
            await MainActor.run {
                self.onPart?(channel, nick, partMessage)
            }

        case "QUIT":
            let nick = message.source?.nick ?? ""
            let quitMessage = message.parameters.first
            await MainActor.run {
                self.onQuit?(nick, quitMessage)
            }

        case "NICK":
            let oldNick = message.source?.nick ?? ""
            let newNick = message.parameters.first ?? oldNick
            if !message.parameters.isEmpty && message.parameters[0].hasPrefix(":") == false {
                await MainActor.run {
                    self.onNickChange?(oldNick, newNick)
                }
            } else if currentNick == oldNick {
                currentNick = newNick
            }

        case "TOPIC":
            let channel = message.parameters.first ?? ""
            let topic = message.parameters.count > 1 ? message.parameters[1] : ""
            let nick = message.source?.nick ?? ""
            await MainActor.run {
                self.onTopicChange?(channel, topic, nick)
            }

        case "353":  // RPL_NAMREPLY
            if let channel = message.parameters.dropFirst().last,
               let nicksParam = message.parameters.dropFirst(2).first {
                let nicks = nicksParam.split(separator: " ").map(String.init)
                await MainActor.run {
                    self.onNamesList?(channel, nicks)
                }
            }

        case "PRIVMSG", "NOTICE":
            if chathistoryEnabled && isHistoryBatch(message) {
                await handleHistoryMessage(message)
            } else {
                await MainActor.run {
                    self.onMessage?(message)
                }
            }

        case "ERROR":
            let errorMsg = message.parameters.joined(separator: " ")
            let ircError = IRCError.connectionFailed(errorMsg)
            await MainActor.run {
                self.onError?(ircError)
            }

        default:
            break
        }
    }
    
    private func handleCapMessage(_ message: IRCMessage) async {
        guard message.parameters.count >= 3 else { return }
        
        let subcommand = message.parameters[1]
        
        switch subcommand {
        case "LS":
            if let caps = message.parameters.last {
                let capabilities = caps.split(separator: " ").map(String.init)
                for cap in capabilities {
                    if cap.hasPrefix("batch") {
                        pendingCapabilities.insert("batch")
                    } else if cap.hasPrefix("server-time") {
                        pendingCapabilities.insert("server-time")
                    } else if cap.hasPrefix("message-tags") {
                        pendingCapabilities.insert("message-tags")
                    } else if cap.hasPrefix("draft/chathistory") || cap.hasPrefix("chathistory") {
                        pendingCapabilities.insert("chathistory")
                    } else if cap.hasPrefix("sasl") {
                        pendingCapabilities.insert("sasl")
                    }
                }
            }
            
        case "ACK":
            if let caps = message.parameters.last {
                let acknowledged = caps.split(separator: " ").map(String.init)
                for cap in acknowledged {
                    acknowledgedCapabilities.insert(cap)
                    
                    if cap == "batch" || cap.hasPrefix("batch") {
                        chathistoryEnabled = true
                    } else if cap == "server-time" || cap.hasPrefix("server-time") {
                        serverTimeEnabled = true
                    } else if cap.hasPrefix("chathistory") {
                        chathistoryEnabled = true
                    }
                }
            }
            
        case "NAK":
            break
            
        case "END":
            isCapNegotiationComplete = true
            
        default:
            break
        }
    }
    
    private func handleISupportMessage(_ message: IRCMessage) {
        for param in message.parameters {
            if param.hasPrefix("CHATHISTORY=") {
                let limitStr = param.replacingOccurrences(of: "CHATHISTORY=", with: "")
                if let limit = Int(limitStr) {
                    chathistoryMaxLimit = limit
                }
            }
        }
    }
    
    private func isHistoryBatch(_ message: IRCMessage) -> Bool {
        return message.tags?["batch"]?.contains("chathistory") ?? false
    }
    
    private func handleHistoryMessage(_ message: IRCMessage) async {
        await MainActor.run {
            self.onHistoryMessage?(message)
        }
    }
    
    func requestHistory(target: String, limit: Int) async throws {
        let effectiveLimit = min(limit, chathistoryMaxLimit)
        try await send(command: "CHATHISTORY", parameters: ["LATEST", target, "*", String(effectiveLimit)])
    }
}
