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
    nonisolated(unsafe) var onKick: ((String, String, String, String?) -> Void)?   // channel, kicked, by, reason
    nonisolated(unsafe) var onInvite: ((String, String) -> Void)?                  // nick, channel
    nonisolated(unsafe) var onMode: ((String, String, [String]) -> Void)?          // target, modestring, params
    // Catch-all for server messages not handled by a specific callback above
    nonisolated(unsafe) var onUnhandledMessage: ((IRCMessage) -> Void)?
    // Dedicated LIST result callbacks (avoids clobbering onUnhandledMessage)
    nonisolated(unsafe) var onListEntry: ((String, Int, String) -> Void)?   // name, count, topic
    nonisolated(unsafe) var onListEnd:   (() -> Void)?
    
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
            self?.debugLog.log("State changed: \(String(describing: state))", type: .info)
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

                    // RFC 2812 §3.1: send CAP LS to begin capability negotiation
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
                        try await self.send_raw("AUTHENTICATE PLAIN")
                        self.saslRequested = true
                    }
                    
                    // RFC 2812 §3.1: registration order is PASS (if any), then NICK, then USER.
                    if let password = serverPassword, !password.isEmpty {
                        try await self.send_raw("PASS \(password)")
                    }
                    // NICK takes a single middle parameter — do NOT use send() which appends ":"
                    try await self.send_raw("NICK \(nickname)")
                    // USER: second param must be "0" per modern IRC spec; "8" sets invisible+wallops
                    try await self.send_raw("USER \(username) 0 * :\(realname)")
                    
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
                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        self?.debugLog.log("send_raw error: \(error.localizedDescription)", type: .error)
                        Task { @MainActor in
                            self?.onError?(error)
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
        // RFC 2812 §3.2.1: JOIN <channel> — channel is a middle param, no trailing colon needed
        try await send_raw("JOIN \(channel)")
    }

    func join(channel: String, key: String) async throws {
        try await send_raw("JOIN \(channel) \(key)")
    }

    func leave(channel: String, message: String? = nil) async throws {
        // RFC 2812 §3.2.2: PART <channel> [:<part message>]
        if let message = message {
            try await send_raw("PART \(channel) :\(message)")
        } else {
            try await send_raw("PART \(channel)")
        }
    }

    func quit(message: String = "Parso IRC") async throws {
        // RFC 2812 §3.1.7: QUIT [:<quit message>]
        try await send_raw("QUIT :\(message)")
    }
    
    func nick(_ newNickname: String) async throws {
        // RFC 2812 §3.1.2: NICK <nickname> — middle param, no trailing colon
        try await send_raw("NICK \(newNickname)")
    }
    
    func list() async throws {
        try await send_raw("LIST")
    }
    
    func names(_ channel: String) async throws {
        // RFC 2812 §3.2.5: NAMES [<channel>]
        try await send_raw("NAMES \(channel)")
    }
    
    func whois(_ username: String) async throws {
        // RFC 2812 §3.6.2: WHOIS [<server>] <nickmask>
        try await send_raw("WHOIS \(username)")
    }
    
    func away(_ message: String?) async throws {
        if let message = message {
            try await send_raw("AWAY :\(message)")
        } else {
            // AWAY with no params clears away status
            try await send_raw("AWAY")
        }
    }
    
    func me(_ message: String, to channel: String) async throws {
        // CTCP ACTION: \x01ACTION text\x01
        let action = "\u{0001}ACTION \(message)\u{0001}"
        try await send(command: "PRIVMSG", parameters: [channel, action])
    }
    
    func topic(channel: String, newTopic: String? = nil) async throws {
        if let topic = newTopic {
            try await send_raw("TOPIC \(channel) :\(topic)")
        } else {
            try await send_raw("TOPIC \(channel)")
        }
    }
    
    func kick(channel: String, nick: String, reason: String? = nil) async throws {
        if let reason = reason {
            try await send_raw("KICK \(channel) \(nick) :\(reason)")
        } else {
            try await send_raw("KICK \(channel) \(nick)")
        }
    }
    
    func invite(nick: String, channel: String) async throws {
        // RFC 2812 §3.2.7: INVITE <nickname> <channel>
        try await send_raw("INVITE \(nick) \(channel)")
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

    // SASL PLAIN authentication (separate from the connect flow)
    func authenticateSASL(username: String, password: String) async throws {
        // Build PLAIN credential: \0username\0password, base64-encoded
        let saslData = "\0\(username)\0\(password)"
        let encoded = saslData.data(using: .utf8)?.base64EncodedString() ?? ""
        try await send_raw("AUTHENTICATE \(encoded)")
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
                    self?.debugLog.log("receive error: \(error.localizedDescription)", type: .error)
                }
                
                if let data = data, !data.isEmpty {
                    await self?.handleReceivedData(data)
                }

                if isComplete {
                    self?.debugLog.log("Connection completed (isComplete=true)", type: .error)
                    await self?.disconnect()
                } else if error != nil {
                    self?.debugLog.log("receive loop ending due to error", type: .error)
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
            // RFC 2812 §3.7.2: PONG must echo back the server's token
            let param = message.parameters.first.map { ":\($0)" } ?? ":"
            try? await send_raw("PONG \(param)")

        case "CAP":
            await handleCapMessage(message)
            
        case "005":
            // RPL_ISUPPORT — parse tokens, then pass to UI
            handleISupportMessage(message)
            await MainActor.run {
                self.onUnhandledMessage?(message)
            }
            
        case "903":
            // RPL_SASLSUCCESS
            if saslRequested {
                try? await send_raw("CAP END")
                saslRequested = false
            }
            await MainActor.run {
                self.onUnhandledMessage?(message)
            }
            
        case "904":
            // ERR_SASLFAIL
            if saslRequested {
                try? await send_raw("CAP END")
                saslRequested = false
            }
            await MainActor.run {
                self.onUnhandledMessage?(message)
            }

        case "001":
            // RPL_WELCOME — first param is the nick the server assigned us
            let nick = message.parameters.first ?? currentNick
            currentNick = nick
            await MainActor.run {
                self.onWelcome?(nick)
            }

        case "JOIN":
            // RFC 2812 §3.2.1: :nick!user@host JOIN <channel>
            let channel = message.parameters.first ?? ""
            let nick = message.source?.nick ?? ""
            // Update our tracked nick if we are the one joining
            if nick == currentNick {
                debugLog.log("We joined \(channel)", type: .info)
            }
            await MainActor.run {
                self.onJoin?(channel, nick)
            }

        case "PART":
            // RFC 2812 §3.2.2: :nick!user@host PART <channel> [:<reason>]
            let channel = message.parameters.first ?? ""
            let nick = message.source?.nick ?? ""
            let partMessage: String? = message.parameters.count > 1 ? message.parameters[1] : nil
            await MainActor.run {
                self.onPart?(channel, nick, partMessage)
            }

        case "QUIT":
            // RFC 2812 §3.1.7: :nick!user@host QUIT [:<reason>]
            let nick = message.source?.nick ?? ""
            let quitMessage = message.parameters.first
            await MainActor.run {
                self.onQuit?(nick, quitMessage)
            }

        case "NICK":
            // RFC 2812 §3.1.2: :oldnick!user@host NICK <newnick>
            let oldNick = message.source?.nick ?? ""
            let newNick = message.parameters.first ?? oldNick
            // Track our own nick change
            if oldNick == currentNick {
                currentNick = newNick
            }
            await MainActor.run {
                self.onNickChange?(oldNick, newNick)
            }

        case "TOPIC":
            // RFC 2812 §3.2.4: :nick!user@host TOPIC <channel> :<topic>
            let channel = message.parameters.first ?? ""
            let topic = message.parameters.count > 1 ? message.parameters[1] : ""
            let nick = message.source?.nick ?? ""
            await MainActor.run {
                self.onTopicChange?(channel, topic, nick)
            }

        case "KICK":
            // RFC 2812 §3.2.8: :nick!user@host KICK <channel> <kicked_nick> [:<reason>]
            let channel = message.parameters.first ?? ""
            let kicked = message.parameters.count > 1 ? message.parameters[1] : ""
            let by = message.source?.nick ?? ""
            let reason: String? = message.parameters.count > 2 ? message.parameters[2] : nil
            await MainActor.run {
                self.onKick?(channel, kicked, by, reason)
            }

        case "INVITE":
            // RFC 2812 §3.2.7: :nick!user@host INVITE <yournick> <channel>
            let nick = message.source?.nick ?? ""
            let channel = message.parameters.count > 1 ? message.parameters[1] : (message.parameters.first ?? "")
            await MainActor.run {
                self.onInvite?(nick, channel)
            }

        case "MODE":
            // RFC 2812 §3.1.5 / §3.2.3: :source MODE <target> <modestring> [<params>...]
            let target = message.parameters.first ?? ""
            let modeString = message.parameters.count > 1 ? message.parameters[1] : ""
            let modeParams = message.parameters.count > 2 ? Array(message.parameters.dropFirst(2)) : []
            // Track our own mode changes silently; surface to UI via onMode
            await MainActor.run {
                self.onMode?(target, modeString, modeParams)
            }

        case "353":
            // RPL_NAMREPLY: :server 353 <yournick> <chantype> <channel> :<nicks...>
            // parameters[0] = yournick, [1] = chantype (=/*/@), [2] = channel, [3] = nicks
            if message.parameters.count >= 4 {
                let channel = message.parameters[2]
                let nicksRaw = message.parameters[3]
                let nicks = nicksRaw.split(separator: " ").map(String.init)
                await MainActor.run {
                    self.onNamesList?(channel, nicks)
                }
            } else if message.parameters.count >= 3 {
                // Fallback for servers that omit chantype
                let channel = message.parameters[1]
                let nicksRaw = message.parameters[2]
                let nicks = nicksRaw.split(separator: " ").map(String.init)
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
            // RFC 2812 §3.7.4: ERROR terminates the connection
            let errorMsg = message.parameters.joined(separator: " ")
            let ircError = IRCError.connectionFailed(errorMsg)
            await MainActor.run {
                self.onError?(ircError)
            }
            // Cleanly close after receiving ERROR
            connection?.cancel()
            connection = nil
            isConnected = false

        default:
            // RPL_LIST entries get their own dedicated callback in addition to the
            // generic onUnhandledMessage so ChannelBrowserSheet doesn't clobber the latter.
            if command == "322" {
                // RPL_LIST: params = [nick, channel, count, :topic]
                if message.parameters.count >= 3 {
                    let name  = message.parameters[1]
                    let count = Int(message.parameters[2]) ?? 0
                    let topic = message.parameters.count > 3 ? message.parameters[3] : ""
                    await MainActor.run { self.onListEntry?(name, count, topic) }
                }
            } else if command == "323" {
                // RPL_LISTEND
                await MainActor.run { self.onListEnd?() }
            }
            // All other server messages (numerics, etc.) are passed to the UI
            // via onUnhandledMessage so they can be displayed in the terminal.
            await MainActor.run {
                self.onUnhandledMessage?(message)
            }
        }
    }
    
    private func handleCapMessage(_ message: IRCMessage) async {
        guard message.parameters.count >= 2 else { return }
        
        // CAP params: [target, subcommand, ...]  where target is our nick or *
        let subcommand = message.parameters[1]
        
        switch subcommand {
        case "LS":
            // May be multi-line: CAP * LS * :caps...  (asterisk = more coming)
            // Last param holds the capability list
            if let caps = message.parameters.last {
                let capabilities = caps.split(separator: " ").map(String.init)
                for cap in capabilities {
                    let capName = cap.split(separator: "=").first.map(String.init) ?? cap
                    if capName == "batch" {
                        pendingCapabilities.insert("batch")
                    } else if capName == "server-time" {
                        pendingCapabilities.insert("server-time")
                    } else if capName == "message-tags" {
                        pendingCapabilities.insert("message-tags")
                    } else if capName == "draft/chathistory" || capName == "chathistory" {
                        pendingCapabilities.insert("chathistory")
                    } else if capName == "sasl" {
                        pendingCapabilities.insert("sasl")
                    }
                }
            }
            // If this is not a multi-line LS (no asterisk before last param), negotiation is done
            if message.parameters.count < 4 || message.parameters[2] != "*" {
                isCapNegotiationComplete = true
            }
            
        case "ACK":
            if let caps = message.parameters.last {
                let acknowledged = caps.split(separator: " ").map(String.init)
                for cap in acknowledged {
                    let capName = cap.trimmingCharacters(in: .init(charactersIn: "-~="))
                    acknowledgedCapabilities.insert(capName)
                    
                    if capName == "batch" || capName.hasPrefix("batch") {
                        chathistoryEnabled = true
                    } else if capName == "server-time" {
                        serverTimeEnabled = true
                    } else if capName == "chathistory" || capName == "draft/chathistory" {
                        chathistoryEnabled = true
                    }
                }
            }
            
        case "NAK":
            // Server rejected our CAP REQ; nothing to do
            break
            
        case "END":
            isCapNegotiationComplete = true
            
        case "NEW":
            // IRCv3 cap-notify: server advertising a new capability
            break
            
        case "DEL":
            // IRCv3 cap-notify: server removing a capability
            break
            
        default:
            break
        }
    }
    
    private func handleISupportMessage(_ message: IRCMessage) {
        // RPL_ISUPPORT params: [yournick, token1, token2, ..., "are supported by this server"]
        for param in message.parameters.dropFirst() {
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
