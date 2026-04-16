import SwiftUI
import Combine

struct TerminalLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let content: String
    let isSent: Bool
    let isSystem: Bool
    
    init(timestamp: Date = Date(), content: String, isSent: Bool = false, isSystem: Bool = false) {
        self.timestamp = timestamp
        self.content = content
        self.isSent = isSent
        self.isSystem = isSystem
    }
}

struct TerminalView: View {
    @EnvironmentObject var ircManager: IRCClientManager
    @EnvironmentObject var appState: AppState
    
    let server: Server
    let channel: Channel
    var isConnecting: Bool = false
    
    @State private var ircClient: IRCClient?
    
    @State private var lines: [TerminalLine] = []
    @State private var showCommandSheet = false
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Terminal header
                HStack {
                    VStack(alignment: .leading) {
                        Text(server.name)
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(channel.name)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if ircManager.connectionState(for: server.id) == .connected {
                        Text("CONNECTED")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .padding()
                .background(Color(white: 0.1))
                
                // Terminal output
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(lines) { line in
                                Text(line.content)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(line.isSent ? .yellow : (line.isSystem ? .cyan : .green))
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        scrollProxy = proxy
                        scrollToBottom()
                    }
                }
                
                // Command bar
                HStack {
                    Button {
                        showCommandSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Text("[\(channel.name)]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(white: 0.1))
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCommandSheet) {
            CommandInputSheet(
                channel: channel,
                server: server,
                onSend: { command, arguments in
                    sendCommand(command: command, arguments: arguments)
                    showCommandSheet = false
                },
                onCancel: {
                    showCommandSheet = false
                }
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            if isConnecting {
                showConnectingState()
            } else {
                setupIRCCallbacks()
            }
        }
    }
    
    private func showConnectingState() {
        addSystemMessage("* Connecting to \(server.host):\(server.port)")
        
        let nickname = server.nickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : server.nickname
        let username = server.realname.isEmpty ? "parso" : server.realname
        let realname = server.realname.isEmpty ? "Parso IRC" : server.realname
        
        ircClient = IRCClient()
        
        guard let client = ircClient else {
            addSystemMessage("* Error: Failed to create client")
            return
        }
        
        client.onMessage = { message in
            let line = "\(message.command) \(message.parameters.joined(separator: " "))"
            Task { @MainActor in
                self.addReceivedMessage(line)
            }
        }
        
        client.onWelcome = { nick in
            Task { @MainActor in
                self.addSystemMessage("* You are now known as \(nick)")
            }
        }
        
        client.onDisconnect = {
            Task { @MainActor in
                self.addSystemMessage("* Disconnected")
            }
        }
        
        client.onError = { error in
            Task { @MainActor in
                self.addSystemMessage("* Error: \(error.localizedDescription)")
            }
        }
        
        Task {
            do {
                try await client.connect(
                    host: server.host,
                    port: server.port,
                    tls: server.ssl,
                    nickname: nickname,
                    username: username,
                    realname: realname,
                    serverPassword: server.password,
                    useSASL: server.saslEnabled,
                    saslPassword: server.password
                )
                
                await MainActor.run {
                    self.addSystemMessage("* Connected to \(server.host)")
                    self.ircManager.connections[self.server.id] = client
                    self.ircManager.connectionStates[self.server.id] = .connected
                }
            } catch {
                await MainActor.run {
                    self.addSystemMessage("* Connection failed: \(error.localizedDescription)")
                    self.ircManager.connectionStates[self.server.id] = .failed(.connectionFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func setupIRCCallbacks() {
        guard let client = ircManager.getClient(for: server.id) else { return }
        
        client.onMessage = { message in
            let line = "\(message.command) \(message.parameters.joined(separator: " "))"
            Task { @MainActor in
                self.addReceivedMessage(line)
            }
        }
        
        client.onWelcome = { nick in
            Task { @MainActor in
                self.addSystemMessage("* You are now known as \(nick)")
            }
        }
        
        client.onDisconnect = {
            Task { @MainActor in
                self.addSystemMessage("* Disconnected")
            }
        }
    }
    
    private func sendCommand(command: String, arguments: String) {
        let fullCommand = command.uppercased()
        var message = ":\(fullCommand)"
        
        if !arguments.isEmpty {
            message += " \(arguments)"
        }
        
        // Add to terminal as sent
        addSentMessage(message)
        
        // Send via IRC client
        Task {
            do {
                if let client = ircManager.getClient(for: server.id) {
                    try await client.send_raw(message)
                }
            } catch {
                addSystemMessage("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func addSentMessage(_ content: String) {
        let line = TerminalLine(content: "→ \(content)", isSent: true)
        lines.append(line)
        scrollToBottom()
    }
    
    private func addReceivedMessage(_ content: String) {
        let line = TerminalLine(content: content)
        lines.append(line)
        scrollToBottom()
    }
    
    private func addSystemMessage(_ content: String) {
        let line = TerminalLine(content: content, isSystem: true)
        lines.append(line)
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let lastLine = lines.last {
                withAnimation {
                    scrollProxy?.scrollTo(lastLine.id, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    TerminalView(
        server: Server.defaultNetworks[0],
        channel: Channel(name: "#linux")
    )
    .environmentObject(IRCClientManager.shared)
    .environmentObject(AppState())
}