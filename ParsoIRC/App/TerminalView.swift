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
    var startConnecting: Bool = false
    
    @State private var ircClient: IRCClient?
    
    @State private var lines: [TerminalLine] = []
    @State private var showCommandSheet = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isConnecting = true
    @State private var connectionStartTime = Date()
    @State private var showConnecting = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if showConnecting {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .green))
                        .scaleEffect(1.5)
                    Text("Connecting to \(server.host)...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 16)
                }
            }
            
            VStack(spacing: 0) {
                // Terminal header
                HStack {
                    VStack(alignment: .leading) {
                        Text(server.name)
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(showConnecting ? "Connecting to \(server.host)..." : channel.name)
                            .font(.caption)
                            .foregroundColor(showConnecting ? .yellow : .gray)
                    }
                    
                    Spacer()
                    
                    if !isConnecting {
                        if ircManager.connectionState(for: server.id) == .connected {
                            Text("CONNECTED")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Text("DISCONNECTED")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(4)
                        }
                    } else {
                        Text("CONNECTING...")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.2))
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
        .task {
            if startConnecting {
                await showConnectingState()
            } else {
                setupIRCCallbacks()
            }
        }
    }
    
    private func showConnectingState() async {
        connectionStartTime = Date()
        addSystemMessage("[DEBUG] Starting connection to \(server.host):\(server.port)")
        print("[DEBUG] showConnectingState called for \(server.host):\(server.port)")
        
        let nickname = server.nickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : server.nickname
        let username = server.realname.isEmpty ? "parso" : server.realname
        let realname = server.realname.isEmpty ? "Parso IRC" : server.realname
        
        addSystemMessage("* Using nick: \(nickname)")
        print("[DEBUG] Creating IRCClient...")
        ircClient = IRCClient()
        
        guard let client = ircClient else {
            addSystemMessage("* Error: Failed to create client")
            print("[DEBUG] ERROR: Failed to create IRCClient")
            return
        }
        print("[DEBUG] IRCClient created, setting up callbacks...")
        
        client.onMessage = { message in
            let line = "\(message.command) \(message.parameters.joined(separator: " "))"
            print("[DEBUG] onMessage: \(line)")
            Task { @MainActor in
                self.addReceivedMessage(line)
                self.isConnecting = false
            }
        }
        
        client.onWelcome = { nick in
            print("[DEBUG] onWelcome: \(nick)")
            Task { @MainActor in
                self.addSystemMessage("* You are now known as \(nick)")
                self.isConnecting = false
                self.showConnecting = false
            }
        }
        
        client.onDisconnect = {
            print("[DEBUG] onDisconnect")
            Task { @MainActor in
                self.addSystemMessage("* Disconnected")
                self.isConnecting = false
                self.showConnecting = false
            }
        }
        
        client.onError = { error in
            print("[DEBUG] onError: \(error.localizedDescription)")
            Task { @MainActor in
                self.addSystemMessage("* Error: \(error.localizedDescription)")
                self.isConnecting = false
                self.showConnecting = false
            }
        }
        
        print("[DEBUG] Starting connection task...")
        Task {
            do {
                print("[DEBUG] Calling client.connect()...")
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
                print("[DEBUG] client.connect() succeeded")
                
                await MainActor.run {
                    self.addSystemMessage("* Connected to \(server.host)")
                    self.addSystemMessage("[DEBUG] Connection complete!")
                    self.ircManager.connections[self.server.id] = client
                    self.ircManager.connectionStates[self.server.id] = .connected
                    self.isConnecting = false
                    self.showConnecting = false
                }
            } catch {
                print("[DEBUG] client.connect() failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.addSystemMessage("* Connection failed: \(error.localizedDescription)")
                    self.isConnecting = false
                    self.showConnecting = false
                }
            }
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run {
                if self.isConnecting && self.lines.count <= 1 {
                    let elapsed = Date().timeIntervalSince(self.connectionStartTime)
                    print("[DEBUG] Connection timeout check: \(elapsed)s elapsed, lines: \(self.lines.count)")
                    self.addSystemMessage("[DEBUG] Still connecting after \(Int(elapsed))s...")
                }
            }
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await MainActor.run {
                if self.isConnecting && self.lines.count <= 1 {
                    let elapsed = Date().timeIntervalSince(self.connectionStartTime)
                    self.addSystemMessage("* Connection timeout after \(Int(elapsed))s")
                    self.addSystemMessage("* Please check your network connection")
                    self.isConnecting = false
                    self.showConnecting = false
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