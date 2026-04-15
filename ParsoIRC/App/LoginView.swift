import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var isAuthenticated: Bool
    
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
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
                            SecureField("Enter your password", text: $password)
                                .textContentType(.password)
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
        }
    }
    
    private var isFormValid: Bool {
        !username.isEmpty && !password.isEmpty
    }
    
    private func login() {
        guard isFormValid else { return }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                let user = try DatabaseManager.shared.authenticateUser(username: username.lowercased(), password: password)
                
                await MainActor.run {
                    AppState.shared.currentUser = user
                    isAuthenticated = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Invalid username or password"
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
