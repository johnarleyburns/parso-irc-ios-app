import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var isAuthenticated: Bool
    
    @AppStorage("lastServerHost") private var lastServerHost = "irc.libera.chat"
    @AppStorage("lastServerName") private var lastServerName = "Libera.Chat"
    @AppStorage("lastUsername") private var savedUsername = ""
    @AppStorage("lastPassword") private var savedPassword = ""
    
    @State private var selectedServer: Server
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showPassword = false
    
    init(isAuthenticated: Binding<Bool>) {
        self._isAuthenticated = isAuthenticated
        self._selectedServer = State(initialValue: Server.defaultNetworks.first { $0.name == "Libera.Chat" } ?? Server.defaultNetworks[0])
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("IRC Server")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("Server", selection: $selectedServer) {
                                ForEach(Server.defaultNetworks) { server in
                                    Text(server.name).tag(server)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Enter your nickname", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                if showPassword {
                                    TextField("Password", text: $password)
                                        .textContentType(.password)
                                } else {
                                    SecureField("Password", text: $password)
                                        .textContentType(.password)
                                }
                                
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    
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
                    .background(isFormValid ? Color.theme.sentBubble : Color.theme.sentBubble.opacity(0.5))
                    .cornerRadius(12)
                    .disabled(!isFormValid || isLoading)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                username = savedUsername
                password = savedPassword
                
                if let server = Server.defaultNetworks.first(where: { $0.host == lastServerHost }) {
                    selectedServer = server
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !username.isEmpty
    }
    
    private func login() {
        guard isFormValid else { return }
        
        lastServerHost = selectedServer.host
        lastServerName = selectedServer.name
        savedUsername = username
        if !password.isEmpty {
            savedPassword = password
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                let user = try DatabaseManager.shared.authenticateUser(username: username.lowercased(), password: password)
                
                if let user = user {
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
                        channels: selectedServer.channels
                    )
                    try DatabaseManager.shared.saveServer(serverToSave)
                    
                    await MainActor.run {
                        AppState.shared.currentUser = user
                        isAuthenticated = true
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Invalid username or password"
                        showError = true
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    LoginView(isAuthenticated: .constant(false))
}
