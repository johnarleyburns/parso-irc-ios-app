import SwiftUI

struct SimpleConnectView: View {
    @State private var status: ConnectionStatus = .disconnected
    @State private var messages: [String] = []
    @State private var inputText: String = ""
    @State private var ircClient: IRCClient?
    @State private var scrollProxy: ScrollViewProxy?
    @EnvironmentObject private var debugLog: DebugLogManager
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Libera.Chat")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
                statusView
            }
            .padding()
            .background(Color(white: 0.1))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
                            Text(msg)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
            
// Input
            HStack {
                TextField("Enter command or message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
                    .onSubmit {
                        sendCommand()
                    }
                    .disabled(status != .connected)
                
                Button("Send") {
                    sendCommand()
                }
                .foregroundColor(.green)
                .disabled(status != .connected)
            }
            .padding()
            .background(Color(white: 0.1))
            
            // Debug Panel
            VStack(spacing: 0) {
                // Debug Header
                HStack {
                    Text("Debug Log")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Button("Clear") {
                        debugLog.clear()
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.15))
                
                // Debug Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(debugLog.logs.enumerated()), id: \.element.id) { index, entry in
                                HStack(spacing: 4) {
                                    Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Color(red: 0, green: 1, blue: 1))
                                    
                                    Text("[\(entry.type.rawValue)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(entry.type == .error ? Color(red: 1, green: 0.27, blue: 0.27) : Color(red: 1, green: 1, blue: 0))
                                    
                                    Text(entry.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onAppear {
                        if let lastId = debugLog.logs.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                    .onChange(of: debugLog.logs.count) { _, _ in
                        if let lastId = debugLog.logs.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(height: 200)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    var statusView: some View {
        switch status {
        case .disconnected:
            Button("Connect") {
                connect()
            }
            .foregroundColor(.green)
            .font(.headline)
            
        case .connecting:
            ProgressView()
                .scaleEffect(0.8)
            
        case .connected:
            Text("CONNECTED")
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(4)
            
        case .failed(let error):
            Text("FAILED")
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.2))
                .cornerRadius(4)
        }
    }
    
    private func connect() {
        status = .connecting
        messages.append("[Connecting to irc.libera.chat:6697...]")
        
        ircClient = IRCClient()
        guard let client = ircClient else {
            status = .failed("Failed to create client")
            return
        }
        
        let nickname = "parso\(Int.random(in: 1000...9999))"
        
        client.onMessage = { [self] msg in
            var line: String
            
            switch msg.command {
            case "PRIVMSG":
                let from = msg.source?.nick ?? "unknown"
                let target = msg.parameters.first ?? ""
                let content = msg.parameters.count > 1 ? msg.parameters.dropFirst().joined(separator: " ") : ""
                line = "<\(from)> \(content)"
                
            case "NOTICE":
                let from = msg.source?.nick ?? "server"
                let target = msg.parameters.first ?? ""
                let content = msg.parameters.count > 1 ? msg.parameters.dropFirst().joined(separator: " ") : ""
                line = "[\(from)] \(content)"
                
            case "JOIN":
                let nick = msg.source?.nick ?? "unknown"
                let channel = msg.parameters.first ?? ""
                line = "* \(nick) has joined \(channel)"
                
            case "PART":
                let nick = msg.source?.nick ?? "unknown"
                let channel = msg.parameters.first ?? ""
                line = "* \(nick) has left \(channel)"
                
            case "QUIT":
                let nick = msg.source?.nick ?? "unknown"
                line = "* \(nick) has quit"
                
            case "NICK":
                let oldNick = msg.source?.nick ?? "unknown"
                let newNick = msg.parameters.first ?? oldNick
                line = "* \(oldNick) is now known as \(newNick)"
                
            case "353": // RPL_NAMREPLY
                let channel = msg.parameters.dropFirst().first ?? ""
                let nicks = msg.parameters.last ?? ""
                line = "[NAMES] \(channel): \(nicks)"
                
            case "366": // RPL_ENDOFNAMES
                let channel = msg.parameters.first ?? ""
                line = "[NAMES] End of list for \(channel)"
                
            case "332": // RPL_TOPIC
                let channel = msg.parameters.first ?? ""
                let topic = msg.parameters.dropFirst().last ?? ""
                line = "[TOPIC] \(channel): \(topic)"
                
            case "322": // RPL_LIST
                let channel = msg.parameters.count > 1 ? msg.parameters[1] : ""
                let count = msg.parameters.count > 2 ? msg.parameters[2] : ""
                line = "[LIST] \(channel) (\(count) users)"
                
            case "323": // RPL_LISTEND
                line = "[LIST] End of channel list"
                
            default:
                line = ":\(msg.source?.nick ?? "server") \(msg.command) \(msg.parameters.joined(separator: " "))"
            }
            
            Task { @MainActor in
                messages.append(line)
                scrollToBottom()
            }
        }
        
        client.onWelcome = { [self] nick in
            Task { @MainActor in
                messages.append("* You are now known as \(nick)")
                status = .connected
                scrollToBottom()
            }
        }
        
        client.onDisconnect = { [self] in
            Task { @MainActor in
                messages.append("* Disconnected")
                status = .disconnected
                scrollToBottom()
            }
        }
        
        client.onError = { [self] error in
            Task { @MainActor in
                messages.append("* Error: \(error.localizedDescription)")
                status = .failed(error.localizedDescription)
                scrollToBottom()
            }
        }
        
        Task {
            do {
                try await client.connect(
                    host: "irc.libera.chat",
                    port: 6697,
                    tls: true,
                    nickname: nickname,
                    username: "parso",
                    realname: "Parso IRC",
                    serverPassword: nil,
                    useSASL: false,
                    saslPassword: nil
                )
            } catch {
                await MainActor.run {
                    messages.append("* Connection failed: \(error.localizedDescription)")
                    status = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    private func sendCommand() {
        guard !inputText.isEmpty, let client = ircClient else { return }
        
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append("→ \(cmd)")
        
        Task {
            do {
                try await client.send_raw(cmd)
            } catch {
                messages.append("* Error sending: \(error.localizedDescription)")
            }
        }
        
        inputText = ""
    }
    
    private func scrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let lastIndex = scrollProxy.map({ $0 }) {
                withAnimation {
                    scrollProxy?.scrollTo(messages.count - 1, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    SimpleConnectView()
}