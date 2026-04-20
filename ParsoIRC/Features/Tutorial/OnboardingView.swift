import SwiftUI

/// Three-page first-launch onboarding flow.
///
/// Page 1 – Welcome: what Parso IRC is, with a friendly illustration.
/// Page 2 – Identity: set a global default nickname and real name.
///          These are stored in AppState (and UserDefaults) so every new
///          server inherits them unless overridden per-server.
/// Page 3 – Add first server: simplified server picker that saves to DB
///          and sets autoConnect so the app connects on first open.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ircManager: IRCClientManager

    @State private var currentPage: Int = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage(currentPage: $currentPage)
                .tag(0)
            IdentityPage(currentPage: $currentPage)
                .tag(1)
            AddFirstServerPage(isPresented: $isPresented)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .top) {
            pageIndicator
                .padding(.top, 60)
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Page dots

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color(.systemFill))
                    .frame(width: index == currentPage ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero illustration
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 200, height: 200)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 40)

            Text("Welcome to Parso IRC")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text("IRC is one of the oldest and most vibrant chat networks on the internet — home to open-source communities, hackers, and friends worldwide.\n\nParso makes it easy to join in.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Page 2: Identity

private struct IdentityPage: View {
    @Binding var currentPage: Int
    @EnvironmentObject private var appState: AppState

    @State private var nickname: String = ""
    @State private var realName: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case nick, realName }

    private var isValid: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 100)

                Image(systemName: "person.fill.badge.plus")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 32)

                Text("Set Your Identity")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .padding(.bottom, 8)

                Text("Your nickname is how others see you on IRC. You can change it any time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)

                VStack(spacing: 12) {
                    OnboardingTextField(
                        title: "Nickname",
                        placeholder: "e.g. hacker42",
                        text: $nickname,
                        hint: "Max 9 characters, letters/numbers/-/_"
                    )
                    .focused($focusedField, equals: .nick)
                    .onSubmit { focusedField = .realName }
                    .onChange(of: nickname) { _, new in
                        // Enforce nick character rules: alphanumeric + - _ [ ] { } \ | `
                        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_[]{}\\|`"))
                        let filtered = new.unicodeScalars.filter { allowed.contains($0) }
                        let truncated = String(String.UnicodeScalarView(filtered).prefix(9))
                        if truncated != new { nickname = truncated }
                    }

                    OnboardingTextField(
                        title: "Real Name (optional)",
                        placeholder: "e.g. Ada Lovelace",
                        text: $realName,
                        hint: "Shown in WHOIS queries"
                    )
                    .focused($focusedField, equals: .realName)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)

                Button {
                    saveIdentity()
                    withAnimation { currentPage = 2 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.accentColor : Color(.systemFill))
                        .foregroundStyle(isValid ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isValid)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            // Pre-fill from previously saved identity if any
            nickname = appState.globalNickname
            realName = appState.globalRealName
            focusedField = .nick
        }
    }

    private func saveIdentity() {
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        let real = realName.trimmingCharacters(in: .whitespaces)
        appState.globalNickname = nick
        appState.globalRealName = real.isEmpty ? nick : real
    }
}

// MARK: - Page 3: Add First Server

private struct AddFirstServerPage: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState

    @State private var selectedPresetIndex: Int = 0
    @State private var showAddServer = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 100)

            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 32)

            Text("Choose a Network")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.bottom, 8)

            Text("Pick a server to get started. You can add more later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

            // Quick-pick network grid — all 10 presets
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(Server.defaultNetworks.enumerated()), id: \.offset) { index, network in
                    NetworkCard(
                        network: network,
                        isSelected: selectedPresetIndex == index
                    ) {
                        selectedPresetIndex = index
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    saveAndConnect()
                } label: {
                    Text("Connect to \(Server.defaultNetworks[selectedPresetIndex].name)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)

                Button {
                    showAddServer = true
                } label: {
                    Text("Configure a custom server")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.bottom, 8)

                Button {
                    isPresented = false
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showAddServer, onDismiss: {
            if (try? DatabaseManager.shared.fetchServers())?.isEmpty == false {
                isPresented = false
            }
        }) {
            AddServerSheet(existingServer: nil) { _ in
                isPresented = false
            }
            .environmentObject(appState)
        }
    }

    private func saveAndConnect() {
        let template = Server.defaultNetworks[selectedPresetIndex]
        let server = Server(
            id: UUID().uuidString,
            name: template.name,
            host: template.host,
            port: template.port,
            ssl: template.ssl,
            nickname: appState.globalNickname.isEmpty ? "parso\(Int.random(in: 1000...9999))" : appState.globalNickname,
            realname: appState.globalRealName.isEmpty ? "Parso IRC" : appState.globalRealName,
            password: nil,
            saslEnabled: false,
            autoConnect: true,
            channels: [],   // user adds channels manually via the browser
            lastActiveChannel: nil
        )
        try? DatabaseManager.shared.saveServer(server)
        isPresented = false
    }
}

// MARK: - Helper views

private struct NetworkCard: View {
    let network: Server
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: network.ssl ? "lock.fill" : "lock.open")
                        .font(.caption)
                        .foregroundStyle(network.ssl ? Color.green : Color.orange)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(network.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(network.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
        .environmentObject(AppState.shared)
        .environmentObject(IRCClientManager.shared)
}
