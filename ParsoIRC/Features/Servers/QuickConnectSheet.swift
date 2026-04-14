import SwiftUI

struct QuickConnectSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    let server: Server
    let isFirstTime: Bool
    
    @State private var hostname: String
    @State private var port: String
    @State private var ssl: Bool
    @State private var username: String
    @State private var password: String
    @State private var saslEnabled: Bool
    
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var connectionTimeout: Bool = false
    
    @State private var connectionTask: Task<Void, Never>?
    
    init(server: Server, isFirstTime: Bool = false) {
        self.server = server
        self.isFirstTime = isFirstTime
        _hostname = State(initialValue: server.host)
        _port = State(initialValue: String(server.port))
        _ssl = State(initialValue: server.ssl)
        _username = State(initialValue: server.nickname)
        _password = State(initialValue: server.password ?? "")
        _saslEnabled = State(initialValue: server.saslEnabled)
    }
    
    private var effectiveNickname: String {
        if !username.isEmpty {
            return username
        }
        if let saved = appState.lastUsername, !saved.isEmpty {
            return saved
        }
        return "parso\(Int.random(in: 1000...9999))"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isConnecting {
                    connectingView
                } else {
                    formView
                }
            }
            .navigationTitle(isFirstTime ? "Welcome to Parso" : "Connect to \(server.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        connectionTask?.cancel()
                        dismiss()
                    }
                    .disabled(isConnecting)
                }
            }
            .interactiveDismissDisabled(isConnecting)
        }
    }
    
    private var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.theme.sentBubble)
            
            VStack(spacing: 8) {
                Text("Connecting to \(hostname)...")
                    .font(.headline)
                
                if connectionTimeout {
                    Text("Taking longer than expected...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if let error = connectionError {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Try Again") {
                        connectionError = nil
                        connectionTimeout = false
                        initiateConnection()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initiateConnection()
        }
    }
    
    private var formView: some View {
        Form {
            Section("Server") {
                TextField("Hostname", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .disabled(!isFirstTime)
                
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                    .disabled(!isFirstTime)
                
                Toggle("SSL/TLS", isOn: $ssl)
                    .disabled(!isFirstTime)
            }
            
            Section("Identity") {
                TextField("Nickname", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                if !isFirstTime {
                    SecureField("Server Password (optional)", text: $password)
                } else {
                    SecureField("Password (optional)", text: $password)
                }
            }
            
            Section("Authentication") {
                Toggle("SASL Authentication", isOn: $saslEnabled)
            }
            
            if let connectionState = ircManager.connectionStatesPublisher[server.id], connectionState == .connected {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Currently connected")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let connectionState = ircManager.connectionStatesPublisher[server.id], connectionState == .connected {
                    Button(role: .destructive) {
                        ircManager.disconnect(from: server.id)
                        dismiss()
                    } label: {
                        Text("Disconnect")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        saveAndConnect()
                    } label: {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hostname.isEmpty || username.isEmpty)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
    
    private func saveAndConnect() {
        appState.lastUsername = effectiveNickname
        
        var updatedServer = server
        updatedServer.nickname = effectiveNickname
        updatedServer.password = password.isEmpty ? nil : password
        updatedServer.saslEnabled = saslEnabled
        
        if isFirstTime {
            updatedServer = Server(
                id: UUID().uuidString,
                name: "Libera.Chat",
                host: hostname,
                port: Int(port) ?? 6697,
                ssl: ssl,
                nickname: effectiveNickname,
                realname: "Parso IRC User",
                password: password.isEmpty ? nil : password,
                saslEnabled: saslEnabled,
                autoConnect: false,
                channels: [Channel(name: "#libera")]
            )
        }
        
        Task {
            do {
                try DatabaseManager.shared.saveServer(updatedServer)
                await MainActor.run {
                    if let index = appState.servers.firstIndex(where: { $0.id == updatedServer.id }) {
                        appState.servers[index] = updatedServer
                    } else {
                        appState.servers.append(updatedServer)
                    }
                }
            } catch {
                print("Failed to save server: \(error)")
            }
        }
        
        initiateConnection()
    }
    
    private func initiateConnection() {
        isConnecting = true
        connectionError = nil
        connectionTimeout = false
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    connectionTimeout = true
                }
            }
        }
        
        let targetChannel = isFirstTime ? "#libera" : (server.lastActiveChannel ?? server.channels.first?.name ?? "")
        
        connectionTask = Task {
            var serverToConnect = server
            
            if isFirstTime {
                serverToConnect = Server(
                    id: server.id,
                    name: "Libera.Chat",
                    host: hostname,
                    port: Int(port) ?? 6697,
                    ssl: ssl,
                    nickname: effectiveNickname,
                    realname: "Parso IRC User",
                    password: password.isEmpty ? nil : password,
                    saslEnabled: saslEnabled,
                    autoConnect: false,
                    channels: [Channel(name: "#libera")],
                    lastActiveChannel: "#libera"
                )
            } else {
                serverToConnect.nickname = effectiveNickname
                serverToConnect.password = password.isEmpty ? nil : password
                serverToConnect.saslEnabled = saslEnabled
                serverToConnect.lastActiveChannel = server.channels.first?.name
            }
            
            do {
                try await ircManager.connectWithHistory(to: serverToConnect) { serverId, channelName in
                    timeoutTask.cancel()
                    Task { @MainActor in
                        appState.navigateToChannel(serverId: serverId, channelName: channelName)
                        isConnecting = false
                        dismiss()
                    }
                }
            } catch {
                timeoutTask.cancel()
                await MainActor.run {
                    isConnecting = false
                    connectionError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    QuickConnectSheet(
        server: Server(
            name: "Libera.Chat",
            host: "irc.libera.chat",
            port: 6697,
            ssl: true,
            nickname: "testuser",
            channels: [Channel(name: "#libera")]
        ),
        isFirstTime: true
    )
    .environmentObject(AppState())
    .environmentObject(IRCClientManager.shared)
}
