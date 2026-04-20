import SwiftUI

/// A compact sheet for changing your nick/realname/password on a specific server.
///
/// If connected, changes take effect immediately via NICK command.
/// If disconnected, changes are saved to the DB for next connect.
struct NickIdentitySheet: View {
    let server: Server

    @EnvironmentObject private var ircManager: IRCClientManager
    @Environment(\.dismiss) private var dismiss

    @State private var nick: String = ""
    @State private var realName: String = ""
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var validationError: String? = nil
    @State private var isApplying = false

    private var isConnected: Bool {
        ircManager.connectionState(for: server.id) == .connected
    }

    private var currentNick: String {
        ircManager.currentNicknames[server.id] ?? server.nickname
    }

    var body: some View {
        NavigationStack {
            Form {
                // Status banner
                Section {
                    HStack(spacing: 12) {
                        ConnectionDot(state: ircManager.connectionState(for: server.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.headline)
                            Text(isConnected ? "Connected — changes take effect immediately" : "Disconnected — changes apply on next connect")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Identity fields
                Section {
                    HStack {
                        Label("Nickname", systemImage: "person.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        TextField("nickname", text: $nick)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Label("Real Name", systemImage: "signature")
                            .foregroundStyle(.primary)
                        Spacer()
                        TextField("Real Name", text: $realName)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Nickname: max 9 characters, letters/digits/- only.")
                        .font(.caption)
                }

                // Optional server password
                Section {
                    HStack {
                        Label("Server Password", systemImage: "key.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        if showPassword {
                            TextField("optional", text: $password)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("optional", text: $password)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Used for NickServ IDENTIFY or server password.")
                        .font(.caption)
                }

                if let error = validationError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Identity on \(server.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await applyChanges() }
                    } label: {
                        if isApplying {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Apply")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isApplying)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            nick = currentNick
            realName = server.realname
            password = server.password ?? ""
        }
    }

    // MARK: - Apply

    private func applyChanges() async {
        let trimmedNick = nick.trimmingCharacters(in: .whitespaces)
        guard !trimmedNick.isEmpty else {
            validationError = "Nickname cannot be empty."
            return
        }
        // IRC nick validation: max 9 chars, letters/digits/- _ [ ] { } \ | `
        guard trimmedNick.count <= 32 else {
            validationError = "Nickname is too long (max 32 chars)."
            return
        }
        let invalidChars = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_[]{}\\|`"))
            .inverted
        guard trimmedNick.unicodeScalars.allSatisfy({ !invalidChars.contains($0) }) else {
            validationError = "Nickname contains invalid characters."
            return
        }

        validationError = nil
        isApplying = true
        defer { isApplying = false }

        // If connected, send NICK command live
        if isConnected, let client = ircManager.getClient(for: server.id) {
            if trimmedNick != currentNick {
                try? await client.send_raw("NICK \(trimmedNick)")
                // Update local tracking — the server will echo back 001/NICK to confirm
                await MainActor.run {
                    ircManager.currentNicknames[server.id] = trimmedNick
                }
            }
        }

        // Persist to DB regardless of connection state
        var updated = server
        updated.nickname = trimmedNick
        updated.realname = realName.trimmingCharacters(in: .whitespaces)
        updated.password = password.isEmpty ? nil : password
        try? DatabaseManager.shared.saveServer(updated)

        dismiss()
    }
}

#Preview {
    NickIdentitySheet(server: Server.defaultNetworks[0])
        .environmentObject(IRCClientManager.shared)
}
