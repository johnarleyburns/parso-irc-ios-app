import SwiftUI

struct DebugSheetView: View {
    @ObservedObject var debugMessages = DebugMessages.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if debugMessages.messages.isEmpty {
                    Text("No messages yet")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(debugMessages.messages.enumerated()), id: \.offset) { index, msg in
                                    Text(msg)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(msg.contains("ERROR") ? .red : (msg.contains("RECV") ? .blue : (msg.contains("SEND") ? .green : .primary)))
                                        .textSelection(.enabled)
                                        .id(index)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: debugMessages.messages.count) { _, _ in
                            if let lastIndex = debugMessages.messages.indices.last {
                                withAnimation {
                                    proxy.scrollTo(lastIndex, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug Log (\(debugMessages.messages.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        debugMessages.clear()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct RegistrationView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var isAuthenticated: Bool
    @State private var showDebug = true
    
    @AppStorage("lastServerHost") private var lastServerHost = "irc.libera.chat"
    @AppStorage("lastServerName") private var lastServerName = "Libera.Chat"
    @AppStorage("lastChannelName") private var lastChannelName = "#linux"
    @AppStorage("lastUsername") private var savedUsername = ""
    @AppStorage("lastPassword") private var savedPassword = ""
    
    @StateObject private var ircManager = IRCClientManager.shared
    
    @State private var selectedServer: Server
    @State private var selectedChannel: Channel
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    init(isAuthenticated: Binding<Bool>) {
        self._isAuthenticated = isAuthenticated
        let defaultServer = Server.defaultNetworks.first { $0.name == "Libera.Chat" } ?? Server.defaultNetworks[0]
        self._selectedServer = State(initialValue: defaultServer)
        self._selectedChannel = State(initialValue: defaultServer.channels.first ?? Channel(name: "#linux"))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Debug info at top
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DEBUG INFO")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            
                            Text("Server: \(selectedServer.name) (\(selectedServer.host))")
                            Text("Channel: \(selectedChannel.name)")
                            Text("Username: \(username)")
                            Text("Password: \(password.isEmpty ? "(empty)" : "****")")
                        }
                        .font(.caption)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Color.theme.sentBubble)
                            
                            Text("Create Account")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Sign up to connect to IRC")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("IRC Server")
                                Picker("Server", selection: $selectedServer) {
                                    ForEach(Server.defaultNetworks) { server in
                                        Text(server.name).tag(server)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .onChange(of: selectedServer) { _, newServer in
                                    if let firstChannel = newServer.channels.first {
                                        selectedChannel = firstChannel
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Default Channel")
                                Picker("Channel", selection: $selectedChannel) {
                                    ForEach(selectedServer.channels) { channel in
                                        Text(channel.name).tag(channel)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Username")
                                TextField("Choose a nickname", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password (optional)")
                                HStack {
                                    if showPassword {
                                        TextField("Password", text: $password)
                                    } else {
                                        SecureField("Password", text: $password)
                                    }
                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        
                        if showError {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                        
                        Button {
                            register()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign Up")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.theme.sentBubble)
                        .cornerRadius(12)
                        .disabled(username.isEmpty || isLoading)
                        .padding(.horizontal)
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Already have an account? Sign In")
                                .font(.subheadline)
                                .foregroundColor(Color.theme.sentBubble)
                        }
                        .padding(.top)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Debug") {
                        showDebug = true
                    }
                }
            }
            .sheet(isPresented: $showDebug) {
                DebugSheetView(isPresented: $showDebug)
            }
            .onAppear {
                username = savedUsername.isEmpty ? "parso\(Int.random(in: 1000...9999))" : savedUsername
                if let server = Server.defaultNetworks.first(where: { $0.host == lastServerHost }) {
                    selectedServer = server
                }
                DebugMessages.shared.addMessage("=== Registration View Opened ===")
                DebugMessages.shared.addMessage("Initial username: \(username)")
            }
        }
    }
    
    private func register() {
        guard !username.isEmpty else {
            errorMessage = "Please enter a username"
            showError = true
            return
        }
        
        showDebug = true
        
        DebugMessages.shared.addMessage("=== STARTING REGISTRATION ===")
        DebugMessages.shared.addMessage("Username: \(username)")
        DebugMessages.shared.addMessage("Server: \(selectedServer.name) (\(selectedServer.host))")
        DebugMessages.shared.addMessage("Channel: \(selectedChannel.name)")
        
        isLoading = true
        showError = false
        
        lastServerHost = selectedServer.host
        lastServerName = selectedServer.name
        lastChannelName = selectedChannel.name
        savedUsername = username
        savedPassword = password
        
        DebugMessages.shared.addMessage("Step 1: Creating User object...")
        
        Task {
            do {
                let user = User(
                    username: username.lowercased(),
                    passwordHash: password.isEmpty ? "" : password,
                    nickname: username,
                    avatarSeed: username.lowercased()
                )
                DebugMessages.shared.addMessage("Step 2: User object created: \(user.username)")
                
                DebugMessages.shared.addMessage("Step 3: Saving user to database...")
                try DatabaseManager.shared.saveUser(user)
                DebugMessages.shared.addMessage("Step 4: User saved to database!")
                
                DebugMessages.shared.addMessage("Step 5: Creating server config...")
                let serverToSave = Server(
                    id: selectedServer.id,
                    name: selectedServer.name,
                    host: selectedServer.host,
                    port: selectedServer.port,
                    ssl: selectedServer.ssl,
                    nickname: username,
                    realname: username,
                    password: password.isEmpty ? nil : password,
                    saslEnabled: selectedServer.saslEnabled,
                    autoConnect: false,
                    channels: [selectedChannel],
                    lastActiveChannel: selectedChannel.name
                )
                DebugMessages.shared.addMessage("Step 6: Server config created")
                
                DebugMessages.shared.addMessage("Step 7: Saving server to database...")
                try DatabaseManager.shared.saveServer(serverToSave)
                DebugMessages.shared.addMessage("Step 8: Server saved!")
                
                DebugMessages.shared.addMessage("Step 9: Setting current user in AppState...")
                AppState.shared.currentUser = user
                DebugMessages.shared.addMessage("Step 10: Current user set!")
                
                DebugMessages.shared.addMessage("Step 11: Setting isAuthenticated = true...")
                isAuthenticated = true
                DebugMessages.shared.addMessage("=== REGISTRATION COMPLETE ===")
                
                DebugMessages.shared.addMessage("Step 12: Connecting to IRC server...")
                var serverConfig = serverToSave
                serverConfig.lastActiveChannel = selectedChannel.name
                if serverConfig.channels.first(where: { $0.name == selectedChannel.name }) == nil {
                    serverConfig.channels.insert(selectedChannel, at: 0)
                }
                
                do {
                    try await ircManager.connectWithHistory(to: serverConfig) { serverId, channelName in
                        DebugMessages.shared.addMessage("=== IRC CONNECTED to \(channelName) ===")
                        Task { @MainActor in
                            isLoading = false
                            AppState.shared.navigateToChannel(serverId: serverId, channelName: channelName)
                        }
                    }
                } catch {
                    DebugMessages.shared.addMessage("ERROR: IRC connection failed - \(error.localizedDescription)")
                    await MainActor.run {
                        errorMessage = "Connection failed: \(error.localizedDescription)"
                        showError = true
                        isLoading = false
                    }
                }
                
            } catch {
                DebugMessages.shared.addMessage("ERROR: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = "Registration failed: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}
