import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ircManager: IRCClientManager
    
    @State private var nickname: String = ""
    @State private var status: String = ""
    @State private var showingSaveSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        AvatarView(nick: nickname, size: 80)
                        
                        if let user = appState.currentUser {
                            Text(user.username)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                Section("Profile") {
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("Status", text: $status)
                        .textInputAutocapitalization(.sentences)
                }
                
                Section("Account") {
                    if let user = appState.currentUser {
                        HStack {
                            Text("Member since")
                            Spacer()
                            Text(formatDate(user.createdAt))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Last login")
                            Spacer()
                            Text(formatDate(user.lastLogin))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button("Sign Out") {
                        signOut()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadUserData()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Profile Saved", isPresented: $showingSaveSuccess) {
                Button("OK", role: .cancel) {}
            }
        }
    }
    
    private func loadUserData() {
        if let user = appState.currentUser {
            nickname = user.nickname ?? user.username
            status = user.status ?? ""
        }
    }
    
    private func saveProfile() {
        guard var user = appState.currentUser else { return }
        
        user.nickname = nickname.isEmpty ? nil : nickname
        user.status = status.isEmpty ? nil : status
        
        Task {
            try? DatabaseManager.shared.updateUser(user)
            await MainActor.run {
                appState.currentUser = user
                showingSaveSuccess = true
            }
        }
    }
    
    private func signOut() {
        Task {
            ircManager.disconnectAll()
            await MainActor.run {
                AppState.shared.currentUser = nil
                AppState.shared.hasLaunchedBefore = false
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
