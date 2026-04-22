import SwiftUI

/// Three-page first-launch onboarding flow.
///
/// Page 1 – Welcome: what Parso IRC is, with a friendly illustration.
/// Page 2 – Identity: set a global default nickname, username, and password.
///          These are stored in AppState (and UserDefaults) so every new
///          server inherits them unless overridden per-server.
///          Special case: if the user enters "demo" as their nickname the app
///          switches to demo mode and page 3 shows only the Parso Demo Server.
/// Page 3 – Add first server: simplified server picker that saves to DB
///          and sets autoConnect so the app connects on first open.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ircManager: IRCClientManager

    /// Which page to open first.
    /// Pass 1 to land directly on the Identity (nick/user/password) screen —
    /// used when coming from the EULA so the user doesn't hit a redundant
    /// "Welcome to Parso IRC" marketing page they just scrolled past.
    /// Defaults to 0 (WelcomePage) for any other entry point.
    @State private var currentPage: Int

    init(isPresented: Binding<Bool>, initialPage: Int = 0) {
        self._isPresented = isPresented
        self._currentPage = State(initialValue: initialPage)
    }

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage(currentPage: $currentPage)
                .tag(0)
            IdentityPage(currentPage: $currentPage)
                .tag(1)
            AddFirstServerPage(isPresented: $isPresented)
                .tag(2)
                // Force a full re-render when isDemoMode changes so the
                // paged TabView cache doesn't show stale normal-mode content.
                .id(appState.isDemoMode)
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
        // Announce current page and total to VoiceOver users
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentPage + 1) of 3")
        .accessibilityValue(["Welcome", "Set Your Identity", "Choose Networks"][currentPage])
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @Binding var currentPage: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero illustration — purely decorative, hidden from VoiceOver
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 200, height: 200)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)
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
                if reduceMotion { currentPage = 1 } else { withAnimation { currentPage = 1 } }
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
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = true
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case nick, username, password }

    private var isValid: Bool {
        !nickname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    // MARK: Word lists for memorable nick generation

    private static let adjectives = [
        "swift", "bright", "bold", "calm", "cool",
        "dark", "deep", "fast", "free", "grey",
        "keen", "loud", "mild", "neat", "pure",
        "quiet", "rough", "sharp", "slim", "wild"
    ]
    private static let nouns = [
        "bear", "bird", "cat", "deer", "duck",
        "fish", "fox", "frog", "hawk", "hare",
        "kite", "lion", "lynx", "mink", "mole",
        "newt", "puma", "rook", "seal", "wolf"
    ]

    /// Generates a memorable adjective+noun nick that fits within 9 IRC chars.
    /// e.g. "swiftwolf", "brighthawk", "coolbear42"
    static func generateNick() -> String {
        let adj  = adjectives.randomElement() ?? "cool"
        let noun = nouns.randomElement()      ?? "wolf"
        let base = adj + noun
        // If combined is ≤ 7 chars, append 2 digits for uniqueness; otherwise truncate to 9
        if base.count <= 7 {
            let suffix = Int.random(in: 10...99)
            return String((base + "\(suffix)").prefix(9))
        } else {
            return String(base.prefix(9))
        }
    }

    /// Generates a strong 14-character alphanumeric password.
    static func generatePassword() -> String {
        let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<14).compactMap { _ in chars.randomElement() })
    }

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

                Text("Your nickname is how others see you on IRC. We've generated unique credentials — save your password somewhere safe.\n\nTip: enter \"demo\" as your nickname to try the app with a sample server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)

                VStack(spacing: 12) {
                    // Nickname
                    OnboardingTextField(
                        title: "Nickname",
                        placeholder: "e.g. swiftwolf42",
                        text: $nickname,
                        hint: "Max 9 characters, letters/numbers/-/_"
                    )
                    .focused($focusedField, equals: .nick)
                    .onSubmit { focusedField = .username }
                    .onChange(of: nickname) { _, new in
                        // Enforce IRC nick rules, max 9 chars
                        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_[]{}\\|`"))
                        let filtered = new.unicodeScalars.filter { allowed.contains($0) }
                        let truncated = String(String.UnicodeScalarView(filtered).prefix(9))
                        if truncated != new { nickname = truncated }
                        // Keep username in sync unless user has manually diverged
                        if username == previousNick || username.isEmpty {
                            username = truncated
                        }
                        previousNick = truncated
                    }

                    // Username (same as nick by default, kept in sync)
                    OnboardingTextField(
                        title: "Username",
                        placeholder: "e.g. swiftwolf42",
                        text: $username,
                        hint: "Used as your IRC ident"
                    )
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
                    .onChange(of: username) { _, new in
                        // Allow user to diverge from the nick; no auto-sync back
                        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
                        let filtered = new.unicodeScalars.filter { allowed.contains($0) }
                        let clean = String(String.UnicodeScalarView(filtered))
                        if clean != new { username = clean }
                    }

                    // Password with show/hide + copy
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 0) {
                            Group {
                                if showPassword {
                                    TextField("auto-generated", text: $password)
                                } else {
                                    SecureField("auto-generated", text: $password)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .password)
                            .onSubmit { focusedField = nil }

                    // Show/hide toggle
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")

                    // Copy button
                    Button {
                        UIPasteboard.general.string = password
                        HapticManager.selectionFeedback()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .padding(.trailing, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy password to clipboard")
                        }
                        .padding(.vertical, 14)
                        .padding(.leading, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        Text("Save this password — use it to register your nick with NickServ once you've joined a server: /msg NickServ REGISTER <password> <email>")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)

                Button {
                    saveIdentity()
                    if reduceMotion { currentPage = 2 } else { withAnimation { currentPage = 2 } }
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
                .accessibilityLabel("Continue")
                .accessibilityHint(isValid ? "Proceeds to choose networks" : "Fill in all fields to continue")
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            // Pre-fill from saved identity if re-visiting; otherwise auto-generate
            if appState.globalNickname.isEmpty {
                let generated = IdentityPage.generateNick()
                nickname = generated
                username = generated
                previousNick = generated
            } else {
                nickname = appState.globalNickname
                username = appState.globalRealName.isEmpty ? appState.globalNickname : appState.globalRealName
                previousNick = appState.globalNickname
            }
            if appState.globalPassword.isEmpty {
                password = IdentityPage.generatePassword()
            } else {
                password = appState.globalPassword
            }
            focusedField = .nick
        }
    }

    /// Tracks the last auto-synced nick value so we know when username was manually edited.
    @State private var previousNick: String = ""

    private func saveIdentity() {
        var nick = nickname.trimmingCharacters(in: .whitespaces)
        var user = username.trimmingCharacters(in: .whitespaces)
        var pass = password

        // Demo mode: normalise credentials
        if nick.lowercased() == "demo" {
            nick = DemoContent.nick
            user = DemoContent.username
            pass = DemoContent.password
            appState.isDemoMode = true
        } else {
            appState.isDemoMode = false
        }

        appState.globalNickname = nick
        appState.globalRealName = user.isEmpty ? nick : user
        appState.globalPassword = pass
    }
}

// MARK: - Page 3: Add First Server

private struct AddFirstServerPage: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState

    /// Multi-select: set of indices into Server.defaultNetworks (non-demo mode only)
    @State private var selectedIndices: Set<Int> = [0]   // Libera.Chat pre-selected
    @State private var showAddServer = false

    private var isDemo: Bool { appState.isDemoMode }

    private var buttonLabel: String {
        if isDemo { return "Connect to Parso Demo Server" }
        switch selectedIndices.count {
        case 0: return "Select at least one network"
        case 1: return "Connect to \(Server.defaultNetworks[selectedIndices.first!].name)"
        default: return "Connect to \(selectedIndices.count) Networks"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (fixed)
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 80)
                    .padding(.bottom, 8)

                Text("Choose Networks")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text(isDemo
                     ? "Your demo server is ready. Tap below to connect."
                     : "Select one or more servers to get started. You can add more later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 16)

            if isDemo {
                // Demo mode: show a single pre-selected demo server card
                demoServerCard
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                // Normal mode: 2-column network grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(Server.defaultNetworks.enumerated()), id: \.offset) { index, network in
                            NetworkCard(
                                network: network,
                                isSelected: selectedIndices.contains(index)
                            ) {
                                if selectedIndices.contains(index) {
                                    selectedIndices.remove(index)
                                } else {
                                    selectedIndices.insert(index)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }

            // Footer (fixed)
            VStack(spacing: 10) {
                Divider()
                Button {
                    if isDemo {
                        saveAndConnectDemo()
                    } else {
                        saveAndConnect()
                    }
                } label: {
                    Text(buttonLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            (isDemo || !selectedIndices.isEmpty) ? Color.accentColor : Color.gray
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .disabled(!isDemo && selectedIndices.isEmpty)

                if !isDemo {
                    Button {
                        showAddServer = true
                    } label: {
                        Text("Configure a custom server")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer().frame(height: 24)
            }
            .padding(.bottom, 16)
        }
        // Dismiss keyboard inherited from the previous identity page
        .onAppear {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
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

    // MARK: - Demo server card

    private var demoServerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color(.systemTeal).opacity(0.8))
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Text(DemoContent.serverName)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(DemoContent.serverHost)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                )
        )
    }

    // MARK: - Save helpers

    private func saveAndConnect() {
        guard !selectedIndices.isEmpty else { return }
        let nick = appState.globalNickname.isEmpty
            ? IdentityPage.generateNick()
            : appState.globalNickname
        let real = appState.globalRealName.isEmpty ? nick : appState.globalRealName
        let pass = appState.globalPassword.isEmpty ? nil : appState.globalPassword

        for index in selectedIndices.sorted() {
            let template = Server.defaultNetworks[index]
            let server = Server(
                id: UUID().uuidString,
                name: template.name,
                host: template.host,
                port: template.port,
                ssl: template.ssl,
                nickname: nick,
                realname: real,
                password: pass,
                saslEnabled: false,
                saslMechanism: "PLAIN",
                autoConnect: true,
                channels: [],
                lastActiveChannel: nil
            )
            try? DatabaseManager.shared.saveServer(server)
        }
        isPresented = false
    }

    private func saveAndConnectDemo() {
        // Save demo server
        let demoServer = DemoContent.server
        try? DatabaseManager.shared.saveServer(demoServer)

        // Save demo channel with joinedAt so it appears in sidebar
        var ch = DemoContent.channel
        ch.joinedAt = Date()
        try? DatabaseManager.shared.saveChannel(ch, serverId: DemoContent.serverId)
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
                        .foregroundStyle(network.ssl ? Color(.systemTeal).opacity(0.8) : Color(.systemGray))
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
        // VoiceOver: announce selection state so colour+checkmark aren't the only cues
        .accessibilityLabel("\(network.name), \(network.ssl ? "encrypted" : "unencrypted")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select")")
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
