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

    private var readStream: InputStream?
    private var writeStream: OutputStream?
    private var useTLS = false

    init() {}

    // MARK: - Connection

    func connect(
        host: String,
        port: Int,
        tls: Bool,
        nickname: String,
        username: String,
        realname: String
    ) async throws {
        guard !isConnected else { return }

        serverInfo = (host, UInt16(port))
        useTLS = tls

        let hostNW = NWEndpoint.Host(host)
        let portNW = NWEndpoint.Port(integerLiteral: UInt16(port))

        let parameters: NWParameters
        if tls {
            parameters = NWParameters(tls: .init())
        } else {
            parameters = .tcp
        }

        let connection = NWConnection(host: hostNW, port: portNW, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleStateChange(state)
            }
        }

        connection.start(queue: queue)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    try await self.waitForConnection(timeout: 30)
                    self.isConnected = true
                    self.currentNick = nickname

                    try await self.send_raw("NICK :\(nickname)")
                    try await self.send_raw("USER \(username) 8 * :\(realname)")

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        startReceiving()
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
            try await Task.sleep(nanoseconds: 100_000_000)
            if Date().timeIntervalSince(startTime) > Double(timeout) {
                throw IRCError.timeout
            }
        }
    }

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
        case .failed(let error):
            if let error = error {
                Task { @MainActor in
                    self.onError?(error)
                }
            }
            Task {
                await disconnect()
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
            throw IRCError.notConnected
        }

        var data = message.data(using: .utf8) ?? Data()
        data.append(contentsOf: [0x0D, 0x0A])

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                let err = error
                Task { @MainActor in
                    self.onError?(err)
                }
            }
        })
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
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task {
                if let data = data, !data.isEmpty {
                    await self?.handleReceivedData(data)
                }

                if isComplete || error != nil {
                    await self?.disconnect()
                } else {
                    await self?.startReceiving()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) async {
        guard let string = String(data: data, encoding: .utf8) else { return }

        let lines = string.components(separatedBy: "\r\n")
        for line in lines where !line.isEmpty {
            let message = IRCMessage(rawLine: line)
            await handleMessage(message)
        }
    }

    private func handleMessage(_ message: IRCMessage) async {
        let command = message.command

        switch command {
        case "PING":
            let param = message.parameters.first.map { ":\($0)" } ?? ":"
            try? await send_raw("PONG \(param)")

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
            await MainActor.run {
                self.onMessage?(message)
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
}