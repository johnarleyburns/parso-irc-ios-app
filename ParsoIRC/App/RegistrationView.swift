import SwiftUI

struct RegistrationView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var isAuthenticated: Bool
    
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreeToTerms = false
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
                        
                        Text("Create Account")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Sign up to save your chat history and preferences")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Choose a nickname", text: $username)
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
                            SecureField("Create a password", text: $password)
                                .textContentType(.newPassword)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            SecureField("Confirm your password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        
                        Toggle(isOn: $agreeToTerms) {
                            Text("I agree to the Terms of Service and Privacy Policy")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
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
                    .background(isFormValid ? Color.theme.sentBubble : Color.theme.sentBubble.opacity(0.5))
                    .cornerRadius(12)
                    .disabled(!isFormValid || isLoading)
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
        !username.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 6 &&
        agreeToTerms
    }
    
    private func register() {
        guard isFormValid else {
            if username.isEmpty {
                errorMessage = "Please enter a username"
            } else if password.isEmpty {
                errorMessage = "Please enter a password"
            } else if password != confirmPassword {
                errorMessage = "Passwords do not match"
            } else if password.count < 6 {
                errorMessage = "Password must be at least 6 characters"
            } else if !agreeToTerms {
                errorMessage = "Please agree to the terms"
            }
            showError = true
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                let user = User(
                    username: username.lowercased(),
                    passwordHash: password,
                    nickname: username,
                    avatarSeed: username.lowercased()
                )
                try DatabaseManager.shared.saveUser(user)
                
                await MainActor.run {
                    AppState.shared.currentUser = user
                    isAuthenticated = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Registration failed: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    RegistrationView(isAuthenticated: .constant(false))
}
