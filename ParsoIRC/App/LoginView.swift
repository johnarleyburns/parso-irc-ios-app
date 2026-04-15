import SwiftUI

struct LoginView: View {
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
        let firstChannel = defaultServer.channels.first ?? Channel(name: "#linux")
        self._selectedChannel = State(initialValue: firstChannel)
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
                            
                            Text("Welcome Back")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Sign in to continue")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                        
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
                                TextField("Enter your nickname", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
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
                            login()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign In")
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
                            Text("Don't have an account? Sign Up")
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
            }
            .sheet(isPresented: $showDebug) {
                DebugSheetView(isPresented: $showDebug)
            }
            .onAppear {
                username = savedUsername
                password = savedPassword
                if let server = Server.defaultNetworks.first(where: { $0.host == lastServerHost }) {
                    selectedServer = server
                    if let lastChannel = savedUsername.isEmpty ? nil : server.channels.first(where: { $0.name == lastChannelName }) {
                        selectedChannel = lastChannel
                    } else {
                        selectedChannel = server.channels.first ?? Channel(name: "#linux")
                    }
                }
                DebugMessages.shared.addMessage("=== Login View Opened ===")
                DebugMessages.shared.addMessage("Saved username: \(savedUsername)")
                DebugMessages.shared.addMessage("Saved password: \(savedPassword.isEmpty ? "(empty)" : "****")")
                DebugMessages.shared.addMessage("Last channel: \(lastChannelName)")
            }
        }
}
    
    private func login() {
        guard !username.isEmpty else {
            errorMessage = "Please enter a username"
            showError = true
            return
        }
        
        showDebug = true
        DebugMessages.shared.addMessage("=== STARTING LOGIN ===")
        DebugMessages.shared.addMessage("Username: \(username)")
        
        isLoading = true
        showError = false
        
        lastServerHost = selectedServer.host
        lastServerName = selectedServer.name
        lastChannelName = selectedChannel.name
        savedUsername = username
        savedPassword = password
        
        Task {
            do {
                DebugMessages.shared.addMessage("Step 1: Authenticating...")
                let user = try DatabaseManager.shared.authenticateUser(username: username.lowercased(), password: password)
                
                guard let user = user else {
                    DebugMessages.shared.addMessage("ERROR: Invalid credentials")
                    await MainActor.run {
                        errorMessage = "Invalid credentials"
                        showError = true
                        isLoading = false
                    }
                    return
                }
                
                DebugMessages.shared.addMessage("Step 2: User OK")
                
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
                
                DebugMessages.shared.addMessage("Step 3: Saving server...")
                try DatabaseManager.shared.saveServer(serverToSave)
                DebugMessages.shared.addMessage("Step 4: Done")
                
                AppState.shared.currentUser = user
                DebugMessages.shared.addMessage("=== LOGIN COMPLETE ===")
                DebugMessages.shared.addMessage("Connecting to IRC...")
                
                var serverConfig = serverToSave
                serverConfig.lastActiveChannel = selectedChannel.name
                serverConfig.channels = [selectedChannel]
                
                DebugMessages.shared.addMessage("Calling connectWithHistory...")
                
                try await ircManager.connectWithHistory(to: serverConfig) { serverId, channelName in
                    DebugMessages.shared.addMessage("IRC CONNECTED")
                    Task { @MainActor in
                        isLoading = false
                        isAuthenticated = true
                        AppState.shared.navigateToChannel(serverId: serverId, channelName: channelName)
                    }
                }
                
                DebugMessages.shared.addMessage("IRC connection complete")
            } catch {
                DebugMessages.shared.addMessage("ERROR: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = "Failed: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}
